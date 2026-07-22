import Flutter
import UIKit
import ActivityKit

// Shared ActivityAttributes struct (mirrors Widget/LiveActivityAttributes.swift)
@available(iOS 16.1, *)
struct JeffNotesAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var activeSentence: String
        var nextSentence: String
        var currentIndex: Int
        var totalCount: Int
        var docTitle: String
        var isPlaying: Bool
    }
    var id: String
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var currentActivity: Any? = nil

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController

        // Wakelock channel (existing)
        let wakelockChannel = FlutterMethodChannel(name: "com.zhenfeng.jeffnotes/wakelock",
                                                   binaryMessenger: controller.binaryMessenger)
        wakelockChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            if call.method == "setWakelock" {
                if let args = call.arguments as? [String: Any],
                   let enable = args["enable"] as? Bool {
                    DispatchQueue.main.async {
                        UIApplication.shared.isIdleTimerDisabled = enable
                    }
                    result(true)
                } else {
                    result(false)
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        })

        // Live Activity channel
        let liveActivityChannel = FlutterMethodChannel(name: "com.zhenfeng.jeffnotes/liveactivity",
                                                       binaryMessenger: controller.binaryMessenger)
        liveActivityChannel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { result(nil); return }

            switch call.method {
            case "startActivity":
                if let args = call.arguments as? [String: Any] {
                    self.startLiveActivity(args: args, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
                }
            case "updateActivity":
                if let args = call.arguments as? [String: Any] {
                    self.updateLiveActivity(args: args, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
                }
            case "endActivity":
                self.endLiveActivity(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        })

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }

    private func startLiveActivity(args: [String: Any], result: @escaping FlutterResult) {
        if #available(iOS 16.2, *) {
            let activeSentence = args["activeSentence"] as? String ?? ""
            let nextSentence = args["nextSentence"] as? String ?? ""
            let currentIndex = args["currentIndex"] as? Int ?? 1
            let totalCount = args["totalCount"] as? Int ?? 1
            let docTitle = args["docTitle"] as? String ?? "Jeff Notes"
            let isPlaying = args["isPlaying"] as? Bool ?? true

            let attributes = JeffNotesAttributes(id: UUID().uuidString)
            let contentState = JeffNotesAttributes.ContentState(
                activeSentence: activeSentence,
                nextSentence: nextSentence,
                currentIndex: currentIndex,
                totalCount: totalCount,
                docTitle: docTitle,
                isPlaying: isPlaying
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: contentState, staleDate: nil),
                    pushType: nil
                )
                self.currentActivity = activity
                result("started")
            } catch {
                result(FlutterError(code: "ACTIVITY_ERROR", message: error.localizedDescription, details: nil))
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.2+", details: nil))
        }
    }

    private func updateLiveActivity(args: [String: Any], result: @escaping FlutterResult) {
        if #available(iOS 16.2, *) {
            guard let activity = self.currentActivity as? Activity<JeffNotesAttributes> else {
                result(FlutterError(code: "NO_ACTIVITY", message: "No active Live Activity", details: nil))
                return
            }

            let activeSentence = args["activeSentence"] as? String ?? ""
            let nextSentence = args["nextSentence"] as? String ?? ""
            let currentIndex = args["currentIndex"] as? Int ?? 1
            let totalCount = args["totalCount"] as? Int ?? 1
            let docTitle = args["docTitle"] as? String ?? "Jeff Notes"
            let isPlaying = args["isPlaying"] as? Bool ?? true

            let contentState = JeffNotesAttributes.ContentState(
                activeSentence: activeSentence,
                nextSentence: nextSentence,
                currentIndex: currentIndex,
                totalCount: totalCount,
                docTitle: docTitle,
                isPlaying: isPlaying
            )

            Task {
                await activity.update(
                    .init(state: contentState, staleDate: nil)
                )
                result("updated")
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.2+", details: nil))
        }
    }

    private func endLiveActivity(result: @escaping FlutterResult) {
        if #available(iOS 16.2, *) {
            guard let activity = self.currentActivity as? Activity<JeffNotesAttributes> else {
                result("no_activity")
                return
            }
            Task {
                await activity.end(dismissalPolicy: .immediate)
                self.currentActivity = nil
                result("ended")
            }
        } else {
            result("unsupported")
        }
    }
}
