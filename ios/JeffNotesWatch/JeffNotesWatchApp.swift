import SwiftUI

@main
struct JeffNotesWatchApp: App {
    init() {
        WatchConnectivityReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
