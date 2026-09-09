# Live Activity Demo and SMS Classifier Cleanup Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with tests first. All runtime verification uses a connected iPhone; do not use Simulator.

**Goal:** 删除旧版独立 SMS Classification 体验及其旧模型测试；保留当前 SMS AppIntent 的端侧分类→实况窗链路，并将“System Intelligence → App”重命名为中文“系统智能调用 App”，提供分阶段验证入口。

**Architecture:** 实况窗使用独立的演示状态模型和可注入的管理器协议；系统智能页面负责分阶段验证。当前 SMS AppIntent 仍调用 `SMSIncomingClassificationService` 的真实 `SystemLanguageModel.default`，并把分类结果映射到实况窗；仅删除旧的独立页面、旧服务和旧评测夹具。

**Tech Stack:** SwiftUI, ActivityKit, WidgetKit, AppIntents, Swift Testing, Xcode 27 / iOS 27 SDK.

**Spec:** `docs/superpowers/specs/2026-09-03-sms-live-activity-design.md`

## Global Constraints

- 仅使用 iOS 27 Public API。
- 不使用 Simulator；编译和测试使用已连接 iPhone 的 `iphoneos` destination。
- 保留当前 SMS AppIntent、`SMSIncomingClassificationService` 及其确定性单测；不恢复旧版独立 SMS 页面、旧服务、旧评测夹具。
- 实况窗打桩测试只证明状态编排和展示数据契约，不宣称系统锁屏 UI 已真实显示。

### Task 1: Add failing Live Activity demo contract tests

**Files:**
- Create: `AppleOnDeviceModelDemoTests/DemoLiveActivityTests.swift`
- Test: `AppleOnDeviceModelDemoTests/DemoLiveActivityTests.swift`

- [ ] **Step 1: Write failing tests** for an independent demo category/state, unique symbols, and `analyzing → classified` transitions through an injected manager.
- [ ] **Step 2: Run only the new tests** on the connected iPhone and confirm failure because the independent demo types do not exist.

### Task 2: Decouple Live Activity implementation

**Files:**
- Create: `AppleOnDeviceModelDemo/DemoLiveActivityShared.swift`
- Modify: `AppleOnDeviceModelDemo/SMSLiveActivityCoordinator.swift`
- Modify: `AppleOnDeviceModelDemoLiveActivity/SMSLiveActivityWidget.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

- [ ] **Step 1:** Add `DemoLiveActivityCategory`, `DemoLiveActivityAttributes`, theme symbols, and content builder independent of SMS classifier types.
- [ ] **Step 2:** Update coordinator protocol and actor to use demo attributes while preserving ActivityKit concurrency isolation.
- [ ] **Step 3:** Update the widget source to render demo states and add the widget extension target/file membership if it is not already present.
- [ ] **Step 4:** Run the new tests and verify they pass.

### Task 3: Delete old standalone SMS classifier implementation and tests

**Files:**
- Keep: `AppleOnDeviceModelDemo/SMSIncomingClassification.swift`
- Keep: `AppleOnDeviceModelDemo/SMSIncomingClassificationService.swift`
- Keep/add focused tests for the current AppIntent path.
- Modify: `AppleOnDeviceModelDemo/ExperienceAppIntents.swift`
- Modify: `AppleOnDeviceModelDemo/AppleOnDeviceModelDemoApp.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceCatalog.swift`
- Modify: `AppleOnDeviceModelDemo/Experience.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceIndexing.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`
- Delete or rewrite: `AppleOnDeviceModelDemoTests/SMSLiveActivityIntentTests.swift`

- [ ] **Step 1:** Remove the SMS classifier files and project references.
- [x] **Step 2:** Remove only the old standalone SMS page/legacy service; preserve `RunOnDeviceModelIntent` SMS parameters, model service injection, and shortcut metadata/provider.
- [ ] **Step 3:** Remove SMS classification catalog/routing entries and update tests to assert the visible catalog no longer contains SMS classification.
- [ ] **Step 4:** Rewrite Live Activity tests to use demo states only.
- [ ] **Step 5:** Run a source scan proving legacy standalone names are gone while current `SMSIncoming`/`RunOnDeviceModelIntent` references remain.

### Task 4: Rename and redesign System Intelligence → App entry

**Files:**
- Modify: `AppleOnDeviceModelDemo/SystemExperiences.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceCatalog.swift`
- Modify: `AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- Create or modify: `AppleOnDeviceModelDemo/SystemIntelligenceToAppVerificationView.swift`
- Modify: related catalog/UI tests

- [ ] **Step 1:** Rename user-facing title/copy to `系统智能调用 App`.
- [ ] **Step 2:** Add a staged verification panel: `阶段 1 · 状态准备`, `阶段 2 · 打桩更新`, `阶段 3 · 展示契约`.
- [ ] **Step 3:** Wire the panel to the injected demo activity manager; show pass/fail state and reset action without invoking any SMS model.
- [ ] **Step 4:** Add tests for stage transitions and renamed copy.

### Task 5: Physical-device verification

- [ ] **Step 1:** Run signed `xcodebuild test` with `-only-testing` for the demo Live Activity and renamed system-intelligence tests on the connected iPhone.
- [ ] **Step 2:** Build/install/launch the signed app on the same iPhone.
- [ ] **Step 3:** Record build, test, install, and extension-target evidence separately; report any missing system-rendering evidence.
