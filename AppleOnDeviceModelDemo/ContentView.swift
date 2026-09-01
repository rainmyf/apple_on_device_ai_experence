import SwiftUI

struct ContentView: View {
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .category(category):
                        CategoryView(category: category)
                    case let .experience(id):
                        ExperienceDestinationView(experience: ExperienceCatalog[id])
                    }
                }
        }
        .tint(.blue)
    }
}
