# iOS 26 真机失败修复实施计划

> **面向执行代理：** 必须使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 按任务实施；每个生产改动先按 `superpowers:test-driven-development` 完成 RED→GREEN，交付前使用 `superpowers:verification-before-completion`。步骤使用复选框 (`- [ ]`) 跟踪。

**目标：** 修复真机已确认的兼容画布/双列卡布局与 Speech 无 transcript，校正 Content Tagging 真机诊断，保留 Translation 的真实系统边界，修复测试 target 真机签名阻塞，并用可复现的单测、构建和 iPhone 复测闭环。

**架构：** UI 将把动态字体布局决策提取为纯值 `HomeLayoutMetrics`，由主页根据可用宽度和 Dynamic Type 选择 Header、精选卡和网格；Speech 在一次录音生命周期内复用一个 `AVAudioConverter`，保持 `SpeechAnalyzer` 的连续输入。Foundation Content Tagging 使用 route-specific model 和 typed `ContentTags`，原始 availability/refusal 错误不被折叠或伪装成成功；Translation 的语言资产状态继续由系统 `LanguageAvailability` 决定。

**技术栈：** Swift 6、SwiftUI、SpeechAnalyzer、SpeechTranscriber、AVAudioEngine、AVAudioConverter、FoundationModels、Translation、Swift Testing、Xcode 26.6、iOS 26.5 SDK。

**规格：** `docs/superpowers/plans/2026-08-31-ios26-physical-device-test-plan.md`、`docs/superpowers/specs/2026-08-26-ios26-on-device-experiences-design.md`、`docs/device-test/2026-08-31/fix-plan-input.md`

## 全局约束

- 使用 iOS 26.0 deployment target 和已安装 iOS 26.5 SDK 的 public API。
- 保留 `SpeechAnalyzer`、`SpeechTranscriber`、`SystemLanguageModel`、`LanguageModelSession` 和系统 Translation；禁止 `SFSpeechRecognizer`、云端 fallback、第三方模型、Core ML 自定义模型和 MLX。
- `FAIL_APP` 只表示 App 源码、交互、布局、状态或错误处理；Foundation eligibility/refusal、Translation 资产、ImageCreator 不支持属于 `BLOCKED_SYSTEM`；需要用户说话、改设置、选照片或操作系统 UI 属于 `NEEDS_USER_ACTION`。
- 测试 target 签名是 test-infrastructure blocker，不得伪装成模型通过，也不得把系统资源阻塞记为 App 修复完成。
- 不增加 Foundation Model adapter entitlement；Custom Adapter 保持 setup-only。
- 当前工作区不是 Git 工作流；计划执行不添加 commit、push、merge 或 reset 步骤。所有 `xcodebuild` 使用显式 `/tmp/...` `-derivedDataPath`。

## 当前失败与边界（执行前必须保持）

| 事件 | 证据 | 分类/处置 |
| --- | --- | --- |
| 真机上下大面积黑边、主页 `Experi- / ences`；双列分类卡逐字断行 | `docs/device-test/2026-08-31/screenshots/01-home-letterboxed.png`、`02-home-grid-fixed-simulator.png`；工程缺少 `UILaunchScreen`，横向 `ExperienceRow` 被塞入双列网格 | `FAIL_APP`；已补生成式 Launch Screen，并改为真正的纵向双列网格卡 |
| 48 kHz 单声道输入持续转换到 16 kHz，但 0 个 `SpeechTranscriber.Result`、空 transcript | `/tmp/apple-physical-speech-runtime.log`；`docs/device-test/2026-08-31/console.log`；`SpeechInputService.swift:402-474` | `FAIL_APP`，先锁定连续 converter 的 RED，再 GREEN 和两次真机复测 |
| Foundation default availability 为 `.available`，真实生成成功 | 本轮真机输出：`DEVICE_RESULT|FM-AVAILABILITY|available`、`DEVICE_RESULT|FM-01|PASS|...` | `PASS`；不得再引用语言修复前的 `.appleIntelligenceNotEnabled` |
| Content Tagging availability 为 `.available`，旧诊断用普通字符串 session 请求后返回 refusal `May contain sensitive content` | 本轮真机 `PhysicalDeviceFoundationModelTests` 输出 | 修复诊断，使其走页面相同的 typed `FoundationModelService.tag`；系统 refusal 原样记录为 `BLOCKED_SYSTEM`，不得伪装成 App 成功 |
| 真机 Translation `en→zh-Hans` 为 `.supported`，未到 `.installed` | `docs/device-test/2026-08-31/console.log`；`TranslationExperience.swift:11-18,113-121,171-194` | `BLOCKED_SYSTEM`，无需伪造翻译；用户安装语言资产后复测 |
| 测试 target 缺 `DEVELOPMENT_TEAM` | `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj:415-443`；此前真机命令依赖 `DEVELOPMENT_TEAM=DH255M46VJ` 覆盖 | test-infrastructure blocker；给 Debug/Release 测试配置补 team，之后不再命令行覆盖 |
| ImageCreator API 初始化返回 5 种样式 | 本轮真机输出：`DEVICE_RESULT|SYS-01|PASS|styles=5` | `PASS`；实际生成图片仍需单独页面交互测试 |
| 17 页点击、PhotosPicker、系统 UI、Apple Intelligence/Translation 设置、离线步骤 | `docs/device-test/2026-08-31/execution-results.md` | `NEEDS_USER_ACTION`；未观察前不得标记 PASS |

## 任务 1：建立可审计的失败基线与 Content Tagging 分流

**文件：**
- 读取：`docs/device-test/2026-08-31/execution-results.md`
- 读取：`docs/device-test/2026-08-31/console.log`
- 修改：`AppleOnDeviceModelDemoTests/FoundationModelServiceTests.swift`
- 修改：`AppleOnDeviceModelDemoTests/FoundationExperienceTests.swift`

**接口：**
- 保持现有 `FoundationModelService.status(for:)` 映射，不改变产品状态枚举。
- 真机 Content Tagging 诊断必须调用 `FoundationModelService.tag(_:)`，即 `SystemLanguageModel(useCase: .contentTagging)` + typed `ContentTags`，不能用普通 `session.respond(...).content` 代替页面链路。

- [ ] **步骤 1：先写 RED 真机诊断契约测试。** 将 Content Tagging 真机用例从普通 `LanguageModelSession.respond(...).content` 改为注入/调用 `FoundationModelService.tag(_:)` 的 typed 页面链路；使用中性文本夹具，并验证 refusal 分类不会被误报为 `PASS`。

- [ ] **步骤 2：运行单测确认 RED。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanFMRed \
  -only-testing:AppleOnDeviceModelDemoTests/FoundationModelServiceTests test
```

预期：现有真机用例仍直接构造普通 session，契约测试失败；记录 RED 后再替换诊断实现。

- [ ] **步骤 3：把真机诊断改成页面同一条 typed route。** availability 非 `.available` 时只打印 `DEVICE_RESULT|FM-05|BLOCKED_SYSTEM|<原始 availability>` 并 return；可用时调用 `try await FoundationModelService().tag(...)`，至少断言四个数组字段可读，异常打印原始 error 并以 `FAIL_APP` 结束测试。这样可区分“系统未就绪/拒绝”和“App 吞掉 typed-route 错误”。

- [ ] **步骤 4：保留生产状态语义。** 不新增状态枚举；确认 `ContentTaggingViewModel` 继续使用 `contentTaggingAvailabilityStatus`，不得回退到 default model；refusal 必须显示原始系统错误。

- [ ] **步骤 5：运行 Foundation 单测确认 GREEN。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanFMGreen \
  -only-testing:AppleOnDeviceModelDemoTests/FoundationModelServiceTests \
  -only-testing:AppleOnDeviceModelDemoTests/FoundationExperienceTests test
```

验收：映射测试通过；Content Tagging route-specific availability 测试仍通过；不可用时不创建 session。

## 任务 2：修复 Speech 连续音频转换（P0）

**文件：**
- 修改：`AppleOnDeviceModelDemo/SpeechInputService.swift:5-12,224-251,402-474,476-492`
- 修改：`AppleOnDeviceModelDemoTests/SpeechTranscriptAccumulatorTests.swift`

**接口：**
- 新增 `SpeechAudioBufferConverter.init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws`。
- 新增 `SpeechAudioBufferConverter.convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer`。
- 一个 `startTranscribing` session 只创建一个 converter；stop、cancel、failed-start 都释放它。

- [ ] **步骤 1：写 RED 连续 buffer 测试。** 在 `SpeechTranscriptAccumulatorTests.swift` 增加测试：用同一个 converter 连续输入两个 48 kHz/单声道/4800-frame 非零 buffer，分别断言输出格式为 16 kHz、每个输出 `frameLength == 1600`、首帧非零；不要在测试中每次重新初始化 converter。

```swift
@Test @MainActor
func converterKeepsAContinuousSessionAcrossBuffers() throws {
    let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let converter = try SpeechAudioBufferConverter(inputFormat: input, outputFormat: output)
    let first = try converter.convert(makeNonZeroBuffer(format: input, frames: 4_800))
    let second = try converter.convert(makeNonZeroBuffer(format: input, frames: 4_800))
    #expect(first.format.sampleRate == 16_000)
    #expect(second.format.sampleRate == 16_000)
    #expect(first.frameLength == 1_600)
    #expect(second.frameLength == 1_600)
    #expect((first.floatChannelData?[0][0] ?? 0) != 0)
    #expect((second.floatChannelData?[0][0] ?? 0) != 0)
}

private func makeNonZeroBuffer(format: AVAudioFormat, frames: Int) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for channel in 0..<Int(format.channelCount) {
        for frame in 0..<frames {
            buffer.floatChannelData![channel][frame] = 0.25
        }
    }
    return buffer
}
```

- [ ] **步骤 2：运行 RED。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanSpeechRed \
  -only-testing:AppleOnDeviceModelDemoTests/SpeechTranscriptAccumulatorTests test
```

预期：当前没有 `SpeechAudioBufferConverter`，测试编译失败；这一步证明测试确实先于实现。

- [ ] **步骤 3：实现最小 converter。** 参考当前 SDK 的 `AVAudioConverter` public API：初始化时保存 converter 和 output format，设置 `primeMethod = .none`；每次 `convert` 为当前输入容量分配 output buffer，回调只供应当前输入一次，检测 `.error`、nil output 和 `frameLength == 0` 并抛出 `SpeechInputError.audioConversionFailed`。不要在 `installMicrophoneTap` 的每次回调中 `AVAudioConverter(...)`。

- [ ] **步骤 4：接入生命周期并补日志。** 在 `SpeechInputService.startTranscribing` 完成 `analyzerFormat` 后创建 session converter；把 converter 传给 `installMicrophoneTap`；每次 yield 前记录转换后的 `frameLength`、rate 和非零 frame count（节流为 DEBUG 级别），不要只记录输入 buffer。清理时先停止 tap，再 finish input，最终释放 analyzer、results task 和 converter。

- [ ] **步骤 5：运行 GREEN。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanSpeechGreen \
  -only-testing:AppleOnDeviceModelDemoTests/SpeechTranscriptAccumulatorTests test
```

验收：连续 converter 测试通过，既有 accumulator/lifecycle 测试无回归；Simulator 只证明转换逻辑，不证明端侧 transcript。

- [ ] **步骤 6：真机复测原症状两次。** 在测试 target 签名修复后执行：

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS,id=00008150-001202923A83401C' \
  -derivedDataPath /tmp/ApplePhysicalSpeechFix \
  -only-testing:AppleOnDeviceModelDemoTests/PhysicalDeviceSpeechTests test
```

用户在每次 8–12 秒窗口说 `Please explain the advantage of on-device AI.`。两次都必须出现至少一个非空 transcript、至少一个 result 回调和成功 finalize；只有“缓冲持续输入”仍归 `FAIL_APP`，不要标记 PASS。

## 任务 3：主页 Dynamic Type 自适应（P1）

**文件：**
- 修改：`AppleOnDeviceModelDemo/HomeView.swift:6-89`
- 修改：`AppleOnDeviceModelDemo/SharedExperienceViews.swift:3-45`
- 修改：`AppleOnDeviceModelDemoTests/ExperienceCatalogTests.swift`

**接口：**
- 新增纯值 `HomeHeaderLayout: Equatable`，取 `.horizontal` 或 `.vertical`。
- 新增 `HomeLayoutMetrics: Equatable`，公开 `headerLayout`、`featuredWidth`、`gridColumnCount`，并提供 `init(dynamicTypeSize: DynamicTypeSize, containerWidth: CGFloat)`。
- `featuredWidth <= containerWidth`；accessibility Dynamic Type 使用纵向 header、单列网格；标准字号使用横向 header、双列网格。

- [ ] **步骤 1：写 RED 布局策略测试。** 断言 `.large` + 390 宽得到 horizontal/2 列；`.accessibility1` + 390 宽得到 vertical/1 列；精选宽度不超过 390-40 的内容宽度。

```swift
@Test func homeMetricsSwitchForAccessibilityDynamicType() {
    let regular = HomeLayoutMetrics(dynamicTypeSize: .large, containerWidth: 390)
    let accessible = HomeLayoutMetrics(dynamicTypeSize: .accessibility1, containerWidth: 390)
    #expect(regular.headerLayout == .horizontal)
    #expect(regular.gridColumnCount == 2)
    #expect(accessible.headerLayout == .vertical)
    #expect(accessible.gridColumnCount == 1)
    #expect(accessible.featuredWidth <= 350)
}
```

- [ ] **步骤 2：运行 RED。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanHomeRed \
  -only-testing:AppleOnDeviceModelDemoTests/ExperienceCatalogTests test
```

预期：新类型/初始化器尚不存在，编译失败。

- [ ] **步骤 3：实现最小布局。** `HomeView` 读取 `@Environment(\.dynamicTypeSize)`，用 `GeometryReader` 或等价容器宽度计算 `HomeLayoutMetrics`；accessibility 时 Header 改为 VStack、标题保持完整词组并允许自然换行，分类 `LazyVGrid` 改单列。`FeaturedExperienceCard` 删除固定 `245` 宽和会被字体撑爆的最小高度，改为接收不超过容器的宽度上限；保留横向滚动和现有路由。

- [ ] **步骤 4：运行 GREEN 与现有目录测试。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanHomeGreen \
  -only-testing:AppleOnDeviceModelDemoTests/ExperienceCatalogTests test
```

- [ ] **步骤 5：真机视觉复测。** 重装新包并在当前文字大小截图；验收 `On-device Experiences` 不出现 `Experi-`/`ences`，首屏能看到完整标题、说明和至少一张完整精选卡，四分类仍可滚动访问。截图写入 `docs/device-test/2026-08-31/screenshots/home-fixed.png`。

## 任务 4：修复真机测试 target 签名阻塞

**文件：**
- 修改：`AppleOnDeviceModelDemo.xcodeproj/project.pbxproj:415-443`

- [ ] **步骤 1：用无命令行覆盖重现签名 RED。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS,id=00008150-001202923A83401C' \
  -derivedDataPath /tmp/AppleFixPlanSigningRed build-for-testing
```

预期：测试 bundle 报 requires a development team/provisioning profile；记录原始错误，不把它算作 App runtime 失败。

- [ ] **步骤 2：只改测试 target 的 Debug 与 Release 配置。** 在 `A00000000000000000000005` 和 `A00000000000000000000006` 的 `buildSettings` 中加入 `DEVELOPMENT_TEAM = DH255M46VJ;`，保留 `CODE_SIGN_STYLE = Automatic`、现有测试 Bundle ID 和 `TEST_HOST`；不改 App target 的 entitlements，不增加 adapter 权限。

- [ ] **步骤 3：无覆盖验证 GREEN。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS,id=00008150-001202923A83401C' \
  -derivedDataPath /tmp/AppleFixPlanSigningGreen build-for-testing
```

验收：App 和 test bundle 均完成签名；命令中没有 `DEVELOPMENT_TEAM=...` 覆盖；签名修复不改变产品能力资格。

## 任务 5：Translation/系统边界闭环（不以代码伪造资源）

**文件：**
- 读取：`AppleOnDeviceModelDemo/TranslationExperience.swift:11-18,113-121,171-194,304-351`
- 读取：`AppleOnDeviceModelDemoTests/TranslationExperienceTests.swift:8-18,62-76,305-315`
- 更新：`docs/device-test/2026-08-31/execution-results.md`

- [ ] **步骤 1：先运行 Translation 单测确认当前映射。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanTranslation \
  -only-testing:AppleOnDeviceModelDemoTests/TranslationExperienceTests test
```

验收：`.supported == .assetsRequired`、页面 detail 明确要求下载 source/target assets；若单测通过，不修改 Translation 生产代码。

- [ ] **步骤 2：用户完成系统前置条件。** 在 iPhone 上允许 Translation session 准备并安装英语与简体中文资产；不要把 `.supported` 改成 `.ready`，不要增加网络 fallback。

- [ ] **步骤 3：真机复测并记录。** 仅在 `LanguageAvailability().status(from:to:) == .installed` 后输入 `On-device processing protects privacy.`，观察非空真实译文；仍为 `.supported` 继续记录 `BLOCKED_SYSTEM`。ImageCreator 的 unsupported 同理保留 `BLOCKED_SYSTEM`。

## 任务 6：最终回归与证据交付

**文件：**
- 更新：`docs/device-test/2026-08-31/execution-results.md`
- 更新：`docs/device-test/2026-08-31/fix-plan-input.md`
- 更新：`docs/ios26-manual-test-checklist.md`

- [ ] **步骤 1：运行 Simulator 全量回归。**

```bash
xcodebuild -project AppleOnDeviceModelDemo.xcodeproj -scheme AppleOnDeviceModelDemo \
  -destination 'platform=iOS Simulator,id=CC5B0062-AF46-4ABE-8579-9D448208D0B6' \
  -derivedDataPath /tmp/AppleFixPlanFullSimulator \
  CODE_SIGNING_ALLOWED=NO clean test
```

验收：退出码 0，记录实际 `tests/suites` 和 xcresult；不能用历史的 175/12 结果替代本次输出。

- [ ] **步骤 2：运行无覆盖的真机全量测试。** 使用 `-destination 'platform=iOS,id=00008150-001202923A83401C'` 和独立 `/tmp/AppleFixPlanFullDevice`，记录签名、安装、测试执行和 xcresult；所有未直接观察的页面继续为 `NEEDS_USER_ACTION`。

- [ ] **步骤 3：重复关键真机用例。** Speech 连续录音两次；Foundation default 保留已观察的真实 PASS；Content Tagging 使用 typed route 复测并保留 refusal 原因；Translation 只有 `.installed` 才运行真实翻译；SoundAnalysis、NaturalLanguage、Vision OCR 保留直接证据。

- [ ] **步骤 4：按枚举更新结果。** 每条记录包含 Case ID、输入、预期、实际、结果枚举、原始日志、截图、设备/OS 和 xcresult。明确写出：App 修复项为 NAV-01/AUDIO-03；系统阻塞为 Foundation availability/Content Tagging refusal（按复现分流）、Translation assets、ImageCreator；签名是 test-infrastructure；交互未完成项为 `NEEDS_USER_ACTION`。

## 完成门槛

- `ExperienceCatalogTests` 中的 Home layout assertions 和 Speech converter RED→GREEN 均有新鲜命令输出；全量 Simulator test/build 退出码为 0。
- 真机 test target 在无 `DEVELOPMENT_TEAM` 命令行覆盖时可签名执行。
- Speech 两次真机录音均出现非空 transcript；否则保持 `FAIL_APP`，不得以 converter 日志代替结果。
- 首页截图没有词内断行或首屏卡片截断。
- Content Tagging/Translation 只在系统前置条件满足时报告真实输出；不可用或拒绝时保留原始原因。
- 每个未完成人工交互明确为 `NEEDS_USER_ACTION`，不把安装成功、编译成功、Simulator 或单元测试结果当作端侧模型通过。
