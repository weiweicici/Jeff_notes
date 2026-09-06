import Foundation
import WatchConnectivity

extension Notification.Name {
    static let jeffNotesWatchLibraryChanged = Notification.Name(
        "JeffNotesWatchLibraryChanged"
    )
    static let jeffNotesWatchRecordingStateChanged = Notification.Name(
        "JeffNotesWatchRecordingStateChanged"
    )
}

final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityReceiver()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendRemoteCommand(_ command: String) async throws {
        try await sendMessage(["command": command])
    }

    func sendRecordingCommand(_ command: String) async throws -> RecordingCommandDelivery {
        let message: [String: Any] = [
            "command": command,
            "commandId": UUID().uuidString,
        ]
        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
            session.transferUserInfo(message)
            return .queued
        }
        if !session.isReachable {
            session.transferUserInfo(message)
            return .queued
        }
        do {
            try await sendMessage(message)
            return .immediate
        } catch {
            // A reply can be lost after the phone already accepted the command.
            // commandId makes this fallback delivery idempotent.
            session.transferUserInfo(message)
            return .queued
        }
    }


    private func sendMessage(_ message: [String: Any]) async throws {
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.activate()
            throw RemoteCommandError.notConnected
        }
        guard session.isReachable else {
            throw RemoteCommandError.notReachable
        }

        try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { reply in
                    if reply["ok"] as? Bool == true {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: RemoteCommandError.rejected)
                    }
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata,
              let documentId = metadata["documentId"] as? String,
              let kind = metadata["kind"] as? String else { return }

        do {
            let destination = try Self.destinationURL(
                documentId: documentId,
                kind: kind
            )
            let manager = FileManager.default
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: file.fileURL, to: destination)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .jeffNotesWatchLibraryChanged,
                    object: documentId
                )
            }
        } catch {
            NSLog("[WatchSync] Receive failed: %@", error.localizedDescription)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        applyStateEnvelope(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyStateEnvelope(message)
    }

    private func applyStateEnvelope(_ envelope: [String: Any]) {
        if let state = envelope["recordingState"] as? [String: Any] {
            UserDefaults.standard.set(state, forKey: "JeffNotesRecordingState")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .jeffNotesWatchRecordingStateChanged,
                    object: nil,
                    userInfo: state
                )
            }
        }
    }

    static func libraryURL() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents.appendingPathComponent("JeffNotes", isDirectory: true)
    }

    private static func destinationURL(documentId: String, kind: String) throws -> URL {
        let safeId = documentId.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        let directory = try libraryURL().appendingPathComponent(safeId, isDirectory: true)
        let filename: String
        switch kind {
        case "audio": filename = "audio.mp3"
        case "boundaries": filename = "boundaries.json"
        case "markdown": filename = "document.md"
        case "manifest": filename = "manifest.json"
        default: filename = "ignored"
        }
        return directory.appendingPathComponent(filename)
    }
}

enum RemoteCommandError: LocalizedError {
    case notConnected
    case notReachable
    case rejected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "正在连接手机，请稍后重试"
        case .notReachable:
            return "手机 Jeff Notes 未连接"
        case .rejected:
            return "手机未接受控制命令"
        }
    }
}


enum RecordingCommandDelivery {
    case immediate
    case queued
}

final class WatchDocumentStore: ObservableObject {
    @Published private(set) var documents: [WatchDocument] = []

    init() {
        reload()
    }

    var latest: WatchDocument? { documents.first }

    func reload() {
        do {
            let root = try WatchConnectivityReceiver.libraryURL()
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            let directories = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let decoder = JSONDecoder()
            documents = directories.compactMap { directory in
                let manifestURL = directory.appendingPathComponent("manifest.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path),
                      let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? decoder.decode(
                        WatchDocumentManifest.self,
                        from: data
                      ),
                      manifest.schemaVersion == 1,
                      FileManager.default.fileExists(
                        atPath: directory
                            .appendingPathComponent(manifest.markdownFile)
                            .path
                      ) else { return nil }
                return WatchDocument(manifest: manifest, directoryURL: directory)
            }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        } catch {
            documents = []
        }
    }
}

@MainActor
final class WatchRecordingStore: ObservableObject {
    @Published private(set) var snapshot: WatchRecordingSnapshot
    private var observer: NSObjectProtocol?

    init() {
        let cached = UserDefaults.standard.dictionary(
            forKey: "JeffNotesRecordingState"
        ) ?? [:]
        snapshot = WatchRecordingSnapshot(dictionary: cached)
        observer = NotificationCenter.default.addObserver(
            forName: .jeffNotesWatchRecordingStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo else { return }
            let values = userInfo.reduce(into: [String: Any]()) { result, entry in
                guard let key = entry.key as? String else { return }
                result[key] = entry.value
            }
            Task { @MainActor in
                self?.snapshot = WatchRecordingSnapshot(dictionary: values)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
