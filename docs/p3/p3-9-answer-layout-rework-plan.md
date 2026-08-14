# P3-9 回答/文章详情页按上游排版重构计划

> 制定日期：2026-08-14
> 依据：Android 上游 `shared/src/commonMain/kotlin/com/github/zly2006/zhihu/ui/ArticleScreen.kt`
> （回答与文章共用，2189 行）与 `ui/AnswerEndorsementChip.kt`
> 状态：计划文档（未开始实现）

## 一、背景

鸿蒙端回答/文章详情页（`entry/src/main/ets/pages/ContentDetailPages.ets`）当前的操作区
（赞同/反对/感谢/收藏/评论/屏蔽）为**正文上方横排文字按钮**，与上游 Android 的
**底部操作栏 + 顶部折叠作者栏 + 正文中部信息区**三段式布局差异较大。本计划按上游排版
重构鸿蒙端详情页，使交互位置与上游一致，并为后续元素（认可徽章、IP 属地、阅读进度条、
底部菜单）预留接入点。

## 二、上游排版完整结构（基准）

上游回答/文章共用 `ArticleScreen.kt`，Scaffold 三段式：`topBar`（两行折叠顶栏）+
`bottomBar`（可自动隐藏操作栏）+ 中部 `verticalScroll` 正文 Column。

### 2.1 顶部：`ZhihuTwoRowsTopAppBar`（两行折叠顶栏）

- **收起态（第 1 行）**：返回键（圆底 IconButton，surfaceVariant 底色）｜标题
  （单行省略，`TextOverflow.Ellipsis`，回答类型可点击跳问题页）｜…更多按钮。
- **展开态（第 2 行）**：作者行（整行可点击进用户主页）：
  - 作者头像 40dp 圆形（`AsyncImage`，无图时 surfaceVariant 占位圆）。
  - 作者名 + 可选 `AuthorBadge` 徽章。
  - 作者简介（展开态显示，bodyMedium）。
- 顶栏左侧朗读按钮（TTS 播报中显示停止按钮）。
- 展开/收起跟随滚动（`rememberPreferCollapsedExitUntilCollapsedScrollBehavior`），
  有 `translationY`+`alpha` 动画。

### 2.2 中部：正文 Column（`verticalScroll`）

自上而下：

1. **日期行**：`发布于 <时间>`、`编辑于 <时间>`（11sp Gray，可 `pinAnswerDate` 置顶）。
2. **社交信用行**（`ArticleVotersSocialCredit`）：
   - 「N 人赞同了该回答」（bodySmall，可点击 → `VotersSheet` 赞同者列表）。
   - 「有 N 人认为此回答包含AIGC内容」（error 色，AIGC 标记人数）。
3. **认可徽章流**（`AnswerEndorsementChip`）：`FlowRow` 流式换行，间隔 8dp；
   每个徽章为圆角胶囊（RoundedCornerShape(50)），内边距
   `start=10, top=5, end=8, bottom=5`，含可选 16dp 前后图标 + 13sp SemiBold 文本，
   颜色取知乎 token 表（`GBK/GBL/GRD/GYL` 系列，明暗两套 + alpha）。
4. **正文**：`RenderMarkdown`（Compose Markdown，`selectable=true`），`header={}`
   `footer={}` 内含视频附件 + 日期 + **IP 属地**（右对齐 11sp Gray）。
5. 正文底部留白 `16 + 36dp`，避开底部操作栏。

### 2.3 底部操作栏（`bottomBar`）

- **主视觉（默认）**：单行 `Row`，`fillMaxWidth` + 水平 16dp 内边距 + 系统栏底部
  内边距 + 8dp，高度 36dp，`Arrangement.SpaceBetween` 分两组：

  **左组**（圆角 50 胶囊容器，按投票状态整体变色）：
  - 赞同：图标+数字按钮（蓝色主题色 `#3671EE`/暗色 `#628DF7`）。
  - 反对：独立图标按钮（同容器内）。
  - 状态联动：Neutral 时白底蓝字（`voteUpNeutralButtonColors`）；Up/Down 时蓝色
    实底白字（`voteUpActiveButtonColors`），另一侧收成纯图标。

  **右组**（`Arrangement.End`）：
  - 收藏：IconButton（已收藏 = 橙色 `#F57C00` 实底白图标；未收藏 = secondaryContainer
    底 onSecondaryContainer 图标）。
  - 评论：图标+数字按钮（`💬 185`，`voteUpNeutralButtonColors`）。
  - …更多（`MoreVert`）：打开底部菜单弹窗（`showActionsMenu=true`）。

- **duo3 药丸视觉**（设置 `useDuo3ArticleActions` 切换）：投票区为分段胶囊动画
  （赞/踩滑动切换，`animateColorAsState` 颜色动画），收藏/评论同构，右侧组圆角 50
  surfaceContainerHighest 容器。
- 底部栏**自动隐藏**：滚动时 `translationY` 下移 + alpha 淡出，上滑恢复。

### 2.4 底部菜单弹窗（`MyModalBottomSheet`）

`MenuActionButton`（图标+文字，12dp 间隔竖排）依次：
**朗读** → **分享** → **总结本文** → **标记疑似 AIGC** → **复制链接** →
**进入沉浸式** → **导出文章 (Markdown/图片/HTML/PDF)** → **在电脑中打开**。

### 2.5 附加元素

- **阅读进度条**：`VerticalReadingProgressBar` 右侧竖条（避开系统栏）。
- **跳过回答按钮**：FAB（`buttonSkipAnswer`，可自动隐藏）。
- **回答切换手势**：`AnswerHorizontalOverscroll`/`AnswerVerticalOverscroll`
  （tanh 阻尼 + 弹簧回弹 + 震动反馈，`answerSwitchMode` 配置）。
- **双击操作**：`answerDoubleTapAction`（点赞/进入沉浸式）。

## 三、鸿蒙端现状与差距

当前鸿蒙详情页（`ContentDetailPages.ets` 的 `ContentDetailPage`）结构：
标题 Text → 作者文字行 → 统计文本 → 屏蔽作者/收藏/评论/屏蔽关键词文字按钮 →
`interactionBar`（赞同/反对/感谢横排）→ `NativeContentDocument` 正文 → 弹层
（收藏/屏蔽用户/屏蔽关键词/评论）。

| 元素 | 上游 | 鸿蒙当前 | 差距 |
| --- | --- | --- | --- |
| 赞同/反对/感谢 | 底部栏（胶囊组） | 正文上方横排 | **位置不符，需下沉到底部栏** |
| 收藏 | 底部栏 IconButton | 正文上方文字按钮 | **位置不符** |
| 评论 | 底部栏（带数字） | 正文上方文字按钮 | **位置不符** |
| 菜单 | 底部弹窗 8 项 | 无 | **缺失** |
| 顶栏作者行 | 头像+徽章+简介（折叠两行） | 仅文字行 | 需重构为折叠顶栏 |
| 认可徽章 | FlowRow 胶囊流 | 无 | **缺失** |
| 社交信用行 | 赞同数/AIGC 人数（可点） | 统计文本内 | 需拆分 |
| IP 属地 | 正文底部右对齐 | 无 | **缺失** |
| 阅读进度条 | 右侧竖条 | 无 | **缺失** |
| 底部栏自动隐藏 | 滚动隐藏/上滑恢复 | 无 | **缺失** |
| 朗读/分享/总结/导出 | 菜单内 | 无 | **缺失**（依赖系统能力） |

## 四、重构方案（分阶段）

### 阶段 A：底部操作栏（核心，先做）

将互动区从正文上方移至页面底部固定栏，对齐上游主视觉：

1. `ContentDetailPages.ets` 新增 `bottomActionBar` @Builder：
   - **左组胶囊**：赞同（图标+数字）/ 反对（图标），沿用 P3-3 `ContentVoteController`
     状态（`voteState/voteupCount`），容器按状态变色。
   - **右组**：收藏 IconButton（已收藏橙色）+ 评论按钮（图标+数字，接 P3-5
     `CommentLayer`）+ …更多（先占位，阶段 C 接入菜单）。
   - 页面布局改 `Stack`：正文 `layoutWeight(1)` + 底部栏固定。
2. 移除 `interactionBar` 在正文上方的渲染，逻辑（控制器/乐观更新）不动。
3. 底部栏保留「感谢」——上游无独立感谢按钮（合并进菜单或省略，按产品决策），
   先与上游对齐去掉独立按钮，感谢保留在详情数据内。

### 阶段 B：顶部折叠作者栏

1. 顶部改为两行可折叠作者栏（ArkUI `Navigation` 标题区或自定义 `Stack` 叠加）：
   - 收起态：返回键 + 标题单行 + 更多。
   - 展开态：头像（圆形，无图占位）+ 作者名 + 徽章（如有）+ 简介。
   - 跟随正文滚动折叠（ArkUI 可用 `Scroll` 的 `onScrollIndex`/偏移量驱动显隐）。
2. 作者行整行可点击 → 用户主页（复用 `P1DestinationName.PEOPLE`）。

### 阶段 C：底部菜单弹窗

新增 `ActionMenuSheet`（ArkUI `bindSheet` 或自绘弹层），`MenuActionButton` 竖排：
分享（复用 `ZhihuShare`/系统分享）→ 复制链接 → 朗读（如系统 TTS 可用）→
总结本文（预留）→ 标记疑似 AIGC（**P3-8 已移除，仅预留接口，不渲染入口**）→
导出（预留）→ 沉浸式（预留）。

### 阶段 D：信息区与附加元素

1. 社交信用行：从统计文本拆分「N 人赞同了该回答」（可点 → 赞同者列表，
   预留 `VotersSheet`）+「有 N 人认为此回答包含AIGC内容」（**默认不显示**，
   服务未接，仅模型预留）。
2. 认可徽章流：`endorsements` 模型 + FlowRow 胶囊（按 token 表映射颜色），
   上游字段接入 `ContentDetailDecoder`。
3. IP 属地：正文底部右对齐灰色小字（数据来自详情接口，若未返回则隐藏）。
4. 阅读进度条：右侧竖条，随正文滚动更新（ArkUI 用 `Scroll` 偏移比）。
5. 底部栏自动隐藏：滚动下移 + 上滑恢复（`Scroll` 方向判定 + 动画）。

## 五、安全与正确性边界

- 所有交互沿用既有仓库/控制器（`VoteRepository`/`CollectionRepository`/
  `CommentRepository`），不新增网络路径；登录门禁、乐观更新回滚、busy 门禁不变。
- 认可徽章颜色映射只接受已知 token（`GBK/GBL/GRD/GYL` 前缀），未知 token 回退
  主题色，不回显原始 token 到日志。
- IP 属地、AIGC 人数等展示字段解码时校验类型，非法输入不进入 UI 文案。
- 底部栏/顶栏折叠动画仅视觉层，不改变数据流；导航去重（P3-7）保持。

## 六、测试

- 现有 Hypium：`ContentDetailState.test.ets`、`ContentInteractionState.test.ets`
  （P3-3）继续全绿；新增布局相关用例：
  - `BottomActionBar` 状态映射（Neutral/Up/Down 三态 → 容器/按钮配色与文案）。
  - 底部栏按钮点击路由（收藏→弹窗、评论→CommentLayer、菜单→Sheet）。
  - 顶栏折叠状态切换不触发重载（P3-7 重显幂等守卫兼容）。
  - 徽章流解码：合法 token 渲染、未知 token 回退、缺失字段不抛错。
- 设备验收：回答/文章详情页底部栏与上游一致；滚动时底部栏隐藏/恢复；
  折叠顶栏头像可进用户主页；菜单弹窗各入口可达。

## 七、验收清单（设备）

- [ ] 回答详情页底部操作栏：赞同（图标+数字）/反对胶囊组，状态切换变色；
- [ ] 收藏 IconButton（已收藏橙色）、评论按钮（图标+数字）位置与上游一致；
- [ ] …更多打开底部菜单弹窗（分享/复制链接等入口可达）；
- [ ] 顶部两行折叠作者栏：收起单行标题、展开头像+作者名+简介，滚动联动；
- [ ] 作者行点击进用户主页，返回后正文滚动位置保留（P3-7 回归）；
- [ ] 「N 人赞同了该回答」社交信用行可点开赞同者列表（如有数据）；
- [ ] 认可徽章 FlowRow 胶囊流渲染正确（token 色板映射）；
- [ ] IP 属地右对齐显示（接口有值时）；
- [ ] 阅读进度条随滚动更新；
- [ ] 底部栏滚动自动隐藏、上滑恢复；
- [ ] 移除正文上方互动区后无残留按钮、无布局跳变；
- [ ] 原有屏蔽作者/屏蔽关键词/收藏/评论入口行为回归。

## 八、风险与注意事项

- **阶段 A 是最小可行步**：只移动互动区到底部栏即可显著对齐上游观感，其余阶段
  可分批推进；避免一次性大改导致 `ContentDetailPages.ets`（718 行）冲突面过大。
- ArkUI 无 Compose `FlowRow` 等价物：认可徽章流用 `Flex` 换行或
  `GridRow`/`List` 实现，注意换行语义与间隔一致性。
- 底部栏固定 + 正文滚动在 ArkUI 用 `Stack` + `Scroll`（`layoutWeight`）组合，
  注意键盘弹出（评论输入）时底部栏避让（`expandSafeArea`/`keyboard` 监听）。
- 感谢按钮上游无独立入口：移除前与用户确认产品决策（保留在菜单 or 完全移除）。
- 「总结本文」/「朗读」依赖 AI/系统 TTS 能力，本计划仅预留入口与占位文案，
  不承诺能力。
