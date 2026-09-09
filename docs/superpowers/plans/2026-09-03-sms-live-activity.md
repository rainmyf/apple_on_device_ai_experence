# SMS Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing `RunOnDeviceModelIntent` into a physical-device SMS automation that classifies an incoming message with Apple’s on-device Foundation Model and keeps one category-themed Live Activity visible until the user opens it.

**Architecture:** Shortcuts’ Message personal automation invokes `RunOnDeviceModelIntent`, which conforms to `LiveActivityIntent`. The intent starts one ActivityKit activity, calls a new five-category classifier using `SystemLanguageModel.default`/`LanguageModelSession`, then updates the same activity with a normalized Chinese summary. A WidgetKit extension renders the activity; the main app ends it when the activity URL is opened.

**Tech Stack:** Swift 6, iOS 27, SwiftUI, AppIntents, FoundationModels, ActivityKit, WidgetKit, Swift Testing. No server, APNs push, PCC, third-party model, database, or Simulator validation.

**Spec:** `docs/superpowers/specs/2026-09-03-sms-live-activity-design.md`

## Global Constraints

- Deployment target and all runtime validation: iOS 27.0 physical iPhone only.
- Do not use or download Simulator runtimes; do not report Simulator builds/tests as feature evidence.
- The only model path is `SystemLanguageModel.default` → `LanguageModelSession`; no cloud fallback.
- The five stable categories are `delivery`, `bank_repayment`, `train_waitlist_success`, `weather_alert`, and `ordinary`.
- Classification IDs are language-neutral; all generated summaries shown in the activity are Chinese.
- Model errors, missing Shortcut Input, invalid categories, and unavailable model status normalize to `ordinary` with summary `收到一条短信`; preserve a non-user-facing fallback reason for evidence.
- Maintain one ongoing activity and update it for later messages; tapping it opens the app and ends it. “Long-lived” is bounded by ActivityKit/system limits and authorization.

## Real Foundation Model Gate Before Live SMS Testing

The following fixtures are mandatory real-model inputs before any live SMS automation is attempted. `SMSIncomingClassificationService()` must call the physical device’s `SystemLanguageModel.default`; a deterministic recording activity manager may be used only to verify orchestration around the real classification result. A fake classifier is not an acceptance substitute.

| ID | Category | Expected activity payload |
| --- | --- | --- |
| `delivery-fengchao` | `delivery` | `取件码=85692800`; `取件地点=荣星东苑2幢与4幢东边丰巢柜1号柜` |
| `delivery-jd` | `delivery` | `取件码=8-3-6317`; `取件地点=铭城国际铭城便利店` |
| `train-beijing-shanghai` | `train_waitlist_success` | `北京南站→上海虹桥站`; `9月30日 09:20`; `10车2C、2F` |
| `train-changsha-xian` | `train_waitlist_success` | `长沙南站→西安北站`; `6月21日 14:05`; `12车6F` |
| `bank-citic` | `bank_repayment` | `银行=中信信用卡`; `欠款金额=2692.05元`; `最后还款日=06月29日` |
| `bank-minsheng` | `bank_repayment` | `银行=民生银行`; `欠款金额` 为空且不编造；`最后还款日=2025年01月16日17:00` |
| `ordinary-pinduoduo` | `ordinary` | 只显示一句中文摘要，不显示其他四类字段 |
| `weather-spb-wind-12` | `weather_alert` | `圣彼得堡8月12日预计风力达18米/秒，请注意安全` |
| `weather-spb-rain-19` | `weather_alert` | `圣彼得堡8月19日预计有强降雨，请注意安全` |
| `weather-spb-wind-19` | `weather_alert` | `圣彼得堡8月19日预计风力达18米/秒，请注意安全` |
| `weather-spb-rain-wind-23` | `weather_alert` | `圣彼得堡8月23日预计大雨、阵风达20米/秒，请注意安全` |

The Russian weather strings are taken from the supplied screenshot. The real-model gate proves actual multilingual classification and extraction; deterministic doubles remain limited to wiring tests.

### Exact Fixture Bodies

The implementation must store these exact bodies in the test fixture table; do not paraphrase or repair punctuation in the fixture input. The real-model test must send the body unchanged to the classifier.

```text
delivery-fengchao = 【丰巢】凭取件码85692800至荣星东苑2幢与4幢东边丰巢柜1号柜取件。快递员及畅存规则p.fcbox.com/vRACa
delivery-jd = 【京东配送】请凭8-3-6317到铭城国际铭城便利店领取运单尾号4211包裹，详询13484902114
train-beijing-shanghai = 【12306】候补订单已兑现成功，EH87720208，9月30日G117次10车2C、2F,北京南站（09:20开）至上海虹桥站，检票口9A、9B。12306.cn/g
train-changsha-xian = 【12306】候补订单已兑现成功，EG97299714,6月21日G842次12车6F，长沙南站（14:05开）至西安北站，检票口A5。请查收差价38.0元。(12306.cn/g)
bank-citic = 中信信用卡】您尾号3711的Huawei Card本期账单人民币2692.05元，还款到期06月29日。06月28日前回FQ+卡末四位可申请将2557.45元分6期还（您的信用卡额度会根据账单分期业务的办理结果而发生变化，具体请以您的实际额度展示为准），每期应还436.46元（含手续费10.22元），申请成功后本期仅需还人民币134.60元，最终以审批结果为准。
bank-minsheng = 【民生银行】尊敬的客户，您本期账单最后还款日已延期至2025年01月16日17:00前。请将本期账单应还款金额还入至您的信用卡账户中，如有外币账单请于宽限期内及时购汇，如有多个账户需分别还款。部分还款渠道非实时到账，建议您通过本行渠道实时还款，避免造成逾期。
ordinary-pinduoduo = 拼多多】请确认：2391亲，恭喜您被西安市选中有机会免单得华为P30！次日作废，请及时查收 y4n.cn/QZbRmdN 回TD退
weather-spb-wind-12 = Ветер до 18 м/с прогнозируется в Санкт-Петербурге 12 августа. Будьте внимательны и осторожны! Телефон вызова экстренных служб 112.
weather-spb-rain-19 = Сильный дождь, местами очень сильный прогнозируется в Санкт-Петербурге 19 августа. Телефон вызова экстренных служб 112.
weather-spb-wind-19 = Ветер до 18 м/с прогнозируется в Санкт-Петербурге 19 августа. Будьте внимательны и осторожны! Телефон вызова экстренных служб 112.
weather-spb-rain-wind-23 = Дожди, местами сильные, порывы ветра до 20 м/с прогнозируются в Санкт-Петербурге 23 августа. Телефон вызова экстренных служб 112.
```

### Real-Model Gate Requirement

Tasks 1–5 are not complete until all fixture IDs have been sent through the real Foundation Model on the connected iPhone and pass exact category assertions plus required-field assertions. If the model is unavailable, the test must fail with an explicit availability result; it must not be skipped or replaced with a fake result. Only after this gate passes may Task 6 configure Shortcuts and send live messages.

### Task 1: Add the five-category domain model and RED contract tests

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSIncomingClassification.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSIncomingClassificationTests.swift`
- Create: `AppleOnDeviceModelDemoTests/Resources/sms_live_activity_real_fixtures.jsonl`
- Create: `AppleOnDeviceModelDemoTests/SMSIncomingRealModelDeviceTests.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj` to add the Swift files to the test target and the JSONL resource to the test resources phase

**Interfaces:**
- `enum SMSIncomingCategory: String, CaseIterable, Codable, Hashable, Sendable` with raw IDs `delivery`, `bank_repayment`, `train_waitlist_success`, `weather_alert`, and `ordinary`.
- `struct SMSIncomingDetails: Codable, Equatable, Hashable, Sendable` with optional fields `pickupCode`, `pickupLocation`, `bankName`, `amountDue`, `dueDate`, `departureStation`, `arrivalStation`, `departureDateTime`, `seatInfo`, `weatherSummary`, and `ordinarySummary`.
- `struct SMSIncomingClassification: Codable, Equatable, Sendable` containing `category`, `details`, `source` (`model` or `fallback`), and optional `fallbackReason`.
- `SMSIncomingPresentation.from(rawCategory:details:source:fallbackReason:)` converts an arbitrary model category string into the enum and turns invalid/missing values into `ordinary` with `ordinarySummary == "收到一条短信"`.
- `SMSIncomingPresentation.normalized(_:)` keeps only fields allowed by the category and removes blank strings; it never fabricates a field.

- [ ] **Step 1: Write failing tests** for all five categories, category-specific field filtering, blank-field cleanup, invalid-category normalization, and fallback reason preservation.

```swift
@Test func categoryNormalizationDropsFieldsFromOtherCategories() {
    let value = SMSIncomingClassification(
        category: .delivery,
        details: SMSIncomingDetails(pickupCode: "A123", bankName: "不应显示"),
        source: .model,
        fallbackReason: nil
    )
    let normalized = SMSIncomingPresentation.normalized(value)
    #expect(normalized.details.pickupCode == "A123")
    #expect(normalized.details.bankName == nil)
}
```

- [ ] **Step 2: Run only the new physical-device test target** and confirm the tests fail because the types/normalizer do not exist.
- [ ] **Step 3: Implement the enums, details value type, source/fallback metadata, and pure normalizer.** Never store the full SMS body in the activity model.
- [ ] **Step 4: Run the same test selection on the connected iPhone and confirm PASS.**
- [ ] **Step 5: Commit** `test: define incoming SMS classification contract`.

The real-model fixture test must include the exact message bodies supplied by the user, including the malformed leading bracket in the CITIC sample and the four Russian weather samples from the screenshot. Test fixtures are identified by stable IDs rather than inferred from sender text.

### Task 2: Implement the language-agnostic Foundation Model classifier

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSIncomingClassificationService.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSIncomingClassificationServiceTests.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj` to add both files

**Interfaces:**
- `protocol SMSIncomingClassifying: Sendable { func classify(_ text: String) async throws -> SMSIncomingClassification }`.
- `protocol SMSIncomingModelSessionServing: Sendable { func respond(to prompt: String) async throws -> SMSIncomingGeneratedResult }` and `typealias SMSIncomingSessionFactory = @Sendable (SystemLanguageModel) -> any SMSIncomingModelSessionServing`.
- `@Generable struct SMSIncomingGeneratedResult` with a `.anyOf` guide over the five category IDs and optional String properties matching `SMSIncomingDetails`.
- `@MainActor final class SMSIncomingClassificationService: SMSIncomingClassifying` with `init(model: SystemLanguageModel = .default, sessionFactory: @escaping SMSIncomingSessionFactory)` and `func classify(_ text: String) async throws -> SMSIncomingClassification`; the default factory creates a `LanguageModelSession` adapter.
- `SMSIncomingClassificationPrompt.make(text:)` explicitly says the SMS may be Chinese, English, Russian, or another language; choose exactly one ID; emit only relevant fields; do not infer missing values; write summaries in concise Chinese.

The production prompt must preserve this decision order and wording intent (the implementer may only adjust formatting, not category semantics):

```text
你是短信分类器。短信可能是中文、英文、俄文或其他语言。请先理解原文，再严格选择一个 category：
delivery = 已有包裹/运单，需要取件码或取件地点；
bank_repayment = 银行或信用卡账单、欠款、最后还款日或还款提醒；
train_waitlist_success = 明确出现候补订单已兑现/候补成功，并包含铁路行程；
weather_alert = 极端天气、强风、暴雨、预警、危险提示或应急建议；
ordinary = 不满足以上条件的所有短信，包括营销、抽奖、验证码、聊天和普通通知。
天气判断要理解俄文风力/降雨表达，不能因为不是中文而归为 ordinary。
只输出 schema 字段；category 必须是允许值之一。只填写当前 category 的相关字段，找不到就留空，禁止猜测。
所有摘要用简洁中文。不得调用网络、云端模型或第三方服务。
原始短信：<SMS>
```

Category classification and detail extraction are two sequential real-model calls in one intent execution: the first response contains only the constrained category; the second prompt includes the chosen category and requests only its allowed fields. This prevents a second generation from changing the category after it has been accepted.

- [ ] **Step 1: Write failing prompt-contract tests** with a fake session that records the prompt and returns generated content. Assert the prompt contains all five IDs, the language rule, no-cloud rule, category definitions, the Russian-weather interpretation rule, and the field rules; assert the adapter maps generated output into `SMSIncomingClassification`.
- [ ] **Step 2: Add tests** for empty input, the existing `SystemLanguageModel.default.availability` gate, malformed generated content, and cancellation; assert no model call occurs when unavailable or empty.
- [ ] **Step 3: Run the contract tests on the connected iPhone and confirm RED.**
- [ ] **Step 4: Implement the `@Generable` schema and adapter using the current iOS 27 SDK’s real `LanguageModelSession.respond(to:generating:)` signature.** Construct the session per intent invocation; do not add streaming or network code.
- [ ] **Step 5: Normalize the adapter result through `SMSIncomingPresentation.normalized(_:)` and map all thrown errors to the caller; the intent owns fallback policy.
- [ ] **Step 6: Run the service contract tests on the connected iPhone and confirm PASS.**
- [ ] **Step 7: Run `SMSIncomingRealModelDeviceTests` against the connected iPhone with `SMSIncomingClassificationService()` and no fake session. Assert each fixture’s exact category and required fields; print one JSON evidence row per fixture containing input ID, extracted fields, latency, and availability. Do not accept a skipped test.
- [ ] **Step 8: Tune only the category Prompt, schema guides, and deterministic validator when a fixture fails; rerun the entire 11-row real-model suite after every change.
- [ ] **Step 9: Commit** `test: add real-device SMS classification fixtures`.

### Task 3: Add the shared ActivityKit state and coordinator

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSLiveActivityShared.swift` (compiled by both app and extension)
- Create: `AppleOnDeviceModelDemo/SMSLiveActivityCoordinator.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSLiveActivityTests.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj` to include shared/coordinator files and tests

**Interfaces:**
- `enum SMSLiveActivityPhase: String, Codable, Hashable, Sendable { case analyzing, classified }`.
- `struct SMSLiveActivityAttributes: ActivityAttributes` with stable `activityID: UUID` and `ContentState` containing `phase`, `category`, `title`, `summary`, `details`, `source`, `updatedAt`.
- `protocol SMSLiveActivityManaging: Sendable` with `startAnalyzing(sender:) async`, `update(_ state:) async`, and `endActive() async`.
- `actor SMSLiveActivityCoordinator: SMSLiveActivityManaging` with `init(store:)`; ActivityKit authorization/request/update failures are captured as diagnostics and never thrown through the Intent. `activeActivityID() async -> UUID?` is used for inspection.
- `SMSLiveActivityTheme` pure mapping from category to Chinese title, SF Symbol name, and color token; the Widget maps the token to SwiftUI `Color`.

- [ ] **Step 1: Write failing tests** for analyzing → classified transitions, one-activity replacement/update behavior, five theme mappings, and end-after-click behavior using a fake `SMSLiveActivityManaging`/Activity store.
- [ ] **Step 2: Add tests** for Activity authorization denied, request/update errors, and multiple incoming calls; assert the coordinator never creates more than one active activity in its store.
- [ ] **Step 3: Run the tests on the connected iPhone and confirm RED.**
- [ ] **Step 4: Implement the shared Codable/Hashable state and coordinator using `Activity.request`/`update` with the iOS 27 standard style.** Do not use ActivityKit push notifications.
- [ ] **Step 5: Implement `widgetURL` value `appleondevicemodeldemo://sms-live-activity` in the extension-facing state/view contract and an `endActive()` path for that URL.
- [ ] **Step 6: Run the coordinator tests on the connected iPhone and confirm PASS.**
- [ ] **Step 7: Commit** `feat: add single persistent SMS Live Activity coordinator`.

### Task 4: Replace the current AppIntent behavior and register the SMS automation action

**Files:**
- Modify: `AppleOnDeviceModelDemo/ExperienceAppIntents.swift`
- Modify: `AppleOnDeviceModelDemo/AppleOnDeviceModelDemoApp.swift`
- Modify: `AppleOnDeviceModelDemoTests/ExperienceAppIntentsTests.swift`

**Interfaces:**
- `RunOnDeviceModelIntent` becomes `AppIntent, LiveActivityIntent` with `@Parameter(title: "短信正文") var text: String` and optional `@Parameter(title: "发件人") var sender: String?`.
- Add injectable static entry point `RunOnDeviceModelIntent.execute(text:sender:classifier:activity:) async -> SMSIncomingClassification` for deterministic tests; production defaults are `SMSIncomingClassificationService()` and `SMSLiveActivityCoordinator()` conforming to `SMSIncomingClassifying`/`SMSLiveActivityManaging`.
- `perform()` starts analyzing, classifies, catches classifier errors into the ordinary fallback, updates the activity, and returns `ReturnsValue<String>` containing the category raw ID; only cancellation may escape as an Intent error.
- `AppleOnDeviceModelDemoShortcuts.appShortcuts` exposes the renamed action text “收到短信并分类” while keeping the existing provider type. The old open-ended `FoundationModelService` action is no longer registered as the shortcut action, though its service/code remains available for other pages.

- [ ] **Step 1: Update tests first.** Replace the old generic-response expectation with call-order tests: `startAnalyzing` → classifier → `update`; assert the returned ID and all five category outputs.
- [ ] **Step 2: Add tests** for missing text, model unavailable/error, invalid raw category, missing sender, and cancellation; assert each produces ordinary fallback and still attempts the analyzing activity when authorized.
- [ ] **Step 3: Add a contract test** that the shortcut provider contains the SMS action and no longer claims the old generic phrase.
- [ ] **Step 4: Run the AppIntent tests on the connected iPhone and confirm RED.**
- [ ] **Step 5: Implement the new parameters, dependency injection, `LiveActivityIntent` conformance, and fallback handling.** Do not read Messages data directly and do not log the message body.
- [ ] **Step 6: Add `.onOpenURL` handling in `AppleOnDeviceModelDemoApp` for `appleondevicemodeldemo://sms-live-activity`, calling `endActive()` and retaining the latest result in app state.
- [ ] **Step 7: Run the AppIntent tests on the connected iPhone and confirm PASS.**
- [ ] **Step 8: Commit** `feat: trigger SMS classification from LiveActivityIntent`.

- [ ] **Deterministic orchestration check:** Keep a table-driven test over all 11 fixture IDs with a fake classifier and recording activity manager to prove each result causes one `startAnalyzing` and one `update`, renders only allowed fields, and leaves no full SMS body in the activity payload. This test checks wiring only; the real-model gate in Task 2 is the acceptance gate.

### Task 5: Add the WidgetKit Live Activity extension and app capabilities

**Files:**
- Create: `AppleOnDeviceModelDemoLiveActivity/SMSLiveActivityWidget.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj` to add the Widget Extension target, embed it in the app, and compile `SMSLiveActivityShared.swift` in both targets
- Modify: app target build settings to set `INFOPLIST_KEY_NSSupportsLiveActivities = YES`

**Interfaces:**
- `struct SMSLiveActivityWidget: Widget` registers `ActivityConfiguration(for: SMSLiveActivityAttributes.self)`.
- Lock Screen and Dynamic Island layouts render only `SMSLiveActivityAttributes.ContentState`; choose the five themes through `SMSLiveActivityTheme`; show category-specific fields in the exact priority supplied by the user.
- The view sets `widgetURL(URL(string: "appleondevicemodeldemo://sms-live-activity"))` and does not expose the complete SMS body.

- [ ] **Step 1: Write pure rendering tests** for each category’s title, symbol, color token, and field priority; assert empty fields are omitted and ordinary shows exactly one sentence.
- [ ] **Step 2: Add the Widget Extension target at iOS 27.0 with the app’s team/signing settings and required ActivityKit/WidgetKit imports.**
- [ ] **Step 3: Implement compact, expanded, and Lock Screen layouts with the shared state.
- [ ] **Step 4: Build the app and extension for the connected iPhone destination only; fix signing/embedding errors until the physical-device build succeeds.
- [ ] **Step 5: Run the rendering and target integration tests on the connected iPhone and confirm PASS.
- [ ] **Step 6: Commit** `feat: render SMS categories in Live Activity widget`.

### Task 6: Execute the physical-device Shortcuts and SMS acceptance matrix

**Files:**
- Create: `docs/device-test/2026-09-03-sms-live-activity-test-plan.md`
- Create: `docs/superpowers/evidence/2026-09-03-sms-live-activity-evidence.md`
- No Simulator files, runtime downloads, or code changes are allowed in this task.

- [ ] **Step 1: Install the signed Debug app and Widget Extension on the connected iPhone running iOS 27; open the app once and enable Live Activities.
- [ ] **Step 2: In Shortcuts, create a personal automation: Message received → choose the test sender or a unique marker → Run Immediately/disable Ask Before Running → action “收到短信并分类”. Map Shortcut Input to `短信正文` if iOS exposes that variable; record whether the mapping exists.
- [ ] **Step 3: Send five messages from the second phone, one at a time, and record evidence:
  - delivery: a Chinese courier message containing a pickup code and location;
  - bank repayment: an English or Chinese bank reminder containing bank, amount, and due date;
  - train waitlist success: a Chinese/English ticket confirmation containing origin, destination, time, and seat;
  - weather alert: a non-Chinese extreme-weather warning containing region and warning/advice;
  - ordinary: a conversational message.
- [ ] **Step 4: For each message, verify the shortcut ran without opening the app, the activity first showed “分析中”, then showed the expected theme and fields, and the activity remained until tapped.
- [ ] **Step 5: Tap the activity, verify the app opens and the activity ends; send a second message and verify the same activity is updated rather than duplicated.
- [ ] **Step 6: Repeat with Apple Intelligence unavailable or Shortcut Input empty; verify ordinary fallback and the recorded fallback reason. Restore settings afterward.
- [ ] **Step 7: If full SMS正文 mapping is unavailable, record that limitation explicitly; do not claim arbitrary-message classification is proven. If available, record the exact mapping and the five real outputs.
- [ ] **Step 8: Run the complete physical-device test suite and attach build/test logs, screenshots, and the evidence record. Commit only the test plan/evidence documents if they are part of the requested deliverable.

## Acceptance Criteria

- A user-configured Message personal automation invokes the modified AppIntent automatically on the connected iPhone.
- The AppIntent starts a Live Activity in the background without opening the app, calls only the on-device Foundation Model, and updates one activity with a category-specific Chinese summary.
- All five categories and their requested priority fields render correctly for real SMS samples, including at least one non-Chinese message.
- The activity remains visible until the user taps it, then opens the app and ends cleanly; later SMS updates the same activity.
- Model unavailability, missing input, malformed output, cancellation, and authorization failures do not crash the app and normalize to ordinary fallback.
- Evidence distinguishes SDK/API validity, physical-device build/test, Shortcut automation execution, Live Activity rendering, and what remains unproven about SMS正文 delivery or Siri.
