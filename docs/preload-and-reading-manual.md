# 知乎++ 鸿蒙版：改造手册（需求 → 方法 → 落点）

> 本文记录本轮全部改动的**原始需求**、**采用的方法**、**代码落点**与**尚未完成项**。
> 代码位置以仓库根目录为基准；分支 `feature/preload-and-reading`，基线 `920017b5`（`main`，含 #127 顶栏统一）。

---

## 0. 环境与工程约定（前置）

| 项 | 内容 |
|---|---|
| IDE / SDK | DevEco Studio 26.0.0（自带 HarmonyOS SDK 26.0.0.105，API 26） |
| 构建命令 | `pwsh -NoProfile -File scripts/verify-harmony.ps1`（Debug）／`-BuildMode release`（发行包） |
| 必需环境变量 | `JAVA_HOME=<DevEco>/jbr`（否则 `spawn java ENOENT`）、`DEVECO_SDK_HOME=<DevEco>/sdk` |
| PowerShell | 必须 pwsh 7（5.1 会因 UTF-8 中文乱码失败） |
| 工程路径 | **必须 ASCII**：hvigor 拒绝含中文的路径（否则 `00306003 Invalid project path`） |
| 依赖 | 根与各模块 `ohpm install`；`entry/oh_modules` 里指向 `core/data/reader` 的软链不能指向旧路径 |

---

## 1. 登录页：键盘遮挡输入框/协议与登录按钮

**你的需求**：登录页键盘会挡住设置项，要更优雅。

**我的方法**：登录页范围内把页面键盘避让改为「压缩（RESIZE）」，离开页面还原。

- 新增 `entry/src/main/ets/pages/LoginKeyboardAvoidance.ets`
  - `applyLoginKeyboardResize(uiContext)`：`getKeyboardAvoidMode()` 存旧值 → `setKeyboardAvoidMode(RESIZE)`
  - `restoreKeyboardAvoidMode(uiContext, previous)`：离开页面还原
- `entry/src/main/ets/pages/LoginPage.ets`（+7 行）：`aboutToAppear` / `aboutToDisappear` 各一行调用
- 效果：键盘只挤压内容区，协议勾选、登录按钮可滚到键盘上方；弹层（国家/地区）仍走自己的 Sheet 避让。

---

## 2. 正文滚动手感（非线性 + 多档预设）

**你的需求**：向下滑动手感差，要非线性、更符合直觉；**后续追加**：把"顺滑"定为新版本标准，两端再加两档。

**我的方法**：`List.friction` 调惯性 + `onScrollFrameBegin` 按速度做缓出增益（只作用手指按住阶段，惯性帧原样放行）。

- 新增 `entry/src/main/ets/pages/ReadingTweaks.ets`
  - 增益：`gain = min + (max−min) × (2r−r²)`，`r = min(1, |本帧位移|/12vp)`
- 接入（各 +16 行）：`ContentDetailPages.ets` 的正文 List 由 `NativeContentDocument.ets` 承担、连续阅读由 `ContinuousAnswerPage.ets` 承担，两处各加 `.friction(...)` + `.onScrollFrameBegin(...)`
- 档位（默认「标准」）：

| 档位 | 增益 | 摩擦 | 说明 |
|---|---|---|---|
| 跟随系统 | 1.00 | 系统默认 | 完全原生 |
| 柔和 | 1.00→1.08 | 0.72 | 比标准克制 |
| **标准**（原顺滑，默认） | 1.00→1.18 | 0.60 | 本版本基准 |
| 迅捷 | 1.05→1.40 | 0.45 | 滑得更远 |
| 极速 | 1.10→1.60 | 0.35 | 最激进 |
| 沉稳 | 0.85→1.02 | 1.05 | 收窄、停得快，适合精读 |

---

## 3. 回答整页切换：动画样式 + 触感反馈

**你的需求**：上下滑动切答要更多样式、更好用、有反馈。

**我的方法**：三套过渡样式 + 提交成功触感。

- 新增 `entry/src/main/ets/pages/ReadingTweaks.ets`（纯函数，可单测）
  - `answerSwitchTranslate()`（fade 保留 12% 位移，stack 保留 55%）、`answerSwitchDurationMs()`（slide 220 / fade 200 / stack 260）
  - `answerSwitchPaneScale()`（stack：预览页 0.92→1，当前页轻微后退）、`answerSwitchPaneOpacity()`（fade 按进度交接透明度）
- `entry/src/main/ets/pages/ContentDetailPages.ets`（约 +20 行）：4 个一行包装 + 模板里 `.opacity(...)`/`.scale(...)` 改为调用
- 提交成功：`if (committed) { performConfirmHaptic(); }`
- 设置键：`answerSwitchStyle`（slide / fade / stack）

---

## 4. 热评：条数可配、独立评论框、无热评不渲染

**你的需求**：回答底部热评数量可配；有独立评论框（像知乎网页版）；点击进完整评论；**后续追加**：没有热评就一开始不渲染这个框。

**我的方法**：
- 条数：设置项 `hotCommentPreviewCount`（1–5，默认 3）
  - `entry/src/main/ets/pages/HotCommentState.ets`：`normalizeHotCommentLimit()`，`load(..., limit)`
- 评论框：新增组件 `entry/src/main/ets/pages/components/ReadingWidgets.ets`
  - 自带草稿/发送状态/错误提示，`onSubmit` 返回空串即成功；与完整评论页互不影响
  - **不修改上游 `HotCommentSection`**：热评区与评论入口互相独立，各自出现或消失
- 无热评不闪框：
  - `hotCommentSectionVisible()` 只在 `READY` 为真（加载中/空/失败都不画框）
  - `ContentDetailPages.answerFooter`：热评可见才画热评卡片，评论框恒常驻
- 页面接线：`ContentDetailPages.ets`
  - `submitHotComment()` 写一条根评论，成功后作废该正文评论缓存并原地重取热评
  - `answerFooter` 用**单一 `Column`** 包裹热评卡片与评论框：`ListItem` 里放多个兄弟组件会互相重叠（评论框会被热评行压住），这是本分支修掉的一个真机可见 bug

---

## 5. 首页搜索栏样式（默认蓝细边白底）

**你的需求**：先要深蓝实底，**后续改**为「蓝色细边、白色内框」。

**我的方法**：三档样式，默认 `outlined`。

- 新增 `entry/src/main/ets/pages/components/ReadingWidgets.ets`
  - `outlined`：白底 + 1vp `#056DE8` 细边 + 蓝色图标文字（不使用玻璃材质）
  - `filled`：`#056DE8` 实底白字；`glass`：沿用 #127 的沉浸光感胶囊
  - 组件内部 `@StorageProp('homeSearchBarStyle')` 自取设置，三档只改表面、不改轮廓
- `entry/src/main/ets/pages/AppShell.ets`（改 4 行删 24 行）：`homeSearchPillSlot()` 改为一行 `HomeSearchBar`，删掉原 `homeSearchPillContent()`
- 设置键：`homeSearchBarStyle`（outlined / glass / filled）

---

## 6. 设置页整页点不动（严重 bug）

**现象**：任意设置详情页滚动正常、点击全失效（含我未改过的页面）。

**根因**：`SettingsSearchHighlight` 的高亮覆盖层作为**兄弟节点**盖在内容之上吃掉了 tap（pan 仍冒泡给 Scroll，所以滚动正常）。

**结论**：这是**上游源码自身的缺陷**，已在 main 的 #127 中修复（`level > 0` 才绘制 + 两个矩形 `hitTestBehavior(None)`）。
本分支**不再改动** `SettingsSearchHighlight.ets`，基线已含修复。

---

## 7. 预加载优化总开关（开启/关闭）

**你的需求**：一个按钮管理；先要 WiFi/开启/关闭三态，**后续改**为只有开启/关闭，去掉 WiFi 与以太网判定。

**我的方法**：
- 设置键：`preloadOptimization`（`PreloadOptimizationMode.OFF / ON`，默认 ON）
- 新增 `entry/src/main/ets/pages/PreloadCenter.ets`：`applyPreloadOptimization(mode)` → `preloadCache().setEnabled()` + `preloadService().setEnabled()` + 热榜首屏预取/重置
- `AppShell.ets`（+12 行）：`@StorageProp('preloadOptimization') @Watch(...)`，启动时先按默认值落地，偏好读回后由 Watch 纠正
- 关闭时两层缓存与调度器全部早退，回到项目原始按需加载

---

## 8. 首页加载：缓存优先、双缓冲、空结果保护

**你的需求**：冷启动直接从硬盘出内容、不要先登录再显示；主页内容硬盘存一份；从任意入口回主页时预取一份但**不生效**，只有下拉刷新才生效并立即重置重取；下拉不要提前预判；**后续追加**：冷启动立刻刷新会显示"暂时没有可显示的内容"。

**我的方法**：

1. **仓库层缓存优先**：`data/src/main/ets/repository/DefaultFeedRepository.ets`（+15 行）
   - 首屏一律先读启动快照；新增 `refreshAfterStartupCache()`（沿用「启动时自动刷新首页」决定是否补一次网络刷新）与构造参数 `skipStartupCache`
2. **静默刷新**：`entry/src/main/ets/pages/HomeFeedState.ets`（+48 行）
   - `refresh(background)`：background 时不显示下拉指示器、不清空已渲染内容
   - `restoreItems()`（首帧直出）、`applyPreparedPage()`（提交预取页，不重置游标）
3. **首帧直出**：新增 `entry/src/main/ets/pages/ColdStartPreload.ets`
   - `warmHomeStartupFeed(context)` 在 `EntryAbility` 启动时把快照解码进内存（`EntryAbility.ets` 仅 +3 行）
   - `HomeFeedPage` 首帧 `takeHomeStartupFeedItems()` → `restoreItems()` 直接渲染
4. **主页双缓冲（pending）**：新增 `entry/src/main/ets/pages/PreloadCenter.ets`
   - `prefetch(factory, enabled)` 用**独立 FeedRepository**（`skipStartupCache=true`）提前取下一页
   - 下拉**松手过阈值**：`take(items.length)` 直接提交（零等待）→ 清空并立刻重新预取
   - 拖拽过程**不做任何提前预判**；小页保护：pending 条目 < 3 且少于当前列表时不提交
   - **预取页一取回就连同它的正文一起预热**：`HomePendingFeed.prefetch(..., onReady)` 回调里立刻
     `prefetchPendingFeedAnswers(page.items)`（回答/文章正文，排在 NORMAL 队尾），所以下拉提交后点开任意一条都不用等；
     冷启动从快照直出走的是同一条路径（`restoreItems → applyState → prefetchFeedAnswers`）
5. **空结果保护**：`HomeFeedState.loadFirstPage()`
   - 本轮拿到空结果但列表已有内容时，**保留原内容并维持 READY**，不再退化成"暂时没有可显示的内容"

---

## 9. 逐级预加载（回答/评论/子评论/段评/相邻）

**你的需求**：主页从第一条开始预加载回答+图文+热评；进入回答预加载评论；进评论预加载子评论；回答里立刻缓存下一个回答及热评；点段评时也要预加载；「主页优先预加载前五条、搜索只预加载前五条与可视区」这类策略要能在设置里调。
**后续收窄**：进入回答后预加载负担过重，改为固定顺序「下一个回答正文 → 当前回答评论（首屏含热评）→ 下一个回答评论」，**不预取上一个回答与所属问题**（上一个回答靠缓存回溯，未命中就正常加载）；热评不再单独排队，跟随评论一起取。段评改为面板出现后才预热当前段。主页预取只取回答/文章正文，热评交给进入回答后的评论任务。

**我的方法**：所有预取收敛到一个串行调度器，调用方只报「该预热什么」，去重与排队由调度器负责。

- 新增 `entry/src/main/ets/pages/PreloadCenter.ets`
  - `prefetchFeedAnswers(items)`：主页当前显示页，只取**回答与文章**的正文，排进 `NORMAL`
  - `prefetchPendingFeedAnswers(items)`：主页双缓冲那一页（还没显示），**连它的回答/文章正文一起预热**，排在 `NORMAL` 档队尾（当前页正文优先，但不能垫到整队最后）
  - `prefetchOnAnswerOpened(previousId, answerId, nextId)`：固定 3 步（批内顺序不变）
    ① 下一个回答正文（最高优先级、不设寿命）→ ② 当前回答评论（首屏即热评）→ ③ 下一个回答评论；
    热评不再单独排队，把「当前答 ±1」设为缓存钉住窗口
  - `prefetchChildCommentsFor(items)`（前 20 条有子评论的根评论）与
    `prefetchSegmentComments(paragraph, markIndex, …)`（只热当前划线）走 `URGENT`
  - `prefetchCommentPages(contentType, contentId)`：进入评论页后继续翻 3 页评论（`NORMAL`，排在子评论之后）
  - `prefetchHotFeed(onPage)`：热榜首屏，`HOT_FEED` 档；取回后写 `feed:hot` 并交给 `HotFeedPending`
  - 只有落在当前钉住窗口里的条目才会 `promote()`，主页预取与段评不再无差别钉住

- **队列模型**（`PreloadPriority`）：单线程串行
  - 四档：`URGENT`（段评、子评论）> `NORMAL`（回答/评论/主页当前页）> `HOT_FEED`（热榜）> `HOME_PENDING`（最低档，当前未使用）
  - 同档**后进先出**（最新入队的批次先跑）；一个批次内部顺序保持不变（回答页那 3 步、信息流条目顺序都不会被倒置）
  - 主页双缓冲的**页面本身**由 `HomePendingFeed` 独立请求、不进队列；它的回答/文章正文排 `NORMAL` 队尾
  - **任务生命周期**：评论/子评论/段评/评论翻页 15s，其余非豁免任务（热榜）5s；到点没跑完就丢弃/中止，
    取消在途请求且不再重试；**主页预取与「回答页的下一答」不设上限**，保证冷启动与切答的兜底
  - 唯一会清空整条队列并取消全部在途请求的是关闭「预加载优化」这个开关
  - 同一内容重复入队时用新任务替换旧任务（“以你最后一次操作为准”）
  - `BUSY`（同一 client 单飞被占）不算失败：退到本档队尾延迟重试，最多 3 次（0.8s / 1.6s / 2.4s），过期后同样丢弃
- **两个导致段评/评论预取形同虚设的真 bug（已修）**
  1. `Index` 里 `preloadService().configure(...)` 在 `hotCommentRepositoryFactory` 赋值**之前**调用，
     存进去的是默认的 `() => undefined` → 评论/热评预取一直空转。改为赋值之后再用闭包装配。
  2. 段评预取原先自己 `new DefaultSegmentCommentRepository(...)`（无 session 的默认 HTTP 客户端）且不走队列；
     后来又与页面共用 `segmentCommentRepositoryHttpClient`，撞上 client 单飞（`rejected busy`）。
     现在由 `Index` 注入**独立的、带登录态**的段评客户端，并作为 `URGENT` 任务排队。
- 段评去重键含 `segmentId`：同一回答的不同划线不会被当成重复任务丢掉。
- 当前策略：主页「首屏就绪即全量排队」、搜索页不主动预取（沿用原按需加载）。**前五条/可视区分档尚未做成设置项**，见第 13 节。

---

## 10. 缓存架构与查找顺序

**你的需求**：1GB 总队列；**后续改** 2GB；**再改**为可切 512MB/2GB/4GB（默认 512MB）；相邻回答与热评要**独立内存空间额外重复缓存、更新激进**，拿不到再看队列，再没有才走网络；返回上一级不要销毁这一级的缓存。

**我的方法**：

- 新增 `data/src/main/ets/cache/PreloadCache.ets`（唯一一份内存缓存）
  - 配额可在设置里切 **512MB / 2GB / 4GB**（默认 512MB，`setQuota` 调小会立即回收）；到 85% 才批量回收到 70%，避免抖动
  - 分级淘汰：子评论 < 评论 < 回答正文 < 热评 < 信息流
  - **PINNED 层（上限 64MB，独立回收）**：只钉「当前答 ±1」的正文与评论；换窗口时先全部降级再重钉，超额按最久未访问回收
  - `readPreloadJson()` / `writePreloadJson()`：解析失败即作废该键，仓库层各只需 2~3 行
  - 回答与文章都走读穿缓存（`preloadAnswerKey` / `preloadArticleKey`），主页预取两类内容都覆盖
- 查找顺序（仓库层统一实现）：`PreloadCache`（命中即返回）→ 网络 → 取回后回填
  - 相邻回答的"不掉缓存"由 PINNED 窗口保证（只钉当前答 ±1）。曾实现的 64MB `AdjacentAnswerCache` 是**写而从不读**的死代码（两份内存副本语义重复），本分支已删除。
- 键函数：`preloadAnswerKey` / `preloadCommentsKey` / `preloadChildCommentsKey` / `preloadHotCommentsKey` / `preloadSegmentCommentsKey` / `preloadFeedKey`

---

## 11. 热榜预取

**你的需求**：启动进主页后台预取热榜；之后只在回前台或切到热榜时更新；切走再切回也生效。

**我的方法**：
- 新增 `entry/src/main/ets/pages/PreloadCenter.ets`：`HotFeedPending`
  - `prefetch()` 单飞取热榜首屏 → 存 pending（10 分钟 TTL）并写 `PreloadCache('feed:hot')`
  - `consumeForDisplay()`：切到热榜时判断新鲜度、清 pending 并立刻重新预取
- `DefaultChannelFeedRepository.loadPage`：热榜首屏命中缓存直接返回（+8 行）
- 触发：
  - 开关开启时 `PreloadBootstrap.applyPreloadOptimization()` 调 `prefetch()`
  - `AppShell.onTopLevelTabIndexChanged`：切到热榜且 pending 新鲜时 `consumeHotFeedPending()` → `refreshHot()`，页面重拉即命中缓存，随后自动重置重取（+4 行）

---

## 12. 返回上一级不清缓存

**你的需求**：从评论返回回答，不能丢掉前后回答缓存。

**我的方法**：
- `entry/src/main/ets/pages/AnswerSwitchPrefetch.ets`（+11 行）：新增 `cancelInFlight()`（只作废在途、**保留缓存**）
- `ContentDetailPages.invalidateAnswerSwitch(keepCache = false)`：页面被遮挡（打开评论/图集）时传 `true`，保留候选面板与预取缓存，返回后上下切答仍零等待

---

## 13. 尚未完成 / 已知边界

| 项 | 状态 | 说明 |
|---|---|---|
| 预加载策略分档（主页前五条、搜索前五条+可视区） | **未做成设置项** | 现在是「主页首屏就绪即全量按序预取、搜索页不预取」的单一策略 |
| 「全部评论」预取页数 | 固定 3 页 | `COMMENT_PAGES_PREFETCH_LIMIT`，未做成设置项 |
| 抢占只取消在途请求 | 已废止 | 现规则是「任务之间互不打断」，抢占与暂停取消都已移除 |
| 单飞 BUSY | 已处理 | 预取各档尽量使用独立 client（段评已分离）；仍撞上时退到本档队尾重试，最多 3 次 |
| 前台让带宽 | 已移除 | 改为靠 LIFO 让「用户刚操作的那批」天然排在最前；页面自身请求与预取不再互相取消 |
| 热榜 UI 级种子渲染 | **近似实现** | 切到热榜时靠缓存命中零等待，没有直接把预取页塞进 `ChannelFeedPage` 的状态 |
| 图片主动预热 | 未做（按约定） | 只预热文字与评论；图片交给系统 Image 缓存 |
| 冷启动首帧 | 已做 | 仍受 preferences 读取耗时影响，极端慢存储下可能有几十毫秒 |
| 手感曲线 | 按帧判定 | 120Hz 下同样手速的每帧位移更小，增益略低；如需可改为按时间归一 |

---

## 14. 变更文件清单（本轮）

**新增（8 个文件，功能各自收敛到一个文件）**
- `data/src/main/ets/cache/PreloadCache.ets`（512MB 主队列 + 64MB 钉住窗口 + JSON 读写；必须在 data 模块，供各仓库直接调用）
- `entry/src/main/ets/pages/PreloadCenter.ets`（**预加载唯一实现文件**：预取队列 `PreloadService`、
  热榜 `HotFeedPending`、主页双缓冲 `HomePendingFeed`、开关落地 `applyPreloadOptimization` /
  切热榜生效 `consumeHotFeedPending`）
- `entry/src/main/ets/pages/ColdStartPreload.ets`（**冷启动唯一实现文件**：快照暂存 `takeHomeStartupFeedItems`
  与预热 `warmHomeStartupFeed`）
- `entry/src/main/ets/pages/ReadingTweaks.ets`（**其余阅读向纯逻辑**：滚动手感六档、切答过渡参数、
  新增设置项的下标/文案换算）
- `entry/src/main/ets/pages/components/ReadingWidgets.ets`（**其余阅读向 UI**：首页搜索栏三档皮肤、
  回答底部独立评论框）
- `entry/src/main/ets/pages/LoginKeyboardAvoidance.ets`（登录页键盘避让两个函数）
- `entry/src/test/ReadingExperience.test.ets`（纯策略单测）
- `docs/preload-and-reading-manual.md`（本手册）

> 合并是为了“预加载 / 冷启动 / 其余”各占一个文件、便于整体搬运；`data` 模块的 `PreloadCache` 因为
> 仓库层（data 内部）直接读写，无法搬到 entry，单独保留。

**修改（25 个文件；括号内为相对基线的增/删行数，均只做接线）**
- `data/Index.ets`（+3）：导出缓存模块
- `data/.../preferences/AppPreferencesStore.ets`（+125/-3）：5 项新偏好（手感/搜索栏/切答动画/热评条数/预加载优化）
- `data/.../repository/FeedRepository.ets`（+2）：`refreshAfterStartupCache?()`
- `data/.../repository/DefaultFeedRepository.ets`（+17/-2）：启动快照优先 + 是否需要补刷新 + 构造参数 `skipStartupCache`
- `data/.../repository/DefaultContentRepository.ets`（+17/-2）：回答正文缓存
- `data/.../repository/DefaultCommentRepository.ets`（+31/-2）：根/子评论首屏缓存（仅热度排序）
- `data/.../repository/SegmentCommentRepository.ets`（+13/-1）：段评首屏缓存
- `data/.../repository/DefaultChannelFeedRepository.ets`（+8）：热榜首屏缓存
- `entry/.../entryability/EntryAbility.ets`（+3）：冷启动预热一行调用
- `entry/.../pages/AppShell.ets`（+38/-24）：搜索栏替换、预加载开关、热榜切页生效、5 项广播
- `entry/.../pages/AppearanceSettingsPage.ets`（+98/-1）：5 个新设置行 + 写回分支
- `entry/.../pages/ContentDetailPages.ets`（+165/-36）：切答动画、评论框、热评条数、逐级预取、遮挡时保留缓存
- `entry/.../pages/HomeFeedPage.ets`（+57/-5）：首帧直出、双缓冲接线、条目预取
- `entry/.../pages/HomeFeedState.ets`（+41/-7）：静默刷新、提交/还原、空结果保护
- `entry/.../pages/HotCommentState.ets`（+27/-8）：条数上限、仅 READY 可见
- `entry/.../pages/CommentLayer.ets`（+9）：子评论预取
- `entry/.../pages/CommentState.ets`（+1/-1）：`commentActionError` 导出
- `entry/.../pages/AnswerSwitchPrefetch.ets`（+11）：`cancelInFlight`
- `entry/.../pages/ContinuousAnswerPage.ets`（+16）、`NativeContentDocument.ets`（+16/-1）：滚动手感接入
- `entry/.../pages/LoginPage.ets`（+7）：键盘避让调用
- `entry/.../pages/Index.ets`（+23/-3）：双缓冲仓库工厂与预取服务装配
- `entry/.../pages/SettingsSearchIndex.ets`（+72）：5 个新设置项索引
- `entry/src/test/List.test.ets`（+2）、`HotCommentState.test.ets`（+2/-2）：注册新用例、更新热评可见性断言

总计：33 个文件；代码与文档改动约 +3.1k / −0.1k 行（含手册与单测，注释整理另计）。

---

## 15. 提交记录（本地，未推送）

分支 `feature/preload-and-reading`，基线 `920017b5`：

```
refactor: 预加载 / 冷启动 / 阅读体验各自收敛为单文件，原始源码只留接线
refactor(preload): 预取队列改为四档 + 同档后进先出，任务之间互不打断
feat(preload): 首页内容一进内存就预热该页全部回答与热评（含冷启动与双缓冲预取页）
perf(preload): 前台加载期让出带宽，首页预取改为只取正文并分层
fix(preload): 修复段评/评论预取空转，并让段评与子评论抢占队列最前
fix(reading): 修复回答底部评论框与热评行重叠，并收窄进答后的预取范围
docs: 新增阅读体验与预加载改造手册
test(reading): 补充滚动增益、切答过渡、首页双缓冲与缓存策略单测
feat(reading): 正文非线性滚动手感、切答过渡样式、底部评论框与热评条数
feat(settings): 新增阅读体验五项偏好与设置入口
fix(login): 登录页改用压缩键盘避让，键盘不再遮挡协议与登录按钮
```

验证（最终提交）：`pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -BuildMode release`
→ 编译通过、元数据校验通过、Hypium 1162/1162、产出 `ZhihuPlusPlus-HMOS-v0.5.10-unsigned.hap`。
