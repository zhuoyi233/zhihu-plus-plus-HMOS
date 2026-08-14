# P3-7 返回栈与滚动恢复验证

> 实现日期：2026-08-14；工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 26 编译 / target+compatible API 24。
> 验证命令：`pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`（结果：`Hypium 337/337` 通过，即基线 327 + 本批 10）。

## 范围

P3-7 是**贯穿性治理切片**：不新建大功能，只对 P3 1-4 已合入 dev 的页面（屏蔽规则页、屏蔽记录页、已读记录页、
收藏夹列表页、收藏夹内容页、回答/文章/问题详情页、用户主页、想法详情页、搜索页、首页/关注/热榜/日报列表）做
返回栈与滚动恢复的统一补齐，并建立后续切片可复用的机制。本批**不实现**评论弹层（P3-5 负责）与通知页（P3-6
负责）的恢复——它们尚未合入 dev。

治理范围逐项：

1. **列表进入详情返回后恢复位置**（首页/频道/搜索/收藏夹列表/收藏夹内容/屏蔽记录/已读记录 7 类列表页 + 详情页正文）；
2. **弹层关闭后重开的输入/开关状态**（详情页收藏弹窗、屏蔽确认弹窗）；
3. **导航去重**（同一目标不重复入栈，重点是 LOGIN/PEOPLE/QUESTION 等参数化目标）；
4. **进程重建后的必要恢复**（登录态恢复已覆盖；导航路径持久化评估结论）；
5. 为上述各项补 Hypium 测试并在 `List.test.ets` 注册（本批新增 `BackStackState.test.ets` 10 个用例）；
6. 本验证文档。

## 治理结论（逐项）

### 1. 列表进入详情返回后的位置恢复 —— 已固化机制 + 补重显防护

**结论：机制 = Navigation 页面栈自带的页面保留 + 页面重显幂等防护，无需 Scroller 手动保存/恢复。**

- ArkUI Navigation（`NavPathStack`）覆盖页面时不销毁被覆盖的 NavDestination（触发 `onHidden`，返回触发
  `onShown`，SDK 声明 `nav_destination.d.ts` 生命周期即此契约）；根页面（首页）始终保留在组件树中。因此
  「列表 → 详情 → 返回」时列表组件实例与其滚动位置默认保留，不需要 `Scroller` 保存/恢复像素位置。
- 但页面重显（被覆盖后重新成为栈顶）时 `aboutToAppear` 可能再次触发，且 `CollectionController` /
  `CollectionContentController` 的 `loadInitial()` 会无条件清空列表重载（`CollectionState.ets:98`、
  `CollectionContentState.ets:96` 均 `items = []`），若重显时重建控制器并重载，列表会回到顶部、丢失位置。
- **本批修复**：为全部列表/详情页补 `aboutToAppear` 幂等守卫（控制器仍存活时直接 `activate()` 复用，不重建、
  不重载）——首页、关注/热榜/日报、搜索（已有此模式，保持）、收藏夹列表、收藏夹内容、屏蔽记录、已读记录、
  问题/回答/文章详情、日报详情、用户主页、想法详情。`HomeFeedController` / `ChannelFeedController` /
  `CollectionController` / `CollectionContentController` / `SearchController` 的 `activate()` 本身幂等
  （已加载数据不重置、`loadInitial` 对非 IDLE 相位不重拉），页面守卫与之配套即保证重显不触发重载。
- 列表滚动位置本身依赖 Navigation 保留页面实例（框架契约），Hypium 无法断言真实滚动像素，本批以**状态层契约**
  固化「重显不重载」行为（见测试节），真实像素保留列入设备验收清单。

### 2. 弹层关闭后重开的输入/开关状态 —— 现状核查通过，一处已知小缺口

- **屏蔽确认弹窗（userBlockDialog）/ 关键词屏蔽弹窗（keywordBlockDialog）**：`pendingUserBlock` /
  `keywordBlockVisible` / `keywordBlockInput` 均声明在**页面级 `@State`**（`ContentDetailPages.ets`、
  `HomeFeedPage.ets`、`ChannelFeedPage.ets`），不活在弹层构建器内部；关闭（取消/确认）会清空输入属**有意设计**
  （每次屏蔽应重新输入关键词），重开即重新触发，无状态残留或串台。**结论：符合预期，无需改动。**
- **收藏弹窗（favoriteDialog，`CollectionDialogComponent`）**：选择列表数据来自仓库（每次打开重新加载，反映
  最新收藏状态，符合预期）；弹窗内「新建收藏夹」表单草稿（标题/描述/公开开关）位于弹层组件内部，关闭整个弹窗
  会丢失草稿。按 CLAUDE.md「可关闭编辑器的草稿应提升到弹层之外并按编辑目标隔离」的经验，此属**已知小缺口**：
  建议在主代理合并时把 `createTitle/createDescription/createIsPublic/showCreate` 提升到
  `ContentDetailPage` 并回传（改动涉及 `ContentDetailPages.ets` + `CollectionDialogComponent.ets`，为避免与
  P3-5 评论 worker 冲突块过大，本批不直接动，给出具体建议见「建议合并时处理」）。

### 3. 导航去重 —— 已修复（核心治理）

**问题**：原 `P1Shell.navigate()` 只与**栈顶**比较（`shouldPushP1Destination`），同一目标（name+参数）若已在
栈中**非栈顶**位置，会再次 push 造成重复页面；返回时可能只是露出前一个重复页面（CLAUDE.md「返回栈上下文保存」
教训）。`isInfrastructureDestination` 使用 `MOVE_TO_TOP_SINGLETON` 按 **name** 匹配，对参数化页面（如
PEOPLE/QUESTION，不同 id 是不同页面）不适用——不能按 name 去重。

**修复**（`core/.../navigation/StartupDestinationChannel.ets` + `P1Shell.ets`）：

- 新增 `P1StackEntry`（与 `NavPathInfo` 结构兼容）与 `findP1DestinationStackIndex(entries, destination)`：
  按身份（`p1DestinationIdentity`，即 name+参数）扫描整个返回栈，返回首个匹配下标，不存在返回 -1。与既有
  `shouldPushP1Destination` 相比，这是**栈级**去重（后者只比栈顶），且不误伤不同 id 的参数化页面。
- `navigate()` 在入栈前先调用 `findP1DestinationStackIndex`：同一目标已在栈中任何位置 → **直接忽略该次导航**
  （不入栈、不移栈顶），返回路径保持原样；基础设施页面（LOGIN 等）沿用 `MOVE_TO_TOP_SINGLETON`。
- 设计取舍：重复目标在栈中但非栈顶时选择「忽略」而非「移栈顶」（`moveToTop`/`popToIndex` 会弹出其上页面、
  改变返回路径），避免在无法真机验证时引入栈重构风险；如需「移栈顶」语义可改为 `popToIndex(existingIndex)`，
  建议真机验证后决定。实际场景里「查看问题」「再点作者」类入口在当前 dev 页面中不存在（详情页没有回链到栈内
  目标的入口），「忽略」不会造成可见的死按钮。

### 4. 进程重建后的必要恢复 —— 登录态已覆盖，导航路径持久化列为后续

- **登录态恢复已覆盖**：`EntryAbility.onCreate` 的 `session-restore` 启动任务 → `getAppSessionOwner()
  .restoreDeferred()` → `Index` 组合根在会话恢复完成前只显示「正在恢复登录状态」，完成后注入 `session` 渲染
  `P1Shell`；`P1Persistence.test.ets` / `AppStartup.test.ets` / `SessionRepository.test.ets` 固化该契约。
- **导航路径持久化（进程被杀后恢复到之前的页面）未实现**：进程重建后始终回到首页（除非携带深链，深链走
  `startupDestinationChannel` 恢复目标页）。本批**评估结论：列为后续**。理由：恢复路径需把当前
  `P1Destination` 序列化进 Preferences、在 `Index` 会话恢复后按序 re-push（或用 `NavPathStack.setPathStack`），
  并处理登录态未就绪、`shouldReloadAfterAuthentication` 重载、去重策略等多处交互；属于跨页面状态架构改动，
  与「最小侵入、优先测试固化」的本批边界不符。建议主代理合并后单独立项（可复用本批的 `findP1DestinationStackIndex`
  与 `p1DestinationIdentity` 做恢复前的栈重建与去重）。

### 5. 复用机制

- `findP1DestinationStackIndex` + `P1StackEntry`（core 导出）即为后续切片（评论弹层、通知页）入栈前
  去重的复用入口；`p1DestinationIdentity`（既有）与之一致。页面重显幂等守卫模式（`aboutToAppear` 内
  `controller !== undefined` 时直接 `activate()`）供 P3-5 评论弹层、P3-6 通知页沿用。

## 自动化覆盖

新增 `BackStackState.test.ets` 共 10 个用例（327 → 337），并由共享入口 `List.test.ets` 注册（仅追加，未动其他注册行）：

- **导航去重（6 个，纯函数层，可断言）**：
  - 同一目标在栈底/中间/栈顶均返回对应下标（`deduplicatesSameTargetAtAnyStackPosition`）；
  - 不同 id 的 PEOPLE/QUESTION、不同类型的 content 目标不误去重（`allowsDifferentParameterizedTargets`）；
  - 不同搜索词按身份区分、相同搜索词去重（`distinguishesSearchQueriesByIdentity`）；
  - 解码失败的栈条目被跳过、不影响后续匹配（`ignoresUndecodableStackEntries`）；
  - 无参基础设施页（SETTINGS/LOGIN）按 name 去重（`deduplicatesStatelessInfrastructureDestinations`）；
  - 空栈/已清空栈返回 -1（`returnsMinusOneForEmptyOrClearedStack`）。
- **列表重显不重载（4 个，状态层断言，不依赖真实滚动像素）**：`deactivate` → `activate` 后
  - 首页 items 保留、相位保持 READY、仓库 load 次数不增（`keepsHomeFeedItemsAcrossReappearanceWithoutReload`）；
  - 收藏夹列表 items 保留、不重载（`keepsCollectionListItemsAcrossReappearanceWithoutReload`）；
  - 收藏夹内容 items 保留、detail/items 各只请求一次（`keepsCollectionContentItemsAcrossReappearanceWithoutReload`）；
  - 搜索已加载结果保留、不重搜（`keepsSearchResultsAcrossReappearanceWithoutReload`）。

验证结果：`Hypium 337/337` 通过（API 26 编译，target=6.1.1(24)，compatible=6.1.1(24)）。

## 本批改动文件

- `core/src/main/ets/navigation/StartupDestinationChannel.ets`：新增 `P1StackEntry` 与 `findP1DestinationStackIndex`。
- `entry/src/main/ets/pages/P1Shell.ets`：`navigate()` 接入栈级身份去重。
- 页面重显幂等守卫（`aboutToAppear` 补 `controller !== undefined` 分支）：
  `HomeFeedPage.ets`、`ChannelFeedPage.ets`、`CollectionPage.ets`、`CollectionContentPage.ets`、
  `BlockedFeedHistoryPage.ets`、`ReadHistoryPage.ets`、`ContentDetailPages.ets`、`DailyStoryDetailPage.ets`、
  `PeoplePinDetailPages.ets`。
- `entry/src/test/BackStackState.test.ets`（新增）+ `entry/src/test/List.test.ets`（追加注册）。

## 建议合并时处理

1. **收藏弹窗新建表单草稿提升**：把 `CollectionDialogComponent` 的 `showCreate/createTitle/createDescription/
   createIsPublic` 提升到 `ContentDetailPage`（调用方持有、关闭重开回传），对齐 CLAUDE.md 草稿约定；涉及
   `ContentDetailPages.ets` 与 `CollectionDialogComponent.ets`，为避免与 P3-5 评论 worker 冲突块过大，本批未动。
2. **进程重建导航路径持久化**：见上文第 4 节，建议单独立项。
3. **「忽略 vs 移栈顶」取舍**：若真机验收发现「同一目标已在栈中时点击无反馈」影响体验，可将
   `findP1DestinationStackIndex >= 0` 分支改为 `this.pathStack.popToIndex(existingIndex)`（需真机验证返回路径）。

## 设备验收清单（API 24 虚拟机 + 登录态；[ ] 需真机/虚拟机验证）

- [ ] 首页/热榜/关注/日报列表下滑后进入回答/文章/问题详情，返回后列表停留在原位置（含分页加载后）；
- [ ] 搜索页滚动后进入详情返回，输入框内容与结果列表位置保留；
- [ ] 收藏夹列表 → 收藏夹内容 → 详情，逐级返回后各级列表位置保留；
- [ ] 屏蔽记录/已读记录列表滚动后进入详情返回，位置保留；
- [ ] 详情页（长正文）下滑后进用户主页再返回，正文滚动位置保留；
- [ ] 详情页收藏弹窗关闭重开：选择列表刷新、新建收藏夹表单草稿丢失为已知小缺口（如接受则勾选通过）；
- [ ] 详情页/首页/频道「屏蔽关键词」弹窗取消后重开，输入框为空且无残留；
- [ ] 同一用户主页在栈中出现过的场景（详情→作者→返回→再点作者）不再产生重复页面；
- [ ] 登录页从多个入口进入，返回后不残留重复 LOGIN 页；
- [ ] 进程被杀后重启：登录态自动恢复；当前停留在非首页时重启回首页（导航路径持久化为后续项）；
- [ ] 评论弹层（P3-5 合入后）与通知页（P3-6 合入后）进入详情返回的滚动/弹层恢复回归。

## 环境备注（主代理合并时需知）

本 worktree 的 oh_modules 链接初始配置存在**跨 worktree 泄漏**，已在本批修复（均为文件系统层面，不入提交）：

1. `entry/oh_modules/{core,data,reader}` 曾指向主 checkout 的 `entry/oh_modules/*` → 改为指向本 worktree 内模块；
2. `data/oh_modules/core`、`reader/oh_modules/core` 曾指向主 checkout → 改为指向本 worktree 的 `core`（该泄漏会导致
   entry 编译时 core 导出表取到主 checkout 的旧版，新导出不可见）；
3. 根 `oh_modules` 曾是指向主 checkout 的 junction（其下 `@ohos/hypium` 经主 checkout 链到 p3-8 worktree 的安装），
   hvigor 的 esmodule 打包会跳过项目根之外的内容，导致 `modules.abc` 缺少 hypium 记录、测试应用启动即抛
   `cannot find record '&@ohos/hypium/index&1.0.25'`、Hypium 永远不执行 → 已把根 `oh_modules` 重建为自包含真实目录
   （`@ohos/hypium@1.0.25`、`@ohos/hamock@1.0.0`、`.ohpm`，内容复制自 p3-4 worktree 的已知可用安装）；
4. 期间还清掉了一个自 13:32 起存活的陈旧 hvigor daemon 与多轮中断构建遗留的 node/Previewer 僵尸进程。
