import SwiftUI
import WidgetKit

@main
struct JeffNotesWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            JeffNotesLiveActivity()
        }
    }
}
