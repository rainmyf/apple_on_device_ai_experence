import CoreSpotlight
import SwiftUI

@main
struct AppleOnDeviceModelDemoApp: App {
    @StateObject private var navigation = AppNavigationState.shared

    var body: some Scene {
        WindowGroup {
            ContentView(navigation: navigation)
                .preferredColorScheme(.light)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard
                        let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                        let entityID = ExperienceIndexing.entityID(from: identifier),
                        let experienceID = ExperienceID(rawValue: entityID)
                    else { return }

                    navigation.open(experience: experienceID)
                }
                .task {
                    do {
                        try await ExperienceIndexing.indexVisibleExperiences()
                    } catch {
                        // Spotlight is an optional system entry point; the app remains
                        // usable when indexing is unavailable or interrupted.
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "appleondevicemodeldemo",
                          url.host == "demo-live-activity"
                    else { return }
                    Task {
                        await DemoLiveActivityCoordinator.shared.endActive()
                    }
                }
        }
    }
}
