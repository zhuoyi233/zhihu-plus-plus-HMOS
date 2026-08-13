# P2 用户主页与想法详情纵向切片验证

## 范围

本批对齐 Android Lite 的用户资料头和想法详情，只实现只读浏览：

- 用户主页展示头像、名称、签名、机构标识、回答数、文章数、关注数、粉丝数和当前关注关系文本。
- 想法详情展示作者、赞数、评论数、话题和 `content_html` 正文；正文进入现有原生
  `NativeContentDocument`，继续复用图片预览、公式渲染和节点级公式降级。
- 想法成功解析后直接复用生产 `OpenedContentStore` 写入 `pin:{id}`。写入失败只显示非敏感提示，
  不遮挡已加载正文。

本批不包含用户回答/文章/动态等分页 tab，不包含关注、屏蔽、点赞、投票、评论、分享、发布、
WebView 或任何端侧 AI 能力。

## Android Lite 合同

用户资料沿用 Android Lite 的 endpoint 和 include：

```text
GET https://api.zhihu.com/people/{urlToken-or-id}
include=allow_message,is_followed,is_following,is_org,is_blocking,badge_v2,answer_count,
        follower_count,following_count,articles_count,question_count,pins_count
```

想法详情沿用：

```text
GET https://www.zhihu.com/api/v4/pins/{id}?include=topics
```

Android 两个页面都使用 `allowGuestAccess=false`。HarmonyOS 的两个 controller 同样在发起网络前读取注入的
`LoginSessionGateway`：只有 `SessionStatus.AUTHENTICATED` 才访问 repository；游客态直接发布结构化
`requiresLogin=true`，页面提供“去登录”动作。响应提交前会再次确认会话仍为已登录，注销与响应竞态不会把
受保护页面重新发布为 READY。登录后的返回目的地需要由共享导航执行重建，确保页面重新读取
全局 `SessionRepository` 的新状态。

## 安全与正确性边界

- People 标识仅接受 1–200 位 ASCII 字母、数字、下划线和连字符，拒绝 `/`、`?`、`#`、`%`、userinfo、
  控制字符和超长输入；Pin 只接受 1–30 位不带前导零的正十进制 ID。
- endpoint 的 scheme、host、path 和 include 由代码固定；底层客户端继续使用 0 redirect、1 MiB 响应上限、
  连接和读取超时，并拒绝 userinfo、显式端口与相似恶意域名。
- Android 的 People endpoint 位于 `api.zhihu.com`。按照统一 HTTP 安全边界，该请求即使已登录也不携带
  Cookie、`d_c0`、ZSE、Referer 或 `x-requested-with`；登录状态只作为本地产品门禁。Pin 位于精确
  `www.zhihu.com`，请求携会话并使用 ZSE 签名。
- decoder 不采用响应中的 URL，而是从已验证的标识生成 canonical URL；People 响应必须让请求标识与
  `id` 或 `url_token` 之一一致，Pin 响应 ID 必须与请求一致。长数字 Pin ID 仍以调用方的已验证字符串为权威，
  避免 JavaScript `Number` 精度丢失。
- 根结构、作者、话题、布尔字段与非负统计均运行时校验；非知乎图片主机的头像被丢弃。上游 `message`、
  响应 URL、原始响应体、Cookie 和签名材料不会进入 UI 文案或日志。
- repository 和 controller 各自维护取消代次。离页、重试和目的地切换会取消 HTTP handle，旧结果不能回写；
  `snapshot()` 深拷贝 People、Pin 作者和话题数据。
- HTTP 认证失败只有状态缺失或为 401 时提供登录动作；普通 403 固定提示可能需要完成风控，并保留重试动作。

## 自动化覆盖

新增两组共 13 个 Hypium 用例：

- `PeoplePinDetailRepository.test.ets` 6 个：固定 endpoint/include 与注入边界、People 禁止 Cookie/ZSE、
  Pin 会话/ZSE、0 redirect、资料/作者/话题/统计与 canonical URL、响应标识错配与非法统计、恶意头像和敏感
  上游错误不泄露、取消永久 pending transport。
- `PeoplePinDetailState.test.ets` 7 个：两类游客态在网络前门禁、People 加载与防御性副本、离页取消和旧结果
  门禁、注销与响应竞态、Pin 作者/话题深拷贝、401 与 403 CTA 分流、真实 `contentHtml` 进入原生 Reader 公式路线。

## 集成状态

共享 barrel、两组测试、PIN/PEOPLE 强类型导航、登录成功重建白名单、P1Shell 页面分支和组合根依赖均已接入。People 生产请求保持 `useSession=false`；Pin 使用独立 client 并复用应用级数据库上的 `OpenedContentStore`。Pin 已读记录可在历史页展示、删除并重新导航。

## 验证状态

当前静态集成已完成，但本轮尚未取得新的构建、Hypium、模拟器或设备结果。工具可用后应依次执行 `arkts_check`、`build_project` 和 `start_app`，
再在 DevEco API 24 虚拟机验证游客 Login CTA、登录成功返回重建、真实用户资料、真实长 ID 想法、图片、公式、
403 风控文案、重试、弱网、离页取消和 `pin:{id}` 打开记录。
