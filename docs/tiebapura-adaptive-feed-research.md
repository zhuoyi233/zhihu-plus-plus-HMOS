# TiebaPura 自适应多栏信息流调研

本项目接入步骤与分阶段验收见 [自适应多栏信息流接入方案](./adaptive-multicolumn-feed-plan.md)。

调研日期：2026-10-24。上游基线：`a307608689-afk/TiebaPura` 默认分支提交 `18b1d2bef3978b8ded286c9bdd541a6e4bfc7190`（v1.0.9，2026-10-19）。本仓库对照基线：`1b572364`。本次为源码与文档静态调研，未构建或运行 TiebaPura，未进行真机性能复测。

核心结论：TiebaPura 的首页用原生 `WaterFlow + LazyForEach`，由框架完成不等高卡片的瀑布流排布；应用负责设备/窗口判定、列数策略、卡片内部几何、数据变更通知和分页。另有部分页面采用手工分桶形成多栏，不能把这套算法误认为首页的实现。本项目已有 WaterFlow 基础，适合补齐策略和懒加载，无需重写布局容器。

## 1. 首页的实际布局链

    Refresh
      └─ WaterFlow(scroller)
          └─ LazyForEach(ThreadDataSource)
              └─ FlowItem
                  └─ ThreadCard

`HOME_SINGLE_USE_WATERFLOW = true`，所以当前单列也走这条链；源码保留的 Scroll + 窗口化挂载分支是回退代码。推荐、关注动态各有独立数据源、Scroller、分页状态和滚动位置。

WaterFlow 接收 `homeColumnsTemplate()` 生成的 1～4 个 `1fr`，左右 padding 为 16vp，行列间距均为 12vp。卡片保持自然高度，纵向 WaterFlow 将下一项放到累计高度最小的列；这不是同行等高的 Grid，也不是每列独立滚动。

离屏预建数量为 `Math.max(5, homeColumns() * 2)`：1/2/3/4 列分别缓存 5/5/6/8 个 FlowItem。加载骨架同样消费 `homeColumns()`，避免加载完成后列数突变。

来源：[首页容器与缓存](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L2530-L2607)、[单列开关](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L138-L146)、[列模板](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L545-L561)。

## 2. 自适应策略：窗口闸门 → 用户档位 → 设备默认值

首页的实际执行顺序：

1. 已知页面宽度小于 600vp 时回到 1 列；阔直屏满足全屏近似判定时例外放行。
2. 大屏形态且用户选择了列数档位时，用页面宽高判断横竖，返回“竖二横三”或“竖三横四”。
3. 默认档下，阔直屏和大折叠使用 `updateColumns()` 得到的列数；普通手机返回 1；其他大屏通过宽度闸门后使用默认列数。

| 默认形态 | 竖屏 | 横屏 | 限定条件 |
| --- | --- | --- | --- |
| 普通手机 | 1 | 1 | 即使横屏宽度超过 600vp，也受设备形态限制 |
| 平板、2in1 | 2 | 3 | 窄窗口先回退 1 列 |
| 大折叠展开 | 2 | 3 | 展开态及比例判定命中，且窗口闸门放行 |
| 阔直屏 | 1 | 3 | 包含代码识别的部分 Pura X 形态 |
| 自由小窗、窄分屏 | 1 | 1 | 宽度 <600vp；有阔直屏例外 |

这不是简单的“600 两列、840 三列”通用断点方案。Theme 虽声明了 840vp 等断点，当前首页默认列数主要由设备与方向决定；源码一些“竖三横四”“600～840 两列”的旧注释已经落后于实际分支。

窗口与屏幕的分工也并未完全统一：页面通过 WaterFlow 的 `onAreaChange` 取得实际 vp 宽高，解决分屏/自由窗口问题；但默认 `updateColumns()` 仍读 `display.getDefaultDisplaySync()` 的物理屏幕方向。只有用户覆盖档直接用页面宽高判横竖。这意味着窄窗保护有效，但宽度 ≥600vp 的竖向窗口仍可能沿用横向物理屏幕的三列默认值。

冷启动先用 display 尺寸初始化，随后用实际页面尺寸修正；同时监听 display change。相同尺寸、相同列数不重复写 @State/AppStorage，列数切换不包过渡动画。手动更改档位会让两条 feed 回顶；这不等于旋转时具备按内容锚点恢复阅读位置的实现。

来源：[首页列数计算](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L447-L561)、[实际窗口测量](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L2341-L2378)、[设备与档位函数](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/common/Theme.ets#L1260-L1351)。

阔直屏全屏例外用 `pageWidth >= 屏幕短边vp - 24` 判断，是宽度启发式，并未核对实际窗口模式或高度。迁移时不应把它当作通用的“全屏检测 API”。用户强制档位没有最小卡宽限制，窄卡内容要另外处理。

## 3. 多列时卡片内部也会变化

| 项目 | 单列 | 多列 |
| --- | --- | --- |
| 标题 | 最多 2 行 | 最多 2 行 |
| 摘要 | 最多 4 行 | 最多 2 行 |
| 单图 | 固定高 220vp | 宽高比 1.6，高度上限 220vp |
| 多图格 | 按图数固定高 140/100vp | 方形比例，并保留高度上限 |
| 分享/评论/点赞 | 常规胶囊尺寸 | 估算卡宽 <240vp 时收紧文字、图标、间距和按钮高 |

父页将最终列数写入 AppStorage `cardColumns`，ThreadCard 使用 `@StorageProp` 读取。进入单列也必须写回 1；同值则跳过写入。卡内图片 Grid 禁用自身滚动，避免图集截获整个信息流的拖动。

来源：[摘要](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/components/CommonComponents.ets#L708-L735)、[图片比例](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/components/CommonComponents.ets#L1070-L1128)、[窄卡操作栏判断](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/components/CommonComponents.ets#L339-L387)。

迁移建议：保留“卡片跟随最终布局参数”的思想，但采用页面作用域参数与真实卡宽。上游 `cardColumns` 是所有页面共享的单值；若多个页面同时存活，存在互相覆盖的可能。其紧凑模式用物理屏宽估算卡宽，而且仅按列数缓存，窗口同列数缩放时可能不更新。这些是静态推导出的边界，未在上游设备上复现。

## 4. 长列表与分页

`ThreadDataSource` 实现 IDataSource，@Watch 将页面数组同步到它：

- 尾部追加：先逐项核对旧列表 tid 前缀，避免把“刷新后变长”误判为追加。
- 等长同序更新：比较对象引用，只对变化项发 `onDataChange`，用于点赞和昵称回填。
- 顺序改变、整批替换：发 `onDataReloaded`。

来源：[数据源与通知](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L57-L103)、[数组同步](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L379-L443)。

注意：上游一次追加多个条目时，现有实现只调用一次 `onDataAdd(old.length)`。迁移时应独立核对通知协议，使新增通知准确覆盖实际新增范围；不要只复制适配器。其 key 也包含作者、点赞状态与数量，部分更新会通过 key 改变重建卡片，应按本项目状态更新方式选择稳定身份键。

分页有三条触发路径：滚动接近底部、onReachEnd 兜底、数据/视口变化后检测内容不足一屏。滚动预取从 Scroller.currentOffset() 读偏移，不把 onScroll 入参当绝对位置。默认剩余距离阈值为 1200vp，重复触发的偏移步长为 120vp，另有 loadingMore/hasMore 与请求代际校验。

虚拟容器的高度是视口高度，所以上游用估算总高作预取判据：

    卡高 ≈ round(200 + 卡宽 × 0.5625 × 0.5)
    内容高 ≈ ceil(条数 / 列数) × (估算卡高 + 行间距)
    剩余距离 = 估算内容高 - 视口高 - 当前偏移

该估算只服务网络预取，不决定首页卡片的实际高度或落列位置。业务快照写入会合并延后，滚动中避免重复序列化和落盘。

来源：[预取闸门与公式](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/common/PrefetchGate.ets#L42-L130)、[首页滚动处理](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L2180-L2217)、[不足一屏补取](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/HomeTab.ets#L2310-L2378)。

## 5. 手工分栏是另一条实现路径

PersonalContent 多列使用 `List → 单个 ListItem → Row → 多个 Column`；楼中楼等页面用 Scroll 内的 Row/Column。每列普通 ForEach 全量构建，外层存在 List 并不意味着其中每张卡都有独立的虚拟化。

代表性分桶算法为“轮转为主，差距超过阈值才补短列”：

    为每列初始化估算高度 0
    按原始顺序遍历第 i 条
      target = i % columns
      shortest = 当前估算最矮的列
      如果 height[target] - height[shortest] > 240vp
        target = shortest
      把条目追加到 target
      height[target] += estimateHeight(item, columnWidth) + gap

高度根据文本长度、列宽、标题/摘要行数、图片行数估计，无需等待实测后再搬卡。保持相同列数、列宽和旧内容时，尾部追加重算不会改变旧前缀的落列。它能控制列高差，并尽量保留轮转阅读顺序，但不保证严格的逐行顺序；布局参数或旧内容变化时也可能重新分配。

PersonalContent 的列容器使用稳定列索引 key，列内直接读取状态派生数组，避免复用列容器后绑定旧数组。SubPostDetail 则使用包含列长度等信息的 key；两者不能视为完全统一的组件实现。

来源：[PersonalContent 容器](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/PersonalContent.ets#L319-L345)、[分桶与估高](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/PersonalContent.ets#L574-L625)、[楼中楼分栏](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/SubPostDetail.ets#L907-L987)。

此外，吧主页多列继续使用 WaterFlowSections：一个单列 section 容纳通栏吧头，一个多列 section 容纳帖子；单列分支使用无 sections 的 WaterFlow。作者曾记录沉浸布局和跨 section 虚拟化的显示问题，因此存在不同页面采用不同容器的取舍。不能将其历史经验概括为“WaterFlow 一律不可用”或“sections 一律有问题”。

来源：[吧主页分组](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/ThreadList.ets#L1948-L1979)、[多列分支](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/ThreadList.ets#L3334-L3348)、[当前单列分支](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/entry/src/main/ets/pages/ThreadList.ets#L3504-L3510)。

## 6. 对本项目的具体借鉴

| 维度 | 本项目当前实现 | 建议 |
| --- | --- | --- |
| 瀑布流基础 | HomeFeedPage、ChannelFeedPage 已使用 WaterFlow | 沿用 |
| 列数 | 实际页面宽度 <600 一列，≥600 两列 | 抽出统一策略；如需三列/四列，以可用宽度和最小卡宽约束为主 |
| 布局模式 | 已显式设置 SLIDING_WINDOW | 保留，这是动态换列的重要基础 |
| 节点创建 | 信息流主体使用 ForEach | 值得评估 LazyForEach 或 Repeat 虚拟滚动，先验证刷新/屏蔽/分页数据通知 |
| 通栏内容 | WaterFlowSections 表达公告、日期、页尾 | 沿用既有 FeedFlowLayout 与索引映射 |
| 首屏和预取 | 首屏目标数量、onScrollIndex 提前加载、onReachEnd | 保留索引方案，扩展多列时同步容量与预取余量 |
| 卡片 | 已有宽屏卡片外观 | 将摘要行数、图片占位、操作区与实际卡宽联动 |

对应位置：`entry/src/main/ets/pages/HomeFeedPage.ets:200`（布局模式）、`:229`（ForEach）、`:244`（可见索引预取）、`:295`（实际宽度）、`:774`（列数与 sections）；`ChannelFeedPage.ets:250`、`:784`；`FeedWaterfallLayout.ets:1`（600vp 断点）、`:5`（双列首屏容量）；`entry/src/test/FeedWaterfallLayout.test.ets` 已覆盖分组、日期、身份键等纯函数行为。

两项容易误用的区别已通过 deveco-cli 官方文档核对：

1. `SLIDING_WINDOW` 解决布局计算范围，`LazyForEach`/Repeat 解决按需创建节点，两者互补。仅给 ForEach 增加 cachedCount 不会获得对应的懒加载缓存行为。TiebaPura 首页未设置 layoutMode，使用默认 ALWAYS_TOP_DOWN；本项目已有的滑动窗口模式不应照搬回默认值。
2. SLIDING_WINDOW 下跳转或数据更新后，currentOffset/offset 的总偏移可能是估算值，回到顶部时重新校准。因此 TiebaPura 的“总高估算减绝对偏移”不能直接替代本项目现有的 onScrollIndex 预取，也不宜据此实现精确阅读位置恢复。

WaterFlowSections、layoutMode 的文档起始版本为 API 12，cachedCount 两参数形式为 API 14，可纳入本项目 API 23 兼容范围；不能连带复制上游 API 26 专属材质 import。动态增删公告、页尾、日期时，所有 sections.itemsCount 总和仍须始终匹配真实 FlowItem 数量。

[官方 WaterFlow 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-waterflow)。正文由 `devecocli docs read` 读取本地官方文档库；同时核对 FAQ 文档 ID `FAQ/技术质量/性能/WaterFlow组件切换列数时卡顿/faqs-performance-51`。

建议后续实施顺序：先统一由实际容器尺寸计算的布局参数，再改懒加载数据源，最后增加用户密度档位。三列/四列断点应根据知乎卡片的最小可读宽度确定；升级档位时同步调整 `homeFeedInitialItemTarget()` 中固定的双列乘数。窗口旋转时的阅读位置建议用内容身份和局部偏移恢复，用户手动换密度是否回顶则单独确定交互。

## 7. 调研边界与验证建议

本次未修改业务代码、未提交或推送。新增本文；未执行编译/Hypium 或模拟器验证。

上游文档含多轮方案、回退记录和未同步注释，本文以固定提交的实际分支为准。作者的性能文档报告：首页迁移到 WaterFlow 后，最差帧由 40～75ms 降到 11～34ms，同时保留孤立 706ms 异常帧待观察记录；这些是作者自述测量，不代表本项目或所有设备已验证。

来源：[上游性能结果与已知差异](https://github.com/a307608689-afk/TiebaPura/blob/18b1d2bef3978b8ded286c9bdd541a6e4bfc7190/docs/TiebaPura%20v1.0.8%E9%A6%96%E9%A1%B5%E4%BF%A1%E6%81%AF%E6%B5%81%E6%8E%89%E5%B8%A7%E9%97%AE%E9%A2%98%E5%92%8C%E7%A9%BA%E7%99%BD%E9%97%AE%E9%A2%98%E4%BF%AE%E5%A4%8D.md#L169-L214)。

未来实现的重点回归：600vp 边界、长列表滚动中换列、分屏和同列数缩窗、折叠展开、图片加载前后高度稳定、筛除已读/屏蔽后补屏、追加多条和刷新变长、动态通栏 section、切页与返回后的阅读位置、字号放大后的最小卡宽。
