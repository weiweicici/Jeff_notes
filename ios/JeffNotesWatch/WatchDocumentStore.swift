import Foundation
import WatchConnectivity

extension Notification.Name {
    static let jeffNotesWatchLibraryChanged = Notification.Name(
        "JeffNotesWatchLibraryChanged"
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

@MainActor
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
                let audioURL = directory.appendingPathComponent("audio.mp3")
                guard FileManager.default.fileExists(atPath: manifestURL.path),
                      FileManager.default.fileExists(atPath: audioURL.path),
                      let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? decoder.decode(
                        WatchDocumentManifest.self,
                        from: data
                      ),
                      manifest.schemaVersion == 1,
                      !manifest.sentences.isEmpty else { return nil }
                return WatchDocument(manifest: manifest, directoryURL: directory)
            }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        } catch {
            documents = []
        }
    }
}
