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

### Task 1: Add the five-category domain model and RED contract tests

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSIncomingClassification.swift`
- Create: `AppleOnDeviceModelDemoTests/SMSIncomingClassificationTests.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj` to add both files to their existing targets

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

- [ ] **Step 1: Write failing tests** with a fake session that records the prompt and returns generated content. Assert the prompt contains all five IDs, the language rule, no-cloud rule, and the field rules; assert the adapter maps generated output into `SMSIncomingClassification`.
- [ ] **Step 2: Add tests** for empty input, the existing `SystemLanguageModel.default.availability` gate, malformed generated content, and cancellation; assert no model call occurs when unavailable or empty.
- [ ] **Step 3: Run the tests on the connected iPhone and confirm RED.**
- [ ] **Step 4: Implement the `@Generable` schema and adapter using the current iOS 27 SDK’s real `LanguageModelSession.respond(to:generating:)` signature.** Construct the session per intent invocation; do not add streaming or network code.
- [ ] **Step 5: Normalize the adapter result through `SMSIncomingPresentation.normalized(_:)` and map all thrown errors to the caller; the intent owns fallback policy.
- [ ] **Step 6: Run the service tests on the connected iPhone and confirm PASS.**
- [ ] **Step 7: Commit** `feat: classify incoming SMS with Foundation Model`.

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
