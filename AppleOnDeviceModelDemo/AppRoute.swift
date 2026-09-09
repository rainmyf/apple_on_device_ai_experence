import SwiftUI

enum AppRoute: Hashable {
    case category(ExperienceCategory)
    case experience(ExperienceID)
    case search(String)
    case visionSegmentation
}

enum ExperienceDestinationKind: Hashable {
    case category(ExperienceCategory)
    case experience(ExperienceID)
}

enum AppRouteResolver {
    static let featuredItems = ExperienceCatalog.featured

    static func route(for item: ExperienceDefinition) -> AppRoute {
        .experience(item.id)
    }

    static func homeSelection(for item: ExperienceDefinition) -> AppRoute {
        route(for: item)
    }

    static func categorySelection(for category: ExperienceCategory) -> AppRoute {
        .category(category)
    }

    static func items(in category: ExperienceCategory) -> [ExperienceDefinition] {
        ExperienceCatalog.all.filter { $0.category == category }
    }

    static func destinationKind(for route: AppRoute) -> ExperienceDestinationKind {
        switch route {
        case let .category(category):
            .category(category)
        case let .experience(id):
            .experience(id)
        case .search:
            .category(.languageText)
        case .visionSegmentation:
            .experience(.vision)
        }
    }
}

@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()

    @Published var path: [AppRoute] = []

    func open(_ route: AppRoute) {
        path = [route]
    }

    func open(experience id: ExperienceID) {
        open(.experience(id))
    }

    func showSearch(_ query: String) {
        open(.search(query))
    }

    func reset() {
        path.removeAll()
    }
}
