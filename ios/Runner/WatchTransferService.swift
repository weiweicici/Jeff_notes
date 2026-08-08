import Foundation
import WatchConnectivity

final class WatchTransferService: NSObject, WCSessionDelegate {
    static let shared = WatchTransferService()

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
              let title = values["title"] as? String,
              let audioPath = values["audioPath"] as? String,
              let boundaryPath = values["boundaryPath"] as? String,
              let markdownPath = values["markdownPath"] as? String,
              let manifestPath = values["manifestPath"] as? String else {
            return false
        }

        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else {
            return false
        }

        let transfers: [(String, String)] = [
            ("audio", audioPath),
            ("boundaries", boundaryPath),
            ("markdown", markdownPath),
            ("manifest", manifestPath),
        ]

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
        return queuedAny
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            NSLog("[WatchSync] Activation failed: %@", error.localizedDescription)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
