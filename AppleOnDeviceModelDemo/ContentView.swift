import SwiftUI

struct ContentView: View {
    @ObservedObject var navigation: AppNavigationState

    init(navigation: AppNavigationState = .shared) {
        self.navigation = navigation
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .category(category):
                        CategoryView(category: category)
                    case let .experience(id):
                        ExperienceDestinationView(experience: ExperienceCatalog[id])
                    case let .search(query):
                        ExperienceSearchView(query: query, navigation: navigation)
                    case .visionSegmentation:
                        VisionSegmentationView()
                    }
                }
        }
        .tint(.blue)
    }
}
