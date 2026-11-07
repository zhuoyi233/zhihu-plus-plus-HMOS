# P2 知乎日报正文详情验证记录

> 本文件记录日报链路的**历史行为边界**与**当前实现/验证状态**。
> 上半部分（§1）是旧的「日报 → 原文中转」方案，已不再是列表默认路径，保留以便追溯；
> §2 起是 2026-10-29 实施的原生日报阅读（`docs/plans/知乎日报原生渲染分析计划.md`）。

## 1. 历史方案（旧列表直跳路径，仍作为开关关闭时的回退）

将日报 API7 的正文映射为既有原生问题、回答或文章详情，不引入 WebView、端侧 AI 或任意外链打开。

- 请求：`GET https://daily.zhihu.com/api/7/story/{storyId}`；story ID 只接受 1–30 位、非零十进制整数。
- 网络：匿名请求、无 Cookie、无 ZSE、禁止重定向，沿用 `ZhihuHttpClient` 的 1 MiB 响应上限与超时策略。
- 解析：仅读取 JSON `body`，优先 `a.originUrl`，其不支持时再读取 `div.view-more a`；只接纳既有深链解析器识别的文章、问题和回答。
- 跳转：将受信链接转为原生目的地，复用原生详情与阅读记录；用户、视频、任意外站及未解析正文显示“暂不支持原生阅读”。
- 生命周期：重复打开会取消旧请求并丢弃旧结果；页面离开后不再发布导航。

该链路在「日报原生阅读」开关关闭时**完整保留**（`ChannelFeedPage.openDailyStory` 的 else 分支），
开关默认开启（原生阅读为默认路径），显式关闭后才走旧路径。

## 2. 原生日报阅读：分层与契约

| 层 | 文件 | 职责 |
| --- | --- | --- |
| data | `domain/DailyStoryDetailDecoder.ets` | `DailyStoryPayload`（id/title/bodyHtml/image/栏目/type/规范 shareUrl/讨论目标）；按 UTF-8 字节预算拒绝超限正文；响应 ID 必须与请求 ID 一致；讨论目标按 `div.view-more` → `a.originUrl` → 正文第一个问答链接（归一为问题页）取值 |
| data | `repository/DailyStoryRepository.ets`、`DefaultDailyStoryRepository.ets` | 新增 `getStory()`；保留 `getDestination()` 供旧路径使用；请求仍匿名、无 Cookie、禁止重定向 |
| data | `preferences/DailyStoryReaderPreferences.ets` | 集中式本地开关（`native` 默认 / `legacy`）与文案 |
| reader | `reader/DailyStoryDocument.ets` | 日报方言 → `ReaderBlock[]`，附统计、受限诊断码与完整性（COMPLETE/PARTIAL/UNSUPPORTED）；页尾 `div.view-more` 导航条丢弃，由页面按钮承接 |
| reader | `reader/ReaderImageSourcePolicy.ets` | 图片展示/预览/保存统一政策（https + 无用户信息 + 无自定义端口 + `pic*/pica/picx.zhimg.com`） |
| entry | `pages/DailyStoryDetailState.ets` | 状态机 IDLE/LOADING/READY/PARTIAL/UNSUPPORTED/ERROR，generation 丢弃过期结果 |
| entry | `pages/DailyStoryDetailPage.ets` | 头图 + 标题 + 栏目/分享 + 整份阅读器（预解析块）+ 页尾「查看知乎讨论」按钮 + 图片预览叠层 |
| entry | `pages/NativeContentDocument.ets` | 新增 `documentBlocks`（预解析块输入）与 `contentNotice`（PARTIAL 就地提示） |
| core | `navigation/DeepLinkResolver.ets` | `https://daily.zhihu.com/story/{id}` 精确 host/path 识别 → `DAILY_STORY`；`toAppDestination` 与入口 `contentLinkDestination` 同步支持 |
| entry | `module.json5` | 声明 `https` + `daily.zhihu.com` 的 browsable URI，外部点击日报链接可路由进本应用（仅 `resolveZhihuLink` 认可的 `/story/{id}` 形态才会进原生页） |

**没有新增 `data → reader` 依赖**：data 只返回载荷，块转换在 reader，组合在 entry。

## 3. P0 证据（本次观测，2026-10-29）

采样方式：匿名 `curl.exe` 读取 `https://daily.zhihu.com/api/7/story/{id}`，原始响应只落
`.tmp/daily-plan-audit/`（被 Git 忽略），**不入库、不作为单测前提**。

| story | type | body UTF-8 字节 | question | blockquote | img | figure | figcaption | hr | LinkCard | 解析结果 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9793572 | 0 | 4379 | 1 | 5 | 3 | 1 | 1 | 1 | 5 处 class 命中（1 张卡片） | COMPLETE |
| 9793594 | 0 | 3446 | 1 | 4 | 3 | 1 | 1 | 1 | 1 张卡片 | COMPLETE |
| 9793605 | 0 | 9111 | 1 | 2 | 2 | 1 | 0 | 6 | 0 | COMPLETE |
| 9793581 | 0 | 7176 | 1 | 0 | 8 | 7 | 0 | 5 | 0 | COMPLETE |
| 9793588 | 0 | 16763 | 1 | 0 | 20 | 19 | 19 | 1 | 0 | COMPLETE |

差分脚本（`.tmp/parser-harness/`，临时工具，未入库）把 `reader` 源码**原样复制**后在 Node 中运行，
因此不存在「测试里另写一份解析器」的漂移。检查项与结果：

- 5 个样本的正文块数与**源 HTML 可见文本**逐段比对（排除 `div.meta` 作者区、`div.img-place-holder`
  占位与页尾 `div.view-more`）：**0 处丢字**。`view-more` 里的「查看知乎讨论」是导航入口，
  现由阅读页页尾按钮承接，不再作为正文段落出现（同一链接仍可点，只是换了位置与形态）；
- figure 数与 IMAGE 块数一致（1/1、1/1、1/1、7/7、19/19）；
- blockquote 数与引用块数一致；头像（1 个）从不进入正文图集；卡片封面不会重复成 IMAGE；
- 重复解析得到的块 ID 序列完全一致（`daily-block-{n}`），可作阅读锚点。

**未观测**：多 question/answer 的真实样本、历史版式、特殊 `type`、空 `body` 的真实响应、
带 `table`/`iframe`/音视频的样本。这些路径只用合成输入验证防御逻辑（见 §4），不声称有真实样本。

## 4. 自动验证

| 用例文件 | 覆盖 |
| --- | --- |
| `entry/src/test/DailyStoryDocument.test.ets` | 主样本结构（5 引用/5 回答链接/5 用户链接/1 正文图/1 卡片/1 头像不计入/1 空占位）、嵌套引用深度、行内链接前后文本、实体解码、script/style/注释丢弃、页尾 `view-more` 导航条丢弃、不可信图片主机降级、危险协议链接不可点、纯图正文、空/超预算/超深嵌套、确定性、诊断不泄正文、属性内 `>` 与未闭合标签、多节多作者、不支持结构 PARTIAL、公式块、列表 |
| `entry/src/test/DailyStoryRepository.test.ets` | 载荷解码（规范 shareUrl、栏目、头图候选）、响应 ID 不符、UTF-8 字节预算、讨论目标优先级（`view-more` > `originUrl` > 正文问答链接归一为问题页、非问题链接忽略）、`getStory` 一次请求且匿名无重定向、非法 ID 不发请求、取消后丢弃迟到结果 |
| `entry/src/test/DailyStoryDetailState.test.ets` | READY/PARTIAL/UNSUPPORTED/ERROR 状态、一次打开一次正文请求、A/B 乱序丢弃、离页不发回调、错误后重试、规范 webUrl 不被响应 url 污染 |
| `entry/src/test/DailyStoryReaderPreferences.test.ets` | 开关默认原生阅读、未知值回退原生、显式 `legacy` 生效、文案区分 |
| `entry/src/test/DeepLinkResolver.test.ets` | 日报 URL 精确识别与拒绝（http/伪造后缀/userinfo/端口/多段路径/非法 ID/超长 ID） |
| `entry/src/test/ReaderDocument.test.ets` 等既有用例 | 共享 Reader 改动回归（普通回答/文章解析行为未变） |

结果：`pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`
→ API 26 编译通过，**Hypium 1114/1114** 全量通过。

## 5. 设备验收

构建：`pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall`（Debug 包 + 签名 + Hypium）。

### 5.1 设备与环境（如实记录）

| 设备 | 类型 | API | 分辨率 | `hdc` |
| --- | --- | --- | --- | --- |
| `MatePad Pro 11` | 平板模拟器 | 26（HarmonyOS 7.0.0） | 2560×1600 横屏 | `127.0.0.1:5555` |
| `ZhihuPlus_API23` | 手机模拟器 | 23（HarmonyOS 6.1.0，最低兼容线） | 1080×2400 竖屏 | `127.0.0.1:5557` |

**更正**：上一版本文写作「API 23 模拟器 127.0.0.1:5555」有误——`5555` 实际是 API 26 平板模拟器，
API 23 手机模拟器在 `5557`。下表按设备分别标注；两机均完成安装、冷启动与日报全流程。

### 5.2 逐场景结果

| 场景 | API 23 手机 | API 26 平板 |
| --- | --- | --- |
| 深链 `-U https://daily.zhihu.com/story/{id}` | 通过：`daily_story_detail_page`、头图/标题/栏目/正文/进度条齐备 | 通过（同上） |
| 正文顺序（9793572） | 通过：标题 → 5 组「Q：…/@作者：回答」→ 正文图 → 分隔线 → 圈子引导 → 推荐卡片 | 通过（同上） |
| 正文图 `pica.zhimg.com` | 通过：正常加载 | 通过 |
| 图片预览 | 通过：`daily_story_image_preview_overlay`，顶栏 `HdsTitleBar` 隐藏 | 通过 |
| 关闭预览回原位 | 通过：关闭前后同一图文块边界一致 | 通过 |
| 推荐卡片 | 通过：`content_link_card_daily-block-14` + 封面 | 通过 |
| 正文尾部（改版前） | 通过：「在浏览器中查看日报」按钮可见 | 通过；改版后结果见 §5.5 |
| 行内链接 | 通过：「Q：如何看待…」→ 原生回答页（非浏览器） | 通过 |
| 列表入口（旧路径，开关关闭） | 通过：→ 原生回答页（旧路径不变） | 通过 |
| 列表入口（开关开启） | 通过：→ `daily_story_detail_page` | 通过 |
| 返回 | 通过：回到日报列表（`top_level_daily_content`） | 通过 |
| 会话内阅读锚点 | 通过：第 3 组问答 → 回答页 → 返回，同一条目仍在 y=1318（边界一致） | 通过（同一方法） |
| 失败态 | 通过：`daily_story_error_status` + 重试 + 浏览器入口 | 通过 |
| 标题栏 | 通过：顶栏「知乎日报」，预览时隐藏 | 通过 |
| 深色模式 | 通过：页面底 `#FF000000`、栏目/分享按钮 `#FF191A1D`，与 `dark/element/color.json` 一致 | 未单独复测 |
| 大字号 | 通过：字号 85% → 200% 时首个正文块起点由 y=1648 变为 y=2328，正文随字号重排 | 未单独复测 |
| 大字号下不截断 | 通过（200%）：标题、栏目胶囊、分享按钮、页脚按钮均完整显示；分享按钮右边界 1200 < 屏宽 1260，未被挤出 | 未单独复测 |
| 旋转 / 宽屏 | 通过（平板上旋转）：横屏 2560×1600 → 竖屏 1600×2560，标题列由 `[470,2090]` 收窄为 `[45,1555]`，图文与图注完整、无重叠 | 同左 |
| 图片加载窗口内漂移 | 通过（0px）：打开后 2.2s 与 10s 两次布局比对，5 个正文块 Y 完全一致、图片块高度 104px 未变 | 未单独复测 |
| 加载中返回 | 通过：点开日报 300ms 内返回 → 干净回到日报列表，无幽灵页面、无错误弹窗 | 未单独复测 |
| A→B 快速切换 | 通过：点 A → 350ms 返回 → 立刻点 B，最终停在 B 的日报页（「瞎扯 · 如何正确地吐槽」），未被 A 的迟到响应覆盖 | 未单独复测 |
| 进后台再返回 | 通过：日报页按 Home → 重新唤起，仍停在同一日报页与同一标题，无重载闪回、无幽灵导航 | 未单独复测 |

### 5.3 解析性能（非设备指标）

Node（桌面 CPU）对 5 个真实样本各解析 20 次并取中位/p95，用于判断解析是否线性可接受：

| story | body 字节 | 块数 | 中位 | p95 |
| --- | --- | --- | --- | --- |
| 9793572 | 4379 | 15 | 0.85 ms | 2.42 ms |
| 9793594 | 3446 | 13 | 0.61 ms | 1.73 ms |
| 9793605 | 9111 | 63 | 1.27 ms | 4.09 ms |
| 9793581 | 7176 | 37 | 0.49 ms | 0.86 ms |
| 9793588 | 16763 | 107 | 1.53 ms | 3.68 ms |

**这是桌面 Node 数据，不是设备端指标**：ArkTS/设备端解析耗时、首个正文可交互时间未测量，
不能据此宣称设备性能达标。实现上解析是同步单遍有界扫描，块数与耗时随 body 线性增长。

### 5.4 仍未验证（不写作通过）

- **真机**：两台都是模拟器，`ArkWeb`/材质/图片解码在两机上的表现不覆盖真机差异。
- **沉浸光感材质在 API 23 的降级外观**：日报页顶栏走 `getImmersiveTitleBarStyle`，未逐项比对低版本兜底样式。
- **图片占位比例 → 真实比例**的过渡漂移：本次 2.2s 时图片已加载完，未捕捉到占位切换；
  `ReaderImageBlock` 用 4:3 占位，切换瞬间下方块仍可能跳动，需慢网/大图条件复测。
- **大字体下按钮截断**：已在 200% 下核对标题/栏目/分享/页脚按钮均完整（见 §5.2）；错误页两个按钮未逐一复测。
- **分屏 / 折叠展开态**：未测。
- **进后台再返回**：已手工复测通过（§5.2）。
- **PARTIAL 真实样本**：5 个真实样本均为 COMPLETE，PARTIAL 提示只在合成输入下验证。
- **可访问性专项**：未用屏幕朗读核验链接/图片朗读顺序（代码已为图片、分享按钮、链接提供可朗读名称）。
- **存图 / 实体词与圈子链接打开浏览器**：本轮未逐项手工复测（代码路径与回答/文章页共用同一实现）。


### 5.5 页尾改版与默认开启（只复测 API 26，2026-10-29）

本轮按用户要求把页尾改成单一「查看知乎讨论」按钮、去掉「在浏览器中查看日报」，并把原生渲染设为默认；
验收只做 **API 26 平板模拟器（`127.0.0.1:5555`）**，API 23 手机不再重复跑：

| 检查项 | 结果 |
| --- | --- |
| 默认链路（清应用数据后冷启动） | 通过：`bm clean -n com.github.zhuoyi233.zhplus -d` 后直接深链 `9793572` 进入 `daily_story_detail_page`，说明走的是默认值而不是残留偏好 |
| 开关默认态 | 通过：`daily_story_native_toggle` 的 dump 属性 `checked: true`（清数据后未手工切换） |
| 列表入口 | 通过：日报列表点 `channel_daily_9793605` → 原生日报页；旧「直跳回答」路径只在关闭开关后出现 |
| 页尾按钮 | 通过：页尾只有 `daily_story_discussion`（文本「查看知乎讨论」）；`daily_story_open_browser` / `daily_story_open_origin` 两个旧按钮不再渲染 |
| 胶囊形态 | 通过：按内容自适应宽度的居中胶囊（bounds `[1068,1218][1493,1322]`，约 212×52vp，圆角 23vp ≈ 半高），图标与文字用 `onThemeColor`，不再是整宽色块 |
| 正文不再留孤立链接 | 通过：9793581 正文最后一段是「禁区里的动物没有证明辐射无害…」，分隔线后直接是按钮；`div.view-more` 的「查看知乎讨论」不再作为正文段落出现 |
| 按钮跳转（view-more 样本） | 通过：9793581、9793605 → 原生问题页，标题与日报问题一致（如「核辐射危害巨大，为何切尔诺贝利禁区内的动物仍能生存繁衍？」） |
| 按钮跳转（回退样本） | 通过：9793572 的 `originUrl` 是 `/question/None/answer/None`，目标由正文第一个问答链接归一为问题页；点胶囊进入「如何看待公众号讣告标题写『痛别！巨星陨落』…」问题页，路由与标题都对上 |
| 从问题页返回 | 通过：回到同一日报页，胶囊 bounds 不变（`[1068,1218][1493,1322]`，中心 y=1270） |
| 代码回归 | 通过：`-SkipDependencyInstall -SkipBuild` 与完整 Debug 构建均 **Hypium 1114/1114**、API 26 编译通过 |

未覆盖：按钮在 200% 大字号与深色模式下的外观、PARTIAL 时才出现的「在浏览器中查看完整日报」
（无真实 PARTIAL 样本）、错误/不支持态的浏览器兜底（仍保留，本轮未复测外观）。

## 6. 明确排除的范围（首版）

不按 `type` 分流、不做「Q + blockquote」重组为回答卡片、不做上一期/下一期手势、
不做多源自动容灾、不做离线全文下载、不新增日报过滤器、不做日报跨进程阅读历史、
持久书签、收藏、点赞、评论与朗读；不拿 storyId 当 answerId 调用任何接口。
