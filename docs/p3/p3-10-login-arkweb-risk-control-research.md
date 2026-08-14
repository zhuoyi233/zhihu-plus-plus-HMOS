# 上游登录实现研究 + ArkWeb 非人类验证可行性

> 研究日期：2026-08-15
> 依据：Android 上游 `shared/.../login/QrLogin.kt`、`app/.../LoginActivity.kt`、
> `app/.../WebviewActivity.kt`；HarmonyOS `@ohos.web.webview` / `web.d.ts` API
> 状态：研究完成（未实现）

## 一、上游登录实现（Android Zhihu++）

> 已拉取最新上游（`zly2006/zhihu-plus-plus@0023163d`，2026-08-15）核对：
> 登录入口 `LoginActivity.kt` 提供**三种模式**（`LoginModeScreen` 切换，
> `LOGIN_MODE_PHONE = 2` 默认 / `LOGIN_MODE_QR = 1` / `LOGIN_MODE_WEB = 0`）：
> **手机号登录（独立协议）、扫码登录、网页登录**。

| 模式 | 实现 | 说明 |
| --- | --- | --- |
| **手机号登录**（默认） | `PhoneLoginPane` + `ZhihuPhoneLoginClient`（原生协议） | 见 1.2 |
| **扫码登录** | 二维码轮询（`SharedQrLoginPane`） | 见 1.3 |
| **网页登录** | WebView 加载 `https://www.zhihu.com/signin` | 见 1.4 |

### 1.2 手机号登录（最新上游新增，独立协议）

`PhoneLoginPane.kt`（UI）+ `ZhihuPhoneLoginClient.kt`（协议，`api.zhihu.com`）：

1. **设备信息**：`ZhihuPhoneLoginDeviceInfo`（时区偏移、安装时间、通知/蓝牙开关、
   CPU/内存/存储、机型等 24 项）→ `formParameters()`。
2. **ensureGuestToken**（初始化访客凭证）：
   - 若缺 `d_c0`：`POST https://www.zhihu.com/udid` 获取网页设备 cookie；
   - `POST https://api.zhihu.com/api/account/prod/init/udid_guest`：body 为
     `ZhihuMessageBodyEncryptor.encrypt(form)`（**自定义分组加密**：swapPairs +
     XOR mask + IV + 多轮置换表），headers 带 `x-app-id`/`x-sign-version`/`x-req-ts`/
     `x-req-signature`（HMAC-SHA1：`sha1(CLOUD_APP_SECRET, CLOUD_APP_ID + "2" + form + ts)`）。
   - 返回 `{udid, guest:{access_token, cookie}}` → 设置 `authorization` 与 cookies。
3. **requestDigits**（发送短信验证码）：
   - `GET /captcha` 查是否需图形验证码；需要 → 返回 `CaptchaRequired(imgBase64)`；
   - 否则 `POST /api/account/prod/auth/digits`（加密 form：`username`/`client_id`）；
     错误码 `120001/120002` → 验证码无效；`120005` → 重新查 captcha 后重试。
4. **图形验证码**：`PUT /captcha` 获取图片（base64）；`POST /captcha` 验证
   `{input_text}`。
5. **signIn**：`POST /api/account/prod/sign_in`（加密 form：`client_id`/`digits`/
   `grant_type=digits`/`signature`/`source`/`timestamp`/`username`），signature =
   `hmacSha1Hex(MOBILE_CLIENT_SECRET, "digits8d5227e0aaaa4797a763ac64e0c3b8com.zhihu.android{ts}")`；
   返回 `{access_token, refresh_token, expires_in, cookie}` → 合并 cookies。
6. **headers**：Android 知乎 UA（`com.zhihu.android/Futureve/11.4.0 ...`）、
   `Authorization: oauth 8d5227e0aaaa4797a763ac64e0c3b8`、`x-udid`、`x-api-version=3.0.93`、
   `x-app-*` 系列、`x-zse-93=101_1_1.0`。

> 常量：`MOBILE_CLIENT_ID=8d5227e0aaaa4797a763ac64e0c3b8`、
> `MOBILE_CLIENT_SECRET=ecbefbf6b17e47ecb9035107866380`、`CLOUD_APP_ID=1355`、
> `CLOUD_APP_SECRET=dd49a835-56e7-4a0f-95b5-efd51ea5397f`。

**HMAC-SHA1** 为 expect/actual（Android 平台实现）；ArkTS 可用
`@ohos.security.cryptoFramework` 的 HMAC 等价实现。

### 1.3 扫码登录

二维码登录由 `shared/account/QrLogin.kt` 的 `SharedQrLoginPane` 驱动，流程：

1. **prefetchQrLoginContext**：预热登录上下文——
   - `GET https://www.zhihu.com/signin`（带桌面 headers）
   - `POST https://www.zhihu.com/udid`（`{}`，获取设备标识）
   - `GET https://www.zhihu.com/api/v3/oauth/captcha/v2?type=captcha_sign_in`（验证码探测）
2. **requestQrCode**：`POST https://www.zhihu.com/api/v3/account/api/login/qrcode`（`{}`）
   → 返回 `{link, token, expires_at}`，生成二维码位图展示。
3. **pollQrCodeLogin**：轮询 `GET .../qrcode/{token}/scan_info`，每 500ms：
   - `status == 1` → 提示「请在知乎 App 上确认登录」（`onScanned`）
   - 403 或 `error.code == 40352` / `needLogin` → **风控**（`onRiskControl`，
     携带 `error.message` 与 `error.redirect`）
   - `userId/accessToken/success/loggedIn/loginStatus in CONFIRMED/...` →
     **登录成功**（`onLoginSuccess(cookies)`）
   - `status == 2` / `EXPIRED` → 二维码过期
4. 登录成功：`finalizeLoginFromCookies` → `AccountData.verifyLogin` 校验 →
   持久化 cookies。

关键 headers（`createZhihuLoginHeaders`）：桌面 UA（Chrome 145）、`sec-ch-ua` 三件套、
`x-requested-with: fetch`、`Origin`、`x-xsrftoken`（来自 `_xsrf` cookie）、轮询时带
`x-zse-93`。

### 1.4 网页登录（备用）

`configureWebLogin`（LoginActivity.kt:150）——WebView 加载 `https://www.zhihu.com/signin`，
知乎登录页内含手机号+验证码、手机号+密码、邮箱等所有方式，作为手机号/扫码的备用：

1. `javaScriptEnabled = true`，`setAcceptThirdPartyCookies(webView, true)`
2. **清空 WebView cookie**（`removeAllCookies`，避免残留态）→ `loadUrl(ZHIHU_SIGNIN_URL)`
3. `shouldOverrideUrlLoading`：到达 `https://www.zhihu.com/` 时切换 UA 为
   `AccountData.ANDROID_USER_AGENT`；拦截 `zhihu://` scheme
4. **`onPageFinished` 且 url == 首页**：`CookieManager.getCookie(HOME_URL)`
   → `parseCookieAssignments` → `finalizeLoginFromCookies`（校验+持久化）
5. 登录成功标志 = 页面跳回知乎首页（登录后知乎自动跳首页）

### 1.5 风控处理（核心：WebView 完成非人类验证）

`SharedQrLoginPane` 检测到风控（403/40352）后，切换到 `riskControlContent`
（平台注入的 Composable）。Android 实现（`LoginActivity.kt:338`）：

```
riskControlContent = { url, cookies, onCookiesChanged ->
    WebviewComp(onLoad = { webView ->
        activity.configureRiskControlWebView(webView, url, cookies, onCookiesChanged)
    })
}
```

`configureRiskControlWebView`（LoginActivity.kt:184）：
1. `javaScriptEnabled = true`，UA 设为 `ZHIHU_DESKTOP_USER_AGENT`（桌面 Chrome 145）
2. **注入现有 cookies**：`CookieManager.setCookie("https://www.zhihu.com/",
   "name=value; Domain=.zhihu.com; Path=/")`，`setAcceptThirdPartyCookies(webView, true)`
3. 加载风控 URL（`error.redirect` 或 `https://www.zhihu.com/account/risk_control/`）
4. **`onPageFinished` 时读回 WebView cookies**：
   `readWebViewCookies(url)` → `onCookiesChanged` → 更新会话 cookies
5. 页面内完成滑块/拼图验证后，用户点「完成验证后继续扫码」（`qr_risk_control_continue`）
   → `readRiskControlCookies` 再读一次 → 重新 `refreshKey += 1` 继续轮询扫码

独立 `WebviewActivity.kt`（全屏 WebView）用途：
- 从搜索结果/链接打开知乎网页（内嵌浏览）
- `shouldOverrideUrlLoading` 拦截 `link.zhihu.com` 跳转、`zhihu://` scheme、
  `www.zhihu.com/done` 完成回调
- 同样注入 cookies + 桌面 UA

### 1.3 上游方案总结

| 环节 | 做法 |
| --- | --- |
| 登录主路径 | 二维码轮询（HTTP，无浏览器） |
| 风控拦截 | **系统 WebView 加载风控页**，注入会话 cookie，页面内完成非人类验证 |
| Cookie 回传 | WebView `onPageFinished`/验证后读回 cookie jar，合并进会话 |
| UA 伪装 | 桌面 Chrome 145 UA + sec-ch-ua 三件套 |
| 第三方面 | WebView 接受第三方 cookie |

## 二、HarmonyOS ArkWeb 实现可行性

### 2.1 能力核对（API 26 SDK 实测存在）

| 需要能力 | ArkWeb API | 可用 |
| --- | --- | --- |
| WebView 组件 | `Web` 组件（`web.d.ts`） | ✅ |
| 加载 URL | `WebviewController.loadUrl(url, headers?)` | ✅ |
| Cookie 读取 | `webview.WebCookieManager.getCookie(url)` | ✅ |
| Cookie 写入 | `webview.WebCookieManager.setCookie(url, value)` | ✅ |
| 执行 JS | `WebviewController.runJavaScript(script): Promise<string>` | ✅ |
| UA 设置 | `webview.WebviewController.setUserAgentForHosts(ua, hosts)` | ✅ |
| 页面加载完成 | `Web().onPageEnd(callback)` | ✅ |
| 页面开始 | `Web().onPageBegin(callback)` | ✅ |
| 拦截导航 | `Web().onLoadIntercept(event)` | ✅ |
| 控制台回调 | `Web().onConsole` | ✅ |

### 2.2 实现方案（对齐上游）

**ArkWeb 风控验证页组件** `RiskControlWebPage`（新增）：

```
@Component
struct RiskControlWebPage {
  url: string;                       // error.redirect 或 ZHIHU_QR_RISK_CONTROL_URL
  sessionCookies: Array<SessionCookie>;  // 注入的会话 cookie
  onCookiesChanged: (cookies: Array<SessionCookie>) => void;
  controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear() {
    // 注入会话 cookie（对齐上游 CookieManager.setCookie）
    webview.WebCookieManager.setCookie('https://www.zhihu.com/',
      toCookieHeader(this.sessionCookies) + '; Domain=.zhihu.com; Path=/');
    this.controller.setUserAgentForHosts(ZHIHU_DESKTOP_USER_AGENT, ['www.zhihu.com']);
    this.controller.loadUrl(this.url);
  }

  build() {
    Web({ src: this.url, controller: this.controller })
      .javaScriptAccess(true)
      .onPageEnd(() => {
        // 页面加载完成读回 cookie（对齐上游 onPageFinished → readWebViewCookies）
        const raw = webview.WebCookieManager.getCookie('https://www.zhihu.com/');
        this.onCookiesChanged(parseCookieJarEntries(raw));
      })
  }
}
```

**登录页集成**（LoginPage.ets）：
- `ZhihuQrLoginClient` 已有 `RISK_CONTROL` 状态与 `riskControlUrl`（`ZHIHU_QR_RISK_CONTROL_URL`）
- 状态为 `RISK_CONTROL` 时，渲染 `RiskControlWebPage`（替换二维码区）
- 用户完成验证后点「完成验证后继续扫码」→ `onCookiesChanged` 更新会话 →
  controller 重新 `start()` 继续轮询

**App 内嵌 WebView 浏览**（可选，对齐 `WebviewActivity.kt`）：
- 新增通用 `WebPage`（ArkWeb 全屏），从搜索结果/详情打开知乎网页
- 拦截 `link.zhihu.com`、`zhihu://` scheme、`www.zhihu.com/done` 完成回调

### 2.3 风险与注意

1. **Cookie 格式**：ArkWeb `WebCookieManager.getCookie` 返回 `name=value; name2=value2`，
   需用现有 `parseCookieJarEntries`（NetworkKit 的 Netscape jar 解析）适配——
   上游 `readWebViewCookies` 走 Android CookieManager 返回同样格式。
2. **第三方 cookie**：ArkWeb 需确认默认接受第三方 cookie（对齐上游
   `setAcceptThirdPartyCookies`）；知乎风控页可能依赖。
3. **UA**：`setUserAgentForHosts` 只对指定 host 生效（对齐上游 webview UA 设置）；
   需同时保持 HTTP 客户端用同一 UA（`ZhihuHttpClient` 已有 `ZHIHU_USER_AGENT`，
   需与风控页 UA 一致为桌面 Chrome 145）。
4. **安全边界**：ArkWeb 只允许加载 `www.zhihu.com` / `zhuanlan.zhihu.com` 白名单域
   （对齐 `isTrustedZhihuRequestUrl`）；`runJavaScript` 仅用于读 cookie，不执行
   页面脚本；cookie 读取结果按现有会话校验后合并。
5. **模块依赖**：`@kit.ArkWeb` 需在 entry `module.json5` 或 oh-package 声明；
   模拟器 API 26 支持 ArkWeb（Web 组件自 API 9 起）。

## 三、结论（三种模式落地可行性）

| 模式 | 上游实现 | 鸿蒙落地 | 可行性 | 主要工作 |
| --- | --- | --- | --- | --- |
| **手机号登录** | `ZhihuPhoneLoginClient` 原生协议（`api.zhihu.com`） | 纯 ArkTS HTTP 即可，无需 WebView | ✅ **完全可落地** | 移植协议：自定义分组加密 `ZhihuMessageBodyEncryptor`（纯字节运算）、HMAC-SHA1（`cryptoFramework`）、访客初始化/短信/验证码/sign_in 四步、设备信息采集 |
| **扫码登录** | `SharedQrLoginPane` 二维码轮询 | 鸿蒙已有 `ZhihuQrLoginClient`（P2 已实现） | ✅ **已落地**（风控待接） | 已有：取码/轮询/过期/成功；待接：风控 → ArkWeb 验证页 |
| **网页登录** | WebView 加载 signin 页，`onPageFinished` 读 cookie | ArkWeb 组件 + `WebCookieManager` | ✅ **完全可落地** | 新增 `WebLoginPage`（ArkWeb 全屏 + cookie 读回 + 跳首页判定） |

**风控验证（三种模式共用）**：`RISK_CONTROL` 状态 → `RiskControlWebPage`（ArkWeb 加载
风控页，cookie 注入/回传）→ 「完成验证后继续」→ 重试原流程。

- **上游登录** = 手机号原生协议 + 二维码轮询 + WebView 网页登录三选一；
  风控时**系统 WebView 加载风控页 + cookie 注入回传**。
- **HarmonyOS 完全具备**三模式落地能力：
  - 手机号：ArkTS 可实现自定义加密 + HMAC（`cryptoFramework`）；
  - 扫码：`ZhihuQrLoginClient` 已实现；
  - 网页：ArkWeb（`WebCookieManager`/`onPageEnd`/UA）可复刻；
  - 风控：ArkWeb 验证页解决当前环境「40352 unhuman」无法完成非人类验证的问题。

## 四、待实施清单（如获批准）

1. `data` 移植 `ZhihuPhoneLoginClient` 协议（加密器/HMAC/设备信息/四步请求）
   + `PhoneLoginPage`（手机号/验证码/图形验证码/协议勾选）；
2. `entry` 新增 `RiskControlWebPage`（ArkWeb 风控验证页，cookie 注入/回传）；
3. `entry` 新增 `WebLoginPage`（ArkWeb 网页登录，对齐 `configureWebLogin`）；
4. `LoginPage.ets` 接入三模式切换（手机号/扫码/网页）+ `RISK_CONTROL` 状态 → 风控页；
5. `data` 新增 `parseWebCookieHeader`（`name=value;` → SessionCookie）；
6. Hypium 测试：加密器向量、HMAC、手机号状态机、cookie 头解析、风控状态机；
7. 设备实测：三模式登录 + 风控时 ArkWeb 完成滑块验证后成功。
