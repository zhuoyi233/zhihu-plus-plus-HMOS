# P2 关注、热榜与日报 Feed 验证记录

## 范围

本切片对齐 Android Lite 的三个只读信息流，不包含端侧 AI、推荐重排、日报 WebView 或外链跳转：

- 关注：`GET https://www.zhihu.com/api/v3/moments?limit=10&desktop=true`，附加统一 Feed `include`；
- 热榜：`GET https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total?limit=50&mobile=true`；
- 日报：`GET https://daily.zhihu.com/api/4/stories/latest`，之后请求 `/before/{YYYYMMDD}`。

关注与热榜请求使用现有 Cookie 与 ZSE 签名路径。热榜的 Web API 需要会话中的 `d_c0` 生成 `x-zse-96`；Cookie 仍只会发送到精确 `www.zhihu.com`。日报保持匿名请求，不读取 Cookie，也不产生 ZSE 请求头。2026-08-14 在同一网络匿名验证：`news-at.zhihu.com/api/4/stories/latest` 返回 HTTP 403 `need_login`，`daily.zhihu.com/api/4/stories/latest` 返回 HTTP 200 JSON，因此把 `daily.zhihu.com` 提升为主域；仅当 NetworkKit 返回 `2300006`（Failed to resolve the host name）时，才把同一路径退回 `https://news-at.zhihu.com/api/4/stories`。取消、超时、HTTP 错误及其他网络错误不触发回退。

NetworkKit 错误码依据本机 API 24 SDK `@ohos.net.http.d.ts` 的 `HttpRequest.request` 契约。功能合同依据 `Android-master` 的 `FollowViewModel`、`HotListViewModel`、`ZhihuDailyClient`、`DailyViewModel` 及其测试。

## 安全与状态边界

- FOLLOW/HOT 的 `paging.next` 必须保持 HTTPS、精确 `www.zhihu.com` host 与当前 endpoint path；日报 cursor 只接受 8 位日期。
- URL 查询参数解码后重新编码，旧 `include` 被替换为单一常量，canonical key 不受参数顺序及百分号编码差异影响。
- Repository 在成功解码并完成可选屏蔽匹配前不提交 cursor 或去重集合，因此瞬时失败可以用同一 cursor 重试。
- Repository 与 Controller 均有 generation 隔离；离页会销毁当前 NetworkKit operation，迟到的网络或屏蔽匹配结果不能回写。
- 内容以 `kind:id` 去重，日报以 story ID 去重；响应缺失 next、next 自环或已请求 cursor 会安全终止分页。
- 过滤依赖只使用 `ContentBlockingMatcher`。每个首屏或分页批次只调用一次 `createSession()`，再用不可变 session 同步匹配该批内容；输入固定为标题、摘要、作者 ID 和规范化话题 ID，缺失话题时传空数组，不用名称猜 ID。
- 关注与热榜的本地缺失登录态或 HTTP 401 显示“去登录”；HTTP 403 统一提示稍后重试或完成风控。
- 问题、回答和文章仅在 1 到 30 位十进制 ID 通过边界校验后生成强类型目的地。
- 超过 JavaScript 安全整数范围的数字 ID 使用严格 JSON 节点保存的原始十进制字面量，禁止先转浮点数再转字符串；统计数字仍要求安全整数。
- 日报 API4 列表本身不猜测知乎内容目的地；卡片先进入原生日报详情桥接，再由已经验证的正文来源映射决定是否跳转到问题、回答或文章。

## UI 与可访问性

- 三个频道共用一个以 `ChannelFeedSource` 固定数据源的页面，但每个页面实例拥有独立 Repository/Controller 生命周期。
- 首屏加载、刷新、空页、首屏错误、分页错误、分页重试与登录 CTA 均有独立状态。
- `onReachEnd` 与“加载更多”按钮可以同时触发，但 Controller 在进入请求前同步设置 `loadingMore`，不会形成请求风暴。
- 所有文本不设置固定高度或强制单行，卡片随系统大字体增长；页面沿用 P1Shell 的安全区容器。
- 日报不加载远程图片，避免为了装饰图片扩大网络域名与图片缓存边界。

## 自动化用例

新增 18 个 Hypium 用例：

- `ChannelFeedRepository.test.ets`：10 个，覆盖精确 URL/canonical cursor、跨 endpoint 拒绝、关注/热榜签名、日报游客头隔离、Android 文案字段、话题 ID、可注入屏蔽、unsupported/malformed 分流、日报解码与自环、DNS-only fallback、取消/超时不 fallback、失败重试与跨页去重。
- `ChannelFeedState.test.ets`：8 个，覆盖首屏去重、分页串行与重试、过滤后空页续翻、401/缺失会话 CTA、首屏和分页 403、离页迟到隔离与恢复、强类型导航、跨类型稳定键。
- `ZhihuHttpClient.test.ets`：在既有可信 host 用例中补充两个日报匿名 host 及 session-capable 拒绝断言。

统一接线后使用 DevEco Code 工具按顺序运行：

```text
arkts_check --files <本批修改的 .ets 文件>
build_project
start_app
```

最终自动化环境：DevEco Studio 26.0.0 Beta2 的 API 26 编译工具链，工程 target/compatible 均保持 HarmonyOS API 24。四模块 Debug HAP 构建成功，Hypium `240/240`。

API 26 虚拟机真实验证：日报首屏成功加载并可进入日报详情桥接；热榜成功加载真实列表，包含完整 19 位问题 ID，点击卡片可进入原生问题详情并渲染正文。日报跨页分页尚未获得稳定设备证据，继续作为后续设备回归项。

## 集成状态

共享 barrel、Hypium 入口、关注/热榜/日报强类型目的地、三个页面实例与登录成功后的关注页重建均已接入。生产组合根为 Home、Channel 和 Search 注入同一个 `BlockingRuleMatcher`，每个请求批次创建一次不可变匹配 session。第三批静态注册计入 32 组、223 项，最终执行结果以 DevEco Code 新鲜报告为准。
