import AppIntents
import Foundation
import SwiftUI

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchExperiencesIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    init() {
        criteria = StringSearchCriteria(term: "")
    }

    init(criteria: StringSearchCriteria) {
        self.criteria = criteria
    }

    func perform() async throws -> some IntentResult {
        let term = criteria.term
        await MainActor.run {
            AppNavigationState.shared.showSearch(term)
        }
        return .result()
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenExperienceIntent: OpenIntent {
    var target: ExperienceEntity

    init() {
        target = ExperienceEntity(definition: ExperienceCatalog[.foundationModel])
    }

    init(target: ExperienceEntity) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        // Hidden/retired entries must not be externally routable even when an
        // intent is constructed directly instead of coming from the query.
        guard !target.hideInSpotlight, let route = target.route else { return .result() }
        await MainActor.run {
            AppNavigationState.shared.open(route)
        }
        return .result()
    }
}

@available(iOS 27.0, *)
struct RunOnDeviceModelIntent: AppIntent {
    static let title: LocalizedStringResource = "运行端侧模型"
    static let description = IntentDescription("Send open-ended text to the app's on-device Foundation Model.")

    @Parameter(title: "Text")
    var text: String

    init() {
        text = ""
    }

    init(text: String) {
        self.text = text
    }

    static func execute(
        text: String,
        service: FoundationModelService = FoundationModelService()
    ) async throws -> String {
        try await service.respond(to: text)
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await Self.execute(text: text))
    }
}

enum RunOnDeviceModelShortcut {
    struct Metadata: Equatable, Sendable {
        let title: String
        let phrase: String
        let usesFoundationModel: Bool
        let allowsCloudFallback: Bool
    }

    static let metadata = Metadata(
        title: "运行端侧模型",
        phrase: "运行端侧模型",
        usesFoundationModel: true,
        allowsCloudFallback: false
    )
}

@available(iOS 27.0, *)
struct AppleOnDeviceModelDemoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunOnDeviceModelIntent(),
            phrases: ["运行端侧模型 \(.applicationName)"],
            shortTitle: "运行端侧模型",
            systemImageName: "sparkles"
        )
    }
}

@available(iOS 27.0, *)
struct ExperienceSearchView: View {
    let query: String
    @ObservedObject var navigation: AppNavigationState

    init(query: String, navigation: AppNavigationState = .shared) {
        self.query = query
        self.navigation = navigation
    }

    private var results: [ExperienceDefinition] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalized.isEmpty else { return ExperienceIndexing.visibleDefinitions }
        return ExperienceIndexing.visibleDefinitions.filter { definition in
            [definition.title, definition.summary, definition.framework, definition.minimumOSVersion, definition.openedAPI]
                .joined(separator: " ")
                .localizedLowercase
                .contains(normalized)
        }
    }

    var body: some View {
        List(results) { experience in
            Button {
                navigation.open(experience: experience.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(experience.title)
                    Text("\(experience.framework) · \(experience.minimumOSVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(query.isEmpty ? "Experiences" : "Search results")
    }
}
