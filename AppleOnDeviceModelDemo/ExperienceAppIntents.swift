import ActivityKit
import AppIntents
import Foundation
import SwiftUI

struct SMSAppIntentHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let receivedAt: Date
    let text: String
    let title: String
    let summary: String
}

@MainActor
final class SMSAppIntentHistoryStore: ObservableObject {
    static let shared = SMSAppIntentHistoryStore()

    @Published private(set) var entries: [SMSAppIntentHistoryEntry]

    private let defaults: UserDefaults
    // v1 and v2 were populated by prototype validation. New user-facing
    // history begins only after test calls are isolated from this store.
    private static let storageKey = "smsAppIntentHistory.v3"
    private static let maximumEntries = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    func reload() {
        entries = Self.load(from: defaults)
    }

    func record(text: String, result: SMSIncomingClassification) {
        let category = result.category.demoCategory
        let entry = SMSAppIntentHistoryEntry(
            id: UUID(),
            receivedAt: Date(),
            text: text,
            title: DemoLiveActivityTheme.theme(for: category).title,
            summary: result.summary
        )
        entries = Array(([entry] + entries).prefix(Self.maximumEntries))
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [SMSAppIntentHistoryEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([SMSAppIntentHistoryEntry].self, from: data)
        else { return [] }
        return Array(saved.prefix(maximumEntries))
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchExperiencesIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria
    init() { criteria = StringSearchCriteria(term: "") }
    init(criteria: StringSearchCriteria) { self.criteria = criteria }
    func perform() async throws -> some IntentResult {
        await MainActor.run { AppNavigationState.shared.showSearch(criteria.term) }
        return .result()
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenExperienceIntent: OpenIntent {
    var target: ExperienceEntity
    init() { target = ExperienceEntity(definition: ExperienceCatalog[.foundationModel]) }
    init(target: ExperienceEntity) { self.target = target }
    func perform() async throws -> some IntentResult {
        guard !target.hideInSpotlight, let route = target.route else { return .result() }
        await MainActor.run { AppNavigationState.shared.open(route) }
        return .result()
    }
}

/// Current SMS automation entry point. The old standalone SMS Classification
/// page is gone, but this AppIntent remains the system-to-App proof path.
@available(iOS 27.0, *)
struct RunOnDeviceModelIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "收到短信并分类"
    static let description = IntentDescription("Classify an incoming SMS with the on-device Foundation Model and show a Live Activity.")

    @Parameter(title: "短信正文") var text: String
    @Parameter(title: "发件人") var sender: String?

    init() { text = ""; sender = nil }
    init(text: String, sender: String? = nil) { self.text = text; self.sender = sender }

    @MainActor
    static func execute(
        text: String,
        sender: String? = nil,
        classifier: any SMSIncomingClassifying = SMSIncomingClassificationService(),
        activity: any DemoLiveActivityManaging = DemoLiveActivityCoordinator.shared,
        history: SMSAppIntentHistoryStore
    ) async throws -> SMSIncomingClassification {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: SMSIncomingClassification
        if input.isEmpty {
            result = SMSIncomingPresentation.from(rawCategory: nil, source: .fallback, fallbackReason: "missingShortcutInput")
        } else {
            do {
                result = SMSIncomingPresentation.normalized(try await classifier.classify(input))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result = SMSIncomingPresentation.from(rawCategory: nil, source: .fallback, fallbackReason: String(describing: error))
            }
        }
        let state = liveActivityState(for: result)
        await activity.update(state)
        if !input.isEmpty {
            history.record(text: input, result: result)
        }
        return result
    }

    static func liveActivityState(for result: SMSIncomingClassification) -> DemoLiveActivityAttributes.ContentState {
        DemoLiveActivityContentBuilder.classified(
            category: result.category.demoCategory,
            summary: result.summary
        )
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await Self.execute(
            text: text,
            sender: sender,
            history: .shared
        )
        return .result(value: result.category.rawValue)
    }
}

private extension SMSIncomingCategory {
    var demoCategory: DemoLiveActivityCategory {
        switch self {
        case .delivery: .delivery
        case .bankRepayment: .bankRepayment
        case .trainWaitlistSuccess: .trainWaitlistSuccess
        case .weatherAlert: .weatherAlert
        case .ordinary: .ordinary
        }
    }
}

enum RunOnDeviceModelShortcut {
    struct Metadata: Equatable, Sendable {
        let title: String; let phrase: String; let usesFoundationModel: Bool; let allowsCloudFallback: Bool
    }
    static let metadata = Metadata(title: "收到短信并分类", phrase: "收到短信并分类", usesFoundationModel: true, allowsCloudFallback: false)
}

@available(iOS 27.0, *)
struct AppleOnDeviceModelDemoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunOnDeviceModelIntent(), phrases: ["收到短信并分类 \(.applicationName)"], shortTitle: "收到短信并分类", systemImageName: "message.badge.filled.fill")
    }
}

@available(iOS 27.0, *)
struct ExperienceSearchView: View {
    let query: String
    @ObservedObject var navigation: AppNavigationState
    init(query: String, navigation: AppNavigationState = .shared) { self.query = query; self.navigation = navigation }
    private var results: [ExperienceDefinition] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalized.isEmpty else { return ExperienceIndexing.visibleDefinitions }
        return ExperienceIndexing.visibleDefinitions.filter { definition in
            [definition.title, definition.summary, definition.framework, definition.minimumOSVersion, definition.openedAPI].joined(separator: " ").localizedLowercase.contains(normalized)
        }
    }
    var body: some View {
        List(results) { experience in
            Button { navigation.open(experience: experience.id) } label: {
                VStack(alignment: .leading, spacing: 4) { Text(experience.title); Text("\(experience.framework) · \(experience.minimumOSVersion)").font(.footnote).foregroundStyle(.secondary) }
            }
        }.navigationTitle(query.isEmpty ? "Experiences" : "Search results")
    }
}
