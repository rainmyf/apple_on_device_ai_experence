# SMS 真机 F1 评测设计

## 目标

从 `/Users/rain/project/ai_sms/dataset/domains/**/**_all.jsonl` 中，对每个实际出现的完整 domain 去重后固定抽取 30 条短信，在支持 Apple Intelligence 的 iPhone 上调用正式 `SMSClassificationService`，计算 domain 与 entities 的准确性。

## 数据集

- 只读取文件名以 `_all.jsonl` 结尾的正式数据，禁止混入 `_real` 与 `_ai_generated` 文件造成重复。
- 以 JSONL 中的 `domain` 字段作为真值；当前实际出现 32 个 domain。
- 每个 domain 对 `text` 去重，使用稳定 SHA-256 排序，取前 30 条，生成固定测试资源。
- 保留评测所需字段：`msg_id`、`text`、`domain`、`entities(label,start,end,text)`；不修改源数据集。
- 测试资源只加入 test target，不加入正式 App bundle。

## 指标

- Domain：对每个完整 domain 计算 one-vs-rest precision、recall、F1；同时报告 accuracy、macro-F1、micro-F1 和混淆对。
- Entities：以 `(label,start,end)` 精确匹配为正确；按真值 domain 汇总每个 domain 的 TP/FP/FN、precision、recall、F1，并报告 micro/macro。
- 真值和预测都无实体时，该样本不增加 TP/FP/FN；若整个 domain 均无实体，entity F1 标记为 `N/A`，不得伪报为 1.0。
- 提交门槛：所有可评估 domain 的 domain F1 与 entity F1 均至少 0.90；任一项不足则不提交新评测改动。

## 执行

- FoundationModels 调用必须在真机串行运行，禁止并发 session 压测。
- 以 domain 为分片，每个分片 30 条；每条输出一行机器可解析 JSON，主机端追加到临时结果文件。
- 已完成的 `msg_id` 可跳过，支持中断后续跑。
- 模型错误、拒绝、超时均记录为失败预测，不从分母删除。

## 输出

- 临时抽样与原始预测放在 `/private/tmp`，未达门槛时不进入 Git。
- 生成汇总报告：整体指标、逐 domain 指标、主要混淆、实体标签错误、代表性失败样本，以及可能原因和修复建议。
- 达到门槛后才把固定测试资源、评测工具、报告和生产修复提交到功能分支。
