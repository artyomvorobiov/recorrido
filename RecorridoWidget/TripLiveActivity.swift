import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The walk on the lock screen and in the Dynamic Island.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenTripView(context: context)
                .activitySystemActionForegroundColor(Color.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.emoji)
                        Text(verbatim: "\(context.state.nextNumber)/\(context.state.total)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let distance = context.state.distance {
                        Text(Format.distance(distance))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.finished ? context.attributes.routeTitle : context.state.nextTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Label(context.state.mode.title, systemImage: context.state.mode.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: context.state.progress)
                            .tint(Color.accentColor)
                        if !context.state.finished {
                            Button(intent: CheckInIntent()) {
                                Label("I'm here", systemImage: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .tint(Color.accentColor)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.finished ? "flag.checkered" : context.state.mode.symbol)
                    .foregroundStyle(Color.accentColor)
            } compactTrailing: {
                if let distance = context.state.distance, !context.state.finished {
                    Text(Format.distance(distance))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text(verbatim: "\(context.state.passed)/\(context.state.total)")
                        .font(.caption2.weight(.semibold))
                }
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(Color.accentColor)
            }
            .widgetURL(URL(string: "recorrido://trip"))
            .keylineTint(Color.accentColor)
        }
    }
}

private struct LockScreenTripView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(context.attributes.emoji)
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.finished ? LocalizedStringKey("Route completed") : LocalizedStringKey("Next stop"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(state.finished ? context.attributes.routeTitle : state.nextTitle)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: state.mode.symbol)
                        if let distance = state.distance, !state.finished {
                            Text(Format.distance(distance)).monospacedDigit()
                        } else {
                            Text(state.mode.title)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !state.finished {
                    Button(intent: CheckInIntent()) {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .tint(Color.accentColor)
                    .accessibilityLabel(Text("I'm here"))
                }
            }
            HStack(spacing: 8) {
                ProgressView(value: state.progress)
                    .tint(Color.accentColor)
                Text(verbatim: "\(state.passed)/\(state.total)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}
