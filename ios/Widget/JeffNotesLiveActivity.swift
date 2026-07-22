import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct JeffNotesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JeffNotesAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(context.state.currentIndex)/\(context.state.totalCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.activeSentence)
                        .font(.caption)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.nextSentence.isEmpty {
                        Text("Next: \(context.state.nextSentence)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Text("\(context.state.currentIndex)")
                    .font(.caption2)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
            } minimal: {
                Image(systemName: context.state.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
        }
    }
}

@available(iOS 16.1, *)
struct LockScreenView: View {
    let context: ActivityViewContext<JeffNotesAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(context.state.docTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(context.state.currentIndex)/\(context.state.totalCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(context.state.activeSentence)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(4)
                .minimumScaleFactor(0.8)

            if !context.state.nextSentence.isEmpty {
                Text(context.state.nextSentence)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding()
        .activityBackgroundTint(nil)
    }
}
