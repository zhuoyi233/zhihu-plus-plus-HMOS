# P2 问题、回答与文章详情验证

> 实现日期：2026-08-11；工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 24

## 本批范围

本批实现 P2 的问题、回答和文章只读详情纵向切片，不包含评论互动、关注/赞同写操作、内容发布、WebView 或任何端侧 AI 能力。详情数据、状态和渲染链路如下：

1. `DefaultContentRepository` 对外只接受 1 至 30 位、首位非零的十进制内容 ID；
2. repository 固定构造 `https://www.zhihu.com/api/v4/{questions|answers|articles}/{id}`，并附上 Android Lite 同款 `include`；
3. 统一 `ZhihuHttpClient` 从全局 `SessionRepository` 读取已认证 Cookie，并只对精确 `www.zhihu.com` 添加 Cookie 与 ZSE；
4. `ContentDetailDecoder` 校验根结构、上游错误、内容 ID、作者、统计和时间字段，同时生成固定的知乎公开页 URL；
5. `ContentDetailController` 串行管理加载、重试、取消、离页代次、结构化认证状态和本地打开记录；
6. `QuestionDetailPage`、`AnswerDetailPage`、`ArticleDetailPage` 共享真正具有详情语义的页面内核和原生正文组件；
7. `contentHtml`/`detailHtml` 只进入 `parseZhihuHtml`，转换为 ArkUI 文本、图片和公式节点，不执行 HTML，也不创建 WebView。

## Android Lite 接口证据

只读核对 `Android-master` 分支的
`shared/src/commonMain/kotlin/com/github/zly2006/zhihu/data/ContentDetailCache.kt` 后，HarmonyOS 保持以下请求：

| 类型 | endpoint | include 要点 |
| --- | --- | --- |
| 问题 | `/api/v4/questions/{id}` | `answer_count`、`comment_count`、`follower_count`、`detail`、`author`、`topics` |
| 回答 | `/api/v4/answers/{id}` | `content`、`excerpt`、`voteup_count`、`comment_count`、`question.topics`、`author.badge_v2`、目录设置 |
| 文章 | `/api/v4/articles/{id}` | `content`、`excerpt`、`voteup_count`、`comment_count`、`topics`、`author.badge_v2` |

Android Lite 的 `ZhihuApiEnvironment.fetchJson()` 通过 `fetchZhihuAuthenticatedJson()` 和
`signZhihuFetchRequest(cookies)` 请求这些 endpoint。HarmonyOS 因而同样设置 `useSession=true` 和
`signWithZse=true`，没有把详情请求降级为携带不完整身份的匿名请求。

## 安全与正确性边界

- ID 在拼入 URL 前必须匹配 `^[1-9][0-9]{0,29}$`。斜杠、查询串、百分号、点、前导零、符号、空白和超长输入均在网络前拒绝，错误信息不回显攻击输入。
- endpoint 的 scheme、host、path 集合和 `include` 均由代码固定；底层 HTTP 客户端拒绝 userinfo、显式端口、恶意 suffix 和非 HTTPS，并设置 `maxRedirects=0`、1 MiB 响应上限及连接/读取超时。
- Cookie、`d_c0` 和 ZSE 只能发送给精确 `www.zhihu.com`；`api.zhihu.com` 或任意相似域名不能获得会话请求头。
- decoder 不采用响应中的 `url` 字段，而是用已验证 ID 生成 canonical 公开 URL，避免上游或夹具 URL 被误用于后续导航。
- JavaScript 无法精确表示大于 `Number.MAX_SAFE_INTEGER` 的数字 ID。详情 endpoint 的调用方 ID 是权威值：安全整数响应会与请求严格比对；长数值响应不会覆盖已验证的请求字符串，从而避免把回答 ID 静默舍入。
- 根结构、作者、非负统计和时间字段均做运行时类型检查；上游 `message`、原始响应体、Cookie 和 URL 不进入 UI 错误文案或日志。
- 只有 HTTP 认证失败且状态缺失或为 401 时才发布结构化 `requiresLogin=true`。三类详情页只显示强类型
  “去登录”动作并进入 `P1DestinationName.LOGIN`；普通 403 固定提示请求被拒、可能需要完成知乎风控，
  保持“重新加载”而不误报登录失效。其他网络、服务或解析错误同样不显示登录 CTA。
- 登录认证成功会发出一次不含凭据的完成事件。`P1Shell` 先移除 Login 目的地，再只对问题、回答、
  文章三类已通过运行时解码的返回目的地执行一次 pop/push 重建；因此不依赖 Navigation 是否缓存
  被覆盖组件，返回后会使用同一个全局 `SessionRepository` 中的新会话自动重新加载当前内容 ID。
- 新加载会先取消旧 HTTP handle，并递增 controller/repository 代次。离页、重试或目的地切换后的旧响应不能覆盖新内容；取消不等待 NetworkKit transport 自行 settle。
- 成功解析后直接调用生产 `OpenedContentStore.upsert()`，使用 `question:{id}`、`answer:{id}`、`article:{id}` 作为稳定键。数据库失败不遮挡正文，但会留下非敏感的诊断状态。
- 状态快照按字段复制内容和作者对象，页面或测试修改返回值不会污染 controller 内部状态。

## 原生 Reader 接线

`NativeContentDocument` 复用现有生产 Reader 路线：

- 普通段落、标题、列表和分割线均渲染为 ArkUI 节点；完整标题不设置 `maxLines` 或省略号；
- 图片继续使用 `ReaderImageBlock` 的加载状态、失败重试和全屏预览；
- 块级和行内公式继续使用 `loadFormulaPixelMap()`，其下载策略只允许受信任公式 URL、禁止重定向并校验 SVG 类型、大小和图像尺寸；
- 每个公式节点有自己的 active/generation 门禁。离页或节点回收会释放 `PixelMap`，过期异步解码结果也立即释放；
- 单个公式下载、解码或显示失败时，仅该节点回退为 TeX 文本，不会令整篇正文失败；不可信公式地址在 HTML 解析阶段直接变成可读文本；
- 详情页离开时清理公式字节缓存，不持有已经离开的正文资源。

## 自动化覆盖

新增两组、共 15 个 Hypium 用例，并由共享测试入口纳入总数：

- `ContentDetailRepository.test.ets` 6 个：精确 URL 与 ID 注入边界；三类详情会话/ZSE/禁止重定向；作者、统计和 canonical URL；长数字 ID；错配 ID/非法统计；上游敏感错误不泄露。
- `ContentDetailState.test.ets` 9 个：三类语义字段；加载到就绪与防御性副本；目的地切换旧结果门禁；离页取消；通用安全错误与重试动作；401/无状态认证错误与登录动作；普通 403 的风控/重试分流；三类打开记录稳定键；真实 `contentHtml` 进入原生 Reader 并保留公式节点降级。

共享接线需要完成后运行：

```powershell
./scripts/verify-harmony.ps1 -ExpectedTestCount <共享入口最新总数> -SkipDependencyInstall
```

## 共享接线与设备验证

共享接线已完成以下合同：

1. 从 `data/Index.ets` 导出 `ContentDetailDecoder` 和 `DefaultContentRepository`；
2. 在共享 Hypium `List.test.ets` 注册两个新增测试函数；详情切片合计增加 15 个用例；
3. 各详情目的地创建独立 `ZhihuHttpClient` 和 `DefaultContentRepository`，共同只读全局
   `SessionRepository` 的 Cookie provider，避免相邻页面取消彼此请求；
4. 三类详情页分别持有短生命周期 `OpenedContentStore`，并共享由 `UIAbilityContext` 获取的应用级 `AppDatabase`；
5. 在 `P1Shell` 的 Question/Answer/Article 目的地分别渲染三个详情入口并传入已解码 ID 与强类型
   `navigate` 回调，使认证错误可以进入 Login 目的地；repository 仍保留最终 ID 边界校验；
6. 完成 API 24 定向构建和 Hypium 后，在 DevEco 虚拟机用真实已登录 Cookie 验证问题、长 ID 回答、文章、图片预览、公式成功/单节点失败、重试、弱网、离页取消和打开记录。

设备首轮证据发现游客态详情认证失败时只有“重新加载”，重复操作无法恢复。该 P1 已通过结构化
`requiresLogin` 和三类详情的“去登录”动作修复；普通 403 保留风控提示与重试，不误报会话失效。
登录完成判定只接受 `VERIFYING_COOKIE`/`QR_VERIFYING_ACCOUNT` 到 `AUTHENTICATED` 的用户操作迁移；
打开已有登录态页面不会自动返回。导航策略回归同时确认三类详情会重建，Login 等非详情目的地不会重建。
修复后的真实 Cookie 登录、自动返回和详情重载仍需安装最终包复测留证。

本批没有新增端侧 AI、模型、推理依赖或 WebView。
