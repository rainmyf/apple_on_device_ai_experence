# iOS 27 双向智能入口 Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Demo 升级为 iOS 27 真机可验证的双向端侧模型体验：App 调用 Foundation Model，以及系统智能通过 App Intents 调用 App。

**Architecture:** 保留现有体验服务与 SMS 代码但隐藏入口；新增版本化能力元数据、双向首页、开放式连续 LanguageModelSession 实验页、iOS 27 交互式 Vision 分割页，以及 Spotlight/AppIntent/Shortcuts 路由层。所有真实 API 集成通过 capability gate 和依赖注入测试；真机测试只使用已连接 iPhone。

**Tech Stack:** SwiftUI, FoundationModels (iOS 27), Vision, AppIntents, CoreSpotlight, Swift Testing, xcodebuild physical-device destination.

**Spec:** 侧对话《Xcode 27 双向智能入口 Demo 迭代计划》（2026-09-03 delegation payload）

## Global Constraints

- Deployment Target 必须为 iOS 27.0。
- 只使用 Apple Public API；禁止 PCC、云端、第三方模型、自定义 Core ML、Simulator 验证。
- SMS Classification 保留实现但不出现在首页/目录；Custom Adapter 为 iOS 27 obsoleted，Image Creator 为 iOS 27 deprecated。
- 真实 Foundation Model 链路使用 SystemLanguageModel.default、variant、capabilities、LanguageModelSession、DynamicProfile；不添加假结果。
- 所有异步操作必须有取消、错误和 availability gate；连续会话不自动调用模型，用户触发后执行。
- 测试替身只用于确定性测试，但测试执行目标必须是真机；静态/编译/真机/Shortcuts/Siri 证据分开记录。

### Task 1: iOS 27 元数据与首页双向入口

**Files:** `Experience.swift`, `ExperienceCatalog.swift`, `HomeView.swift`, `CategoryView.swift`, `ExperienceDestinationView.swift`, `AppRoute.swift`, `AppTheme.swift`, tests for catalog/home.

- [ ] 先为每个 `ExperienceDefinition` 写版本/API 类型/端侧/生命周期断言，验证 SMS 隐藏、Custom Adapter obsoleted、Image Creator deprecated。
- [ ] 运行真机测试目标确认 RED。
- [ ] 添加 `minimumOSVersion`, `openedAPI`, `isOnDevice`, `lifecycle` 字段并更新全部定义；将 Deployment Target 改到 27.0。
- [ ] 首页改为两个方向入口和完整分类列表，移除 “Pick something to try” 与 “See all”，保留版本徽标。
- [ ] 真机编译并运行元数据/导航单元测试。

### Task 2: Open On-device Model Lab

**Files:** 新增 `OnDeviceModelLab.swift`, `OnDeviceModelLabView.swift`; 修改 `FoundationModelService.swift`, `ExperienceDestinationView.swift`; tests.

- [ ] 先写 profile 选择、输入校验、连续 session、capability gate、取消和附件测试并在真机 RED。
- [ ] 用真实 `SystemLanguageModel.default` 暴露 availability/variant/capabilities；以依赖注入提供确定性 fake session。
- [ ] 实现纯文本/图像/本地检索三种 DynamicProfile 选择，支持 `Attachment<ImageAttachmentContent>`，显示上下文轮次、耗时、工具调用、错误和取消。
- [ ] 仅在用户点击发送时调用 `LanguageModelSession`；不使用云端 fallback。
- [ ] 真机编译、测试并手工验证文本连续对话、图像理解、OCR/Barcode/Spotlight 工具 gate。

### Task 3: iOS 27 交互式 Vision 分割

**Files:** 新增 `VisionSegmentationExperience.swift`, `VisionSegmentationView.swift`; 修改路由/工程文件；tests.

- [ ] 先写 seed 坐标转换、正负点迭代、框选/涂抹、取消/重置、资产失败测试并在真机 RED。
- [ ] 使用公开 `GenerateIterativeSegmentationRequest` 及系统资产下载 API；实现点/框/涂抹 seed、fast/balanced/accurate、进度、PixelBuffer mask 和耗时。
- [ ] 所有资源下载与推理任务支持 cancellation，禁止扩展为图片编辑器。
- [ ] 真机测试三种 seed、正负点修正、资源完成后断网复测。

### Task 4: 系统智能 → App（Spotlight / App Intents / Shortcuts）

**Files:** 新增 `ExperienceIndexing.swift`, `ExperienceAppIntents.swift`; 修改 `AppleOnDeviceModelDemoApp.swift`, `AppRoute.swift`; tests.

- [ ] 先写 ExperienceEntity 查询/路由、`.system.searchInApp`/`.system.open` 参数和 Shortcut 模型闭环测试，在真机 RED。
- [ ] 将可见体验写入 Spotlight；隐藏 SMS；实现外部导航状态共享。
- [ ] 实现 “运行端侧模型” AppIntent：输入文本 → App FoundationModelService → SystemLanguageModel.default → 返回结果；明确 Siri 仅增强证据。
- [ ] 真机执行 Spotlight 搜索/打开与 Shortcuts 动作，记录入口来源、API/profile/tools/耗时/错误。

### Task 5: 集成、真机回归与 Evidence Record

**Files:** tests, `docs/superpowers/evidence/2026-09-03-ios27-on-device-lab.md`.

- [ ] 仅使用连接 iPhone 的 test destination 编译并执行完整测试；禁止任何 Simulator destination。
- [ ] 手工验证双向入口、连续文本、图像、OCR/Barcode、Spotlight、分割、Shortcuts 和断网行为。
- [ ] 生成 Evidence Record，明确第三方 Provider 与 PCC 未验证；修复失败后重复真机测试。
- [ ] 仅在所有验收证据齐全后提交并 push；不替用户合并。
