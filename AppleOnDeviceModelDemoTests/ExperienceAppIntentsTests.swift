import AppIntents
import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

@Suite(.serialized)
@MainActor
struct ExperienceAppIntentsTests {
    @Test
    func defaultQueryReturnsVisibleCatalogOnly() async throws {
        let entities = try await ExperienceEntityQuery().suggestedEntities()

        #expect(entities.count == ExperienceID.allCases.count - 1)
        #expect(entities.allSatisfy { $0.experienceID != .smsClassification })
        #expect(entities.map(\.experienceID) == ExperienceCatalog.all.filter { $0.id != .smsClassification }.map(\.id))
    }

    @Test
    func stringQueryMatchesTitleFrameworkAndAPIWithoutExposingSMS() async throws {
        let query = ExperienceEntityQuery()

        let vision = try await query.entities(matching: "vision")
        let foundation = try await query.entities(matching: "SystemLanguageModel.default")
        let sms = try await query.entities(matching: "SMS Classification")

        #expect(vision.map(\.experienceID) == [.vision])
        #expect(foundation.map(\.experienceID) == [.foundationModel])
        #expect(sms.isEmpty)
    }

    @Test
    func identifierQueryResolvesOnlyVisibleEntities() async throws {
        let query = ExperienceEntityQuery()
        let entities = try await query.entities(for: ["vision", "smsClassification", "missing"])

        #expect(entities.map(\.experienceID) == [.vision])
    }

    @Test
    func searchableEntityCarriesRouteAndSpotlightMetadata() {
        let entity = ExperienceEntity(definition: ExperienceCatalog[.vision])

        #expect(entity.experienceID == .vision)
        #expect(entity.route == .experience(.vision))
        #expect(entity.hideInSpotlight == false)
        #expect(entity.attributeSet.title == "Vision")
        #expect(entity.attributeSet.contentDescription?.contains("Vision") == true)
    }

    @Test
    func searchableItemsExcludeHiddenSMSAndAssociateVisibleEntities() {
        let items = ExperienceIndexing.searchableItems()

        #expect(items.count == ExperienceID.allCases.count - 1)
        #expect(items.allSatisfy { !$0.uniqueIdentifier.contains("smsClassification") })
        #expect(items.allSatisfy { $0.attributeSet.domainIdentifier == ExperienceIndexing.domainIdentifier })
    }

    @Test(.serialized)
    @MainActor
    func searchIntentRoutesTheSharedNavigationState() async throws {
        AppNavigationState.shared.reset()
        let intent = SearchExperiencesIntent(criteria: StringSearchCriteria(term: "vision"))

        _ = try await intent.perform()

        #expect(AppNavigationState.shared.path == [.search("vision")])
    }

    @Test
    func openIntentResolvesVisibleExperienceRoute() {
        let entity = ExperienceEntity(definition: ExperienceCatalog[.vision])

        #expect(entity.route == .experience(.vision))
    }

    @Test(.serialized)
    @MainActor
    func openIntentRejectsHiddenSMSEvenWhenConstructedDirectly() async throws {
        AppNavigationState.shared.reset()
        let hidden = ExperienceEntity(definition: ExperienceCatalog[.smsClassification])
        let intent = OpenExperienceIntent(target: hidden)

        _ = try await intent.perform()

        #expect(AppNavigationState.shared.path.isEmpty)
    }

    @Test
    func runOnDeviceModelIntentReusesTheAppFoundationModelService() async throws {
        let model = SystemLanguageModel.default
        let fakeService = FoundationModelService(
            model: model,
            availabilityProvider: { _ in .available },
            sessionFactory: { _ in
                TestFoundationLanguageModelSession(response: "native result")
            }
        )

        let result = try await RunOnDeviceModelIntent.execute(text: "hello", service: fakeService)

        #expect(result == "native result")
    }

    @Test
    func shortcutMetadataNamesTheOpenEndedOnDeviceAction() {
        #expect(RunOnDeviceModelShortcut.metadata.title == "运行端侧模型")
        #expect(RunOnDeviceModelShortcut.metadata.phrase.contains("运行端侧模型"))
        #expect(RunOnDeviceModelShortcut.metadata.usesFoundationModel == true)
        #expect(RunOnDeviceModelShortcut.metadata.allowsCloudFallback == false)
    }

    @Test
    func appShortcutProviderRegistersTheOnDeviceModelIntent() {
        let shortcuts = AppleOnDeviceModelDemoShortcuts.appShortcuts

        #expect(shortcuts.count == 1)
    }
}

private final class TestFoundationLanguageModelSession: FoundationLanguageModelSessionServing, @unchecked Sendable {
    let response: String

    init(response: String) {
        self.response = response
    }

    func respond(to prompt: String) async throws -> String { response }

    func analyze(to prompt: String) async throws -> GuidedTextAnalysis {
        fatalError("not used")
    }

    func tag(to prompt: String) async throws -> ContentTags {
        fatalError("not used")
    }
}
