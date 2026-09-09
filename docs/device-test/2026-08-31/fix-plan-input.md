# 修复计划输入证据

## 仍需闭环的 App 失败

### NAV-01：主页动态字体布局不可用

- 复现：在当前真机启动 App。
- 实际：固定横向 Header 在大字号下挤压标题，出现三行和词内断行；精选卡片固定 `245 × >=300` 再被动态字体放大，首屏仅可见部分卡片。
- 代码边界：`AppleOnDeviceModelDemo/HomeView.swift`、`AppleOnDeviceModelDemo/SharedExperienceViews.swift`。
- 证据：`screenshots/home-baseline.png`。

### AUDIO-03：Speech 收到音频但未输出 transcript

- 复现：真机进入 Speech Transcription，录制并停止。
- 实际：控制台反复记录 48 kHz→16 kHz 转换，未观察到 `SpeechTranscriber.Result`；出现 result accumulator timeout。
- 代码边界：`AppleOnDeviceModelDemo/SpeechInputService.swift`。
- 当前实现已改为一次录音生命周期复用一个 `SpeechAudioBufferConverter`，并设置 `primeMethod = .none`；因此“每 buffer 新建 converter”只属于历史基线，不再是当前代码事实。
- 最新 Simulator converter focused test 已通过，但这只能证明连续转换逻辑，不能证明真机 SpeechTranscriber 输出。
- 状态：真机复测仍未完成；在获得两次非空 transcript、result callback 和成功 finalize 前继续保持 `FAIL_APP`。
- 证据：`/tmp/AppleFixPlanSpeechGreen3.log`、`/tmp/AppleFixPlanSpeechExperiment1.log`（2026-08-31 Simulator focused pass）；历史真机失败 `/tmp/apple-physical-speech-runtime.log`。

## 已补齐真机证据

- 真实声学测试窗口：12 秒。
- locale：`en_US`。
- 输入：48 kHz、单声道、每 buffer 4800 frames。
- analyzer 格式：16 kHz。
- 观察：大量 buffer 被送入转换路径，无 conversion error、无 result callback、最终 transcript 为空。
- 测试结论：`FAIL_APP`，日志 `/tmp/apple-physical-speech-runtime.log`。
- 该结论来自修复前真机运行；修复后尚无真机 Speech transcript 证据，不能改标为 PASS。

## 最新真机/Simulator 证据边界

- Foundation default：真机 `SystemLanguageModel.default.availability = available`，真实生成成功，`FM-01 = PASS`。
- Content Tagging：真机 route-specific model 为 `available`，typed `FoundationModelService.tag` 成功，`FM-05 = PASS`。
- ImageCreator：真机初始化成功，`styles=5`，availability `PASS`；实际图片生成仍需用户逐页输入，保留 `NEEDS_USER_ACTION`。
- Home：`02-home-grid-fixed-simulator.png` 是 2026-08-31 20:36 的新鲜 Simulator 视觉证据；修复后真机截图尚未取得，`NAV-01` 的真机缺陷记录继续保留。
- Simulator：`/tmp/apple-full-repair-sim-final` 为最新全量回归证据，报告 181/181 通过；不能替代真机模型、麦克风或系统 UI 证据。

## 仍存在的系统阻塞，不进入代码修复

- Translation：英语→简体中文状态为 `.supported`，资产未安装。
- Custom Adapter：签名中没有 adapter entitlement，且工程没有 `.fmadapter`。

## 仍需用户操作

- Foundation 的 Guided/Streaming/Tool 页面需要逐页输入、取消和重复操作；不能由 FM-01/FM-05 的模型可用性 PASS 推导。
- ImageCreator 真实图片生成、Image Playground/Writing Tools/Genmoji/Smart Reply 系统 UI、PhotosPicker、离线/权限/前后台回归仍未直接观察。
