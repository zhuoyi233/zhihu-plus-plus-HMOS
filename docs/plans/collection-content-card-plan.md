# 收藏夹二级页：主页卡片复刻实施计划

日期：2026-11-07。状态：已实施（收藏页与历史页两轮适配均完成，Hypium 1180/1180，5555 设备验收通过）。

源码基线：`1feee083`。视觉规格以[设计文档](./collection-content-card-design.md)为准。

## 1. 实施结果

将主页现有的单条信息流卡片抽成共享呈现组件，主页和收藏内容页共同使用；收藏页通过独立的展示适配器补齐作者、封面与类型统计，接入既有 `feedCardStyle` 和 `showFeedThumbnail`。

此次只规划单条内容卡片及必要的数据／设置接入。收藏夹目录、导航容器、收藏管理接口、推荐算法、过滤机制和发行流程均不扩展。

## 2. 已确认的实现约束

- 当前收藏页已采用 `WaterFlow + SLIDING_WINDOW + LazyForEach + FlowListSource`，不按旧多列文档中“单列 ForEach”假设重新迁移。
- `HomeFeedPage` 本地 Builder 才是复刻源；`FeedContentSummary` 不是等价实现，直接复用会留下头像、摘要颜色与行距差异。
- 当前主页标题不限行，且多列不会强制开启卡片表面。历史文档中“两行标题”“多列默认卡片”等规则不能用于本次实现。
- 收藏和主页的领域类型不同：收藏包含 PIN，`FeedTargetKind` 不包含 PIN。禁止为了复用组件把想法伪装成回答，或全局扩大 Feed 枚举后引入无关 switch 修改。
- 收藏页 `wideSpec()` 默认以 14vp 求列宽，sections 却传 10vp 间距；此次按设计统一为 14vp。
- 当前收藏数据流中的 `voteupCount` 在问题上表示回答数、想法上表示赞数；展示适配必须保留语义。
- `CollectionContentPage.aboutToDisappear()` 当前会清空 controller，源码注释中的“保留实例”不能作为返回保位已实现的证据。实施前须确认真实导航生命周期，避免将旧问题误判为抽取回归。

## 3. 共享组件与职责

建议新增以下文件；命名可在实现时随同目录习惯调整，职责与边界保持不变。

| 文件 | 职责 |
| --- | --- |
| `entry/src/main/ets/pages/components/FeedContentCard.ets` | 卡片 Button、标题、作者、图文摘要、页脚与菜单槽位；统一表面、尺寸和无障碍信息 |
| `entry/src/main/ets/pages/FeedCardPresentation.ets` | 明确的展示 interface，以及主页／收藏领域对象到展示对象的纯适配函数 |

展示模型最少包含：`title`、`excerpt`、可选作者姓名／头像、可选 `thumbnailUrl`、可选补充说明、`detailsText`、可选屏蔽原因、内容可访问名称。`testId` 和页脚测试 ID 通过显式参数传入，避免在组件内识别页面来源。

组件另接收最终 `columns`、卡片样式、缩略图开关和主体点击回调。展示模型采用明确 interface 和不可变替换，状态输入使用可更新的组件属性；不能只在首次出现时复制一份以后不更新的值。最终列数由每页本地计算，不放进全局 AppStorage。

更多按钮及菜单通过 `@BuilderParam` 槽位提供：共享组件负责页脚布局，页面槽位负责同规格按钮及 bindMenu 业务。槽位闭包只直接调用 Builder，条件写进 Builder 内部，遵守仓库 ArkUI 约束。按钮视觉规格由共享样式或共享按钮 Builder 统一，避免两页各写一套尺寸。

主页保留现有 `openFeedItem()`、菜单状态、异步作者／话题解析、屏蔽、推荐理由、移动页脚及测试 ID。共享组件需支持主页原有“已屏蔽”分支，不能在抽取时恢复其隐藏的标题、作者和图片。

收藏继续调用 `collectionContentDestination()`，页脚使用其 `details`，补充说明留空。收藏的更多菜单仅接“外观设置”，按收藏内容稳定身份控制展开和关闭。

组件不持有 repository、controller、session、推荐曝光上报或收藏修改逻辑；领域数据与页面业务不因视觉共享而合并。

## 4. 数据链路

### 4.1 扩展可选字段

在 `data/src/main/ets/domain/CollectionModels.ets` 的 `CollectionContentItem` 增加可选 `authorAvatarUrl`、`thumbnailUrl`。保留既有 `authorName` 和 `details`，不要求所有调用方立即提供新字段。

实施时先采集或复用脱敏收藏响应，分别核对回答、文章、问题、想法实际提供的作者头像和封面结构。候选字段只作为核对方向，例如作者对象的头像、文章封面或内容缩略图；在响应证据确认前不写死多套猜测路径，不假定四类内容共用同一封面字段。

在 `CollectionDecoder.ets` 增加对已确认字段的可选解码，保留当前 HTML 摘要转纯文本和中文空格整理逻辑。新展示字段缺失／null／不可用时返回 undefined；可选图片异常不能让整页收藏解析失败。内容 ID、必需标题等现有严格校验不放松。

图片地址遵循现有 `FeedThumbnail` 的 HTTPS 展示约束，复用项目既有 URL 处理能力；异常地址不引入 WebView，不改变点击目标。不抓取全文寻找封面，也不为每个条目补详情网络请求。

### 4.2 请求与兼容

`DefaultCollectionRepository.buildCollectionItemsUrl()` 目前 include 为 `data[*].content,excerpt,created_time,updated_time,author`。先确认响应是否已经携带所需字段；只有确实缺失且接口支持明确的 include 时，才调整 include 并同步请求断言。

检查 `CollectionContentState` 的合并／去重、测试 fake 和所有 `CollectionContentItem` 构造处，保证可选字段不会在对象重建时丢失。现有 `mergeCollectionItems()` 对重复身份保留先出现的对象，此次沿用该分页去重语义；当刷新或明确替换产生同 key 的新展示负载时，组件必须能更新，不能因缓存 key 相同而显示旧内容。不修改现有游标校验、失活保护及重复请求防护。

若接口确实不提供某类封面或头像，按设计缺失规则呈现，并在实施结果中注明样本范围。未核验或未接通的字段不能以“共享组件已支持”为由标记整项完成。

## 5. 收藏内容页与样式接入

1. 用收藏展示适配器和共享组件替换 `contentCard()` 内部旧排版，保留 `collection_content_<kind>_<id>` 稳定根 ID 与跳转类型。
2. 订阅 `feedCardStyle`（默认 divider）与 `showFeedThumbnail`。样式通过 `@Watch` 更新布局配置，缩略图变化传递到已挂载卡片；页面首次显示也消费最新广播值。
3. 内容 section 的间距统一为：单列分割线 0；卡片或多列 14vp。`wideSpec()` 的列间距和实际 section 的 `columnsGap` 必须相同。
4. 错误横幅、分页按钮保持通栏，并保留独立的 section 间距。可复用 `buildFlowListSections(entries, columns, itemGap, sectionGap)`：内容 gap 按样式取值，通栏 section gap 保留 10vp；不为本页面改动所有调用方的默认值。
5. 保留页面宽度测量、1120vp 居中上限、字号最小卡宽保护、滚动注册及 `floatingTitleBarOffset()`。样式切换不改变 `items`、controller、collectionId、游标和错误状态。
6. 样式改变只更新必要的 sections 和节点状态。评估用已有 `FlowListSource.applyLayout()` 替代仅因样式变化触发的全表 replace，避免 key 不变时仍把可见节点全部重载；实际数据／section 更新必须使用同一份快照。
7. 变化前记录首个可见内容身份；样式或图片开关改变导致高度重排后，保证该内容仍可见。优先复用项目现有滚动锚点能力，按新条目映射索引，不能直接使用旧的通栏偏移索引。用户拖动期间不与手势争抢滚动。
8. 增加收藏更多菜单的可访问名称、独立测试 ID 与关闭清理；打开设置前收起菜单，避免返回后旧菜单再次出现。
9. 更新 `AppearanceSettingsPage` 中列表样式说明，把收藏内容纳入作用范围。继续复用原存储与 `AppShell` 冷启动广播，不新增设置控件或偏好字段。

纯视觉更新不能主动调用 `loadInitial()`、`retry()` 或 `loadMore()`。若重排触发框架 `onReachEnd`，保留控制器去重门禁，并在设备测试中确认不会产生反复分页。

## 6. 实施阶段与退出条件

| 阶段 | 工作 | 退出条件 |
| --- | --- | --- |
| 1：建立基线 | 留存主页与收藏当前两种样式的截图；核对各类型响应；复现设置返回生命周期 | 有脱敏数据样本、主页尺寸基线和已知旧问题记录 |
| 2：抽取主页呈现 | 建立中立展示模型、共享卡片；主页先迁入 | 普通／带图／已屏蔽／移动页脚卡片与抽取前一致，菜单及跳转不变 |
| 3：收藏数据与卡片 | 可选字段解码、收藏适配、四类内容与更多菜单接入 | 同宽同展示字段时与主页排版一致；类型统计语义准确 |
| 4：全局样式与动态布局 | 样式／图片开关、间距、缓存页更新及可视位置保持 | 两种外观即时生效，数据及游标不重置，宽屏仍支持分割线 |
| 5：验证与交付记录 | 全量编译／测试、Debug 构建、设备对照 | 下述验收通过；记录真实结果与剩余限制 |

以上是未来实施顺序，不代表自动提交或推送授权。当前任务只交付两份文档。

## 7. 预计文件改动

| 文件 | 计划变化 |
| --- | --- |
| `entry/src/main/ets/pages/HomeFeedPage.ets` | 改用共享卡片，保留页面业务与原有测试 ID |
| `entry/src/main/ets/pages/CollectionContentPage.ets` | 共享卡片、菜单、偏好订阅、内容间距、重排保位 |
| 新增 `entry/src/main/ets/pages/components/FeedContentCard.ets` | 主页与收藏唯一的卡片布局实现 |
| 新增 `entry/src/main/ets/pages/FeedCardPresentation.ets` | 两类数据的中立展示适配与摘要行数策略 |
| `data/src/main/ets/domain/CollectionModels.ets` | 头像、封面可选字段 |
| `data/src/main/ets/domain/CollectionDecoder.ets` | 核验后补齐可选展示字段，保留摘要清洗 |
| `data/src/main/ets/repository/DefaultCollectionRepository.ets` | 仅在真实响应证明需要时调整 include |
| `entry/src/main/ets/pages/AppearanceSettingsPage.ets` | 列表样式作用范围说明 |
| `entry/src/test/CollectionRepository.test.ets` | 脱敏字段解码与兼容回归；需要时更新请求断言 |
| 新增 `entry/src/test/FeedCardPresentation.test.ets`、`entry/src/test/List.test.ets` | 展示适配、类型语义和摘要行数边界，注册测试 |

`FeedThumbnail`、`FlowListSource`、`FeedWaterfallLayout` 及锚点设施优先直接复用。确需修改共享设施时补充其调用方回归，不因收藏页需求无条件改动频道、问题回答和历史页的排版。

## 8. 验证计划

### 8.1 有行为价值的自动化覆盖

- 收藏解码：四类内容的已核验字段；缺失／null／异常可选图片；原有无图响应仍可解码；HTML 摘要继续保持纯文本；非法必需字段仍报错。
- 展示适配：想法保持想法，问题回答数不显示为赞同；收藏不生成推荐来源；主页保留移动页脚与本地推荐理由；屏蔽卡不泄露标题、作者、摘要和图片。
- 摘要策略：无图 3／2 行、带图 6／4 行，图片开关关闭时使用无图分支。
- 若新增布局或锚点纯逻辑：通栏项与内容计数一致；样式切换不改变内容 key；插入／移除错误横幅后仍能映射正确内容；不以固定颜色和 padding 的镜像断言代替视觉验收。
- 运行已有收藏仓库与控制器、主页及菜单测试，覆盖分页去重、旧请求失效、登录错误、类型导航和菜单业务。

实现完成后依次运行（PowerShell 7）：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

全量用例数由脚本动态统计。此任务不包含发版，Release 验证留到有发行需求时按仓库流程执行。构建涉及工作区外 SDK／缓存时按会话权限执行。

### 8.2 设备与视觉验收

基础设备为 `ZhihuPlus_API23`，connectKey `127.0.0.1:5555`。宽窗按真实页面容器 vp 宽度验收；没有对应环境时记录未覆盖，不凭模拟器物理像素推断多列效果。

| 场景 | 通过条件 |
| --- | --- |
| 同宽同数据主页／收藏对照 | 标题、作者、图片、摘要、页脚与更多按钮的尺寸、位置、颜色一致；文案只存在已定义的来源语义差异 |
| 单列分割线 | 无圆角底卡，左右文字起点 20vp，底线 1vp，相邻内容无额外 10／14vp 空隙 |
| 单列卡片 | 中性表面、16vp 圆角、18vp 内边距、14vp 卡间距；无额外阴影 |
| 多列两种样式 | 都保持所选表面；14vp 间距与列宽计算一致，长短内容自然瀑布流 |
| 有图／无图／关闭缩略图 | 左图右文与行数规则正确；关闭后文字占满；图片失败保持中性画布及尺寸 |
| 回答／文章／问题／想法 | 页脚单位准确，四种主体跳转保持原类型 |
| 长标题／长作者／空字段 | 标题完整，作者省略，更多按钮不被挤出；无空作者占位或虚构推荐语 |
| 深浅色与大字体 | 语义颜色正确；卡高自然增长；最小卡宽保护有效；控件可达 |
| 更多菜单 | 点击不导航主体；外观设置可打开；返回后菜单关闭且新样式生效 |
| 长列表切样式／切图片 | 已有内容及游标保留，原可见内容仍可见，不循环分页或整页闪空 |
| 分页与错误 | 加载／错误项通栏，已有内容保留，重试及登录入口有效 |
| 返回与旋转 | 没有新引入的重载／回顶；已知生命周期问题单独记录；首尾内容不被顶栏或安全区遮挡 |
| 屏幕朗读 | 主体内容类型与标题可识别，更多按钮可独立聚焦，装饰图片不产生多余操作 |

保存同数据基线、实施后截图和设置切换录屏到 `.tmp/shots/`。截图用于静态排版对比，录屏用于确认偏好即时更新、点击不串路由、重排及返回行为。使用固定本地测试夹具或脱敏数据使主页和收藏卡片可在同宽下比较，不能拿不同摘要长度的线上内容比较卡高后判定复刻。

## 9. 风险与处理

| 风险 | 处理 |
| --- | --- |
| 复用看似接近的摘要组件，仍与主页不同 | 抽取主页真正使用的完整卡片，不另外拼装 `FeedContentSummary` |
| 共享组件导致主页筛选、推荐来源或菜单退化 | 先迁主页并独立对照；保留页面业务、屏蔽分支和移动页脚 |
| 收藏头像／封面结构未核验 | 先取得脱敏样本，再明确字段映射；缺失可选字段正常降级，不逐条补网络请求 |
| 想法类型与 Feed 枚举冲突 | 使用中立展示 interface，业务导航继续使用原领域类型 |
| LazyForEach 缓存节点未响应偏好 | 使用真实可更新属性与 AppStorage 订阅，覆盖已挂载和缓存重显场景 |
| border 重置圆角或宽屏暗中强制卡片 | 同步 border radius；表面只由样式决定，不绑定列数 |
| 样式切换、图片开关或分页触发全量重载／跳位 | 稳定 key、必要增量通知、快照一致与可视身份恢复，设备实测 |
| 返回时旧 controller 生命周期问题 | 先建立基线；若阻碍即时切换验收，以独立最小修复说明原因，不能未经验证宣称已有保位 |

## 10. 本次交付与验证状态

本次仅新增设计、计划两份 Markdown 文档，没有修改应用代码、测试、偏好、版本号和构建配置。

已静态核对主页卡片、收藏页面／模型／解码／仓库／控制器、全局样式广播、共享缩略图、布局及尺寸资源。已确认本机 `devecocli` 版本为 1.3.10，并通过本地 `devecocli docs search WaterFlow --limit 2` 找到相关文档索引；该搜索不等于已核验新 API 或完成运行时验证。

未执行 Hypium、Debug／Release 构建、设备操作或像素对照；后续实现按第 8 节验收。本次不提交、不推送。
