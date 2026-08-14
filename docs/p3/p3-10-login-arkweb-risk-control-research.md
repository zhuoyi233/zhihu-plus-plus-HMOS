# 上游登录实现研究 + ArkWeb 非人类验证可行性

> 研究日期：2026-08-15
> 依据：Android 上游 `shared/.../login/QrLogin.kt`、`app/.../LoginActivity.kt`、
> `app/.../WebviewActivity.kt`；HarmonyOS `@ohos.web.webview` / `web.d.ts` API
> 状态：研究完成（未实现）

## 一、上游登录实现（Android Zhihu++）

### 1.1 登录方式

上游登录入口 `LoginActivity.kt` 提供三种模式（`LoginModeScreen`）：
**二维码登录（主）、手动 Cookie 登录、游客模式**。

二维码登录由 `shared/QrLogin.kt` 的 `SharedQrLoginPane` 驱动，流程：

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

### 1.2 风控处理（核心：WebView 完成非人类验证）

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

## 三、结论

- **上游登录** = 二维码轮询（HTTP）+ 风控时**系统 WebView 加载风控页 + cookie 注入回传**。
- **HarmonyOS ArkWeb 完全具备**实现同样方案的能力（WebCookieManager/runJavaScript/
  UA/onPageEnd），可直接按 2.2 方案落地，解决当前环境「QR 轮询 40352 unhuman 风控」
  无法完成的非人类验证问题。

## 四、待实施清单（如获批准）

1. `entry` 新增 `RiskControlWebPage`（ArkWeb 风控验证页，cookie 注入/回传）；
2. `LoginPage.ets` 接入 `RISK_CONTROL` 状态 → 渲染风控页 → 「完成验证后继续扫码」；
3. `data` 新增 `parseWebCookieHeader`（`name=value;` 格式 → SessionCookie，对齐
   `parseCookieJarEntries` 的 jar 格式分支）；
4. 可选：通用 `WebPage`（App 内嵌浏览，对齐 `WebviewActivity.kt`）；
5. Hypium 测试：cookie 头解析、白名单校验、状态机（RISK_CONTROL → 继续扫码）；
6. 设备实测：QR 风控时用 ArkWeb 完成滑块验证后扫码登录成功。
