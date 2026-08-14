# P3-5 评论与回复验证

> 实现日期：2026-08-16；工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 24

## 本批范围

本批实现 P3-5「评论与回复」纵向切片（P3-5a 只读 + P3-5b 交互），覆盖回答/文章详情页的评论
浏览与交互闭环，不包含收藏、点赞/感谢/关注、AIGC 标记或任何端侧 AI 能力。功能链路如下：

1. 回答/文章详情页新增「评论」按钮，打开评论弹层（`CommentLayer`，常驻详情页组合树、
   以 visibility 切换显隐，关闭再打开不销毁内部状态）；
2. 根评论列表：热度（`order_by=score`）/最新（`order_by=ts`）排序切换、分页加载更多、
   空态/错误态/登录门禁；
3. 子评论树：根评论卡片内联展示服务端携带的可见子评论（可展开/收起），「查看全部 N 条回复」
   进入子评论列表模式（独立分页）；
4. 评论交互：发表评论、回复（弹层输入，草稿由详情页在弹层外持有，跨关闭保留）、
   删除自己的评论（乐观移除 + 失败回滚）、评论点赞/取消（乐观更新 + 失败回滚 + busy 门禁）；
5. 评论作者点击进入用户主页（导航去重由 `P1Shell.shouldPushP1Destination` 已有逻辑保证，
   弹层常驻使返回后弹层与滚动位置恢复）。

## Android 上游接口证据

参考 `shared/src/commonMain/.../viewmodel/comment/RootCommentViewModel.kt`、
`ChildCommentViewModel.kt`、`BaseCommentViewModel.kt` 与
`shared/.../shared/data/DataHolder.kt#Comment` 后，HarmonyOS 使用以下请求
（统一 `useSession=true`、`signWithZse=true`）：

| 操作 | endpoint |
| --- | --- |
| 顶评列表（最热） | `GET /api/v4/comment_v5/{type}s/{id}/root_comment?order_by=score` |
| 顶评列表（最新） | `GET /api/v4/comment_v5/{type}s/{id}/root_comment?order_by=ts` |
| 子评论列表 | `GET /api/v4/comment_v5/comment/{rootCommentId}/child_comment` |
| 发表评论/回复 | `POST /api/v4/comment_v5/{type}s/{id}/comment`（JSON `{content:"<p>…</p>", reply_comment_id?}`） |
| 删除评论 | `DELETE /api/v4/comments/{commentId}` |
| 评论点赞/取消 | `POST` / `DELETE /api/v4/comments/{commentId}/voters`（body `{"type":"up"}`） |

`{type}` 只接受 `answer` / `article` / `question` / `pin`（仓库层完整支持，详情页入口当前只接
回答与文章，与上游 `RootCommentViewModel.submitCommentUrl/rootCommentUrl` 的路径一致）。
排序参数对齐上游 `BaseCommentViewModel.CommentSortOrder`（`SCORE -> score`、`TIME -> ts`）；
子评论端点对齐上游 `ChildCommentViewModel.initialUrl` 的
`comment_v5/comment/{commentId}/child_comment` 路径。

发表/回复的提交端点与上游 `RootCommentViewModel.submitComment` 一致使用
`comment_v5/{type}s/{id}/comment` + JSON 体，正文先经 `escapeCommentHtml` 转义
（`& < > " '`）再包装为 `<p>`，防止 HTML 注入；回复时携带 `reply_comment_id`
（子评论模式缺省回复到 activeRoot，与上游 `ChildCommentViewModel` 一致）。

> 说明：评论点赞采用 `/voters` + `{"type":"up"}`（POST 点赞 / DELETE 取消），
> 与 P3-3 已实测的 `VoteRepository` 的 `/answers/{id}/voters` 模式一致；
> 上游 `BaseCommentViewModel.toggleLikeComment` 使用的 `/comments/{id}/like` 端点
> 未采用（属于旧版端点），voters 为当前 Web 端点语义。

## 安全与正确性边界

- 内容 ID 复用 `normalizeContentId`（`^[1-9][0-9]{0,29}$`），评论 ID 同样校验；
  斜杠、查询串、符号、前导零、空白和超长输入在网络前拒绝，错误信息不回显攻击输入。
- 分页游标必须精确匹配 `comment_v5/{type}s/{id}/root_comment?` 或
  `comment_v5/comment/{rootCommentId}/child_comment?` 前缀，拒绝跨来源游标、控制字符、
  片段和超长 URL；已请求游标与已投递评论 ID 做去重，游标回环被截断为终止态。
- 所有请求只发给精确 `www.zhihu.com`；Cookie、`d_c0` 与 ZSE 不发给
  `api.zhihu.com` 或相似域名（`ZhihuHttpClient.isSessionCapableZhihuRequestUrl` 已有保证）。
- decoder 校验根结构、上游 `error` 对象、评论 ID、内容、时间与计数；
  上游 `message`、原始响应体、Cookie 和 URL 不进入 UI 错误文案或日志。
- 仅 HTTP 认证失败且状态缺失或为 401 时才发布 `requiresLogin=true`，展示「去登录」；
  普通 403 固定提示风控，不误报登录失效。
- 发表/删除/点赞均为乐观更新或乐观移除：先改本地状态，失败时回滚并展示结构化错误；
  操作期间 `busy`/`likeBusy` 门禁阻止并发写操作（点赞为全局单飞门禁，与上游
  `isLikeLoading` 一致）。
- 登录门禁由 `SessionRepository` 状态直接判定：未认证时评论弹层不发出任何网络请求，
  直接进入登录提示态；发表/回复/删除/点赞同样在未认证时仅发布 `requiresLogin`。
- 评论草稿由详情页持有（`commentRootDraft`/`commentReplyDraft` @State），弹层关闭再打开
  保留；弹层常驻组合树（`visibility` 切换），评论列表滚动位置在关闭/返回后不重置
  （遵循 CLAUDE.md 返回栈上下文保存与上游「不要在 if 条件中使用」约定）。

## 自动化覆盖

新增两组、共 27 个 Hypium 用例，并由共享测试入口纳入总数：

- `CommentRepository.test.ets` 12 个：URL 构造与非法输入（类型/ID/空内容）；root/child
  游标前缀校验；会话/ZSE/去重加载；嵌套子评论与标签解码；上游错误与非法结构；
  发表 JSON 体与 HTML 转义；空内容不发请求；删除签名；点赞 POST/DELETE 请求体；
  重复游标终止分页；取消与 transport 销毁。
- `CommentState.test.ets` 15 个：未登录门禁；加载去重；分页合并；失败/重试；排序切换重载；
  子评论模式打开/关闭保留根列表；发表前插与回复目标清除；空内容拒绝；根/子回复目标；
  发表失败不改列表；删除乐观移除与回滚；点赞乐观更新与回滚；游客交互门禁；合并去重。

共享接线需要完成后运行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
```

## 共享接线与设备验证

共享接线已完成以下合同：

1. 从 `data/Index.ets` 导出 `CommentModels`、`CommentDecoder`、`CommentRepository` 与
   `DefaultCommentRepository`；
2. `Index.ets` 组合根创建独立 `ZhihuHttpClient(session)` + `DefaultCommentRepository`，
   注入回答/文章详情页（`AnswerDetailPage`/`ArticleDetailPage`）；
3. 详情页（`ContentDetailPages.ets`）新增「评论」入口与常驻 `CommentLayer`；
4. 共享 Hypium `List.test.ets` 注册两个新增测试函数；本切片合计增加 27 个用例。

> 说明：评论 UI 采用弹层形态（`CommentLayer`），不占用 `P1DestinationName.COMMENT`
> 导航分支；`CommentDestination`（`{name, contentId, commentId?}`）在 core 已定义且
> `decodeP1Destination` 已支持，供后续独立评论页/深链使用，本切片未修改
> `P1Shell.ets` 的导航分支。

### 设备验收清单（API 24 虚拟机 + 登录态）

- [ ] 回答/文章详情页「评论」按钮打开评论弹层，未登录显示「去登录」；
- [ ] 根评论列表按最热/最新排序切换、分页无重复，作者名可进用户主页并返回后弹层仍在原位置；
- [ ] 展开/收起内联子评论，「查看全部 N 条回复」进入子评论列表并可返回；
- [ ] 发表评论/回复成功前插并清空草稿，关闭弹层再打开草稿仍在；
- [ ] 删除自己的评论即时消失，失败回滚；
- [ ] 评论点赞/取消即时生效，失败回滚；
- [ ] 断网/403 场景显示可重试错误，不泄露请求体或 Cookie。

> 说明：以上写接口（发表/回复/删除/点赞）与真实登录态依赖设备实测。
> 本轮已实测编译 + Hypium 自动化：`verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`
> 通过，**354/354 用例全绿**（基线 327 + 本切片新增 27）。
> 环境说明：worktree 的根 `oh_modules` 原为指向主 checkout 的 junction，导致测试运行时
> `@ohos/hypium` 模块解析为工作区外路径而崩溃；已改为在 worktree 内 `ohpm install --all`
> 生成本地 `oh_modules`（含内部 junction）后恢复正常。
