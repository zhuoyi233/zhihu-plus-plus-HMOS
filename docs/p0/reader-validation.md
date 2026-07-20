# P0 原生长正文与公式实验记录

> 验证日期：2026-07-20

## 原型范围

原型使用仓库现有的真实知乎长回答 HTML，复制为 `entry/src/main/resources/rawfile/reader_probe.html`。ArkTS 解析器将 HTML 转换为标题、段落、列表项、分隔线和块公式五类节点，再通过 `List`/`LazyForEach` 懒加载原生组件。整篇正文没有使用 ArkWeb。

当前样本解析结果为：

- 112 个原生块；
- 4296 个可读文本字符；
- 11 个块公式；
- 行内公式保留可读 TeX 文本，不丢失原始内容。

## 公式路线阶段结论

知乎 `https://www.zhihu.com/equation?tex=...` 返回 `image/svg+xml`。API 20 虚拟机中，ArkUI `Image` 直接加载该远程 SVG 会触发 `onError`，因此不能作为最低版本统一方案。

P0 当前候选方案：

1. 正文块继续使用 ArkUI 原生组件。
2. 只对块公式节点使用 `RichText` 加载知乎 SVG；节点 HTML 带 Content Security Policy，仅允许 `https://www.zhihu.com` 图片和内联样式，不启用脚本。
3. 公式节点跟随 `LazyForEach` 创建和回收，避免整页 ArkWeb。
4. TeX 原文始终显示在公式下方，作为加载失败和无障碍降级内容。
5. 行内公式的原生排版留到正文 AST 的 Inline 节点阶段；当前先保留 TeX。

块公式实验可见不代表真实长文公式已经完整渲染。当前样本中的行内公式仍显示为 TeX 文本，因此本批只通过 `P0-READ-01`，`P0-MATH-01` 保持进行中并留待后续修复。

该路线使用 API 8 已提供的 `RichText`，满足最低 API 20。后续若引入经过审计的 HarmonyOS 数学排版库，可以替换公式节点实现而不改变正文 AST。

参考：[ArkTS 概览](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-overview)、[RichText 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-richtext)。

## 设备验证

| 虚拟机 | 安装与启动 | 长正文 | 公式 | 结果 |
| --- | --- | --- | --- | --- |
| `ZhihuPlus_API20` / API 20 | 通过 | 多次滚动并到达公式区域 | 块公式实验可见，行内公式未渲染 | 正文通过，公式未完成 |
| `ZhihuPlus_API24` / API 24 | 通过 | 连续滚动到文章结尾 | 块公式实验可见，行内公式未渲染 | 正文通过，公式未完成 |

API 20 首次验证同时保留了原生 `Image` 失败结果，证明 TeX 降级路径确实会显示；切换到受限公式节点后，同一公式实际渲染可见。API 24 连续滚动至最后一段后，列表仍存在且应用保持前台。

## 自动化验证

新增 4 个 ArkTS 单元测试，覆盖块类型、行内公式降级、块公式 URL/TeX 保真和统计信息。全量结果为 25 个用例通过、失败 0。

## 已知边界与下一步

- 当前是 P0 技术原型，19 KB 样本可在当前页面加载；生产版需要把 HTML 清洗和大文增量解析迁入 TaskPool。
- 行内公式尚未排版为独立 Inline Span。
- 公式节点数量很多时，需要增加内存、首次渲染耗时和滚动帧率基线。
- 网络图片、GIF、失败重试和预览属于 `P0-IMG-01`，本记录不将其标记为完成。
