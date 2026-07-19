# P0 端侧 AI 排除清单

## 禁止迁移

- `sentence_embeddings`
- `rs-hf-tokenizer`
- HanLP 及其词典、模型和缓存
- `NLPService`
- `SentenceEmbeddingManager`
- `NlpServiceKeywordSemanticMatcher`
- 本地向量化、语义相似度和向量检索
- 模型下载、校验、解压和管理页面
- MindSpore、NNRT、NPU 推理和相关 Native 库
- `*.onnx`、`*.bin`、`*.model`、`*.tflite` 等模型资源

## P0 默认排除

- 知答 AI 总结及 SSE 总结链路
- 任何远端生成式 AI 功能

远端能力不是端侧 AI，但不属于 P0 核心迁移门禁。后续只有在用户明确确认后才可立项。

## 允许保留

- 关键词、正则、用户和话题屏蔽
- 规则型本地推荐和确定性排序
- 阅读、点赞、不感兴趣等显式行为信号
- AIGC 社区标记和投票；它是社区数据功能，不是端侧推理
- 系统 TTS；不在 P0 实现

## 提交检查

HarmonyOS 源码和依赖中不得出现以下类别：

```text
sentence_embedding
tokenizer model
HanLP
MindSpore
NNRT
onnx
tflite
NLPService
SentenceEmbeddingManager
```

命中内容必须人工确认。文档中用于说明禁止项的命中可以保留，生产依赖、资源和源码命中必须清除。
