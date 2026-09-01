# iOS 26 真机全量测试实施计划

> **面向执行代理：** 必须使用 `superpowers:executing-plans` 按阶段执行本计划。测试发现缺陷时使用 `superpowers:systematic-debugging`；在生成修复计划前不得修改生产代码。步骤使用复选框 (`- [ ]`) 跟踪。

**目标：** 在已连接的 iPhone 17 Pro Max（iOS 26.6）上，对 17 个独立体验页执行可追溯的真机测试，区分 App 缺陷、系统资格/资源限制和仅系统 UI 的能力边界，并基于失败证据生成修复计划。

**架构：** 使用 Xcode 真机构建、`devicectl` 安装/启动/收集日志、Xcode 设备截图和 Swift/XCTest 自动化覆盖可自动化状态；麦克风、照片选择、系统 UI、飞行模式等必须人工交互的边界单独记录。每个用例保存输入、预期、实际、日志/截图、耗时、可用性原因和结论，不以模拟器结果替代真机能力结果。

**技术栈：** Xcode 26.6、iOS 26.5 SDK、iPhone 17 Pro Max iOS 26.6、Swift Testing、XCTest/XCUITest（仅在现有工程支持时）、`xcodebuild`、`xcrun devicectl`、Xcode Devices and Simulators。

**规格：** `docs/superpowers/specs/2026-08-26-ios26-on-device-experiences-design.md`

## 全局约束

- 不修改生产代码；本轮只测试、收集证据和生成修复计划。
- 不把安装成功、编译成功或单元测试成功解释为端侧模型运行成功。
- 不使用 `SFSpeechRecognizer`、云端模型、第三方模型、Core ML 自定义模型或 MLX。
- 每次只运行一个体验页的一个能力，不执行聚合 benchmark 或“全部运行”。
- 系统 UI 能力只验证公开入口能否打开及边界说明是否准确，不伪造结果。
- 所有不可用状态必须记录原始系统原因；无法自动化的用例标记 `NEEDS_USER_ACTION`，不得标记通过。
- 真机测试期间不改变 Apple ID、Apple Intelligence、网络、隐私或开发者设置；需要改变时先由用户操作。

---

## 证据目录与结果格式

创建目录：

```text
docs/device-test/2026-08-31/
├── environment.md
├── execution-results.md
├── console.log
├── screenshots/
└── fix-plan-input.md
```

每个用例使用以下结果枚举：

- `PASS`：真机上观察到与预期一致的真实结果。
- `FAIL_APP`：App 代码、交互、布局、状态或错误处理错误。
- `BLOCKED_SYSTEM`：系统资格、资源、语言、权限或系统 UI 不可用，App 已诚实呈现。
- `NEEDS_USER_ACTION`：必须由用户说话、选择照片、切换网络或操作系统 UI，尚未观察。
- `NOT_APPLICABLE`：当前设备/配置不适用，且产品说明准确。

每条结果必须包含：`Case ID`、页面、前置条件、输入、预期、实际、结果枚举、耗时、availability 原因、日志片段、截图路径、设备/OS、在线状态。

---

### 任务 1：建立真机基线与证据目录

**文件：**
- 创建：`docs/device-test/2026-08-31/environment.md`
- 创建：`docs/device-test/2026-08-31/execution-results.md`
- 创建：`docs/device-test/2026-08-31/fix-plan-input.md`

- [ ] 运行 `xcrun devicectl list devices` 和 `xcrun devicectl device info details --device E092BF34-649E-5482-B1B6-3B965870FF8A`。
- [ ] 记录设备型号、UDID、iOS 版本、连接方式、Developer Mode 和 DDI 状态。
- [ ] 真机构建并记录签名身份、Provisioning Profile、Bundle ID 和最终退出码。
- [ ] 安装并启动 App，捕获从启动到退出的完整控制台日志。
- [ ] 使用 Xcode `Take Screenshot` 保存主页原始分辨率截图。
- [ ] 记录用户可见的系统语言、当前 Dynamic Type 视觉表现和 Apple Intelligence 是否已由用户确认开启；无法读取的字段不得推断。

**通过门槛：** 真机构建、安装、启动均成功且 App 不在启动阶段崩溃。

### 任务 2：主页、导航和通用体验壳

**Case IDs：** `NAV-01` 至 `NAV-08`

- [ ] `NAV-01`：主页标题、Logo、精选区和四个分类区均可通过滚动访问；文本不被逐字/异常断行。
- [ ] `NAV-02`：三张精选卡均可横向访问并进入对应独立页面。
- [ ] `NAV-03`：四个 `See all` 均进入正确分类页。
- [ ] `NAV-04`：17 个体验入口均可打开并返回，导航栈无错页或空白页。
- [ ] `NAV-05`：不可用页面仍可阅读简介、状态和使用说明。
- [ ] `NAV-06`：默认真机文字大小下，按钮、输入区、结果区无遮挡；记录当前截图中标题三行断裂问题。
- [ ] `NAV-07`：横竖屏策略与 App 声明一致；若仅竖屏，旋转不破坏状态。
- [ ] `NAV-08`：前后台切换后，不遗留录音、生成或流式任务。

**通过门槛：** 17 个页面均可达；入口状态不能把静态 requirement 文案冒充实时 availability。

### 任务 3：FoundationModels 五条真实链路

**Case IDs：** `FM-01` 至 `FM-12`

对 Foundation Model、Guided Generation、Content Tagging、Streaming、Tool Calling 分别执行：

- [ ] 记录 `SystemLanguageModel.default.availability` 或 route-specific model availability 的真实映射。
- [ ] 可用时使用页面默认输入执行一次，记录真实输出、耗时和控制台错误。
- [ ] 空白输入不得创建 session，页面必须给出明确错误。
- [ ] 连续点击不得启动重复请求。
- [ ] Streaming 在首个 partial 后取消，必须保留最后 partial 且停止更新。
- [ ] Tool Calling 只允许 `lookupCapability` 本地工具；不产生网络请求。
- [ ] Content Tagging 使用 `.contentTagging` use case，而非默认模型伪装。
- [ ] Guided Generation 返回真实 typed fields；解码失败必须显示错误。

**输入：**

```text
Foundation: Explain on-device AI in one sentence.
Guided: Book a trip to Tokyo next spring.
Tagging: I am excited to review the Tokyo budget meeting tomorrow.
Streaming: Give three concise benefits of on-device AI.
Tool: Which local capability handles speech transcription?
```

**通过门槛：** availability 为 `.available` 时必须获得真实模型结果；否则必须保留 Apple 原始不可用原因且按钮禁用逻辑与状态一致。

### 任务 4：Translation 与 NaturalLanguage

**Case IDs：** `LANG-01` 至 `LANG-08`

- [ ] Translation 选择英语到简体中文，输入 `On-device processing protects privacy.`。
- [ ] 记录 language asset 状态；需要下载时显示资源准备状态，不误报 Apple Intelligence 不可用。
- [ ] 同语言组合被阻止；切换语言会取消并解绑旧 session。
- [ ] 成功时结果非空且耗时可见；失败时保留系统错误。
- [ ] NaturalLanguage 输入 `Apple opened a research office in Moscow.`，记录语言、tokens、entities、sentiment。
- [ ] NaturalLanguage 空输入失败；取消或重复运行不发布陈旧结果。

**通过门槛：** NaturalLanguage 在该设备上无需 Apple Intelligence 即可运行；Translation 的阻塞原因必须是语言资产/语言对，而不是 Foundation Model 状态。

### 任务 5：Vision

**Case IDs：** `VISION-01` 至 `VISION-08`

- [ ] 用户从 PhotosPicker 选择一张包含清晰英文文本和物体的测试图。
- [ ] OCR、分类、条码（若图片包含）、人体姿态（若图片包含）逐模式单独运行。
- [ ] 结果包含真实文本/标签、confidence 和正确方向坐标。
- [ ] 快速更换图片时，旧图片的迟到结果不得覆盖新选择。
- [ ] 取消选择后清空 preview、findings、latency 和 error。
- [ ] 权限拒绝或选择取消不崩溃。

**通过门槛：** 至少 OCR 与分类对合适测试图产生真实结果；其他模式可因输入不适用返回诚实空状态。

### 任务 6：Speech 与 SoundAnalysis

**Case IDs：** `AUDIO-01` 至 `AUDIO-12`

- [ ] Speech 首次请求麦克风权限，拒绝时显示可恢复错误。
- [ ] 允许权限后说：`Please explain the advantage of on-device AI.`
- [ ] 录制 5–10 秒，观察 volatile transcript；停止后观察 final transcript 与 latency。
- [ ] 日志记录 locale、asset status、麦克风格式、analyzer 格式、每次转换后的非零 frameLength、result 回调和 finalize 结果。
- [ ] 第二次录音不复用已结束 analyzer，且不会超时/无结果。
- [ ] Sound Recognition 录制拍手/铃声，返回系统 classifier 的真实标签与 confidence。
- [ ] Speech 与 SoundAnalysis 交替运行后音频 session 正确释放。

**通过门槛：** 麦克风缓冲被送入分析器不算通过；Speech 必须得到真实 transcript，SoundAnalysis 必须得到真实分类结果。

### 任务 7：Image Creator 与系统 UI 能力

**Case IDs：** `SYS-01` 至 `SYS-12`

- [ ] Image Creator 输入 `A blue robot reading beside a mountain lake`；可用时返回真实图片与耗时。
- [ ] Image Playground 打开系统 sheet，取消和完成均正确回到 App。
- [ ] Writing Tools 在可编辑文本上显示系统入口；操作结果由系统产生。
- [ ] Genmoji 页面只说明并进入系统文本输入路径，不伪造生成结果。
- [ ] Smart Reply 页面诚实说明系统集成边界，不展示假的建议。
- [ ] App Intent 执行 `DescribeDemoCapabilityIntent.perform()` 并显示确定性结果。
- [ ] Custom Adapter 在未配置 `.fmadapter` 与 entitlement 时保持 setup-only，不误报 ready。

**通过门槛：** 公开 API 可用时出现真实系统 UI/输出；不可用时页面说明准确且不崩溃。

### 任务 8：离线、生命周期和权限回归

**Case IDs：** `ROBUST-01` 至 `ROBUST-10`

- [ ] 已完成所需资产下载后，由用户打开飞行模式并关闭 Wi-Fi。
- [ ] 重跑 Speech、Foundation Model、Translation（已安装语言资产）并记录离线结果。
- [ ] 每个运行中页面执行返回/切后台，确认任务取消且无迟到结果。
- [ ] 重启 App，确认不依赖上次内存状态才能使用。
- [ ] 权限拒绝、资源未准备、设备不符合资格均不会崩溃。
- [ ] 检查日志中无 URLSession、云 fallback 或第三方模型调用证据。

**通过门槛：** 只对已直接观察成功的能力标记离线通过；系统资源未下载标记 `BLOCKED_SYSTEM`。

### 任务 9：汇总结果并生成修复计划

**文件：**
- 更新：`docs/device-test/2026-08-31/execution-results.md`
- 更新：`docs/device-test/2026-08-31/fix-plan-input.md`
- 创建：`docs/superpowers/plans/2026-08-31-ios26-physical-device-fix-plan.md`

- [ ] 按 `FAIL_APP`、`BLOCKED_SYSTEM`、`NEEDS_USER_ACTION` 分类，不混合统计。
- [ ] 每个 `FAIL_APP` 关联最小复现步骤、日志、截图和疑似代码边界。
- [ ] 按 P0（崩溃/所有核心能力阻断）、P1（单能力不可用/严重布局）、P2（错误文案/可访问性）排序。
- [ ] 修复计划中每个任务使用 RED→GREEN→真机复测，给出精确文件、测试命令和验收条件。
- [ ] 修复计划不得包含没有证据支持的改动。

**完成门槛：** 所有 Case ID 均有结果枚举；任何未由真机观察的项目不得标记 `PASS`。
