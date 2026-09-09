import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

@Suite(.serialized)
struct DemoLiveActivityTests {
    @Test
    func eachDemoCategoryHasUniqueIconAndDisplayTitle() {
        let categories = DemoLiveActivityCategory.allCases
        let themes = categories.map(DemoLiveActivityTheme.theme(for:))

        #expect(categories.count == 5)
        #expect(themes.allSatisfy { !$0.symbolName.isEmpty && !$0.title.isEmpty })
        #expect(Set(themes.map(\.symbolName)).count == categories.count)
    }

    @Test
    func flowPublishesOnlyTheFinalClassifiedState() async throws {
        let activity = RecordingDemoLiveActivityManager()

        let result = try await SystemIntelligenceToAppDemoFlow.run(
            category: .delivery,
            summary: "取件码 85692800",
            activity: activity
        )

        #expect(result.category == .delivery)
        #expect(await activity.phases == [.classified])
        #expect(await activity.lastState?.category == .delivery)
        #expect(await activity.lastState?.summary == "取件码 85692800")
    }

    @Test
    func demoContentStateRoundTripsThroughActivityPayload() throws {
        let state = DemoLiveActivityContentBuilder.classified(
            category: .weatherAlert,
            summary: "大风预警"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DemoLiveActivityAttributes.ContentState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.category == .weatherAlert)
    }

    @Test
    func fixtureStateBuildsNaturalSummaryForEveryCategory() {
        for category in DemoLiveActivityCategory.allCases {
            let state = DemoLiveActivityContentBuilder.fixture(for: category)
            #expect(state.phase == .classified)
            #expect(!state.summary.isEmpty)
            #expect(state.summary.count > 6)
            #expect(!state.title.isEmpty)
        }
    }

    @Test
    func compactPresentationIncludesTheFinalTitleAndCompleteSummary() {
        let state = DemoLiveActivityContentBuilder.classified(
            category: .delivery,
            summary: "取件码：85692800 · 取件地点：荣星东苑丰巢柜"
        )

        #expect(state.compactPresentationText == "快递提醒 · 取件码：85692800 · 取件地点：荣星东苑丰巢柜")
    }

    @Test
    func newlyCreatedPresentationKeepsTheFinalContentWhileMarkingTheActivityAsAnalyzing() {
        let final = DemoLiveActivityContentBuilder.classified(
            category: .trainWaitlistSuccess,
            summary: "北京南→上海虹桥 · 9月30日 09:20 · 座位：10车2C",
            primaryDetail: "候补订单已兑现"
        )

        let initial = DemoLiveActivityContentBuilder.newlyCreatedPresentation(for: final)

        #expect(initial.phase == .analyzing)
        #expect(initial.category == final.category)
        #expect(initial.title == final.title)
        #expect(initial.summary == final.summary)
        #expect(initial.primaryDetail == final.primaryDetail)
    }
}

private actor RecordingDemoLiveActivityManager: DemoLiveActivityManaging {
    private(set) var phases: [DemoLiveActivityPhase] = []
    private(set) var lastState: DemoLiveActivityAttributes.ContentState?

    func startAnalyzing(sender: String?) async {
        phases.append(.analyzing)
    }

    func update(_ state: DemoLiveActivityAttributes.ContentState) async {
        phases.append(.classified)
        lastState = state
    }

    func endActive() async {}
}
