# 上游问题详情页实现剖析与鸿蒙端仿制指南

> 研究日期：2026-08-31<br>
> 上游基线：zly2006/zhihu-plus-plus，快照 `22f6313c`（#716；问题页自研究快照 `ec77d309` 以来仅 #701
> 改了一处回答切换状态的获取方式，页面结构与数据协议未变）<br>
> 本侧基线：`dev` `a70b983e`（问题详情页已具备标题/统计/正文渲染、关注、问题评论、底栏对齐回答页）<br>
> 范围：剖析上游问题详情页（QuestionScreen）的独立实现，给出鸿蒙 ArkTS/ArkUI 端的仿制方案、
> 图标映射（已逐一验证）与实施步骤；不含代码实施。

## 实施状态（2026-09-04）

本文所列 P1、P2、P3 已在鸿蒙端完成：

- **P1**：问题回答 feeds、真实线格式解码、登录门禁、屏蔽过滤、游标分页、空页续拉、
  下拉刷新、默认/最新排序、与正文贯通的单一懒加载列表、共享回答卡片内容组件均已落地；
- **P2**：标题可复制、浏览/关注/评论图标统计、topics 解码和话题胶囊、写回答入口、
  180vp 正文折叠视口、自然高度测量、420ms 展开动画、渐变遮罩和自动化 testId 均已落地；
- **P3**：问题日志浏览器入口、系统分享、滚动超过 160px 后顶栏显示问题标题，以及继承
  当前排序/已加载列表/下一页游标的上一答、下一答连续阅读均已落地。连续阅读使用独占的
  feeds 仓库会话，避免与返回栈中的问题页互相取消请求。

验证结果：API 26 完整构建及签名通过，Hypium `536/536`；API 26 模拟器以 `ZHIHU_COOKIE`
完成登录后，真实问题 `1991678138325934210` 的问题详情、回答流、最新排序、正文展开、滚动
标题、回答连续切换和日志浏览器入口均已实测通过。

## 一、上游实现剖析

上游问题页是**独立于回答详情页的完整实现**，回答详情页与问题页通过"回答切换状态"衔接。
核心文件（`shared/src/commonMain/kotlin/com/github/zly2006/zhihu/` 下）：

| 文件 | 规模 | 职责 |
| --- | --- | --- |
| `ui/QuestionScreen.kt` | 843 行 | 页面 UI 全部组合 |
| `viewmodel/feed/QuestionFeedViewModel.kt` | 116 行 | 回答信息流状态：排序/分页/屏蔽过滤/关注 |
| `navigation/AnswerNavigator.kt` | — | `zhihuQuestionFeedsUrl` URL 构造 + `QuestionAnswerNavigator` 连续阅读 |

### 1.1 页面结构（自上而下）

```
Scaffold
├─ QuestionTopBar（TopAppBar）
│   ├─ 返回（ArrowBack）
│   ├─ 标题动画切换：未滚动显示"问题"，列表滚动超过 160px 后渐变为问题标题
│   │   （AnimatedContent：fadeIn + slideInVertically，退出反向）
│   ├─ 日志按钮（History 图标 → 系统浏览器打开 zhihu.com/question/{id}/log）
│   └─ 分享按钮（Share 图标 → ShareDialog，正文纯文本可分享时才启用）
└─ FeedPullToRefresh（下拉刷新，复用全局组件）
    └─ PaginatedList（回答信息流：cursor 分页，footer 进度条，key=stableKey）
        ├─ topContent（列表头部固定 section，随列表滚动）
        │   ├─ QuestionHeaderSection
        │   │   ├─ 标题（headlineSmall Bold，SelectionContainer 可长按选择复制）
        │   │   └─ 统计行：Eye 浏览数 · ChatBubble 评论数 · Heart 关注数
        │   │       （FlowRow 小图标 16dp + 辅助文字）＋ 右侧"评论 N" OutlinedButton
        │   └─ QuestionAnimatedBodyHeader（仅问题数据加载完成后渲染）
        │       ├─ 可折叠问题正文视口（见 1.2）
        │       ├─ 话题 chips：FilterChip "#话题名"，点击进话题页
        │       ├─ QuestionPrimaryActions：写回答（Edit 图标，secondaryContainer 底）
        │       │   ＋ 关注问题（Check/Add 随态切换，FilledTonal，已关注 tertiaryContainer）
        │       └─ 排序行："N 回答" ＋ 默认/最新 两个 FilterChip（切换即重置信息流）
        └─ 回答卡片 FeedCard（AnswerTarget：作者名/头像/摘要/详情文本）
            └─ 点击进回答详情，同时挂 QuestionAnswerNavigator（见 1.3）
└─ CommentScreenComponent（问题评论底部面板，comment_v5 通用端点）
```

### 1.2 正文折叠/展开动画（QuestionAnimatedBodyHeader，约 200 行）

- **是否可折叠**：正文纯文本 ≥ 100 字符或 HTML 含 `<img`；否则静态全展示不可折叠。
- **折叠态**：视口高度固定 180dp；底部 88dp 渐变遮罩（透明 → surface 0.7 → surface，
  叠加 12dp blur）；右下角"展开详情/收起详情" TextButton（ExpandMore/ExpandLess 图标），
  按钮热区高 56dp。
- **展开动画**：`Animatable` + 420ms `FastOutSlowInEasing`，在"折叠高（≤全高）"与
  "实测全高"之间插值；全高用 SubcomposeLayout 以无约束测量内容后回填；展开进度
  （0→1）反向驱动遮罩透明度，完全展开后遮罩消失。
- 短正文（不可折叠）直接静态渲染并同样回填高度。

### 1.3 数据流与行为

| 用途 | 端点/方式 | 说明 |
| --- | --- | --- |
| 问题详情 | `GET /api/v4/questions/{id}?include=read_count,visit_count,answer_count,voteup_count,comment_count,follower_count,detail,excerpt,author,relationship.is_following,topics` | 与本侧 `QUESTION_DETAIL_INCLUDE` **逐字一致** |
| 回答信息流 | `GET /api/v4/questions/{id}/feeds?limit=20&order=default\|updated`，cursor 分页 | `AnswerNavigator.kt` 构造；条目为 AnswerTarget |
| 关注/取关 | `POST` / `DELETE /api/v4/questions/{id}/followers` | 带 d_c0 登录态；成功后本地计数 ±1 + toast |
| 问题评论 | `comment_v5/questions/{id}/...` | 通用评论端点 |
| 问题日志 | 网页 `zhihu.com/question/{id}/log` | 浏览器打开 |
| 排序 | `order=default`（默认）/ `updated`（最新） | 切换即 `updateSortOrder` + `refresh` |

其他行为与约束：

- **匿名禁用**：`rememberPaginationEnvironment(allowGuestAccess = false)`——未登录不拉取
  回答信息流（feeds 端点本身也要求登录态）；
- **屏蔽过滤**：`processResponse` 按 `blockedUserIds` 过滤 AnswerTarget 作者；
- **连续阅读**：`QuestionAnswerNavigator` 携带当前回答之后的剩余列表 + 之前的列表 +
  下一页 URL，进入回答详情后可"上一答/下一答"连续切换并接续分页；
- 加载问题详情前写入阅读历史（`addReadHistory`）并上报内容打开事件。

## 二、鸿蒙端仿制方案

### 2.1 组件/机制映射总表

| 上游（Compose） | 鸿蒙端方案 | 本侧现状 |
| --- | --- | --- |
| Scaffold + TopAppBar | `P1Shell` 的 `HdsNavDestination.titleBar(stackBuilder: detailTitleBar('问题'))` | ✅ 已有 |
| 顶栏标题随滚动切换（160px） | 复用回答页 `topBarScrolled` 折叠模式（`onDidScroll` 像素偏移驱动） | 骨架已有，加状态即可（P2） |
| FeedPullToRefresh | `Refresh` + `refreshingContent`（蓝色加载圆圈，`ComponentContent`） + `onRefreshing(controller.refresh)` | ✅ 本周已建同款 |
| PaginatedList 分页 | `List` + `LazyForEach` + `.onReachEnd(loadMore)` + `LoadingProgress` footer | ✅ 上拉动画已统一 |
| FeedCard 回答卡片 | 复用信息流卡片渲染（`HomeFeedPage.feedCard` / `ChannelFeedPage.contentCard` 抽共享 builder） | 部分复用（见 2.3） |
| FilterChip 排序（默认/最新） | `SegmentButton` 两项（关注页"推荐/动态"同款先例） | ❌ 待做 |
| Animatable 展开动画 | `@State` 高度 + `animateTo({ duration: 420, curve: Curve.FastOutSlowIn })` + `.clip(true)` | ❌ 待做 |
| SubcomposeLayout 实测全高 | 内层内容 `onAreaChange` 回填 @State（内容始终按自然高度布局，外层裁剪） | ❌ 待做 |
| 88dp 渐变遮罩 + 12dp blur | Stack 底部覆盖层 `.linearGradient`（透明→背景色 0.7→背景色）+ 可选 `backgroundBlurStyle` | ❌ 待做 |
| 话题 FilterChip | 边框胶囊 Row；点击暂路由搜索页（Topic 目的地后补） | ❌ 待做 |
| SelectionContainer 标题 | `Text` `.copyOption(CopyOptions.LocalDevice)` 长按复制 | 可选 |
| CommentScreenComponent | `CommentLayer`（contentType `question`） | ✅ 本周已接线 |
| 统计行小图标 | `SymbolGlyph` 16fp + 辅助文字 | ❌ 待做（现为纯文本统计） |

### 2.2 数据层改造

1. **解码器补字段**（P2，小改）：include 已请求 `topics` 与 `relationship.is_following`，
   但 `Question` 模型与 `ContentDetailDecoder` 未提取——补 `topics: TopicSummary[]`（id/name）
   与 `isFollowing: boolean` 即可，无新网络请求。
2. **新增 `QuestionAnswerFeedRepository`**（P1 核心）：
   - `getAnswerPage(questionId: string, order: 'default' | 'updated', cursor?: string)`：
     走 `/api/v4/questions/{id}/feeds`，响应为与首页/热榜同族的 Feed 结构
     （`FeedTargetKind.ANSWER` 已存在），**预计直接复用现有 feed 解码**与
     `ZhihuHttpClient(session)`；实现时先抓一次真实响应固定线格式（与现有解码对齐）；
   - 分页/取消/代际控制照抄 `ChannelFeedController` 模式（generation + cancel）；
   - 屏蔽过滤复用 `BlockingRuleGateway`。
3. **关注**：`DefaultFollowRepository` 已有 `questions/{id}/followers` 端点与底栏接线，
   无需新增；如要做"关注计数本地 ±1"在上层补。
4. **登录门禁**：未登录不请求 feeds，信息流位置显示 `AppPageStatusPanel` 引导登录
   （对齐上游 allowGuestAccess=false，也规避 feeds 端点的风控拒绝）。

### 2.3 UI 组装（QuestionDetailPage 改造清单，自上而下）

1. 固定信息头：标题 + 统计行（补 eye/message/heart 小图标与浏览/关注计数）+ 评论按钮
   （评论已接线，样式对齐上游 outlined 风格可选）；
2. **正文折叠视口**（新 `@Builder` 或子组件）：
   ```
   Stack(clip: true, height: 动画高度) {
     Column { 正文分块渲染; 话题胶囊行 }.onAreaChange(回填 fullHeight)
     if (折叠中) 底部渐变遮罩层
     右下角 展开详情/收起详情 按钮（chevron_down/chevron_up + 文字）
   }
   ```
   折叠条件对齐上游（纯文本 ≥100 字或含图）；高度在 `min(fullHeight, 180vp)` 与
   `fullHeight` 间 `animateTo`；
3. **主操作行 + 排序行**：见 2.6 决策点；排序用 SegmentButton，切换即重置回答列表；
4. **回答信息流**：正文同一 `List` 的后续 `ListItem`（推荐——一次滚动贯通，结构最简，
   topContent 即列表头），或独立 List；卡片复用共享 feed 卡片 builder；
5. 未登录/空态/加载态/错误态：`AppPageStatusPanel` 复用；
6. 新交互补 testId（对齐上游 testTag 命名：`question_sort_default`、`question_follow_button`
   等），便于自动化回归。

### 2.4 图标映射（官方符号库，已逐一验证精确命中）

| 上游 Material 图标 | 用途 | `sys.symbol` | 备注 |
| --- | --- | --- | --- |
| AutoMirrored.Filled.ArrowBack | 返回 | `chevron_left` | 项目已用 |
| Filled.History | 顶栏日志 | `clock` | 符号库无 history，clock 为语义最近官方替代 |
| Filled.Share | 顶栏分享 | `share` | |
| AutoMirrored.Filled.Comment / ChatBubbleOutline | 评论 | `message` | 项目已用 |
| Outlined.Visibility | 浏览统计 | `eye`（或精确的 `visibility`） | |
| Outlined.FavoriteBorder | 关注统计 | `heart`（关注态可用 `heart_fill`） | |
| Filled.ExpandLess / ExpandMore | 收起/展开详情 | `chevron_up` / `chevron_down` | |
| Filled.Edit | 写回答 | `square_and_pencil` | 项目已用 |
| Filled.Check / Add | 已关注/关注 | `checkmark` / `plus` | 项目已用 |

验证方法：遍历 DevEco SDK 全量符号表 `ets-loader/sysResource.js`（AGENTS.md 指引方式）。
**图标不构成迁移障碍。**

### 2.5 状态管理约束

- 页面内状态（排序、展开态、回答列表）用 `@State` + 控制器，不出页面；
- 若需跨页面信号（如登录返回后刷新回答流），一律走 **AppStorage 广播 +
  `@StorageProp`+`@Watch`**（`loginFeedReloadTick`/`tabRefreshTick` 先例）——
  `@Builder` 参数传值与 `@Provide/@Consume` 在 HdsTabs/NavDestination 构建树下实测不可靠；
- 控制器对失活态自行 no-op（`refresh`/`reloadNow` 已有该语义）。

### 2.6 布局决策点（需产品拍板）

上游把**写回答 + 关注**放在正文下方的"主操作行"（不在底栏）；本侧现状是底栏左"关注问题"、
右"评论/更多"（本周按用户要求对齐回答页，且已移除写回答）。完全仿上游 vs 维持本侧底栏，
三种选项：

1. **推荐**：维持本侧底栏不动，正文操作行只加"写回答"（补上游核心转化入口，避免与底栏
   关注重复）；
2. 完全仿上游：正文操作行放写回答+关注，底栏关注移除；
3. 最小改动：不加写回答（上游差异项记入差异清单）。

## 三、实施步骤与工作量

| 阶段 | 内容 | 预估 |
| --- | --- | --- |
| P1 主体验 | `QuestionAnswerFeedRepository` + 登录门禁 + 排序切换 + 回答流嵌入（共享卡片） | 2~3 人日 |
| P2 细节对齐 | 正文折叠/展开动画 + 话题胶囊 + 统计行图标化 + 解码补 topics/is_following + testId | 1~2 人日 |
| P3 暂缓 | `QuestionAnswerNavigator`（上一答/下一答连续阅读）、日志网页入口、顶栏标题随滚动切换 | 视反馈 |

P1 完成即解决"问题页读不到回答"的核心缺口，形成可用的最小闭环。

## 四、风险与注意事项

- **feeds 端点需登录且受风控**：上游同样禁用匿名访问；模拟器环境可能整链路被拒
  （参考手机号登录在模拟器被风控的先例），服务端联调需真机 + 登录态；
- **折叠动画帧率**：长正文 + 渐变遮罩 + 模糊在低端机/模拟器上的流畅度需实测调参
  （必要时去 blur 只留渐变）；
- **feeds 线格式**：与现有 feed 解码同族、预期直接复用，但实施时必须先固定一次真实
  响应做单测夹具，防止字段漂移；
- **解析健壮性**：`detail` 为 HTML，沿用 reader 分块渲染与 WebView/Markdown 设置开关，
  不新增渲染路径。

## 五、参考

- 上游：`ui/QuestionScreen.kt`、`viewmodel/feed/QuestionFeedViewModel.kt`、
  `navigation/AnswerNavigator.kt`（快照 `22f6313c`，问题页与 `ec77d309` 研究版一致）
- 本侧：`ContentDetailPages.ets`（QuestionDetailPage/ContentDetailPage）、
  `DefaultContentRepository.ets`（QUESTION_DETAIL_INCLUDE）、`DefaultFollowRepository.ets`、
  `DefaultCommentRepository.ets`、`HomeFeedPage.ets`/`ChannelFeedPage.ets`（卡片与分页先例）
- 图标库：HarmonyOS Symbol（developer.huawei.com/consumer/cn/design/harmonyos-symbol）
