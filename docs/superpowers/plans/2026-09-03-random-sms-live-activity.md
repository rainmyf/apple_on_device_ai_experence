# 随机短信端侧分类实况窗 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在“系统智能调用 App”页面从内置五类短信集合随机抽取一条，真实调用 `SystemLanguageModel.default` 完成分类与字段提取，并将结果更新到实况窗。

**Architecture:** 通过一次性的本地生成脚本，从用户指定的四个 `*_all.jsonl` 文件各复制十条脱敏短信，再加入四条用户提供的俄文天气样本，形成随 App 打包的 JSONL。`SMSIncomingSamplePool` 只负责读取和随机选择；页面调用现有 `RunOnDeviceModelIntent.execute`，后者保留真实 Foundation Model 和 ActivityKit 链路。

**Tech Stack:** Swift 6、SwiftUI、FoundationModels、ActivityKit、Swift Testing、iOS 27 真机；不使用 Simulator、云端、第三方模型或数据库。

**Spec:** `docs/superpowers/specs/2026-09-03-sms-live-activity-design.md`

## Global Constraints

- 样本类别固定为 `delivery`、`bank_repayment`、`train_waitlist_success`、`weather_alert`、`ordinary`。
- 语料来源固定：`pickup_self_code` 10 条、`pickup_special_place` 10 条（均显示为快递）；`repayment_reminder` 10 条；`standby_success` 10 条；`ignored` 10 条；俄文天气样本 4 条。
- 按用户确认，脱敏样本可以进入仓库和 App bundle；不上传运行时模型输出或额外日志。
- 点击随机短信不调用模型；只有“分析并显示通知”调用本机 `SystemLanguageModel.default`。
- 任何模型失败都不得伪造“提取成功”，页面展示错误，实况窗不更新为伪造结果。

### Task 1: 建立样本池与资源契约

**Files:**
- Create: `AppleOnDeviceModelDemo/SMSIncomingSamplePool.swift`
- Create: `AppleOnDeviceModelDemo/Resources/sms_incoming_samples.jsonl`
- Create: `AppleOnDeviceModelDemoTests/SMSIncomingSamplePoolTests.swift`
- Modify: `AppleOnDeviceModelDemo.xcodeproj/project.pbxproj`

- [ ] 写一个 RED 测试，断言 JSONL 可读取、五类都存在、快递总数为 20（两个快递子类各十条）、其余四类各为 10/10/4/10，且随机选择始终返回非空正文。
- [ ] 在连接的 iPhone test destination 编译该测试，确认因缺少样本池类型而失败。
- [ ] 最小实现 `SMSIncomingSample` 与 `SMSIncomingSamplePool`：从 bundle JSONL 解码、按类别随机选择、空池时返回明确错误。
- [ ] 生成资源并加入 App Resources build phase；重新运行同一真机测试，确认通过。

### Task 2: 将真实分类连接到页面

**Files:**
- Modify: `AppleOnDeviceModelDemo/SystemIntelligenceToAppVerificationView.swift`
- Modify: `AppleOnDeviceModelDemoTests/ExperienceAppIntentsTests.swift`

- [ ] 写 RED 测试，给定一条抽样短信与确定性分类器，断言 `RunOnDeviceModelIntent.execute` 接收原文并先后发送 analyzing/classified 状态。
- [ ] 在真机 test destination 编译，确认测试捕获新页面/流程接口缺失。
- [ ] 页面新增“随机短信”和“分析并显示通知”：显示已选正文、选中类别来源；分析时禁用按钮、记录耗时、只在 `source == .model` 时展示成功状态。
- [ ] 页面调用 `RunOnDeviceModelIntent.execute` 的真实默认依赖，不使用 fixture 或 fake 结果。
- [ ] 在真机执行确定性单元测试，确认通过。

### Task 3: 真机构建与手工闭环验证

**Files:**
- Modify: `docs/superpowers/evidence/2026-09-03-sms-live-activity-evidence.md`（如不存在则创建）

- [ ] 使用 Xcode 27 连接的 `NetTeam’s iPhone` Build & Run，不使用 Simulator。
- [ ] 页面依次抽取并分析至少一条快递、还款、候补、天气、普通短信；记录模型 availability、分类、提取摘要、模型耗时和实况窗可见性。
- [ ] 若模型不可用、真机断开或实况窗未出现，记录实际错误并停止宣称已通过。
