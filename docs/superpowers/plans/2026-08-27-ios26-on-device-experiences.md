# iOS 26 设备端体验实施计划

> **面向执行代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施本计划。步骤使用复选框 (`- [ ]`) 跟踪。

**目标：** 将现有单屏 Demo 改造成精致的 SwiftUI 体验库，为范围内的每项 iOS 26 Apple 模型能力提供独立、真实、可亲手操作的体验。

**架构：** 强类型 `ExperienceCatalog` 负责首页、分类页和目标页导航，但不执行模型。每项体验都有专属 ViewModel，并通过精简协议调用 Framework 服务；共享 UI 负责呈现状态、输入、结果、耗时、错误和使用说明。开发按阶段推进，确保导航外壳和各 Framework 能力组都可独立编译。

**技术栈：** Swift 6、SwiftUI、Observation/Combine、FoundationModels、Speech、AVFAudio、Vision、NaturalLanguage、Translation、SoundAnalysis、ImagePlayground、AppIntents、Swift Testing、Xcode 26.6、iOS 26.5 SDK。

**规格：** `docs/superpowers/specs/2026-08-26-ios26-on-device-experiences-design.md`

## 全局约束

- 部署目标仍然是 iOS 26.0。
- 仅使用已安装的 iOS 26.5 SDK 中存在的公共 API。
- 仅主屏幕和类别屏幕导航；他们从不执行某项能力。
- 每种体验在其自己的页面上一次运行一种功能。
- 无基准、总分、通过次数、“全部运行”、伪造输出、云回退、第三方模型、Core ML 自定义模型、MLX、数据库或分析。
- iOS 27 API 和 AFM 3 变体不包括在内。
- 不可用的和仅系统 UI 的体验仍然可读并说明实际边界。
- 将 `SpeechAnalyzer`、`SpeechTranscriber`、`AVAudioEngine`、`SystemLanguageModel.default` 和 `LanguageModelSession` 保留在其实际执行路径中。
- 工作区不是 Git 存储库。如果没有单独的用户请求，请勿初始化 Git 或添加提交步骤。

---

## 文件结构

```text
AppleOnDeviceModelDemo/
├── AppleOnDeviceModelDemoApp.swift
├── AppRoute.swift
├── AppTheme.swift
├── CapabilityAvailability.swift
├── Experience.swift
├── ExperienceCatalog.swift
├── ContentView.swift
├── HomeView.swift
├── CategoryView.swift
├── ExperienceDestinationView.swift
├── SharedExperienceViews.swift
├── FoundationModelService.swift
├── FoundationExperiences.swift
├── NaturalLanguageExperience.swift
├── TranslationExperience.swift
├── VisionExperience.swift
├── SpeechInputService.swift
├── SpeechExperience.swift
├── SoundAnalysisExperience.swift
├── ImageExperiences.swift
├── SystemExperiences.swift
└── SampleAppIntent.swift

AppleOnDeviceModelDemoTests/
├── ExperienceCatalogTests.swift
├── CapabilityAvailabilityTests.swift
├── FoundationModelServiceTests.swift
├── FoundationExperienceTests.swift
├── NaturalLanguageExperienceTests.swift
├── TranslationExperienceTests.swift
├── VisionExperienceTests.swift
├── SpeechTranscriptAccumulatorTests.swift
├── ModelTestViewModelTests.swift
├── SoundAnalysisExperienceTests.swift
└── SystemExperienceTests.swift
```

在 `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj` 的相应项目组和源阶段中注册每个创建的 Swift 文件。仅在替换体验视图模型编译且测试通过后，才从项目中删除 `ModelTestViewModel.swift` 及其测试。

---

### 任务 1：强类型目录、分类与路由

**文件：**
- 创建：`AppleOnDeviceModelDemo/Experience.swift`
- 创建：`AppleOnDeviceModelDemo/ExperienceCatalog.swift`
- 创建：`AppleOnDeviceModelDemo/AppRoute.swift`
- 创建：`AppleOnDeviceModelDemoTests/ExperienceCatalogTests.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 生成：`ExperienceID`、`ExperienceCategory`、`ExperienceDefinition`、`ExperienceCatalog.all` 和 `AppRoute`。
- 消耗：无应用程序类型。

- [ ] **第 1 步：先编写目录测试**

```swift
import Testing
@testable import AppleOnDeviceModelDemo

struct ExperienceCatalogTests {
    @Test func containsEveryApprovedExperienceExactlyOnce() {
        let ids = ExperienceCatalog.all.map(\.id)
        #expect(ids.count == 17)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(ExperienceID.allCases))
    }

    @Test func contentTaggingIsLanguageAndTranslationDoesNotRequireAI() {
        #expect(ExperienceCatalog[.contentTagging].category == .languageText)
        #expect(ExperienceCatalog[.translation].requirement == .languageAssets)
    }

    @Test func featuredItemsAreIndependentDestinations() {
        #expect(ExperienceCatalog.featured.map(\.id) == [
            .speechTranscription, .contentTagging, .imageCreator
        ])
    }
}
```

- [ ] **步骤 2：运行测试目标并验证 RED**

跑步：

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj \
  -scheme AppleOnDeviceModelDemo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AppleExperiencesDerivedData \
  build-for-testing
```

预期：编译失败，因为 `ExperienceCatalog`、`ExperienceID` 和类别类型不存在。

- [ ] **第3步：实现不可变目录**

```swift
enum ExperienceCategory: String, CaseIterable, Hashable, Sendable {
    case languageText = "Language & Text"
    case cameraVision = "Camera & Vision"
    case voiceSound = "Voice & Sound"
    case createSystem = "Create & System"
}

enum ExperienceID: String, CaseIterable, Hashable, Sendable {
    case foundationModel, guidedGeneration, contentTagging, streaming
    case toolCalling, translation, naturalLanguage, vision
    case speechTranscription, soundRecognition, imageCreator
    case imagePlayground, writingTools, genmoji, smartReply
    case appIntents, customAdapter
}

enum ExperienceRequirement: Equatable, Sendable {
    case none, appleIntelligence, languageAssets, microphone
    case photoLibrary, systemUI, entitlementAndAsset
}

struct ExperienceDefinition: Identifiable, Hashable, Sendable {
    let id: ExperienceID
    let title: String
    let summary: String
    let framework: String
    let category: ExperienceCategory
    let requirement: ExperienceRequirement
    let symbolName: String
}

enum AppRoute: Hashable {
    case category(ExperienceCategory)
    case experience(ExperienceID)
}
```

用所有 17 个条目填充 `ExperienceCatalog.all` 并仅公开目录常量的捕获下标：

```swift
static subscript(id: ExperienceID) -> ExperienceDefinition {
    all.first { $0.id == id }!
}
```

- [ ] **第 4 步：运行构建测试并验证 GREEN**

预期：`TEST BUILD SUCCEEDED`，并且稍后在可用模拟器运行时执行测试时不会出现重复 ID 断言失败。

---

### 任务 2：可用性表示模型

**文件：**
- 创建：`AppleOnDeviceModelDemo/CapabilityAvailability.swift`
- 创建：`AppleOnDeviceModelDemoTests/CapabilityAvailabilityTests.swift`
- 修改：`AppleOnDeviceModelDemo/FoundationModelService.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 生成：`CapabilityAvailability`、`CapabilityStatus` 和基础模型映射。
- 消耗：来自任务 1 的 `ExperienceRequirement`。

- [ ] **第 1 步：编写失败的映射测试**

```swift
import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

struct CapabilityAvailabilityTests {
    @Test func mapsFoundationReasonsWithoutLosingMeaning() {
        #expect(CapabilityStatus.foundation(.available) == .ready)
        #expect(CapabilityStatus.foundation(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(CapabilityStatus.foundation(.unavailable(.modelNotReady)) == .modelNotReady)
        #expect(CapabilityStatus.foundation(.unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceDisabled)
    }

    @Test func systemUIIsNavigableButNotRunnable() {
        let status = CapabilityAvailability(status: .systemUIOnly, detail: "Open the system sheet.")
        #expect(status.canOpenPage)
        #expect(!status.canRunInApp)
    }
}
```

- [ ] **第 2 步：运行构建测试并验证 RED**

预期：缺少 `CapabilityStatus` 和 `CapabilityAvailability` 类型。

- [ ] **步骤 3：实现共享状态**

```swift
enum CapabilityStatus: String, Equatable, Sendable {
    case ready = "Ready on this device"
    case requiresAppleIntelligence = "Requires Apple Intelligence"
    case appleIntelligenceDisabled = "Apple Intelligence Disabled"
    case modelNotReady = "Model Not Ready"
    case assetsRequired = "Assets Required"
    case permissionRequired = "Permission Required"
    case deviceNotEligible = "Device Not Eligible"
    case systemUIOnly = "System UI"
    case setupRequired = "Setup Required"
    case unsupported = "Unsupported"
}

struct CapabilityAvailability: Equatable, Sendable {
    let status: CapabilityStatus
    let detail: String
    var canOpenPage: Bool { true }
    var canRunInApp: Bool { status == .ready }
}
```

将基础模型状态映射移动到 `CapabilityStatus.foundation(_:)`；为现有测试保留兼容性计算属性，直到任务 4 替换旧视图模型。

- [ ] **第 4 步：运行构建测试并验证 GREEN**

预期：`TEST BUILD SUCCEEDED`。

---

### 任务 3：已选体验库视觉系统与导航外壳

**文件：**
- 创建：`AppleOnDeviceModelDemo/AppTheme.swift`
- 创建：`AppleOnDeviceModelDemo/HomeView.swift`
- 创建：`AppleOnDeviceModelDemo/CategoryView.swift`
- 创建：`AppleOnDeviceModelDemo/SharedExperienceViews.swift`
- 创建：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo/ContentView.swift`
- 修改：`AppleOnDeviceModelDemo/AppleOnDeviceModelDemoApp.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 使用：任务 1-2 中的目录和路线类型。
- 产生：可导航主页、类别页面、可重用状态/部分组件、目标路由器。

- [ ] **第 1 步：在 UI 代码之前添加路由解析测试**

添加到`ExperienceCatalogTests.swift`：

```swift
@Test func everyCatalogEntryResolvesToAnExperienceRoute() {
    for item in ExperienceCatalog.all {
        #expect(AppRoute.experience(item.id) == .experience(item.id))
    }
}
```

- [ ] **步骤 2：运行测试构建并确认测试失败，直到路由一致性完成**

预期：如果 `AppRoute` 不是 `Equatable` 到 `Hashable` 或 ID 丢失，则会失败。

- [ ] **第 3 步：实施令牌和共享组件**

```swift
enum AppTheme {
    static let background = Color(red: 0.985, green: 0.975, blue: 0.955)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let secondaryInk = Color(red: 0.40, green: 0.40, blue: 0.42)

    static func accent(for category: ExperienceCategory) -> Color {
        switch category {
        case .languageText: Color(red: 0.94, green: 0.30, blue: 0.18)
        case .cameraVision: Color(red: 0.32, green: 0.66, blue: 0.28)
        case .voiceSound: Color(red: 0.08, green: 0.42, blue: 0.96)
        case .createSystem: Color(red: 0.55, green: 0.28, blue: 0.78)
        }
    }
}
```

构建 `FeaturedExperienceCard`、`ExperienceRow`、`CategoryHeader`、`CapabilityStatusLabel`、`ExperienceIntro`、`ResultSurface` 和 `UsageInstructions`。使用 SF 符号进行控制；使用类别颜色的抽象 SwiftUI 表面，直到选择单独生成的缩略图，但不要使用表情符号或假装插图是模型输出。

- [ ] **第4步：实现主页和类别导航**

`ContentView` 变为 `NavigationStack(path:)`； `HomeView` 呈现三个特色条目和精选类别子集。 “查看全部”打开`CategoryView`。每次点击都会附加一条 `.experience(id)` 路线。

- [ ] **第 5 步：在 Xcode 中构建和检查**

运行通用模拟器构建。然后在 Xcode 中运行，并根据选定的参考来直观地验证主页：温暖的背景、编辑标题、水平特色架子、四个彩色部分、独立的条目可供性、无聚合执行 UI。

---

### 任务 4：共享体验运行状态

**文件：**
- 创建：`AppleOnDeviceModelDemo/ExperienceOperation.swift`
- 创建：`AppleOnDeviceModelDemoTests/ExperienceOperationTests.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 产生：具有延迟和取消行为的可重用 `ExperienceOperation<Output>`。
- 消耗：没有特定于框架的 API。

- [ ] **第 1 步：编写失败的状态机测试**

```swift
@MainActor
@Test func operationPublishesResultAndLatency() async {
    var times = [10.0, 10.8].makeIterator()
    let operation = ExperienceOperation<String>(clock: { times.next()! })
    await operation.run { "local result" }
    #expect(operation.output == "local result")
    #expect(operation.latency == 0.8)
    #expect(!operation.isRunning)
    #expect(operation.errorMessage == nil)
}
```

添加针对空状态重置、抛出错误和取消的单独测试。

- [ ] **第 2 步：验证红色**

预期：缺少 `ExperienceOperation`。

- [ ] **第3步：实现最小状态对象**

```swift
@MainActor
final class ExperienceOperation<Output>: ObservableObject {
    @Published private(set) var output: Output?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }) {
        self.clock = clock
    }

    func run(_ work: () async throws -> Output) async {
        guard !isRunning else { return }
        output = nil; errorMessage = nil; latency = nil; isRunning = true
        let start = clock()
        defer { latency = clock() - start; isRunning = false }
        do { output = try await work() }
        catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }
}
```

- [ ] **第 4 步：验证绿色**

预期：`TEST BUILD SUCCEEDED`；当模拟器运行时可用时，在 Xcode 中执行测试。

---

### 任务 5：基础模型 - 提示、引导生成和内容标记

**文件：**
- 修改：`AppleOnDeviceModelDemo/FoundationModelService.swift`
- 创建：`AppleOnDeviceModelDemo/FoundationExperiences.swift`
- 创建：`AppleOnDeviceModelDemoTests/FoundationExperienceTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 产生：`FoundationModelServing.respond`、`.analyze`、`.tag`；三种不同体验的视图。
- 消耗：可用性和操作类型。

- [ ] **第 1 步：编写失败的服务/视图模型测试**

```swift
@MainActor
@Test func contentTaggingRendersStructuredFields() async {
    let service = FoundationServiceStub()
    service.tags = ContentTags(topics: ["travel"], entities: ["Tokyo"], actions: ["book"], emotions: ["excited"])
    let model = ContentTaggingViewModel(service: service)
    model.input = "I am excited to book Tokyo."
    await model.run()
    #expect(model.result?.topics == ["travel"])
    #expect(service.lastUseCase == .contentTagging)
}
```

添加空输入不会调用服务且不可用状态返回真实消息的测试。

- [ ] **第 2 步：验证红色**

预期：缺少 `ContentTags`、`ContentTaggingViewModel` 和扩展协议。

- [ ] **步骤 3：添加实际的引导模式**

```swift
@Generable
struct GuidedTextAnalysis: Equatable, Sendable {
    @Guide(description: "Primary intent") var intent: String
    @Guide(description: "Important entities", .maximumCount(5)) var entities: [String]
    @Guide(description: "Summary under 30 words") var summary: String
}

@Generable
struct ContentTags: Equatable, Sendable {
    @Guide(.maximumCount(5)) var topics: [String]
    @Guide(.maximumCount(5)) var entities: [String]
    @Guide(.maximumCount(3)) var actions: [String]
    @Guide(.maximumCount(3)) var emotions: [String]
}
```

使用 `SystemLanguageModel.default` 进行提示/引导生成，使用 `SystemLanguageModel(useCase: .contentTagging)` 进行标记。在构建会话之前立即检查每个模型的可用性。

- [ ] **第4步：构建三个独立页面**

每个页面都有自己的输入、示例、运行操作、结果、延迟和使用说明。结构化页面呈现带标签的 Swift 字段，而不是原始 JSON。

- [ ] **第 5 步：验证绿色并构建**

预期：测试编译并且通用模拟器构建成功。在没有合格设备观察的情况下，请勿声明真实模型输出。

---

### 任务 6：基础模型 - 流式传输和本地工具调用

**文件：**
- 修改：`AppleOnDeviceModelDemo/FoundationExperiences.swift`
- 创建：`AppleOnDeviceModelDemoTests/FoundationStreamingToolTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 产生：单独的流页面和确定性本地工具页面。
- 消耗：`LanguageModelSession`、共享可用性和操作 UI。

- [ ] **第 1 步：编写失败的行为测试**

测试流是否按顺序替换显示的部分响应，并且该工具仅返回本地夹具数据：

```swift
@Test func localFactToolReturnsKnownLocalValue() async throws {
    let tool = LocalCapabilityTool(values: ["speech": "SpeechAnalyzer is enabled"])
    let output = try await tool.call(arguments: .init(keyword: "speech"))
    #expect(String(describing: output).contains("SpeechAnalyzer is enabled"))
}
```

- [ ] **第 2 步：验证红色**

预期：缺少 `LocalCapabilityTool` 和流累加器。

- [ ] **第3步：实施工具和流适配器**

```swift
struct LocalCapabilityTool: Tool {
    let name = "lookupCapability"
    let description = "Looks up a fixed fact bundled in this demo. It never uses a network."
    let values: [String: String]

    @Generable struct Arguments { var keyword: String }

    func call(arguments: Arguments) async throws -> ToolOutput {
        ToolOutput(values[arguments.keyword.lowercased()] ?? "No local fact found.")
    }
}
```

Streaming 消耗 `session.streamResponse(to:)` 并在 `MainActor` 上发布最新快照。工具调用会话仅使用 `LocalCapabilityTool` 进行初始化；不添加 URLSession、存储或外部服务。

- [ ] **第4步：独立构建和验证页面**

流式传输页面显示增量文本。工具页面解释了固定的本地字典并显示会话的最终响应以及当记录公开该信息时是否调用该工具。

---

### 任务 7：自然语言和翻译

**文件：**
- 创建：`AppleOnDeviceModelDemo/NaturalLanguageExperience.swift`
- 创建：`AppleOnDeviceModelDemo/TranslationExperience.swift`
- 创建：`AppleOnDeviceModelDemoTests/NaturalLanguageExperienceTests.swift`
- 创建：`AppleOnDeviceModelDemoTests/TranslationExperienceTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 产生：确定性 NaturalLanguage 分析和翻译会话 UI。
- 消耗：共享经验组件。

- [ ] **第 1 步：编写 NaturalLanguage RED 测试**

```swift
@Test func analyzerIdentifiesEnglishAndNamedPlaces() {
    let result = NaturalLanguageAnalyzer().analyze("Apple opened an office in London.")
    #expect(result.language == "English")
    #expect(result.entities.contains { $0.text == "London" && $0.kind == "Place" })
}
```

- [ ] **第 2 步：实施 NaturalLanguage 分析**

将 `NLLanguageRecognizer` 和 `NLTagger` 与 `.nameType`、`.lexicalClass` 和 `.sentimentScore` 一起使用。将范围转换为稳定的 `NaturalLanguageEntity` 显示值，以便测试不依赖于 UI。

- [ ] **步骤 3：编写翻译视图模型 RED 测试**

注入异步闭包 `(String) async throws -> String`；断言选定的源/目标对、空验证、输出和错误状态。

- [ ] **步骤 4：使用 SwiftUI 会话环境实现翻译**

页面中自带`TranslationSession.Configuration(source:target:)`，语言改变时调用`configuration.invalidate()`，运行：

```swift
.translationTask(configuration) { session in
    await viewModel.attach(session: session)
}
```

Run 操作调用 `prepareTranslation()` 和 `translate(_:)`。如实展示`isReady`/下载准备。请勿使用基础模型或将翻译标记为需要 Apple Intelligence。

- [ ] **第 5 步：构建并验证两个目标**

预期：通用模拟器构建成功；安装的语言资产决定运行时准备情况。

---

### 任务 8：Vision 交互体验

**文件：**
- 创建：`AppleOnDeviceModelDemo/VisionExperience.swift`
- 创建：`AppleOnDeviceModelDemoTests/VisionExperienceTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 生成：`VisionMode`、`VisionFinding`、`VisionAnalyzing` 和一个多模式视觉页面。
- 消耗：PhotosPicker 和共享操作 UI。

- [ ] **步骤 1：编写失败的结果映射测试**

```swift
@Test func textFindingsSortTopToBottom() {
    let findings = VisionFinding.sortForReadingOrder([
        .text("bottom", box: .init(x: 0, y: 0.1, width: 1, height: 0.1)),
        .text("top", box: .init(x: 0, y: 0.8, width: 1, height: 0.1))
    ])
    #expect(findings.map(\.label) == ["top", "bottom"])
}
```

添加对条形码有效负载、置信度姿势点过滤以及不支持的图像解码的测试。

- [ ] **第 2 步：验证红色**

预期：缺少视觉类型。

- [ ] **第 3 步：实现真实的愿景请求**

定义模式 `.recognizedText`、`.barcodes`、`.humanBodyPose`、`.imageClassification`。使用来自已安装 SDK 的公共 Vision 请求，在主要参与者上运行它们，并将观察结果标准化为 `VisionFinding`，而不是将 `VNObservation` 暴露给 SwiftUI。

- [ ] **第 4 步：构建图像体验**

使用 `PhotosPicker`、图像预览、分段模式选择器、一个分析操作、几何承载结果的归一化覆盖、下面的可选文本、延迟和权限/解码错误。

- [ ] **第 5 步：使用夹具图像构建并手动检查**

使用印刷文本图像、二维码和全身照片。仅记录观察到的结果；不要将视觉信心转化为应用程序范围内的分数。

---

### 任务 9：保留和重构语音转录

**文件：**
- 保留/修改：`AppleOnDeviceModelDemo/SpeechInputService.swift`
- 创建：`AppleOnDeviceModelDemo/SpeechExperience.swift`
- 保留/修改：`AppleOnDeviceModelDemoTests/SpeechTranscriptAccumulatorTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 绿色后删除：`AppleOnDeviceModelDemo/ModelTestViewModel.swift`
- 绿色后删除：`AppleOnDeviceModelDemoTests/ModelTestViewModelTests.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 生成：纯语音视图模型和页面。
- 消耗：现有的 `SpeechInputService` 和共享 UI。

- [ ] **步骤 1：为新的纯语音视图模型添加 RED 测试**

使用现有协议存根模式进行测试启动、实时记录发布、停止/最终延迟、拒绝许可以及重复启动预防。

- [ ] **第 2 步：验证红色**

预期：缺少 `SpeechExperienceViewModel`。

- [ ] **第3步：实现页面而不重写音频引擎**

将编排从 `ModelTestViewModel` 移至 `SpeechExperienceViewModel`。保留输入节点之前的音频会话排序、`format: nil` Tap 安装、每个缓冲区转换、资产准备和非隔离 Tap 处理。

- [ ] **第 4 步：仅在绿色后移除旧的组合屏幕**

从 `ModelTestViewModel` 中删除旧的模型运行编排，从项目中取消注册它及其测试，并确认基础模型体验仍然可以通过其自己的页面访问。

- [ ] **第 5 步：构建并执行 Mac/iPhone 录制检查**

验证实时转录、停止、延迟、无 `0 ch / 0 Hz`、无格式不匹配异常、无参与者队列断言。

---

### 任务 10：声音分析体验

**文件：**
- 创建：`AppleOnDeviceModelDemo/SoundAnalysisExperience.swift`
- 创建：`AppleOnDeviceModelDemoTests/SoundAnalysisExperienceTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 生成：`SoundClassification`、结果观察器适配器和声音识别页面。
- 使用：由 Speech 验证的 AVAudioEngine 约定，但拥有单独的引擎/tap 生命周期。

- [ ] **第 1 步：编写失败的排名测试**

```swift
@Test func classificationsKeepTopThreeAboveThreshold() {
    let output = SoundClassification.filtered([
        .init(label: "speech", confidence: 0.9),
        .init(label: "music", confidence: 0.7),
        .init(label: "noise", confidence: 0.5),
        .init(label: "silence", confidence: 0.02)
    ], threshold: 0.1, limit: 3)
    #expect(output.map(\.label) == ["speech", "music", "noise"])
}
```

- [ ] **第 2 步：验证红色**

预期：缺少 `SoundClassification`。

- [ ] **第 3 步：实施 SoundAnalysis 生命周期**

使用 `SNAudioStreamAnalyzer`、Apple 的内置 `SNClassifySoundRequest`、`SNResultsObserving` 桥接器和 `AVAudioEngine`。在 `MainActor` 上发布之前，将结果转换为可发送的显示值。停止移除水龙头并安全完成分析。

- [ ] **第4步：构建专用页面**

提供记录/停止、经过的分析时间、有信心的排名标签，以及声音分类不是语音转录的解释。

- [ ] **第5步：构建并手动检查**

测试语音、音乐和静室输入。将低置信度/空结果视为有效的空状态，而不是失败。

---

### 任务 11：ImageCreator 和 Image Playground

**文件：**
- 创建：`AppleOnDeviceModelDemo/ImageExperiences.swift`
- 创建：`AppleOnDeviceModelDemoTests/SystemExperienceTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 制作：程序化 ImageCreator 页面和系统 Image Playground 演示文稿。
- 使用：ImagePlayground 公共 SDK。

- [ ] **第 1 步：编写失败的 ImageCreator 视图模型测试**

注入返回 `[CGImage]` 的生成器闭包或测试友好的 `GeneratedImage` 包装器。测试空提示、可用样式选择、第一个结果发布、取消和错误消息传递。

- [ ] **第 2 步：验证红色**

预期：缺少图像体验类型。

- [ ] **第 3 步：实施 ImageCreator**

异步构造`ImageCreator()`，读取`availableStyles`，将提示文本转换为公共`ImagePlaygroundConcept`值，并消费：

```swift
creator.images(for: concepts, style: style, limit: 1)
```

仅在`#available(iOS 26.4, *)`后面使用iOS 26.4 `ImagePlaygroundOptions`。

- [ ] **第4步：实现Image Playground系统演示**

使用已安装 SDK 中存在的公共 SwiftUI/系统演示 API。该页面提供概念并推出一种系统体验；它并不声称应用程序拥有生成的模型 UI。

- [ ] **第 5 步：构建并手动验证可用性**

在不合格的设备上，两个页面仍然可读并显示框架错误。在合格的硬件上，在声称成功之前观察实际生成的图像。

---

### 任务 12：Writing Tools、Genmoji、Smart Reply、App Intents 与 Adapter 边界

**文件：**
- 创建：`AppleOnDeviceModelDemo/SystemExperiences.swift`
- 创建：`AppleOnDeviceModelDemo/SampleAppIntent.swift`
- 修改：`AppleOnDeviceModelDemoTests/SystemExperienceTests.swift`
- 修改：`AppleOnDeviceModelDemo/ExperienceDestinationView.swift`
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

**接口：**
- 产生：诚实的系统集成/设置页面和无害的应用程序意图。
- 消耗：共享状态/使用组件。

- [ ] **第 1 步：编写失败的内容边界测试**

```swift
@Test func systemEntriesNeverClaimDirectModelExecution() {
    for id in [ExperienceID.writingTools, .genmoji, .smartReply, .appIntents, .customAdapter] {
        let page = SystemExperienceContent.content(for: id)
        #expect(page.executionKind != .directModel)
        #expect(!page.instructions.isEmpty)
    }
}
```

- [ ] **第 2 步：验证红色**

预期：缺少内容模型。

- [ ] **步骤 3：实施系统拥有的经验**

书写工具使用可编辑的 SwiftUI 文本界面和系统书写工具可供性。 Genmoji 提供可编辑的文本字段和键盘调用指令。智能回复仅公开 SDK 26.5 中的公共对话/键盘边界；如果不存在独立调用，则设置 `.systemUIOnly`。适配器检查指定的捆绑适配器资产，并在不存在时解释权利要求。

- [ ] **第 4 步：实现无害的应用程序意图**

```swift
struct DescribeDemoCapabilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Describe an On-device Capability"
    @Parameter(title: "Capability") var capability: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: "Open On-device Experiences to try \(capability) separately.")
    }
}
```

该页面解释说，应用程序意图向系统公开应用程序操作，并且不授予对 Siri 私有模型的访问权限。

- [ ] **第 5 步：构建并检查每个边界页面**

确认系统拥有入口点时不存在虚假的运行按钮，并且在没有资产和权利的情况下没有适配器加载尝试。

---

### 任务 13：完整集成、无障碍与视觉 QA

**文件：**
- 修改：根据结果需要查看所有文件。
- 创建：`docs/ios26-manual-test-checklist.md`

**接口：**
- 消耗：之前的所有任务。
- 产生：完整的集成应用程序和记录的验证边界。

- [ ] **第1步：添加手动测试矩阵**

对于所有 17 个 ID，包括列：页面打开、输入工作、操作类型、观察到的输出、延迟、可用性原因、设备、操作系统、离线状态和注释。仅预填预期的操作类型；将观察到的字段留空，直到实际测试为止。

- [ ] **第 2 步：运行完整的全新验证命令**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj \
  -scheme AppleOnDeviceModelDemo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AppleExperiencesFinalDerivedData \
  clean build-for-testing

xcodebuild -project AppleOnDeviceModelDemo.xcodeproj \
  -scheme AppleOnDeviceModelDemo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AppleExperiencesFinalDerivedData \
  build
```

预期：均以 `TEST BUILD SUCCEEDED` 和 `BUILD SUCCEEDED` 退出 0。将警告视为发现；在完成之前删除应用程序编写的警告。

- [ ] **步骤 3：机械检查目录覆盖率**

跑步：

```bash
rg -n "case (foundationModel|guidedGeneration|contentTagging|streaming|toolCalling|translation|naturalLanguage|vision|speechTranscription|soundRecognition|imageCreator|imagePlayground|writingTools|genmoji|smartReply|appIntents|customAdapter)" AppleOnDeviceModelDemo
```

验证每个 `ExperienceID` 在目录中和目标路由中都存在一次。

- [ ] **第 4 步：运行应用程序并与所选视觉效果进行比较**

在 iPhone 肖像视口中拍摄房屋。检查标题比例、暖色背景、特色书架、四种类别颜色、独立条目可供性、间距、无基准 UI、大动态类型下无剪裁以及深色模式易读性（如果支持深色模式）。

- [ ] **步骤 5：执行交互和可访问性检查**

浏览每个条目；验证返回、查看全部、特色分页、44 点目标、VoiceOver 标签、非彩色状态文本、减少动作、拒绝权限、不可用状态、取消和重复运行预防。

- [ ] **步骤 6：仅在连接硬件时执行合格设备检查**

记录实际语音、基础模型、视觉、翻译、声音分析和 ImageCreator 结果。存在所需资产后，重复支持的离线设备体验。切勿将未观察到的模型标记为已执行。

- [ ] **步骤 7：最终需求审核**

逐行阅读设计规范，并通过文件、测试、构建输出或手动观察确认每个完成标准。将任何硬件门控项目报告为未经验证而非完整。
