# P3-3 内容互动切片验证

## 范围

本切片对齐 Android Lite 的内容互动能力，覆盖：

- 回答/文章点赞、反对：详情页操作栏即时生效、可逆（再点取消/切换），失败回滚并显示固定文案。
- 回答感谢：感谢/取消感谢，计数与状态乐观更新，失败回滚。
- 关注/取消关注用户：用户主页关注按钮。
- 关注/取消关注问题：问题详情页关注按钮。
- 登录门禁：未登录点击互动操作不发起网络请求，显示登录提示并提供「去登录」动作。
- 互动状态一致性：详情/用户响应中的投票、感谢、关注关系解析进领域模型，进入页面即显示服务端状态；
  返回/刷新后重新加载保持一致。

不包含评论、收藏、想法点赞、发布、通知、屏蔽操作（分别属于其他 P3 切片）。

## 端点与请求合同

端点沿用 Android 上游（`ArticleViewModel.toggleVoteUp`、`QuestionFeedViewModel.followQuestion`、
`PeopleScreen.toggleFollow`），全部走 `ZhihuHttpClient` 的 `useSession + signWithZse` 写通道：

| 操作 | 方法 | URL | 请求体 | 解析字段 |
| --- | --- | --- | --- | --- |
| 回答投票 | POST | `https://www.zhihu.com/api/v4/answers/{id}/voters` | `{"type":"up"\|"down"\|"neutral"}` | `voteup_count` |
| 文章投票 | POST | `https://www.zhihu.com/api/v4/articles/{id}/voters` | `{"voting":1}`（赞同）/ `{"voting":0}`（反对/中性） | `voteup_count` |
| 回答感谢 | POST / DELETE | `https://www.zhihu.com/api/v4/answers/{id}/thank` | POST 携带 `{}` | `thanks_count`、`is_thanked` |
| 关注用户 | POST / DELETE | `https://www.zhihu.com/api/v4/members/{urlToken}/followers` | — | `follower_count` |
| 关注问题 | POST / DELETE | `https://www.zhihu.com/api/v4/questions/{id}/followers` | — | `follower_count` |

上游说明：

- 回答投票的 `type` 三态与上游 `VoteUpState(up/down/neutral)` 一致；文章投票 `voting` 只区分赞同（1）与非赞同（0），
  与上游 `ArticleViewModel` 的 `mapOf("voting" to if (up) 1 else 0)` 一致（上游未对文章实现真正「反对」区分，
  本文同样不区分，属上游行为对齐，非新增差异）。
- 感谢端点上游未实现，采用知乎 Web 的 `answers/{id}/thank` POST/DELETE 形态；文章页不提供感谢按钮
  （知乎 Web 文章页无感谢入口，且无可靠文章 thank 端点）。

## 状态机与安全边界

- `ContentVoteController`（回答/文章）与 `FollowController`（问题/用户，提交动作注入）均实现：
  点击立即乐观更新状态与计数 → 请求进行中 `pending` 门禁拒绝并发点击 → 成功后采用服务端返回的权威计数，
  服务端未返回时沿用乐观值 → 失败恢复点击前状态并显示固定文案「操作失败，请稍后重试」。
- 未登录（`SessionStatus` 非 `AUTHENTICATED`）不发送任何请求，直接发布 `requiresLogin` 与
  「互动操作需要登录，请先登录」；请求中 401 同样回滚并进入登录提示。403 不提供登录动作。
- 离页/取消：controller 维护 active 标志与 repository 取消代次，离页后迟到响应不能回写状态。
- ID/标识安全：内容 ID 复用 `normalizeContentId`（1–30 位无前导零正十进制），用户标识复用
  `normalizePeopleIdentifier`（1–200 位 ASCII 字母/数字/下划线/连字符），URL 由代码固定拼接，拒绝路径注入。
- 日志脱敏：repository 只解析响应中的计数/布尔字段，不记录 Cookie、令牌、原始响应体；
  错误文案固定，不携带上游 message、URL 或签名材料。
- 领域模型新增可选字段（`Question.isFollowing`、`Answer/Article.voteState/thanksCount/isThanked`），
  decoder 从 `reaction.relation.vote`/`reaction.relation.voting`/`relationship.vote` 与
  `thanks_count`/`is_thanked`/`relationship.is_following` 解析；缺失一律回落到中性/否/0，不拒绝详情加载。

## 自动化覆盖

新增三组共 19 个 Hypium 用例（`List.test.ets` 静态注册）：

- `VoteRepository.test.ets` 5 个：固定 endpoint/请求体与 ID 注入边界；回答投票 POST `type` 三态与
  会话/ZSE/0 redirect 断言与 `voteup_count` 解析；文章投票 `voting` 1/0；感谢 POST/DELETE 与计数/状态解析；
  非 JSON 或缺失/负值计数的容错。
- `FollowRepository.test.ets` 4 个：用户/问题关注 URL 与标识注入边界；关注/取关成员与取关问题的
  POST/DELETE 方法与 `follower_count` 解析；非 JSON/缺失计数的容错。
- `ContentInteractionState.test.ets` 10 个：初始状态应用；投票乐观更新与成功计数收敛；失败回滚与固定文案；
  未登录门禁不发请求；401 回滚+登录提示；感谢乐观与回滚；pending 并发门禁；离页迟到响应门禁；
  关注乐观与回滚；问题关注未登录门禁。

## 集成状态

- `data` 新增 `VoteRepository`/`DefaultVoteRepository`、`FollowRepository`/`DefaultFollowRepository`
  并接入 barrel；`ContentVoteState` 枚举与领域模型扩展字段在 `DomainModels`。
- `entry` 新增 `ContentInteractionState.ets`（两个 controller），详情页操作栏（赞同/反对/感谢/关注问题）
  与用户页关注按钮接入现有页面，`Index.ets` 组合根注入独立 `ZhihuHttpClient(session)` 实例。
- 登录成功返回后共享导航会按 `shouldReloadAfterAuthentication` 重建问题/回答/文章/用户页，互动状态随详情
  重新加载与服务端一致。

## 验证状态

- Hypium：`260/260` 通过（API 26 编译 / target-compatible API 24）。
- 设备验收待外部条件闭环后执行：真实登录态下点赞/反对/感谢/关注往返与计数一致、未登录 CTA 跳转登录、
  401 会话失效回滚、弱网失败回滚、离页取消；文章「反对」与上游一致按 `voting=0` 提交属已知边界。
