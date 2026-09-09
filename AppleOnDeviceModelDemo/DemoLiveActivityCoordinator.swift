import ActivityKit
import Foundation

actor DemoLiveActivityCoordinator: DemoLiveActivityManaging {
    static let shared = DemoLiveActivityCoordinator()

    private var activeActivityIdentifier: UUID?
    private(set) var lastDiagnostic: String?

    func startAnalyzing(sender: String?) async {
        lastDiagnostic = nil
        let state = DemoLiveActivityContentBuilder.analyzing(sender: sender)
        // Start a fresh Activity for each manual category test. Reusing an old
        // instance can leave the island in the previous Activity's UI state.
        await Self.endCurrentActivity()
        activeActivityIdentifier = nil

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastDiagnostic = "activityAuthorizationDenied"
            return
        }

        do {
            activeActivityIdentifier = try Self.requestActivity(state: state)
            lastDiagnostic = "activityStarted:\(activeActivityIdentifier!.uuidString)"
        } catch {
            lastDiagnostic = "activityStartFailed:\(String(describing: error))"
        }
    }

    func update(_ state: DemoLiveActivityAttributes.ContentState) async {
        lastDiagnostic = nil
        // Create a fresh Activity after classification so the system receives a
        // new presentation event. Its content is already final; only the phase
        // transitions briefly from analyzing to classified.
        await Self.endCurrentActivity()
        activeActivityIdentifier = nil

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastDiagnostic = "activityAuthorizationDenied"
            return
        }

        do {
            let newlyCreatedState = DemoLiveActivityContentBuilder.newlyCreatedPresentation(for: state)
            activeActivityIdentifier = try Self.requestActivity(state: newlyCreatedState)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard activeActivityIdentifier != nil else { return }
            await Self.updateCurrentActivity(state: state)
            lastDiagnostic = "activityStartedAndSettled:(activeActivityIdentifier!.uuidString)"
        } catch {
            lastDiagnostic = "activityStartFailed:(String(describing: error))"
        }
    }

    func endActive() async {
        guard activeActivityIdentifier != nil else { return }
        await Self.endCurrentActivity()
        activeActivityIdentifier = nil
    }

    func activeActivityID() -> UUID? {
        activeActivityIdentifier
    }

    func diagnostic() -> String? {
        lastDiagnostic
    }

    private nonisolated static func requestActivity(
        state: DemoLiveActivityAttributes.ContentState
    ) throws -> UUID {
        let activity = try Activity.request(
            attributes: DemoLiveActivityAttributes(activityID: UUID()),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil,
            style: .standard
        )
        return activity.attributes.activityID
    }

    private nonisolated static func endCurrentActivity() async {
        guard let activity = Activity<DemoLiveActivityAttributes>.activities.first else {
            return
        }
        await activity.end(dismissalPolicy: .immediate)
    }

    private nonisolated static func updateCurrentActivity(
        state: DemoLiveActivityAttributes.ContentState
    ) async {
        guard let activity = Activity<DemoLiveActivityAttributes>.activities.first else {
            return
        }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
}
