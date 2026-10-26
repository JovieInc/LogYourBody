import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrainingRestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainingRestActivityAttributes.self) { context in
            HStack {
                Label("Rest timer", systemImage: "timer")
                Spacer()
                countdown(context.state)
                    .font(.title2.weight(.semibold))
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Check how you feel before your next set.")
                        .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                countdown(context.state).frame(width: 48)
            } minimal: {
                Image(systemName: "timer")
            }
            .keylineTint(.white)
        }
    }

    private func countdown(_ state: TrainingRestActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt...state.endsAt, countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .accessibilityLabel("Rest time remaining")
    }
}
