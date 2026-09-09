# iOS 27 真机 Evidence Record

日期：2026-09-03  
设备：NetTeam's iPhone（`00008150-001202923A83401C`，iPhone18,2）  
iOS：27.0（24A5430a）  
Xcode：27.0 beta 6（27A5252f）  
工程目标：iOS 27.0

## 已有证据

| 入口/功能 | API 或 profile | 结果 | 证据 |
|---|---|---|---|
| App → 端侧模型目录 | `ExperienceCatalog` + iOS 27 metadata | 通过 | 核心真机测试 |
| On-device Model Lab seam | `SystemLanguageModel.default` metadata、`LanguageModelSession`、text/image/local-search profiles | 通过 | 58 tests / 4 suites |
| Foundation Model 真机样例 | `FoundationModelService` default/content-tagging | 通过 | 串行全量回归中的 `PhysicalDeviceFoundationModelTests` |
| Vision 分割 seam | `GenerateIterativeSegmentationRequest`、orientation、progress、cancel、point/box/scribble | 通过 | `VisionSegmentationExperienceTests` |
| AppIntent 路由 | `.system.searchInApp`、`.system.open`、共享 `AppNavigationState` | 通过 | query/route tests，隐藏 SMS 直接构造也拒绝 |
| Shortcut 注册 seam | `AppShortcutsProvider` + “运行端侧模型” | 通过 | provider/metadata tests |
| iOS 27 构建 | iPhoneOS SDK | 通过 | `/tmp/ios27-final-build.log`，`** BUILD SUCCEEDED **` |

核心回归结果：
`/tmp/ios27-final-core-tests3/Logs/Test/Test-AppleOnDeviceModelDemo-2026.09.03_11-47-25-+0300.xcresult`，59/59 通过。

## 未完成的人工系统入口证据

以下不以自动化 seam 测试冒充完成：

- 在 Spotlight UI 搜索并点开可见体验、确认 SMS 不出现；
- 在 Shortcuts UI 添加并执行“运行端侧模型”，记录真实返回文本、模型耗时和状态；
- Siri 语音入口（仅增强证据）；
- Vision 页面真实照片的三种 seed、正/负修正、资产首次下载和断网复测；
- Model Lab 真实图片触发 `OCRTool`/`BarcodeReaderTool`、本地内容触发 `SpotlightSearchTool`。

这些项目需要在已解锁 iPhone 上进行 UI 操作；当前 CLI 只完成了物理测试目标执行，未生成上述手工截图/录屏或系统入口日志。

## 全量回归边界

串行执行除旧 960 条 SMS benchmark 外的完整测试：290 tests / 28 suites 中 289 通过，唯一失败为 `PhysicalDeviceSpeechTests.transcribesAcousticInputOnPhysicalDevice`，日志为 `AUDIO-03|FAIL_APP|No transcript returned`。测试期间音频输入帧已采集并正常送入 SpeechAnalyzer，但没有可用语音文本；这是现场没有提供可识别语音的设备输入证据，不应与编译失败混同。960 条 benchmark 运行已停止，避免占用真机长时间，不纳入本轮体验验收。

未使用或下载 Simulator；未验证第三方模型 Provider、Private Cloud Compute（PCC）或云端 fallback。
