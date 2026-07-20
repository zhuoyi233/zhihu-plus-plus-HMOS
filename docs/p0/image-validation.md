# P0 网络图片与 GIF 验证记录

> 验证日期：2026-07-20

## 验证范围

`P0-IMG-01` 验证 ArkUI 原生正文路径中的网络图片能力，不引入整页 ArkWeb。范围包括：

- 知乎静态网络图片；
- 知乎 GIF 动图；
- 加载中、成功和失败状态；
- 用户主动重试；
- 原生全屏预览；
- 正文 HTML 中 `figure/img` 到图片 AST 节点的解析。

真实长回答样本中的 74 个 `img` 都是公式图片，不能代表普通内容图片。因此本项使用仓库既有的两个真实知乎媒体地址分别验证 JPEG 和 GIF，并使用确定性的无效地址覆盖失败与恢复分支。

## 实现结论

正文解析器新增 `IMAGE` 节点，并按 `data-actualsrc`、`data-original`、`src` 的顺序选择知乎懒加载图片地址。解析时忽略 `noscript` 回退副本，保留 `alt` 或 `figcaption` 文本。网络来源仅接受 HTTPS，协议相对地址统一提升为 HTTPS，拒绝 `javascript:`、本地文件和数据 URI。

图片由 ArkUI `Image` 直接渲染：

1. `onComplete` 和 `onError` 驱动可见加载状态。
2. 正文图片失败后显示重试按钮；重试通过查询参数修订值触发重新请求。
3. 点击成功加载的图片进入原生全屏 `Stack` 预览。
4. GIF 继续交给 `Image` 组件逐帧解码，不在 ArkTS 中一次性解码全部帧。

HarmonyOS 官方图片解码文档列出的支持格式包含 JPEG、PNG、GIF、WebP、BMP 和 SVG，并建议 GIF/WebP 动图使用 `Image` 组件逐帧解码以降低内存占用。参考：[Image 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-image)、[图片解码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/image-decoding)。

## 双版本虚拟机结果

| 验证项 | API 20 / HarmonyOS 6.0.0 | API 24 / HarmonyOS 6.1.1 |
| --- | --- | --- |
| JPEG 网络图成功回调 | 通过 | 通过 |
| GIF 成功回调 | 通过 | 通过 |
| GIF 两帧像素变化 | `1799 / 5445` 个采样点变化 | `96 / 5445` 个采样点变化 |
| 无效地址失败提示 | 通过 | 通过 |
| 点击重试后恢复 | 通过 | 通过 |
| 原生全屏预览打开/关闭 | 通过 | 通过 |

GIF 像素差只比较组件可见区域，排除了状态栏时间变化；两台虚拟机都观察到非零变化，因此不是仅加载首帧。

## 自动化与构建

- API 24 SDK 下 Debug HAP：`BUILD SUCCESSFUL`。
- 新增 2 个解析测试，覆盖知乎懒加载图片优先级、图片说明、协议相对地址归一化和危险来源拒绝；当前测试定义总数为 27。
- DevEco CLI 当前没有暴露 `src/test` 本地单元测试任务，本批以 ArkTS 编译、解析测试代码审查和 API 20/24 设备行为共同验收；后续接入 CI 时必须补上 27 个用例的可重复执行入口。

## 边界

- P0 预览只验证打开和关闭；手势缩放、双击、长按保存和分享在 P2 媒体组件中实现。
- P0 依赖系统网络缓存；统一内存/磁盘缓存、并发限流和淘汰策略在 P1 数据层实现。
- 当前正文真实长样本没有普通图片，生产前还需增加图片密集文章 fixture 和滚动内存基线。
- 公式图片是独立问题，仍归 `P0-MATH-01`，不因普通 JPEG/GIF 通过而标记完成。

`P0-IMG-01` 的网络图、失败重试、GIF 和预览策略已经明确，并在最低 API 20 与目标 API 24 上通过，因此本项标记为通过。
