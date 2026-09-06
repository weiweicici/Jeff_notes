import Foundation
import WatchConnectivity

final class WatchTransferService: NSObject, WCSessionDelegate {
    static let shared = WatchTransferService()

    var commandHandler: (([String: Any], @escaping (Bool) -> Void) -> Void)? {
        didSet { deliverPendingCommands() }
    }

    private var pendingPackage: [String: Any]?
    private var retryWorkItem: DispatchWorkItem?
    private var retryCount = 0
    private let maximumRetryCount = 60
    private var pendingCommands: [[String: Any]] = []

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func queuePackage(arguments: Any?) -> Bool {
        guard WCSession.isSupported(),
              let values = arguments as? [String: Any],
              let documentId = values["documentId"] as? String,
              values["title"] is String,
              let markdownPath = values["markdownPath"] as? String,
              let manifestPath = values["manifestPath"] as? String else {
            return false
        }

        let boundaryPath = values["boundaryPath"] as? String
        let requiredPaths = [markdownPath, manifestPath] + (boundaryPath.map { [$0] } ?? [])
        guard requiredPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
            NSLog("[WatchSync] Package rejected because one or more files are missing: %@", documentId)
            return false
        }

        // Keep the newest request until WatchConnectivity is ready. Previously
        // a temporary inactive/not-installed state silently discarded it.
        pendingPackage = values
        retryCount = 0
        retryWorkItem?.cancel()
        enqueuePendingPackageIfPossible()
        return true
    }

    func updateRecordingState(arguments: Any?) -> Bool {
        updateApplicationValue(key: "recordingState", arguments: arguments)
    }

    private func updateApplicationValue(key: String, arguments: Any?) -> Bool {
        guard WCSession.isSupported(),
              let values = arguments as? [String: Any] else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.activate()
            return false
        }
        var envelope = session.applicationContext
        envelope[key] = values
        do {
            try session.updateApplicationContext(envelope)
        } catch {
            NSLog("[WatchSync] Context update failed for %@: %@", key, error.localizedDescription)
        }
        if session.isReachable {
            session.sendMessage([key: values], replyHandler: nil) { error in
                NSLog("[WatchSync] Live %@ update failed: %@", key, error.localizedDescription)
            }
        }
        return true
    }

    private func enqueuePendingPackageIfPossible() {
        guard let values = pendingPackage,
              let documentId = values["documentId"] as? String,
              let title = values["title"] as? String,
              let markdownPath = values["markdownPath"] as? String,
              let manifestPath = values["manifestPath"] as? String else {
            return
        }

        let session = WCSession.default
        // On mixed beta OS versions a directly installed development Watch app
        // can be reachable even while `isWatchAppInstalled` temporarily stays
        // false. Treat activation as the transport gate and let
        // WatchConnectivity queue/retry delivery instead of withholding every
        // document forever.
        guard session.activationState == .activated else {
            if session.activationState != .activated {
                session.activate()
            }
            scheduleRetry()
            return
        }

        var transfers: [(String, String)] = [
            ("markdown", markdownPath),
            ("manifest", manifestPath),
        ]
        if let boundaryPath = values["boundaryPath"] as? String {
            transfers.insert(("boundaries", boundaryPath), at: 0)
        }

        let pendingKinds = Set(transfers.map(\.0))
        for transfer in session.outstandingFileTransfers {
            guard transfer.file.metadata?["documentId"] as? String == documentId,
                  let kind = transfer.file.metadata?["kind"] as? String,
                  pendingKinds.contains(kind) else { continue }
            transfer.cancel()
        }

        var queuedAny = false
        for (kind, path) in transfers {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            session.transferFile(
                url,
                metadata: [
                    "schemaVersion": 1,
                    "documentId": documentId,
                    "title": title,
                    "kind": kind,
                ]
            )
            queuedAny = true
        }

        if queuedAny {
            pendingPackage = nil
            retryWorkItem?.cancel()
            retryWorkItem = nil
            NSLog("[WatchSync] Queued package for transfer: %@", documentId)
        } else {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard pendingPackage != nil, retryCount < maximumRetryCount else {
            if pendingPackage != nil {
                NSLog("[WatchSync] Giving up after %d retries", retryCount)
            }
            return
        }
        retryWorkItem?.cancel()
        retryCount += 1
        let item = DispatchWorkItem { [weak self] in
            self?.enqueuePendingPackageIfPossible()
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            NSLog("[WatchSync] Activation failed: %@", error.localizedDescription)
            scheduleRetry()
        } else {
            enqueuePendingPackageIfPossible()
        }
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        guard userInfo["command"] is String else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingCommands.append(userInfo)
            self.deliverPendingCommands()
        }
    }

    private func deliverPendingCommands() {
        guard let commandHandler, !pendingCommands.isEmpty else { return }
        let queued = pendingCommands
        pendingCommands.removeAll()
        for command in queued {
            commandHandler(command) { accepted in
                if !accepted {
                    NSLog("[WatchSync] Queued command was rejected")
                }
            }
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        enqueuePendingPackageIfPossible()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["command"] is String else {
            replyHandler(["ok": false])
            return
        }
        // Recording commands carry an idempotency id. Acknowledge transport
        // immediately so the Watch button never waits for lengthy recorder
        // shutdown/finalization. If Flutter is still starting, retain it.
        if message["commandId"] is String {
            replyHandler(["ok": true])
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let commandHandler = self.commandHandler else {
                    self.pendingCommands.append(message)
                    return
                }
                commandHandler(message) { accepted in
                    if !accepted {
                        NSLog("[WatchSync] Recording command was rejected")
                    }
                }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let commandHandler = self?.commandHandler else {
                replyHandler(["ok": false])
                return
            }
            commandHandler(message) { accepted in
                replyHandler(["ok": accepted])
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        scheduleRetry()
    }
}
