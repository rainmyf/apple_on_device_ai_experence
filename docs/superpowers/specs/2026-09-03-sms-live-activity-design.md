# 短信自动分类实况窗设计

## 目标

在 iOS 27 真机上验证一条完整的本地自动化链路：收到短信后，系统快捷指令个人自动化自动调用现有 AppIntent；AppIntent 在后台使用 Apple Foundation Model 对短信做五分类和关键信息摘要；ActivityKit 在锁屏和灵动岛显示一个长期实况窗。原型不读取短信数据库、不使用云端、不向 Android 发送数据。

## 已确认的产品行为

- 五个模型分类：`delivery`（快递）、`bank_repayment`（银行还款提醒）、`train_waitlist_success`（火车票候补成功）、`weather_alert`（天气预警）、`ordinary`（普通短信）。
- 短信可为任意语言；分类 ID 是稳定的内部枚举，实况窗摘要统一使用中文。
- 快递显示取件码、取件地点；银行还款显示银行、欠款金额、最后还款日期；火车候补成功显示始发站、终点站、乘车时间、车座信息；天气预警显示关键极端天气摘要；普通短信显示一句话摘要。
- 使用一个 ActivityKit 活动模型切换五种主题，不维护五个独立活动类型。
- 只维护一个活动；新短信更新该活动，避免灵动岛堆积多个活动。
- 活动启动后持续显示，用户点击后进入 App，App 结束活动并保留最近一次结果。系统仍可能因权限、资源、生命周期或数量限制结束活动；“长期”不承诺无限期。
- Foundation Model 不可用、正文为空、正文未从快捷指令传入、模型输出非法或模型调用失败时，活动按 `ordinary` 主题显示安全兜底摘要“收到一条短信”，并记录 `fallback` 原因；不得捏造字段。

## 架构与数据流

```text
Messages 通信触发器（Shortcuts Personal Automation）
        ↓ 运行时传入 Shortcut Input / 发件人
RunOnDeviceModelIntent: AppIntent, LiveActivityIntent
        ↓ 先启动“分析中”单活动
SMSIncomingClassificationService
        ↓ LanguageModelSession.respond(to:generating:)
SMSIncomingClassificationResult（固定五类 + 类别字段）
        ↓ 规范化、缺失字段清理、fallback
SMSLiveActivityCoordinator
        ↓ Activity.request / update
Widget Extension（锁屏、灵动岛）
```

短信触发不是 App 监听：用户必须在快捷指令中手动创建一次“收到信息”个人自动化并选择立即运行。AppIntent 接收正文的能力必须在真机上验证；Apple 公开通信触发器文档确认 Sender 和 Message Contains 过滤条件，但没有承诺完整正文一定作为 AppIntent 参数提供。因此正文缺失是受控失败路径，而不是静态假设。

## 接口边界

### AppIntent

将现有 `RunOnDeviceModelIntent` 的语义改为短信分类动作，保留其类型名以减少 Shortcut 重新发现成本：

```swift
@available(iOS 27.0, *)
struct RunOnDeviceModelIntent: AppIntent, LiveActivityIntent {
    @Parameter(title: "短信正文") var text: String
    @Parameter(title: "发件人") var sender: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String>
}
```

`perform()` 必须先请求/更新唯一活动为 `analyzing`，再调用分类服务；成功后更新 `classified`，返回稳定分类 ID 供快捷指令记录。活动权限/ActivityKit 错误不能阻止分类结果返回；它们只写入调试状态。原有开放式文本服务代码可以保留在 `FoundationModelService`，但不再作为该 Intent 的业务路径。

### 分类模型

新增 `SMSIncomingCategory` 和 `SMSIncomingClassificationResult`。结果 schema 用 `@Generable`，分类字段用 `.anyOf` 限定五个稳定 ID；类别专属字段用可选字符串，模型提示词要求只填当前类别相关字段、缺失即空值、不猜测。分类器通过 `LanguageModelSession` 和 `SystemLanguageModel.default`，不提供第三方或云端 fallback。

### 实况活动

共享类型 `SMSLiveActivityAttributes` 只包含 Codable/Hashable/Sendable 数据：活动 ID、阶段、分类、中文标题、中文摘要、类别字段、时间戳、`source`（`model`/`fallback`）。Widget Extension 根据分类映射 SF Symbol、颜色和字段布局；任何完整短信正文都不写入 Activity 状态，避免锁屏泄露和 4KB 更新限制。

`SMSLiveActivityCoordinator` 负责查找并更新唯一活动、处理授权失败、结束活动和点击回调。对外暴露的协调方法不因 ActivityKit 权限/更新失败抛错，保证 Intent 仍能完成本地分类；活动使用 iOS 27 的 `Activity.request(attributes:content:pushType:style:)`，`pushType` 为 `nil`、`style` 为 `.standard`，不使用 APNs push；点击通过 `widgetURL` 打开 App，App 收到 URL 后结束活动。

## 错误和隐私

- `ActivityAuthorizationInfo` 未允许活动：不崩溃，记录错误并让 Intent 返回普通结果。
- Foundation Model 状态不是 available：不调用模型，显示 ordinary fallback。
- Shortcut Input 没有正文：显示 ordinary fallback“收到一条短信”，并在 App 的调试区域记录 `missingShortcutInput`。
- 模型超时、取消、schema 解码失败或非法类别：显示 ordinary fallback，并记录具体原因。
- 所有日志只记录分类 ID、阶段、耗时和 fallback 原因；不打印短信全文。
- 不使用 SFSpeechRecognizer、云 API、APNs 服务器、PCC、数据库或 Android 传输。

## 验收证据

只接受连接的 iOS 27 真机证据：设备型号/iOS/Xcode/App commit、快捷指令配置、活动授权状态、模型 availability、输入语言、模型分类、字段、活动出现位置、耗时、fallback 原因和点击结束结果。禁止以 Simulator 构建或测试替代真机链路证据。

官方边界参考：[LiveActivityIntent](https://developer.apple.com/documentation/AppIntents/LiveActivityIntent?changes=latest_b_3&language=objc)、[Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities?changes=_2)、[Shortcuts communication triggers](https://support.apple.com/guide/shortcuts/communication-triggers-apdd711f9dff/ios)。
