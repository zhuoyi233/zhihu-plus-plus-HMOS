# 鸿蒙端防风控能力与上游差距分析

> 诊断日期：2026-08-14
> 范围：HarmonyOS 端 `entry/core/data/reader` 相对 Android 上游（`shared`，Android-master 分支）在知乎防风控能力上的差距
> 上游参照：`shared/src/commonMain`、`shared/src/androidMain`
> 关联文档：`docs/p0/zse-validation.md`、`docs/p1/http-pipeline-validation.md`、`docs/p2/channel-feeds-request-failure-analysis.md`

## 1. 背景与结论

知乎 web 端接口由 `x-zse-96` 签名 + Cookie 反爬保护，登录态失效后由 token 刷新自愈。HarmonyOS 端已完成 web 端签名与二维码登录的迁移，但相对上游仍有**两块能力缺失**：

1. **会话 token 自愈**：上游在 401 时通过 `refresh_token` 自动换发 `z_c0`，鸿蒙端缺失，会话失效只能重新登录。
2. **移动端 App 请求伪装**：上游可用 `com.zhihu.android` UA 与 `x-app-za` 等头模拟知乎 App，鸿蒙端只有 web/桌面 UA。

这两块都不是「绕过风控」的主动对抗手段，而是「让请求符合知乎客户端契约 + 会话失效时自愈」的兼容能力。是否补全取决于后续是否要接入移动端端点（如 `api.zhihu.com/topstory/recommend`）以及是否需要减少用户重登频率。

## 2. 已实现的防风控机制（现状）

鸿蒙端已落地下列能力，与上游 web 路径对齐：

| 能力 | 鸿蒙端实现 | 说明 |
| --- | --- | --- |
| web `x-zse-96` 签名 | `data/.../network/ZhihuFetchSignature.ets` + `ZseSigner.ets` | `2.0_` + `encryptZseV4(md5(zse93 + path + d_c0 + body))`，纯 ArkTS，与上游字节级对齐 |
| 浏览器指纹头 | `data/.../network/ZhihuQrLoginClient.ets:136-193` | 桌面 UA + `sec-ch-ua*` + `x-requested-with` + `Referer`/`Origin` + `sec-fetch-*` |
| 二维码登录 prefetch | `ZhihuQrLoginClient.ets:529-550` | `/signin` → `/udid` → `/captcha` 顺序积累 Cookie 再建码 |
| 风控响应识别 | `ZhihuQrLoginClient.ets:595-612` | 403 + `error.code=40352` 或 `need_login` → `RISK_CONTROL` 状态 |
| 会话加密持久化 | `data/.../session/SessionCipher.ets` 等 | Cookie 密文落盘、密钥进 Asset Store |
| 严格域名白名单 | `ZhihuHttpClient.ets` | Cookie/签名只发 `www.zhihu.com` |
| 单活跃请求 + 取消 | `ZhihuHttpClient.ets:286-340` | 并发抛 BUSY，`Promise.race` 可取消 |
| 日志脱敏 | `core/.../logging/AppLogger.ets` + 约定 | 不输出 Cookie/token/响应体/请求头 |

## 3. 差距清单

| 能力 | 上游 Android | 鸿蒙端现状 | 影响 |
| --- | --- | --- | --- |
| web `x-zse-96` 签名 | ✅ | ✅ | 无 |
| 二维码登录 + prefetch + 40352 识别 | ✅ | ✅ | 无 |
| **401 token 自愈（refresh_token → z_c0）** | ✅ | ❌ | 登录态过期只能重登 |
| **移动端 App 伪装（x-app-za / x-api-version）** | ✅ | ❌ | 无法调用移动端端点 |
| 移动端 Home Feed 专用通道 | ✅ | ❌ | 首页只能用 web 端点 |

## 4. 差距一：会话 token 自愈缺失

### 4.1 上游实现

401 触发与刷新分两处：

**触发点**（`shared/.../shared/data/ZhihuApiClients.kt:50-70`）：

```kotlin
suspend fun executeZhihuAuthenticatedRequest(client, url, block): HttpResponse {
    val response = client.request(url) { block() }
    if (response.status != HttpStatusCode.Unauthorized) return response
    if (Clock.System.now().toEpochMilliseconds() - lastRefreshMillis < 10_000) return response  // 10s 节流
    val refreshToken = ZhihuCredentialRefresher.fetchRefreshToken(client)
    ZhihuCredentialRefresher.refreshZhihuToken(refreshToken, client)
    lastRefreshMillis = Clock.System.now().toEpochMilliseconds()
    return client.request(url) { block() }.raiseForStatus()  // 刷新后重试原请求
}
```

**刷新流程**（`shared/.../util/ZhihuCredentialRefresher.kt`）：

```text
POST /api/account/prod/token/refresh   → 拿 refresh_token
    （Content-Type: form-urlencoded，Origin/Referer/x-requested-with 头）
POST /api/v3/oauth/sign_in             → 换新 z_c0
    （HMAC-SHA1 签名 payload：client_id + grant_type + source + timestamp，
      再用 client_secret 做 key；body 经 encryptZseV4 加密；带 x-zse-83: 3_3.0）
```

关键点：`x-zse-83` 用的加密函数就是 `ZseSigner.encryptZseV4`（直接加密 formData，不走 md5），鸿蒙端已具备该原语。

### 4.2 鸿蒙端现状

`data/.../session/SessionRepository.ets` 的 `verifyRestoredSession` 只在启动恢复时校验一次 `/api/v4/me`；401 或 `z_c0` 缺失时走「清理本地会话 → `EXPIRED`」路径，让用户重新登录。没有 `refresh_token` 换发逻辑。

确认依据：`core/data/entry` 三个模块 grep 无 `refresh_token` / `oauth/sign_in` / `token/refresh` / `grant_type` / `hmacSha1` 实现（唯一 `access_token` 命中是 `ZhihuQrLoginClient.ets:274` 的二维码轮询响应字段，与刷新无关）。

### 4.3 补全方案

1. 在 `data` 模块新增纯 ArkTS 的 `ZhihuCredentialRefresher`：
   - 复刻 `fetchRefreshToken`（POST token/refresh）与 `refreshZhihuToken`（HMAC-SHA1 签名 + `encryptZseV4` 加密 body + `x-zse-83`）。
   - HMAC-SHA1 用 `@ohos.security.cryptoFramework` 的 MAC 能力，或按现有 `Md5.ets` 的风格做纯 ArkTS 实现。
2. 在请求层接入 401 自愈：
   - 参考上游 `executeZhihuAuthenticatedRequest`，401 时触发刷新（10s 节流），成功则更新 `z_c0` 并重试原请求，失败退回现有 `SessionRepository` 的失效清理路径。
   - 刷新只发生在精确 `www.zhihu.com` 域内，沿用 `isSessionCapableZhihuRequestUrl` 边界。
3. 安全边界：`refresh_token`、`access_token`、`z_c0`、HMAC 签名均不落日志、不进崩溃信息、不进导出文件。

## 5. 差距二：移动端 App 请求伪装缺失

### 5.1 上游实现

`shared/.../androidMain/.../data/AccountData.kt:52-60`：

```kotlin
internal val ANDROID_HEADERS = mapOf(
    "x-api-version" to "3.1.8",
    "x-app-version" to "10.61.0",
    "x-app-za" to "OS=Android&Release=12&Model=sdk_gphone64_arm64&VersionName=10.61.0" +
        "&VersionCode=26107&Product=com.zhihu.android&Width=1440&Height=2952" +
        "&Installer=%E7%81%B0%E5%BA%A6&DeviceType=AndroidPhone&Brand=google",
)
const val ANDROID_USER_AGENT = "com.zhihu.android/Futureve/10.61.0 Mozilla/5.0 (Linux; Android 12; ...) ..."
```

这套头通过 `mobileHomeFeedHttpClient()`（`shared/.../androidMain/.../AndroidPaginationEnvironment.android.kt:152-169`）挂在**独立的移动端客户端**上，默认 web 客户端不挂，避免污染 web 路径。

### 5.2 鸿蒙端现状

`data/.../network/ZhihuHttpClient.ets:7-9` 只有 web UA（`Mozilla/5.0 (X11; U; Linux x86_64; ...)`）与二维码桌面 UA（`Chrome/145`）。`ZhihuRequestHeaders` 无 `x-api-version` / `x-app-version` / `x-app-za` 字段，也没有移动端专用通道。

### 5.3 补全方案

1. 在 `ZhihuRequestHeaders` 增加可选字段 `x-api-version` / `x-app-version` / `x-app-za`，并在 `prepareZhihuHttpRequest` 支持按需附加。
2. 新增独立移动端请求通道（对齐上游 `mobileHomeFeedHttpClient` 的隔离思路），不改变默认 web 客户端行为。
3. 仅当需要调用移动端端点（如 `api.zhihu.com/topstory/recommend`）时启用。

### 5.4 风险与边界（遵循 AGENTS.md）

- `x-app-za` 是设备指纹，伪造 Android 值存在风控反噬风险：若与 IP、Cookie 来源等其它维度不一致，反而更容易被识别。接入前应评估是否真有移动端端点需求。
- 这是「为了让服务端返回完整数据的窄兼容手段」，应局限在特定移动端通道内，不扩散成 shared 通用数据能力，也不改变任何默认展示策略。
- 不把伪造的设备指纹写入通用会话层或 environment，避免污染 web 路径的请求指纹一致性。

## 6. 验证方法

1. **token 自愈**：用即将过期的 `z_c0` 发起一次需登录请求，确认 401 → 刷新 → 重试成功；再确认刷新失败时退回到「会话失效、需重登」且不删除用户本地 RDB 数据。
2. **移动端伪装**：若接入，先对 `api.zhihu.com/topstory/recommend` 做真实探测，确认「移动端 UA + x-app-za 三件套」能取回数据，且不触发验证码/风控页。
3. **回归**：补全后跑 `data`/`entry` 的会话与 HTTP 相关 Hypium 用例，并回到 P2 主链路验收，确认 web 路径签名行为未被污染。

## 7. 结论

鸿蒙端防风控能力当前处于「web 端完整、移动端缺失、会话自愈缺失」的状态。两块缺失能力是否补全，取决于产品是否需要移动端端点与更长的免重登周期；若补全，必须分别以「独立移动端通道」和「401 自愈 + 节流」的形式落地，遵循窄兼容与安全脱敏边界。
