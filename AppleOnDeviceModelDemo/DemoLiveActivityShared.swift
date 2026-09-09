import ActivityKit
import Foundation

enum DemoLiveActivityCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case delivery
    case bankRepayment
    case trainWaitlistSuccess
    case weatherAlert
    case ordinary

    var id: String { rawValue }
}

enum DemoLiveActivityPhase: String, Codable, Hashable, Sendable {
    case analyzing
    case classified
}

struct DemoLiveActivityAttributes: ActivityAttributes {
    let activityID: UUID

    struct ContentState: Codable, Hashable, Sendable {
        let phase: DemoLiveActivityPhase
        let category: DemoLiveActivityCategory
        let title: String
        let summary: String
        let primaryDetail: String?
        let secondaryDetail: String?
        let updatedAt: Date
    }
}

extension DemoLiveActivityAttributes.ContentState {
    /// The compact Dynamic Island receives the final title followed by the
    /// complete classifier summary. WidgetKit owns its on-screen treatment.
    var compactPresentationText: String {
        "\(title) · \(summary)"
    }
}

struct DemoLiveActivityTheme: Equatable, Sendable {
    let title: String
    let symbolName: String
    let colorToken: String

    static func theme(for category: DemoLiveActivityCategory) -> Self {
        switch category {
        case .delivery:
            Self(title: "快递提醒", symbolName: "shippingbox.fill", colorToken: "orange")
        case .bankRepayment:
            Self(title: "还款提醒", symbolName: "creditcard.fill", colorToken: "blue")
        case .trainWaitlistSuccess:
            Self(title: "候补成功", symbolName: "train.side.front.car", colorToken: "red")
        case .weatherAlert:
            Self(title: "极端天气提醒", symbolName: "cloud.heavyrain.fill", colorToken: "purple")
        case .ordinary:
            Self(title: "短信通知", symbolName: "bell.fill", colorToken: "gray")
        }
    }
}

enum DemoLiveActivityContentBuilder {
    static func analyzing(sender: String?) -> DemoLiveActivityAttributes.ContentState {
        DemoLiveActivityAttributes.ContentState(
            phase: .analyzing,
            category: .ordinary,
            title: "正在准备实况窗",
            summary: sender.map { "来自\($0)的演示通知" } ?? "收到一条演示通知",
            primaryDetail: nil,
            secondaryDetail: nil,
            updatedAt: Date()
        )
    }

    static func classified(
        category: DemoLiveActivityCategory,
        summary: String,
        primaryDetail: String? = nil,
        secondaryDetail: String? = nil
    ) -> DemoLiveActivityAttributes.ContentState {
        let theme = DemoLiveActivityTheme.theme(for: category)
        return DemoLiveActivityAttributes.ContentState(
            phase: .classified,
            category: category,
            title: theme.title,
            summary: summary,
            primaryDetail: primaryDetail,
            secondaryDetail: secondaryDetail,
            updatedAt: Date()
        )
    }

    /// A newly requested Activity should carry the completed on-device result
    /// immediately, while its phase still describes the short presentation
    /// transition from a fresh Activity to a settled one.
    static func newlyCreatedPresentation(
        for classifiedState: DemoLiveActivityAttributes.ContentState
    ) -> DemoLiveActivityAttributes.ContentState {
        DemoLiveActivityAttributes.ContentState(
            phase: .analyzing,
            category: classifiedState.category,
            title: classifiedState.title,
            summary: classifiedState.summary,
            primaryDetail: classifiedState.primaryDetail,
            secondaryDetail: classifiedState.secondaryDetail,
            updatedAt: Date()
        )
    }

    /// Deterministic, human-readable samples used by the on-device demo page.
    static func fixture(for category: DemoLiveActivityCategory) -> DemoLiveActivityAttributes.ContentState {
        switch category {
        case .delivery:
            return classified(category: category, summary: "你的快递已送达荣星东苑丰巢柜，请凭 85692800 取件", primaryDetail: "取件地点：2 幢与 4 幢东边 1 号柜")
        case .bankRepayment:
            return classified(category: category, summary: "中信信用卡本期应还 2692.05 元，还款截止 06 月 29 日", primaryDetail: "尾号 3711 · Huawei Card")
        case .trainWaitlistSuccess:
            return classified(category: category, summary: "候补购票已兑现：北京南开往上海虹桥，09 月 30 日 09:20 出发", primaryDetail: "G117 次 · 10 车 2C、2F")
        case .weatherAlert:
            return classified(category: category, summary: "天气预警：圣彼得堡将出现强降雨，局部地区雨势较强", primaryDetail: "请注意出行安全 · 紧急电话 112")
        case .ordinary:
            return classified(category: category, summary: "拼多多发送了一条限时免单活动通知", primaryDetail: "请谨慎识别陌生链接")
        }
    }
}

protocol DemoLiveActivityManaging: Sendable {
    func startAnalyzing(sender: String?) async
    func update(_ state: DemoLiveActivityAttributes.ContentState) async
    func endActive() async
}

enum SystemIntelligenceToAppDemoFlow {
    static func run(
        category: DemoLiveActivityCategory,
        summary: String,
        primaryDetail: String? = nil,
        secondaryDetail: String? = nil,
        sender: String? = nil,
        activity: any DemoLiveActivityManaging
    ) async throws -> DemoLiveActivityAttributes.ContentState {
        try Task.checkCancellation()
        let state = DemoLiveActivityContentBuilder.classified(
            category: category,
            summary: summary,
            primaryDetail: primaryDetail,
            secondaryDetail: secondaryDetail
        )
        await activity.update(state)
        return state
    }
}
