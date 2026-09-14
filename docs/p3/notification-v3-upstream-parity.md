# 通知页对齐上游 message/v3 重做记录

> 实施日期：2026-09-14。目标：通知页做成与上游一致（`NotificationScreen.kt`/
> `NotificationTimelineScreen.kt`/`PrivateMessageScreen.kt`，Android-master @22f6313c）。

## 背景与决策

P3-6 初版按 web v2（`www.zhihu.com/api/v4/notifications/v2/...`）实现三分类卡片式通知页。
上游其后已整体迁移到移动端 `message/v3` 形态：消息中心 hub（四分类宫格 + 邀请回答行 +
会话列表）+ 分类时间线 + 私信会话页。本次按上游现状重做，替换 web v2 实现：

- `NotificationCategory`(web) / `NotificationItem` / `NotificationDecoder` /
  `DefaultNotificationRepository` 已删除；`NotificationModels.ets` 只保留
  `NotificationKind` / 偏好设置 / `shouldShowMobileNotification`（对齐上游
  `matchNotificationType` 与 `shouldShowNotification`）。
- 新增 `domain/MobileNotificationModels.ets` + `MobileNotificationDecoder.ets`
  （模型逐字段对齐上游 `Notification.kt` 的 `MobileNotification*` 系列）。

## 端点与协议（全部移动端协议，api.zhihu.com）

| 操作 | 端点 |
| --- | --- |
| 消息中心 | `GET /notifications/v3/message/v3?limit=20`（head 未读数 + column_head 邀请行 + data 会话） |
| 分类/邀请时间线 | `GET /notifications/v3/timeline/entry/{comment\|like\|favlist_me\|follow\|invite}?limit=20`（invite 另带 `invite_with_time_slice=1`） |
| 全部已读 | `POST /notifications/v3/timeline/entry/{entry}/actions/readall`（hub 四分类串行；时间线按 autoMarkAsRead 单入口） |
| 私信会话 | `GET /messages?limit=20&sender_id={peerId}`（新→旧）+ `GET /messages/user/{peerId}` |
| 发送私信 | `POST /messages`，表单 `receiver_id/content/content_type=0/source_type=message_list` 经 `encryptZhihuMessageBody` 加密，头 `X-Zse-93: 101_1_1.0` |

- 通道：新增 `network/ZhihuMobileClient.ets`（`ZhihuMobileHttpClient`）。请求头对齐上游
  `AccountData.ANDROID_HEADERS`：Android UA + `x-api-version: 3.1.8` +
  `x-app-version: 10.61.0` + `x-app-za` + 会话 Cookie；**无 web ZSE 签名**（上游
  `mobileHomeFeedHttpClient` 同样不带 x-zse-96）。仅允许精确 `api.zhihu.com`。
- 游标安全：message / timeline / 私信三类游标分别锚定各自 URL 前缀；私信游标还要求
  `sender_id` 参数等于当前会话 peerId；接受 http:// 并规范化为 https://（对齐上游 replace）。

## UI 形态（entry）

- `NotificationPage`：标题栏「消息」+ 右上角已读/设置（`NotificationTitleBar` 经
  stackBuilder 注入 HdsNavDestination，AppStorage 键 `notificationHub*` 通信，同搜索页
  模式）；四分类宫格（36vp 符号图标 + 99+ 角标）→ `NOTIFICATION_ENTRY`；邀请回答行
  （52 圆形 + 未读角标）→ invite 时间线；8vp 分隔条后会话列表（52 头像、标题/日期
  MM-dd、单行摘要、未读角标），点击经 `NotificationLinkResolver` 解析（inbox → 私信，
  timeline-entry → 分类页，其余交给 `resolveZhihuLink`），不可解析弹「暂不支持打开此消息」。
- `NotificationTimelinePage`：对齐 `NotificationItemView`（未读点 + 44 头像 + 标题/
  副标题/正文 3 行（EmojiText）+ 相对时间 + 来源框）与 `InvitationAnswerItem`
  （作者头 + 问题卡 + 写/看回答）。invite 项的问题卡整卡跳问题、按钮按 `hasAnswer`/
  `myAnswerUrl` 走查看或写回答。显示开关过滤与自动已读语义同上游。
- `PrivateMessagePage`：气泡列表（收件左对齐带头像、发件右对齐主色容器，`Text+Span`
  分段渲染 HTML：`<br>`→换行、`<a href>` 着色可点、实体反转义；`plugin.excerpt` 优先）+
  底部输入栏发送（加密表单）。列表按时间正序，新消息滚至底部。

### 私信分页方向（2026-09-14 修复）

`GET /messages` 首页按**新→旧**返回（含自己发出的消息），`paging.next` 游标
（`after_id=<id>`）取的是**更旧一页**。因此 load-more 必须把结果**前插到列表顶部**
（`PrivateMessageController`：块内倒序组装为旧→新后 `block.concat(existing)`），
追加到底部会让发出的消息夹在旧消息中间。配套两点：

- 页面初始定位到底部（`scrollToIndex(last)`）前用 `initialScrollSettled` 门控
  `onReachStart`，否则首屏渲染即触发前插，使初始滚动的目标下标漂移到中间；
- 前插后按「原首条 id 的新下标」滚动锚定，避免视口跳动。

## 关键坑：ZhihuMessageBodyEncryptor 协议表损坏

初版移植的 `ZM_PROTOCOL_DATA` 表**转写时丢了字符**（解码 5220 字节，上游 5296，
首个差异在第 3034 字符处丢 'h'），导致 `POST /messages` 一律 403
`10001 请求参数异常，请升级客户端后重试`（服务端无法解密）。已用上游
`ZhihuMessageBodyEncryptor.kt` 的 `PROTOCOL_DATA` 重建常量并校验 sha256 一致；
算法（表驱动 AES-128 + swapPairs/pre-transform/IV）经 Node 参考实现复核与上游
去协议化向量 `encrypt("hello") == 14RJeQ+vLOS4ihOY/LtYCg==` 完全一致。本地
Hypium 的 `util.Base64Helper` 为空桩，**向量断言无法在本地单测运行**，只能在真机/参考
实现上核对。发送私信端到端已在模拟器实测通过（回执入列 + 刷新后会话含新消息）。

## 测试与验证

- `entry/src/test/NotificationRepository.test.ets` 重写为移动端 v3：URL/游标校验、
  移动端头（UA 前缀 `com.zhihu.android/`、`x-api-version: 3.1.8`、无 x-zse-96）、
  message/timeline/私信解码、readall、加密发送请求形态。
- `entry/src/test/NotificationState.test.ets` 重写：hub 登录门禁/overview 计数/empty
  过滤/四分类 readall 乐观回滚；时间线显示过滤 + 自动已读；私信时间正序 + 发送回执。
- 新增 `PrivateMessageContent.test.ets`（HTML 分段解析、实体/链接安全、plugin.excerpt）。
- `verify-harmony.ps1` 全量通过（Hypium 580/580，API 26 编译 + HAP 签名）；
  模拟器 ZhihuPlus_API23 实测：消息中心/时间线/邀请回答/私信会话渲染与发送均正常。
