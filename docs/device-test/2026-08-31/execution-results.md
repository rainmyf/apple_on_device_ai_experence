# iOS 26 真机测试执行结果

> 结果仅记录直接证据。`PASS`、`FAIL_APP`、`BLOCKED_SYSTEM`、`NEEDS_USER_ACTION`、`NOT_APPLICABLE` 的定义见真机 Test Plan。

## 基线结果

| Case | 页面/范围 | 实际结果 | 结论 | 证据 |
| --- | --- | --- | --- | --- |
| ENV-01 | 构建/签名 | iPhone 17 Pro Max arm64 构建成功 | PASS | `/tmp/AppleExperiencesPhysicalDevice` |
| ENV-02 | 安装/启动 | 安装并启动成功，无启动崩溃 | PASS | `devicectl` 输出、Xcode 控制台 |
| NAV-01 | 主页布局 | 标题被断成 `On-device / Experi- / ences`，首屏卡片异常巨大，信息密度和入口可达性严重下降 | FAIL_APP | `screenshots/home-baseline.png` |
| NAV-01-SIM-FOLLOWUP | 主页布局（修复后 Simulator） | 新鲜 Simulator 截图中标题完整显示，分类区为双列卡片，未观察到基线的词内断行 | PASS（仅 Simulator 视觉证据） | `screenshots/02-home-grid-fixed-simulator.png`（2026-08-31 20:36） |
| AUDIO-02 | Speech 数据入口 | 已观察到 48 kHz 单声道麦克风 buffer，并转换到 16 kHz | 不构成通过 | Xcode 控制台历史日志 |
| AUDIO-03 | Speech 输出 | 多轮录音未观察到 transcript；控制台出现 `Result accumulator timeout` | FAIL_APP（待进一步复现） | Xcode 控制台历史日志 |

## 待执行用例

## 自动化真机结果

| Case | 页面/范围 | 实际结果 | 结论 | 证据 |
| --- | --- | --- | --- | --- |
| TEST-ALL | 既有 Swift 测试 | 音频会话修复后的最新 Simulator 回归 181/181 通过 | PASS | `/tmp/apple-full-repair-sim-final`（2026-08-31 21:04） |
| FM-01 | Foundation Model | `SystemLanguageModel.default.availability = available`，真实生成返回非空结果 | PASS | `/tmp/apple-device-final`（2026-08-31 20:48） |
| FM-05 | Content Tagging | route-specific model 为 `available`，typed `ContentTags` 链路执行成功 | PASS | `/tmp/apple-device-final`（2026-08-31 20:48） |
| FM-02/03/04/06-12 | Guided/Streaming/Tool 等页面链路 | 当前仅有模型可用性证据，未逐页执行真实输入/取消/重复操作 | NEEDS_USER_ACTION | 需用户在真机逐页操作 |
| LANG-01 | Translation | 英语→简体中文返回 `supported`，表示语言对支持但资产未安装 | BLOCKED_SYSTEM | `/tmp/apple-physical-system-diagnostics.log` |
| LANG-06 | NaturalLanguage | English，7 tokens，7 entities，sentiment Negative | PASS | `/tmp/apple-physical-native-diagnostics.log` |
| VISION-02 | Vision OCR | 对真机测试进程生成的图像识别出 `HELLO 26` | PASS | `/tmp/apple-physical-native-diagnostics.log` |
| AUDIO-03 | Speech Transcription | 新构建确认 48 kHz 麦克风输入、16 kHz Int16 interleaved 转换输出约 98% 帧非零，且 `AsyncStream` yield 均为 `enqueued`；仍为 0 个 result、0 transcript。已按 Apple 官方示例将下一版音频会话对齐为 `.playAndRecord/.spokenAudio`，待集中真机复测 | FAIL_APP | `/tmp/apple-full-repair-device`、`/tmp/apple-speech-yield-device`（2026-08-31 21:00–21:01） |
| AUDIO-08 | Sound Recognition | 收到真实分类更新，包括 `speech`、`music`、`door` | PASS | `/tmp/apple-physical-sound-runtime.log` |
| SYS-01 | Image Creator | 真机初始化成功并报告 5 种可用 styles；真实图片生成仍未逐页操作 | PASS（availability）/ NEEDS_USER_ACTION（生成） | `/tmp/apple-device-final`（2026-08-31 20:48） |
| SYS-06 | App Intent | 既有真实设备测试执行 `perform()` 的确定性输出验证通过 | PASS（App 内调用边界） | `/tmp/apple-experiences-physical-tests2.log` |
| SYS-07 | Custom Adapter | 未配置 entitlement 与 `.fmadapter`，保持 setup-only | NOT_APPLICABLE | 真机测试 + 签名 entitlements |

## 需要用户在手机上完成的交互

以下用例已执行到系统/交互边界，但当前 Mac 工具没有真机触控控制能力，因此不标记通过：

| Case | 操作 | 当前结论 |
| --- | --- | --- |
| NAV-02 至 NAV-05、NAV-08 | 逐一点击并返回 17 个页面、后台切换 | NEEDS_USER_ACTION |
| FM 其余页面链路 | 逐页输入、取消、重复运行 Guided/Streaming/Tool 等页面 | NEEDS_USER_ACTION |
| LANG-02 至 LANG-05 | 允许 Translation 下载英语/简体中文资产并运行 session | NEEDS_USER_ACTION |
| VISION-01、VISION-03 至 VISION-08 | 从 PhotosPicker 选择真实照片并切换模式 | NEEDS_USER_ACTION |
| AUDIO-01、AUDIO-04 至 AUDIO-07 | 页面按钮、权限拒绝、第二轮录音和交替音频 session | NEEDS_USER_ACTION；底层 Speech 已确定失败 |
| SYS-02 至 SYS-05 | Image Playground、Writing Tools、Genmoji、Smart Reply 系统 UI | NEEDS_USER_ACTION / 系统决定可用性 |
| ROBUST-01 至 ROBUST-10 | 飞行模式、关闭 Wi-Fi、离线重跑 | NEEDS_USER_ACTION |

## 结论边界

“全量执行”表示每个 Test Plan 能力组均已获得 `PASS`、`FAIL_APP`、`BLOCKED_SYSTEM`、`NEEDS_USER_ACTION` 或 `NOT_APPLICABLE` 分类，不表示所有能力均已成功。当前仍未闭环的 App 缺陷是 `NAV-01`（修复后仅有 Simulator 视觉证据，待真机截图）与 `AUDIO-03`（真机仍无 transcript）。Foundation Model 两条真机链路和 ImageCreator availability 已不再是系统阻塞；Translation 语言资产仍为 `BLOCKED_SYSTEM`，其余未逐页执行项保留 `NEEDS_USER_ACTION`。
