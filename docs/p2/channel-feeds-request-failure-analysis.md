# 热榜、日报 Feed 请求失败原因与修复方案

> 诊断日期：2026-08-14
> 范围：HarmonyOS 端 `entry/core/data/reader` 中热榜（HOT）与日报（DAILY）频道无法正常请求到内容的问题
> 关联文档：`docs/p2/channel-feeds-validation.md`
> 上游参照：`shared/src/commonMain`（Android-master 分支）

## 1. 问题现象

首页、关注、搜索、内容详情等带登录态与 ZSE 签名的模块可以正常返回内容，但热榜与日报频道出现「加载失败」「请求被拒绝，可能需要稍后重试或完成风控」或空列表，无法获取内容。

## 2. 根因分析

### 2.1 热榜：缺 `d_c0` 与 `x-zse-96` 签名，被知乎反爬拒绝

热榜请求端点与上游一致：

```text
GET https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total?limit=50&mobile=true
```

但两端请求头不同。

**HarmonyOS 端**（`data/src/main/ets/repository/DefaultChannelFeedRepository.ets`）：

```typescript
useSession: source === ChannelFeedSource.FOLLOWING,   // 热榜 → false
signWithZse: source === ChannelFeedSource.FOLLOWING  // 热榜 → false
```

只有「关注」才带 Cookie 与 ZSE 签名，热榜与日报被实现为「游客裸请求」，既不读取 Cookie，也不产生 ZSE 请求头。这一决策被明确记录在 `docs/p2/channel-feeds-validation.md:11`。

**Android 上游**（`shared/.../viewmodel/PaginationViewModel.kt` 与 `shared/.../shared/util/ZhihuFetchSignature.kt`）：

```kotlin
// BaseFeedViewModel.fetchFeeds → environment.fetchJson(url, include)
suspend fun fetchJson(url: String, include: String): JsonObject? =
    withAuthenticatedClient { client, cookies ->
        fetchZhihuAuthenticatedJson(client, url) {
            // ...
            signZhihuFetchRequest(cookies)   // 追加 x-zse-93 / x-zse-96 / x-requested-with
        }
    }

fun HttpRequestBuilder.signZhihuFetchRequest(cookies: Map<String, String>, body: String? = null) {
    val dc0 = cookies["d_c0"]?.takeIf { it.isNotBlank() } ?: return  // 无 d_c0 则跳过签名
    header("x-zse-93", zse93)
    header("x-zse-96", ZhihuFetchSignature.createZse96Header(zse93, requestUrl, dc0, body))
    header("x-requested-with", "fetch")
}
```

结论：Android 热榜虽然同样标了 `allowGuestAccess = true`，但只要会话里存在 `d_c0`（知乎下发的游客标识），请求就会带 Cookie 并做 ZSE 签名；HarmonyOS 热榜则是完全裸请求。

`www.zhihu.com/api/v3/feed/topstory/hot-lists/total` 是知乎 web 端接口，受 `x-zse-96` 反爬保护。裸请求会被拒绝，对应两条失败路径：

| 知乎实际返回 | HarmonyOS 端表现 | 出处 |
| --- | --- | --- |
| HTTP 403 | `HttpFailure(AUTHENTICATION, 403)` → 「请求被拒绝，可能需要稍后重试或完成风控」 | `entry/src/main/ets/pages/ChannelFeedState.ets:208-209` |
| HTTP 200 + `{"error":{...}}` | `decodeFeedPage` 抛 `UPSTREAM_ERROR` → 「热榜加载失败」 | `data/src/main/ets/domain/ZhihuDomainDecoder.ets:284-290` |

`decodeFeedPage` 里专门对 `error` 字段做防御性处理，本身就说明预期会收到这种带 `error` 的反爬响应。

反证：首页、关注、搜索、详情均以 `useSession: true, signWithZse: true` 请求，能正常返回；凡是「裸请求」的热榜就失败，两者差异恰好是签名。

### 2.2 日报：签名不是原因，疑点集中在 DNS 回退、接口状态与解析契约

日报两端一致——Android 也是裸 `get`，无签名无 Cookie（`shared/.../shared/data/ZhihuDailyClient.kt:40-50`，`DailyViewModel` 直接调用 `fetchLatestDailyStories()`）。因此日报失败与签名无关，可能原因有三：

1. **主域名 DNS 解析 + 错误码映射脆弱**：`news-at.zhihu.com` 在部分网络会 DNS 解析失败（这正是上游 issue #417 存在 workaround 的原因）。HarmonyOS 端只有在 Network Kit 返回**恰好 `2300006`** 时才回退到 `daily.zhihu.com`（`DefaultChannelFeedRepository.ets:27` 与 `executeDailyWithDnsFallback:223-240`）。若实际错误码不是 `2300006`，回退永不触发，日报直接失败。

2. **接口本身可能已变化**：`https://news-at.zhihu.com/api/4/stories/latest` 是知乎日报较老的公开接口。

3. **解析契约过严**：`decodeDailyFeedPage` 要求 `date` 严格为 8 位数字、`stories` 数组存在、每个 story 必须有数字 `id` 与 `type`（`data/src/main/ets/domain/ZhihuChannelFeedDecoder.ets:144-197`）。任一字段缺失或类型不符都会整页抛 `MISSING_FIELD`，而不是跳过单条。

## 3. 证据索引

| 代码位置 | 说明 |
| --- | --- |
| `data/src/main/ets/repository/DefaultChannelFeedRepository.ets:172-179` | 仅 FOLLOWING 带 `useSession`/`signWithZse`，HOT/DAILY 裸请求 |
| `data/src/main/ets/repository/DefaultChannelFeedRepository.ets:27` | `DAILY_HOST_RESOLUTION_ERROR_CODE = 2300006` |
| `data/src/main/ets/repository/DefaultChannelFeedRepository.ets:223-240` | 日报 DNS-only 回退逻辑 |
| `data/src/main/ets/network/ZhihuHttpClient.ets:117-122` | `useSession`/`signWithZse` 时 Cookie 为空直接抛 AUTHENTICATION |
| `data/src/main/ets/network/ZhihuHttpClient.ets:124-129` | 签名时无 `d_c0` 直接抛 AUTHENTICATION |
| `data/src/main/ets/domain/ZhihuDomainDecoder.ets:284-290` | 响应含 `error` 字段时抛 UPSTREAM_ERROR |
| `entry/src/main/ets/pages/ChannelFeedState.ets:199-215` | 403 / 401 / 其他错误的文案映射 |
| `data/src/main/ets/domain/ZhihuChannelFeedDecoder.ets:144-197` | 日报解码契约 |
| `shared/.../viewmodel/PaginationViewModel.kt:237-251` | 上游 `fetchJson` 统一做 ZSE 签名 |
| `shared/.../shared/util/ZhihuFetchSignature.kt:45-59` | 上游签名在无 `d_c0` 时跳过 |
| `shared/.../viewmodel/feed/BaseFeedViewModel.kt:111-117` | 上游热榜/关注/首页统一走 `fetchJson` |
| `shared/.../shared/data/ZhihuDailyClient.kt:40-50` | 上游日报裸 get 与 DNS 回退 |

## 4. 修复方案

### 4.1 热榜：让请求带 `d_c0` 与 ZSE 签名，与上游对齐

前提是会话层能持有游客 Cookie（`d_c0`）。知乎在访问 `www.zhihu.com` 时会通过 Set-Cookie 下发 `d_c0`，但当前 HarmonyOS 端 `SessionRepository` 维护的是登录态 Cookie，游客 Cookie 的获取与持久化路径不完整。

建议分两步：

1. **会话层扩展游客 Cookie 维护**：在访问知乎页面（登录页/扫码页/首页）时收集并持久化 `d_c0` 等游客 Cookie，使其在未登录状态下也可用。注意 Cookie 仍需加密落盘、脱敏日志，遵循 `data/src/main/ets/session` 既有的安全边界。

2. **热榜请求改为 `useSession: true, signWithZse: true`**：在 `DefaultChannelFeedRepository.loadPage` 中让热榜复用签名路径，使请求携带 `Cookie: d_c0=...` 与 `x-zse-93/96`。同时要处理「纯游客无 `d_c0`」的降级——上游 `signZhihuFetchRequest` 在无 `d_c0` 时跳过签名，HarmonyOS 端目前则会在 `prepareZhihuHttpRequest` 直接抛 AUTHENTICATION（`ZhihuHttpClient.ets:117-129`），需要为游客场景补齐等价行为。

落地前应先用 `HttpProbeClient`（`data/src/main/ets/network/HttpProbeClient.ets`）或真实抓包确认「带 `d_c0` + 签名」确实能取回热榜数据，再决定是否全量接入。

**边界（遵循 AGENTS.md）**：这是「为了让服务端返回完整数据的窄兼容手段」，应局限在该频道请求内，不扩散成 shared 通用数据能力，也不改变热榜的默认展示策略。

### 4.2 日报：先定位真实失败原因，再对症修复

按优先级排查：

1. **核对 Network Kit 真实错误码**：在设备上复现日报失败，确认是否为 DNS 解析失败、实际错误码是否等于 `2300006`。若不等，修正 `DAILY_HOST_RESOLUTION_ERROR_CODE` 或改为更宽但受控的 host 解析失败判定（保持「仅 DNS 失败才回退」的窄语义，不泛化成普通重试）。

2. **核实接口状态**：确认 `news-at.zhihu.com/api/4/stories/latest` 当前是否仍返回有效数据。若主域名已不可用，考虑把 `daily.zhihu.com` 提升为主域名，或切换到新的日报数据源。

3. **校准解析契约**：用真实响应核对 `decodeDailyFeedPage` 的字段假设（`date` 的 8 位格式、`stories` 数组、story 的 `id`/`type` 类型）。对可选或缺失字段做容错，避免整页因单条脏数据失败。

### 4.3 通用注意事项

- 热榜与日报失败可能不是同一根因，修复时应分别验证，不要用一个补丁覆盖两个问题。
- 任何请求头、签名或域名改动都要回到 `docs/p2/channel-feeds-validation.md` 的「安全与状态边界」重新核对：分页 `next` 仍须限制在精确 host 与 endpoint path；日报 cursor 仍只接受 8 位日期；日志继续脱敏，不输出 Cookie 与响应体。

## 5. 验证方法

1. **定向抓包/日志**：在 API 24 虚拟机或真机抓取热榜、日报请求，记录真实 HTTP 状态码、响应体与 Network Kit 错误码，区分「403 / error JSON / DNS 失败 / 结构不匹配」四种情况。
2. **对照上游**：在同一网络下用 Android 上游对相同端点发起请求，比对响应差异。
3. **契约测试**：把真实脱敏响应固化为 fixture，补充/修正 `decodeDailyFeedPage` 与热榜解码的用例。
4. **回归**：修复后重新跑 `entry/src/test/ChannelFeedRepository.test.ets`、`ChannelFeedState.test.ets`，并回到 P2 主链路验收（热榜、日报首屏与分页）。

## 6. 2026-08-14 实施结果

设备修复前复现结果：已登录的 `ZhihuPlus_API26` 虚拟机中，热榜和日报首屏均进入固定的 403/风控错误态。匿名同网络探测进一步区分了两个根因：

- `https://news-at.zhihu.com/api/4/stories/latest` 返回 HTTP 403、`application/json`，错误信封含 `need_login`；
- `https://daily.zhihu.com/api/4/stories/latest` 返回 HTTP 200、`application/json`，真实信封包含 8 位 `date`、4 条 `stories`，每条 story 的 `id` 为整数、`type` 为 0，且存在 `hint`、`url`、`images`；现有解码字段假设与该响应一致。

据此采用两项相互独立的修复：

1. 关注与热榜统一通过 `ZhihuHttpClient` 的已验证会话路径发送 Cookie 和 ZSE；热榜缺少有效会话或收到 401 时显示登录入口，403 仍保持风控提示。纯游客 `d_c0` 的自动采集没有扩散到通用会话层，本批选择明确登录门禁，避免裸请求和未验证游客凭据污染持久会话。
2. 日报把当前可用的 `daily.zhihu.com` 提升为主域，仍保持无 Cookie、无 ZSE；只有该主域发生 NetworkKit `2300006` DNS 解析失败时才退回 `news-at.zhihu.com`，其他网络、超时和 HTTP 错误不触发回退。

首次安装复测时，日报已经能在 `ZhihuPlus_API26` 中加载真实首屏，并能从日报卡片进入原生日报详情桥接页面。热榜在完成会话签名修复后仍显示固定失败，继续检查真实响应发现：2026 年热榜问题 ID 已出现 19 位十进制 JSON 数值，超过 JavaScript 安全整数范围；旧严格 JSON 解析器只保留 `number`，ID 边界为避免精度丢失会拒绝整页。

最终修复让严格 JSON 数值节点同时保存原始十进制字面量，所有内容 ID 在模型边界直接使用该字面量，不经过浮点数往返；统计数字仍走原有安全整数校验，指数和小数形式也不会被误当作 ID。相同规则同步覆盖首页、搜索、内容详情、用户内容和想法详情的数字 ID 边界。

API 26 虚拟机最终验证结果：热榜真实列表加载成功，卡片保留完整 19 位 ID，点击后成功进入原生问题详情并渲染正文；日报真实首屏加载成功并可进入日报详情桥接。日报跨页分页尚未在本轮形成稳定设备证据，不在本次结论中宣称通过。

自动化验证使用 Studio 26 / API 26 编译工具链，工程 target/compatible 继续为 API 24；四模块 Debug HAP 构建成功，Hypium `240/240` 通过。签名只用于本机安装，项目 `build-profile.json5` 已恢复为空 `signingConfigs`，仓库不保存本机证书、密码或签名路径。
