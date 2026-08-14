# P3-4 收藏夹验证

> 实现日期：2026-08-15；工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 24

## 本批范围

本批实现 P3-4「收藏夹」纵向切片，覆盖收藏夹浏览、创建/删除、内容浏览与内容收藏闭环，不包含评论、
点赞/感谢/关注、AIGC 标记或任何端侧 AI 能力。功能与状态链路如下：

1. `CollectionPage`：当前用户或指定用户（urlToken）的收藏夹列表，分页 + 去重 + 登录门禁；
2. `CollectionContentPage`：单个收藏夹的标题/统计与内容列表，分页 + 去重 + 跳转回答/文章/问题/想法详情；
3. 创建/删除收藏夹：详情页与收藏弹窗内可新建（标题、描述、公开开关），列表页可删除，均带乐观更新与失败回滚；
4. 内容详情页（回答/文章）新增「收藏」入口，`CollectionDialogComponent` 列出用户收藏夹与收藏状态，
   切换即加入/移出收藏夹；
5. 入口：设置页「我的收藏夹」、用户主页「收藏夹」，均走 `P1DestinationName.COLLECTIONS`（列表）与
   `P1DestinationName.COLLECTION`（内容）。

## Android Lite 接口证据

参考 `Android-master` 的 `CollectionsViewModel.kt`、`CollectionContentViewModel.kt` 与
`ArticleViewModel.kt` 后，HarmonyOS 使用以下请求（统一 `useSession=true`、`signWithZse=true`）：

| 操作 | endpoint |
| --- | --- |
| 收藏夹列表 | `GET /api/v4/people/{urlToken}/collections?limit=20&include=...` |
| 收藏夹详情 | `GET /api/v4/collections/{id}`（响应取 `collection` 字段） |
| 收藏夹内容 | `GET /api/v4/collections/{id}/items?limit=20&include=...` |
| 内容所属收藏夹 | `GET /api/v4/collections/contents/{contentType}/{contentId}?limit=50`（带 `is_favorited`） |
| 新建收藏夹 | `POST /api/v4/collections`（JSON `{title, description, is_public}`） |
| 删除收藏夹 | `DELETE /api/v4/collections/{id}` |
| 加入收藏夹 | `PUT /api/v4/collections/contents/{contentType}/{contentId}`（表单 `add_collections={id}`） |
| 移出收藏夹 | `PUT /api/v4/collections/contents/{contentType}/{contentId}`（表单 `remove_collections={id}`） |

`contentType` 只接受 `answer` 与 `article`，与上游 `ArticleViewModel` 的
`ArticleType.Answer/Article` 一一对应；收藏夹内容项支持回答/文章/问题/想法四类跳转，其余类型（如
`zvideo`）在解码阶段跳过，不进入列表。

加入/移出收藏夹端点对齐上游 `ArticleViewModel.toggleFavorite` 的
`collections/contents/$contentType/${article.id}` 路径、**PUT 方法**与
`add_collections`/`remove_collections` 表单语义；`ZhihuHttpClient` 增加可选 `contentType` 字段以发送
`application/x-www-form-urlencoded`，默认仍为 `application/json`。

## 安全与正确性边界

- 收藏夹 ID、内容 ID 在拼入 URL 前必须匹配 `^[1-9][0-9]{0,29}$`；用户标识复用 `people` 标识校验
  （`^[A-Za-z0-9_-]{1,200}$`）。斜杠、查询串、符号、前导零、空白和超长输入在网络前拒绝，错误信息不回显攻击输入。
- 分页游标必须精确匹配 `people/{urlToken}/collections?` 或 `collections/{id}/items?` 前缀，
  拒绝跨来源游标、控制字符、片段和超长 URL；已请求游标与已投递条目做去重，游标回环被截断为终止态。
- 所有请求都只发给精确 `www.zhihu.com`；Cookie、`d_c0` 和 ZSE 不发给 `api.zhihu.com` 或相似域名。
- decoder 校验根结构、上游错误、ID、标题、统计和时间字段；上游 `message`、原始响应体、Cookie 和 URL
  不进入 UI 错误文案或日志。
- 仅 HTTP 认证失败且状态缺失或为 401 时才发布 `requiresLogin=true`，展示「去登录」；普通 403 固定提示
  风控，不误报登录失效。
- 创建/删除收藏夹与收藏切换均为乐观更新：先改本地状态，失败时回滚并展示结构化错误；操作期间 `busy`
  门禁阻止并发写操作。
- 登录门禁由 `SessionRepository` 状态直接判定：未认证时 `CollectionPage`/
  `CollectionContentPage` 不发出任何网络请求，直接进入登录提示态。

## 自动化覆盖

新增四组、共 28 个 Hypium 用例，并由共享测试入口纳入总数：

- `CollectionRepository.test.ets` 9 个：URL 构造与非法输入；游标前缀校验；列表会话/ZSE/去重；详情
  `collection` 包装；内容项解码与不支持类型跳过；内容收藏夹 `is_favorited`；创建 JSON 体；删除签名；
  加入/移出表单体与 Content-Type；取消。
- `CollectionState.test.ets` 8 个：未登录门禁；首页加载与去重；分页合并；失败/重试；创建后重载；
  空标题拒绝；删除乐观更新与失败回滚；合并去重。
- `CollectionContentState.test.ets` 6 个：未登录门禁；详情+内容加载去重；分页；详情失败/重试；空态；合并去重。
- `CollectionFavoriteState.test.ets` 8 个：加载内容收藏夹；未登录门禁；加入/移出乐观切换；加入/移出失败回滚；
  创建后重载；空标题拒绝。

共享接线需要完成后运行：

```powershell
powershell -Command "& '.\scripts\verify-harmony.ps1' -SkipDependencyInstall -SkipBuild"
```

## 共享接线与设备验证

共享接线已完成以下合同：

1. 从 `data/Index.ets` 导出 `CollectionModels`、`CollectionDecoder`、`CollectionRepository` 与
   `DefaultCollectionRepository`；
2. `core` 新增 `P1DestinationName.COLLECTIONS`（内容目的地，`id` 为用户标识），`COLLECTION` 目的地
   增加十进制 ID 校验；`shouldReloadAfterAuthentication` 覆盖两者；
3. `Index.ets` 组合根创建独立 `ZhihuHttpClient(session)` + `DefaultCollectionRepository`，
   注入回答/文章详情页、收藏夹列表页与收藏夹内容页；
4. 共享 Hypium `List.test.ets` 注册四个新增测试函数；本切片合计增加 28 个用例。

### 设备验收清单（API 24 虚拟机 + 登录态）

- [x] 设置页「我的收藏夹」进入列表，未登录显示「去登录」；
- [ ] 收藏夹列表分页加载、新建/删除即时生效，删除失败回滚；
- [x] 打开收藏夹看到标题、统计与内容列表，分页无重复，点击跳转详情；
- [ ] 回答/文章详情「收藏」弹窗列出收藏夹与收藏状态，切换即时生效，失败回滚；
- [ ] 用户主页「收藏夹」入口显示该用户收藏夹；
- [ ] 断网/403 场景显示可重试错误，不泄露请求体或 Cookie。

> 说明：收藏/取消收藏端点（`collections/contents/{contentType}/{contentId}`）与上游
> `ArticleViewModel.toggleFavorite` 一致使用 **PUT** + `add_collections`/`remove_collections` 表单语义。
> 真实登录态探测确认：PUT 返回 `{"favlists_count":0,"success":true}` 有执行确认，而 POST/DELETE 虽返回
> 200 但响应为空、无实际效果，故必须使用 PUT。

### 设备实测记录（2026-08-15，ZhihuPlus_API26 模拟器 127.0.0.1:5555）

已安装 `entry-default-signed.hap`（bundle `com.github.zhuoyi233.zhplus`，API 26 编译 / 24 兼容）并实测：

1. **登录门禁**：未登录点设置页「我的收藏夹」→ 跳转登录页（游客/手动 Cookie/二维码三入口齐全），
   与代码中 `openMyCollections` 的 `AUTHENTICATED` 判定一致；
2. **Cookie 登录**：手动 Cookie 登录（使用用户 `ZHIHU_COOKIE`）成功，自动返回设置页；
3. **收藏夹列表**：登录后点「我的收藏夹」→ 拉到真实收藏夹：
   - 「我的收藏」（私密，869 篇内容）、「业余无线电」（公开，2 篇）、「学无止境」（私密，9 篇）；
   - 每项卡片含标题、公开/私密、篇数与关注数、「打开」「删除」按钮；右上角「新建收藏夹」；
4. **收藏夹内容**：打开「业余无线电」→ 标题、统计「2 条收藏」、内容列表正确：
   - 文章《[原创]DMR入门_1.ID申请》（作者 Jesse BD7LLY，含完整 HTML 正文与图片 URL）；
   - 回答《为何日本的地方广播电台都有发行QSL卡？》（作者 temu，含摘要与赞同/评论统计）；
5. **编译修复**：HAP 全量编译暴露收藏夹两个页面 4 类类型错误（`List({ space: Resource })` 不接受
   Resource、箭头函数返回 Promise 不能标注 `: void`），已修复为与项目其他页面一致的
   `List({ space: 10 })` 与 `() => this.controller?.xxx()` 写法，随后构建、签名、安装、启动全部成功。

未覆盖：新建/删除收藏夹写操作、收藏弹窗切换（依赖写接口，需登录态下继续实测）、用户主页入口、断网/403。
