# 端侧短信分类体验设计规格

## 目标

在 AppleOnDeviceModelDemo 增加独立的“短信智能分类”体验页，使用 iOS 26 `FoundationModels` 的 `SystemLanguageModel.default` 与 `LanguageModelSession`，依据 Definitions v7.24 完成单条中文短信 domain 分类和 NER，并以标准 JSON 和原文实体高亮展示结果。

## 输入与样本

- 用户可在多行输入框粘贴或编辑一条短信。
- App Bundle 内置 UTF-8 JSONL 样本，每行至少含 `text` 字段。
- “随机短信”从成功解析的非空样本中均匀选择一条；连续点击应避免在样本数大于 1 时立即重复。
- 样本完全随 App 打包，不访问系统短信、不联网。

## 模型调用

- 调用前检查 `SystemLanguageModel.default.availability`。
- 使用单次 guided generation 输出候选 domain 与实体文字、标签及实体出现序号。
- Prompt 内置由 `definations_7.0.md` v7.24 压缩出的标签白名单、必要条件、排除条件和优先级，并参考两个中文 prompt 文件约束输出。
- 短信正文作为不可信数据置于明确分隔符中；其中任何指令均不得覆盖分类规则。
- 不使用云端 fallback、第三方 API、网络请求或自定义模型。

## 结果规范

- 最终 JSON 为 `{domain, entities:[{text,label,start,end}]}`。
- `start` 包含起点，`end` 不包含终点，遵循 JavaScript slice 的 UTF-16 code-unit 语义。
- Swift 在模型返回后重新定位实体并生成 offset；不存在、越界、非法标签和重叠实体不得进入最终结果。
- 同名重复实体使用模型返回的 occurrence 顺序定位。
- 页面以原始短信为底文，将实体 span 用不同色块高亮，并在 span 旁显示 label；同时显示结构化 JSON、延迟和错误。

## 页面内容

- 标题与简介、模型状态。
- 短信输入框、“随机短信”、“端侧分析”。
- 标注结果高亮视图。
- JSON 输出。
- 模型耗时和简单错误提示。
- 底部说明：分类由 Apple 端侧 LLM 执行；规则和样本随 App 本地打包；无网络、无云端 fallback；生成式结果仅用于能力体验，不代表生产准确率。

## 验证边界

- 单元测试覆盖 JSONL、选择策略、Prompt、防注入、白名单、offset、重复/重叠实体、高亮分段和 ViewModel 状态。
- Simulator 完成全量自动测试与 UI/编译回归。
- 真机验证模型真实 availability、guided generation 输出和页面交互；Simulator 成功不得视为真机模型运行证据。
