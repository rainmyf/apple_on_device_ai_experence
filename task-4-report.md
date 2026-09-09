# Task 4 报告：系统智能 → App

## 实现

- `ExperienceEntity` / `ExperienceEntityQuery` 基于 `IndexedEntity` 和 `EntityStringQuery` 暴露可见体验目录；`smsClassification` 不进入建议、字符串查询或 Spotlight 写入。
- `ExperienceIndexing` 使用 `CSSearchableIndex` 清理本应用体验域后重建可见条目，并写入标题、简介、框架、最低系统版本、开放 API 等元数据。
- `SearchExperiencesIntent` 使用 iOS 27 公开 `@AppIntent(schema: .system.searchInApp)`，通过共享 `AppNavigationState` 打开应用内搜索页。
- `OpenExperienceIntent` 使用 iOS 27 公开 `@AppIntent(schema: .system.open)`，通过共享导航状态打开目标体验。
- `RunOnDeviceModelIntent` 提供 Shortcut 动作“运行端侧模型”，复用现有 `FoundationModelService`，生产路径仍为 `SystemLanguageModel.default`，无云端 fallback。
- App 生命周期在首次内容出现时重建 Spotlight 索引，并处理 `CSSearchableItemActionType` 回调；SMS 回调同样被拒绝。

## 确定性验证

- 新增 `AppleOnDeviceModelDemoTests/ExperienceAppIntentsTests.swift`，覆盖目录过滤、标题/框架/API 查询、标识符解析、Spotlight 元数据、搜索/打开导航、Foundation Model service 注入，以及 Shortcut 元数据边界。
- 测试先于生产实现加入；初始 focused build 对缺失的实体和 App Intent 类型报错（RED），完成实现后使用 Xcode 27、iOS 27 SDK 的 `build-for-testing` 成功（GREEN）。成功日志为 `/tmp/task4-green4.log`，产物为 `build/task4-green4`，日志包含 `Writing Metadata.appintents` 以及 Shortcut 训练短语 `运行端侧模型 ${+applicationName}`。
- 当前主任务已在物理目标执行确定性测试，核心测试结果为 59 项通过（含隐藏 SMS 直接构造拒绝、Spotlight 可见项和 Shortcut provider 契约）。该结果不等同于系统入口手工验证。

## 尚未验证的物理链路

以下需要连接的真实 iPhone 和可用的 Spotlight/Shortcuts 环境，当前未声称完成：

- 在 Spotlight 中搜索可见目录并点开条目；确认 SMS 不可见。
- 从 Spotlight 或系统打开入口进入具体体验。
- 在 Shortcuts 中添加并执行“运行端侧模型”，记录入口来源、耗时和设备错误。
- Siri 语音入口与 Siri enhancement 行为。Task 4 只提供 App Intents/Shortcuts 基础能力；Siri enhancement 是独立的增强证据，不以本报告的确定性测试替代。

当前连接的物理设备为 `NetTeam's iPhone`（UDID `00008150-001202923A83401C`，iOS 27.0）；已使用该设备执行 focused 与串行回归。Spotlight、Shortcuts、Siri 的系统级手工入口仍未操作，因此不把自动化结果当作这些入口的完成证据。

在受限沙箱内重复构建会触发 Swift macro plugin server 的 `sandbox_apply: Operation not permitted` / `malformed response`；这属于当前构建环境限制，不能作为 API 不兼容结论。此前成功的 iOS 27 真机构建使用了相同工程和 `SWIFT_ENABLE_EXPLICIT_MODULES=NO`。

未提交、未推送、未合并；保留工作区中 Task 1/2/3 与 SMS 的既有脏改动。
