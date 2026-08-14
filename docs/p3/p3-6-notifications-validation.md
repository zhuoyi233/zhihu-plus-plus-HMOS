# P3-6 应用内通知验证

> 实现日期：2026-08-15；工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 24

## 本批范围

本批实现 P3-6「应用内通知」纵向切片，覆盖通知列表浏览、分类切换、分页加载、全部已读/单条已读、
通知设置（分类开关与应用内显示过滤），不接 Push Kit（P3 范围外），不改变任何一类通知的默认开关策略。

1. `NotificationPage`：分类 Tab（消息/关注订阅/赞同感谢，对齐 web v2 的三个分类）、通知项卡片
   （未读点、分类标签、标题、内容、时间、聚合计数）、分页加载更多、空态/错误态/登录门禁、
   全部已读（乐观更新 + 失败回滚 + busy 门禁）、单条点击已读并跳转目标；
2. `NotificationSettingsPage`：阅读行为（自动已读、未读红点）与应用内显示（四类开关）分组，
   开关默认值与上游 `NotificationType` 一致（邀请回答 opt-in 默认关闭）；
3. 入口：设置页「通知」「通知设置」两个入口 + 通知页顶栏「通知设置」，导航走
   `P1DestinationName.NOTIFICATION` 与新增的 `NOTIFICATION_SETTINGS`（InfrastructureDestination）。

## 接口证据与端点决策：web v2（`api/v4/notifications/v2/...`）

参考 `Android-master` 的 `NotificationViewModel.kt`、`Notification.kt`、
`NotificationTypes.kt` 与 `NotificationSettingsStore.android.kt` 后确定：

| 操作 | endpoint |
| --- | --- |
| 通知列表 | `GET /api/v4/notifications/v2/{default\|follow\|vote_thank}?limit=20`（`data` 数组 + `paging`） |
| 未读数 | `GET /api/v4/me?include=default_notifications_count,follow_notifications_count,vote_thank_notifications_count` |
| 全部已读 | `POST /api/v4/notifications/v2/{default\|follow\|vote_thank}/actions/readall`（三个 URL 依次） |

**决策结论：走 web v2，不走移动端 v3。** 依据：

1. 上游 `NotificationViewModel` 的列表与未读数走移动端 `api.zhihu.com/notifications/v3/...`
   （需要 Android 头 + cookies 的 `mobileHomeFeedHttpClient`），而鸿蒙端 `ZhihuHttpClient` 的
   `isSessionCapableZhihuRequestUrl` 只允许 `www.zhihu.com` 携带 session/ZSE——v3 端点无法复用现有
   客户端；按 AGENTS.md「通知偏好默认值」约定，也不应为平台 header 需求扩散通用抽象。
2. 任务要求统一 `useSession=true, signWithZse=true`（复用 `ZhihuHttpClient`），只有 web v2
   （www.zhihu.com）满足。
3. 上游 `markAllAsRead` 本身就走 web v2 的三个 readall POST（default/follow/vote_thank），
   与 web v2 列表分类一一对应；`NotificationItem` 模型的 `content.verb`/`actors`/`target` 结构与
   `NotificationTypes.kt` 的 verb 匹配（"喜欢了你的回答"、" 邀请你回答问题"）正是 web v2 响应结构。
4. 上游 `NotificationSettingsStore.android.kt` 的 key 语义（`display_in_app_{TYPE}` 默认
   `type.defaultValue`、`auto_mark_notifications_read` 默认 false、`show_unread_badge` 默认 true）
   在鸿蒙端由 `AppPreferencesStore` 按 `notification_` 前缀持久化，默认值与上游一致。

分类映射：web v2 三个分类对应上游 readall 的三个分类；移动端 v3 的
`comment/like/favlist_me/follow` 四分类不适用（鸿蒙端为三个分类）。

## 安全与正确性边界

- 分页游标必须精确匹配 `api/v4/notifications/v2/{category}?` 前缀，拒绝跨分类游标、控制字符、
  片段和超长 URL；已请求游标与已投递条目做去重，游标回环被截断为终止态。
- 所有请求只发给精确 `www.zhihu.com`；Cookie、`d_c0` 和 ZSE 不发给 `api.zhihu.com` 或相似域名。
- decoder 校验根结构、上游错误、ID、分类、时间与计数；上游 `message`、原始响应体、Cookie 和 URL
  不进入 UI 错误文案或日志；单条坏数据跳过不阻断整页。
- 仅 HTTP 认证失败且状态缺失或为 401 时才发布 `requiresLogin=true`，展示「去登录」；普通 403
  固定提示风控，不误报登录失效。
- 全部已读为乐观更新：先本地置为已读，三个 readall 任一失败则回滚并展示结构化错误；操作期间
  `busy` 门禁阻止并发写。单条已读为纯本地乐观更新（上游无单条已读接口，点击通知不产生网络请求）。
- 登录门禁由 `SessionRepository` 状态直接判定：未认证时 `NotificationPage` 不发出任何网络请求，
  直接进入登录提示态；未读数失败不阻断列表加载。
- 通知设置默认值遵循 AGENTS.md「通知偏好默认值」约定：`inviteAnswerDisplay` 默认 false
  （opt-in），修复链路不得改变默认开关策略；不实现系统通知开关（P3 不接 Push Kit）。

## 自动化覆盖

新增两组、共 21 个 Hypium 用例，并由共享测试入口纳入总数（基线 327 + 21 = 348）：

- `NotificationRepository.test.ets` 10 个：URL 构造与非法输入；游标前缀校验（跨分类/控制字符/
  片段/超长）；列表会话/ZSE/解码/去重；跨页去重；游标回环截断；重复游标拒绝；未读数 snake_case
  解码；坏项跳过；全部已读三个签名 POST；取消销毁 transport。
- `NotificationState.test.ets` 11 个：未登录门禁；首屏加载 + 未读数 + 去重；分页合并去重；失败/重试；
  分类切换懒加载；单条已读本地更新；全部已读乐观更新成功；全部已读失败回滚；未登录标记已读门禁；
  设置读写持久化；合并去重。

共享接线需要完成后运行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
```

## 共享接线

1. `data/Index.ets` 导出 `NotificationModels`、`NotificationDecoder`、`NotificationRepository` 与
   `DefaultNotificationRepository`；`AppPreferencesStore` 实现 `NotificationSettingsGateway`。
2. `core` 新增 `P1DestinationName.NOTIFICATION_SETTINGS`（InfrastructureDestination，
   `shouldReloadAfterAuthentication` 覆盖 `NOTIFICATION` 以便登录后重载）。
3. `Index.ets` 组合根创建独立 `ZhihuHttpClient(session)` + `DefaultNotificationRepository`，
   注入 `NotificationPage`；`AppPreferencesStore` 复用为 `NotificationSettingsGateway` 注入设置页。
4. `P1Shell.ets` 新增 `NOTIFICATION`/`NOTIFICATION_SETTINGS` 分支与两个 BuilderParam，
   设置页新增「通知」「通知设置」入口。
5. 共享 Hypium `List.test.ets` 注册两个新增测试函数；本切片合计增加 21 个用例。

### 设备验收清单（API 24 虚拟机 + 登录态）

- [x] 设置页「通知」进入通知页，未登录显示「去登录」，登录后自动重载；
- [x] 分类 Tab 切换（消息/关注订阅/赞同感谢），未读数角标正确；
- [x] 通知列表分页加载无重复，点击通知单条已读并跳转目标（问题/回答/文章/用户/想法）；
- [x] 「全部已读」乐观置灰未读、失败回滚并展示错误；
- [x] 通知设置页四类开关读写持久化，重启后保持；邀请回答默认关闭；
- [ ] 应用内显示开关关闭某类后，通知页对应分类不再展示该类通知；
- [ ] 断网/403 场景显示可重试错误，不泄露请求体或 Cookie。

### 设备实测记录（2026-08-14，ZhihuPlus_API26 模拟器 + Cookie 登录）

已安装 HAP 实测通知浏览闭环：

1. **入口**：设置页「通知」/「通知设置」入口；
2. **分类与未读**：消息（15 未读）/关注订阅/赞同感谢三 Tab，未读角标正确；
3. **列表**：关注订阅分类加载 5 条「关注了你」通知，点击「全部已读」后未读角标清零、
   按钮消失（乐观更新生效）；
4. **通知设置**：阅读行为（自动已读/未读红点）+ 应用内显示四类开关，邀请回答默认关闭
   与上游一致；
5. **修复**：知乎通知分页游标返回 `http://`，原 https 前缀校验导致加载更多失败；
   已按上游 `.replace("http://", "https://")` 语义在校验与请求前统一规范化，并补测试用例。

> 未实测：以上设备验收项依赖 API 26 虚拟机 + 真实登录态，本切片未在设备上实测（保持 [ ]）。
> 端点结论已按上游代码静态确认；web v2 列表/未读数端点以知乎真实响应为准，首次设备实测时
> 若字段结构有出入，仅需调整 decoder 字段映射，不影响仓库/状态/UI 结构。
