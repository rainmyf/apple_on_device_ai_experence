import AppIntents
import Testing
@testable import AppleOnDeviceModelDemo

@Suite(.serialized)
@MainActor
struct ExperienceAppIntentsTests {
    @Test
    func defaultQueryReturnsTheCompleteVisibleCatalog() async throws {
        let entities = try await ExperienceEntityQuery().suggestedEntities()

        #expect(entities.count == ExperienceID.allCases.count)
        #expect(entities.map(\.experienceID) == ExperienceCatalog.all.map(\.id))
    }

    @Test
    func stringQueryMatchesTitleFrameworkAndAPI() async throws {
        let query = ExperienceEntityQuery()

        let vision = try await query.entities(matching: "vision")
        let foundation = try await query.entities(matching: "SystemLanguageModel.default")

        #expect(vision.map(\.experienceID) == [.vision])
        #expect(foundation.map(\.experienceID) == [.foundationModel])
    }

    @Test
    func identifierQueryResolvesVisibleEntities() async throws {
        let query = ExperienceEntityQuery()
        let entities = try await query.entities(for: ["vision", "missing"])

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
    func searchableItemsIncludeAllVisibleEntities() {
        let items = ExperienceIndexing.searchableItems()

        #expect(items.count == ExperienceID.allCases.count)
        #expect(items.allSatisfy { $0.attributeSet.domainIdentifier == ExperienceIndexing.domainIdentifier })
    }

    @Test
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

    @Test
    func smsAppIntentKeepsTheCurrentClassifierAndShortcutContract() {
        #expect(RunOnDeviceModelIntent.title == "收到短信并分类")
        #expect(AppleOnDeviceModelDemoShortcuts.appShortcuts.count == 1)
        #expect(RunOnDeviceModelShortcut.metadata.usesFoundationModel)
        #expect(RunOnDeviceModelShortcut.metadata.allowsCloudFallback == false)
    }

    @Test
    func smsAppIntentConnectsClassifierToLiveActivity() async throws {
        let suiteName = "SMSAppIntentIsolationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let classifier = IntentFakeClassifier()
        let activity = IntentFakeActivity()
        let history = SMSAppIntentHistoryStore(defaults: defaults)
        let result = try await RunOnDeviceModelIntent.execute(
            text: "快递短信",
            sender: "丰巢",
            classifier: classifier,
            activity: activity,
            history: history
        )
        #expect(result.category == .delivery)
        #expect(await classifier.inputs == ["快递短信"])
        #expect(await activity.states.count == 1)
        #expect(await activity.states.first?.category == .delivery)
        #expect(await activity.startedSenders.isEmpty)
        #expect(history.entries.map(\.text) == ["快递短信"])
    }

    @Test
    func smsAppIntentRecordsOnlyRealSMSInvocationsInLocalHistory() async throws {
        let suiteName = "SMSAppIntentHistoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = SMSAppIntentHistoryStore(defaults: defaults)
        let classifier = IntentFakeClassifier()
        let activity = IntentFakeActivity()

        _ = try await RunOnDeviceModelIntent.execute(
            text: "【丰巢】请凭85692800至荣星东苑丰巢柜取件",
            classifier: classifier,
            activity: activity,
            history: history
        )
        _ = try await RunOnDeviceModelIntent.execute(
            text: "   ",
            classifier: classifier,
            activity: activity,
            history: history
        )

        #expect(history.entries.count == 1)
        #expect(history.entries.first?.text == "【丰巢】请凭85692800至荣星东苑丰巢柜取件")
        #expect(history.entries.first?.title == "快递提醒")
        #expect(history.entries.first?.summary.contains("1234") == true)
    }

    @Test
    func classifiedSMSMapsToTheSameLiveActivityStateShownToTheUser() {
        let result = SMSIncomingClassification(
            category: .bankRepayment,
            details: SMSIncomingDetails(bankName: "中信信用卡", amountDue: "2692.05 元", dueDate: "06 月 29 日"),
            source: .model
        )

        let state = RunOnDeviceModelIntent.liveActivityState(for: result)

        #expect(state.category == .bankRepayment)
        #expect(state.title == "还款提醒")
        #expect(state.summary.contains("2692.05 元"))
        #expect(state.primaryDetail == nil)
        #expect(state.secondaryDetail == nil)
    }

    @Test
    func liveActivityUsesReadableCategorySpecificSummaries() {
        let cases: [(SMSIncomingClassification, String, String)] = [
            (
                SMSIncomingClassification(category: .delivery, details: SMSIncomingDetails(pickupCode: "85692800", pickupLocation: "荣星东苑丰巢柜"), source: .model),
                "快递提醒",
                "取件码：85692800 · 取件地点：荣星东苑丰巢柜"
            ),
            (
                SMSIncomingClassification(category: .trainWaitlistSuccess, details: SMSIncomingDetails(departureStation: "北京南", arrivalStation: "上海虹桥", departureDateTime: "9月30日 09:20", seatInfo: "10车2C"), source: .model),
                "候补成功",
                "北京南→上海虹桥 · 9月30日 09:20 · 座位：10车2C"
            ),
            (
                SMSIncomingClassification(category: .bankRepayment, details: SMSIncomingDetails(bankName: "中信银行", amountDue: "2692.05元", dueDate: "6月29日"), source: .model),
                "还款提醒",
                "中信银行 · 应还：2692.05元 · 最后还款：6月29日"
            ),
            (
                SMSIncomingClassification(category: .weatherAlert, details: SMSIncomingDetails(weatherSummary: "圣彼得堡明日阵风最高18米/秒"), source: .model),
                "极端天气提醒",
                "圣彼得堡明日阵风最高18米/秒"
            ),
            (
                SMSIncomingClassification(category: .ordinary, details: SMSIncomingDetails(ordinarySummary: "收到一条活动通知，请留意链接安全"), source: .model),
                "短信通知",
                "收到一条活动通知，请留意链接安全"
            )
        ]

        for (result, expectedTitle, expectedSummary) in cases {
            let state = RunOnDeviceModelIntent.liveActivityState(for: result)
            #expect(state.title == expectedTitle)
            #expect(state.summary == expectedSummary)
        }
    }
}

private actor IntentFakeClassifier: SMSIncomingClassifying {
    private(set) var inputs: [String] = []
    func classify(_ text: String) async throws -> SMSIncomingClassification {
        inputs.append(text)
        return SMSIncomingClassification(category: .delivery, details: SMSIncomingDetails(pickupCode: "1234"), source: .model)
    }
}

private actor IntentFakeActivity: DemoLiveActivityManaging {
    private(set) var startedSenders: [String?] = []
    private(set) var states: [DemoLiveActivityAttributes.ContentState] = []
    func startAnalyzing(sender: String?) async { startedSenders.append(sender) }
    func update(_ state: DemoLiveActivityAttributes.ContentState) async { states.append(state) }
    func endActive() async {}
}
