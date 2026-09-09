import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DemoLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        DemoLiveActivityWidget()
    }
}

struct DemoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DemoLiveActivityAttributes.self) { context in
            DemoLiveActivityLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 10) {
                        DemoLiveActivityExpandedIcon(state: context.state)
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DemoLiveActivityDetailsView(state: context.state)
                }
            } compactLeading: {
                DemoLiveActivityIcon(state: context.state)
            } compactTrailing: {
                Text(context.state.compactPresentationText)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                DemoLiveActivityIcon(state: context.state)
            }
        }
        .configurationDisplayName("系统智能调用 App")
        .description("展示系统智能调用 App 后的实况状态。")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct DemoLiveActivityLockScreenView: View {
    let state: DemoLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DemoLiveActivityIcon(state: state)
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            DemoLiveActivityDetailsView(state: state)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.white)
    }
}

private struct DemoLiveActivityIcon: View {
    let state: DemoLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: DemoLiveActivityTheme.theme(for: state.category).symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.92))
            .accessibilityLabel(DemoLiveActivityTheme.theme(for: state.category).title)
    }
}

private struct DemoLiveActivityExpandedIcon: View {
    let state: DemoLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: DemoLiveActivityTheme.theme(for: state.category).symbolName)
            .font(.system(size: 26, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.94))
            .frame(width: 44, height: 44)
            .accessibilityLabel(DemoLiveActivityTheme.theme(for: state.category).title)
    }
}

private struct DemoLiveActivityDetailsView: View {
    let state: DemoLiveActivityAttributes.ContentState

    var body: some View {
        Text(state.summary)
            .font(.caption)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
