import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var playbackWakelockRequested = false
    private var foregroundDisplayRequested = false
    private var watchSyncChannel: FlutterMethodChannel?

    private func updateIdleTimer() {
        let appIsActive = UIApplication.shared.applicationState == .active
        UIApplication.shared.isIdleTimerDisabled = appIsActive &&
            (playbackWakelockRequested || foregroundDisplayRequested)
    }

    private func configureWakelockChannel(binaryMessenger: FlutterBinaryMessenger) {
        let wakelockChannel = FlutterMethodChannel(name: "com.zhenfeng.jeffnotes/wakelock",
                                                   binaryMessenger: binaryMessenger)
        wakelockChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            if call.method == "setWakelock" {
                if let args = call.arguments as? [String: Any],
                   let enable = args["enable"] as? Bool {
                    DispatchQueue.main.async {
                        self.playbackWakelockRequested = enable
                        self.updateIdleTimer()
                    }
                    result(true)
                } else {
                    result(false)
                }
            } else if call.method == "setForegroundDisplayMode" {
                if let args = call.arguments as? [String: Any],
                   let enable = args["enable"] as? Bool {
                    DispatchQueue.main.async {
                        self.foregroundDisplayRequested = enable
                        self.updateIdleTimer()
                    }
                    result(true)
                } else {
                    result(false)
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        })

    }

    private func configureWatchSyncChannel(binaryMessenger: FlutterBinaryMessenger) {
        WatchTransferService.shared.activate()
        let channel = FlutterMethodChannel(
            name: "com.zhenfeng.jeffnotes/watch_sync",
            binaryMessenger: binaryMessenger
        )
        watchSyncChannel = channel
        WatchTransferService.shared.commandHandler = { [weak self] message, completion in
            guard let channel = self?.watchSyncChannel else {
                completion(false)
                return
            }
            channel.invokeMethod("watchCommand", arguments: message) { response in
                if response is FlutterError || FlutterMethodNotImplemented.isEqual(response) {
                    completion(false)
                } else {
                    completion((response as? Bool) ?? false)
                }
            }
        }
        channel.setMethodCallHandler { call, result in
            if call.method == "queueTtsPackage" {
                result(WatchTransferService.shared.queuePackage(arguments: call.arguments))
            } else if call.method == "updateRecordingState" {
                result(WatchTransferService.shared.updateRecordingState(arguments: call.arguments))
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        foregroundDisplayRequested = false
        updateIdleTimer()
        super.applicationWillResignActive(application)
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        foregroundDisplayRequested = false
        playbackWakelockRequested = false
        updateIdleTimer()
        super.applicationWillTerminate(application)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        let binaryMessenger = engineBridge.applicationRegistrar.messenger()
        configureWakelockChannel(binaryMessenger: binaryMessenger)
        configureWatchSyncChannel(binaryMessenger: binaryMessenger)
    }
}
