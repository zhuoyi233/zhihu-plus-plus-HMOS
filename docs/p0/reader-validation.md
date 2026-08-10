# P0 原生长正文与公式实验记录

> 首次验证：2026-07-20；API 24 公式路线更新：2026-08-10

## 原型范围

原型使用仓库现有的真实知乎长回答 HTML，复制为 `entry/src/main/resources/rawfile/reader_probe.html`。ArkTS 解析器将 HTML 转换为标题、段落、列表项、分隔线和块公式五类节点，再通过 `List`/`LazyForEach` 懒加载原生组件。整篇正文没有使用 ArkWeb。

当前样本解析结果为：

- 112 个原生块；
- 4296 个可读文本字符；
- 11 个块公式与 63 个行内公式；
- 每个公式都保留可读 TeX 文本作为失败降级数据。

## 公式路线阶段结论

知乎 `https://www.zhihu.com/equation?tex=...` 返回 `image/svg+xml`。项目兼容基线收敛为 API 24 后，公式路线改为 ArkUI 原生组件：

1. 正文 AST 将含 `eeimg="1"` 的段落拆成文本与行内公式 run；普通段落仍使用原生 `Text`。
2. API 24 虚拟机证明把远程 URL 直接交给 `Image`/`ImageSpan` 会连续触发 `onError`，即使同一端点在主机返回 `200 image/svg+xml`，因此该路径已删除。
3. 最终路线由 `NetworkKit` 请求 SVG 二进制，把知乎 SVG 的 `ex` 宽高按端点声明的 15 px 字号换算为 `px`，并把 `currentColor` 固定为正文色，再使用 `ImageSource.createPixelMap()` 解码；行内公式由 `ImageSpan(PixelMap)` 显示，块公式由 `Image(PixelMap)` 显示。
4. 只接受锚定到 `https://www.zhihu.com/equation?tex=` 的精确来源；请求设置连接/读取超时、1 MiB 传输上限、关闭重定向，并校验 HTTP 200、`image/svg+xml` 和 SVG 根节点。失败响应不会进入缓存。
5. 加载前、网络失败或 SVG 解码失败时，仅对应节点显示 TeX，正文和其他公式不受影响。
6. 缓存只保留 SVG 原始字节，使用 64 项/4 MiB 的内存 LRU 和请求合并；离开 Reader 时清空。PixelMap 由可见公式组件独占并在离开或异步结果过期时释放，避免把所有长文公式位图常驻内存。
7. 公式节点仍由 `List`/`LazyForEach` 按可见区域创建与回收；不使用整页或节点 ArkWeb，也不再使用底层复用 Web 的 `RichText`。

本地 API 24 官方文档确认 `ImageSource` 支持从 ArrayBuffer 解码 SVG 为 PixelMap，官方 SVG FAQ 也将“SVG 字节转 PixelMap”列为可行性更高的加载方式。`RichText` 官方文档明确其底层复用 Web、在 `List` 中重复使用可能造成卡顿且组件不再维护，因此不作为当前主路线。

参考：[ArkTS 概览](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-overview)、[ImageSource 图片解码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/image-decoding)、[ImageSpan 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-imagespan)、[RichText 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-richtext)。

## 设备验证

| 虚拟机 | 安装与启动 | 长正文 | 公式 | 结果 |
| --- | --- | --- | --- | --- |
| `ZhihuPlus_API20` / API 20 | 历史记录 | 多次滚动并到达公式区域 | 原生远程 SVG 失败 | 不再作为兼容基线 |
| `ZhihuPlus_API24` / API 24 | 通过 | 从首屏连续滚动至第 112 个原生块，应用保持前台 | 11 个块公式 + 63 个行内公式，最终状态 `API 24 原生公式已解码 74/74` | 通过 |

API 20 结果只作为历史证据，不再限制 API 24 的组件选择。API 24 首屏和文末均完成截图级视觉核验：行内公式参与正文排版，块公式以原生图片节点显示；崩溃查询和应用错误日志均为空。此前解析器复用全局正则导致 `lastIndex` 被嵌套解析重置、形成无限循环的问题也已改为局部迭代器，并通过完整长文滚动验证。

## 自动化验证

公式解析测试覆盖：行内 run 拆分、块/行内统计、公式 URL 与 TeX 保真、仿冒来源拒绝和可读降级。最终版本通过 `devecocli build --product default --modules entry --build-mode debug`。Hypium 的 `test` 任务能完整生成报告；公式新增用例无失败，但全量任务仍暴露 6 个既有 URL Kit 本地 mock 失败（5 个深链、1 个二维码），Hvigor 即使有断言失败仍返回 0，故不能只依赖进程退出码判断测试通过。

## 已知边界与下一步

- 当前是 P0 技术原型，19 KB 样本可在当前页面加载；生产版需要把 HTML 清洗和大文增量解析迁入 TaskPool。
- 公式宽度当前依据 TeX 长度估算；生产版需使用 PixelMap 解码尺寸完善超长公式布局和横向查看策略。
- 公式节点数量很多时，仍需形成内存、首次渲染耗时和滚动帧率的自动化基线。
- 网络图片、GIF、失败重试和预览已由 `P0-IMG-01` 独立验证通过，详见 `image-validation.md`。
