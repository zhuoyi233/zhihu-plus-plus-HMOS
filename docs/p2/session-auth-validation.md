# P2 会话与登录产品化验证

> 首批实现：2026-08-11；工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 24

## 本批结论

会话层已经从 P0 技术实验页的临时调用收敛为可由应用全局持有的 `SessionRepository`。它同时承担以下两个有状态职责：

- 串行执行启动恢复、Cookie 导入和退出，避免异步完成顺序覆盖较新的状态；
- 实现同步 `SessionCookieProvider`，让统一 HTTP 客户端只读取已经装载到内存的 Cookie 副本。

`AppSessionOwner` 现以进程级单例持有唯一 `SessionRepository`。生产工厂从 `UIAbilityContext` 立即提取 `ApplicationContext`，因此不会在 Ability 销毁后继续持有页面/Ability 上下文。`EntryAbility` 把 `session-restore` 注册为依赖关键深链任务的 `DEFERRED` 节点；首页内容加载成功后才启动恢复，恢复网络请求不会阻塞首屏。相同生命周期内重复触发延迟阶段只复用同一个恢复 Promise。

提交前安全审查进一步收紧了生命周期和凭据发布合同：

- 首次恢复时，持久 Cookie 在 `/api/v4/me` 明确认证前不会进入同步 provider；临时失败和普通 403 保留密文但 provider 为空。只有明确 401 或必要 Cookie 缺失才永久清理。若进程内已有已认证会话，后续恢复遇临时失败可继续保留原内存身份和原 Cookie，不用未经验证的新值替换。
- `logout()` 在尝试清理持久层前先清空运行时 Cookie 和 profile。即使 Preferences 或 Asset Store 部分清理失败，后续 HTTP 也不会继续携带旧凭据；错误态只用 `hasRetainedCredentials` 提示磁盘可能仍有残留。
- `SessionState` 返回的 profile 采用字段级深拷贝，页面不能通过修改返回对象污染仓库内部身份。
- 二维码客户端采用单 active 和 generation 合同。重叠 `start()`/`pollOnce()` 返回固定 `BUSY`，`cancel()` 通过独立取消 Promise 立即结束调用并销毁当前 NetworkKit handle；即使 `destroy()` 不能让底层 Promise settle，旧 generation 的 token、Cookie 和响应也不能回写。
- `expires_at` 只接受运行时有限正数，并把有效期限制在最多 24 小时；字符串、`NaN`、Infinity、过大的 TTL 或绝对期限统一回退到 120 秒，不会生成长期有效二维码。
- `EntryAbility` 使用 lifecycle generation 检查关键启动 await 之后和 `loadContent` 回调内的有效性；`onDestroy()` 后不会再加载页面或触发延迟会话恢复。

仓库提供游客、已登录、已过期和可恢复错误四种状态。启动恢复时，只有知乎明确返回 401，或 Cookie 缺失必要字段，才清除加密会话；普通 403、弱网、超时、限流、服务异常和无法识别的响应会保留本地凭据。新 Cookie 必须先通过 `/api/v4/me` 身份校验，再写入 `CookieSessionStore`，只有加密保存成功后才替换同步请求凭据。导入无效 Cookie 或保存失败不会覆盖旧会话。

二维码登录已落地经过 Android-master Lite 源码证实的专用 NetworkKit 协议客户端与状态机，但还没有接入产品登录页面。协议临时 Cookie 与应用会话隔离；只有轮询同步到非空 `z_c0` 后才开放候选 Cookie，调用方仍必须交给 `SessionRepository.loginWithCookies()` 完成 `/api/v4/me` 校验和加密保存。扫码、返回 `success` 或 `status=1` 都不等于登录成功。

## Android Lite 协议证据

只读核对 `Android-master:shared/src/commonMain/kotlin/com/github/zly2006/zhihu/shared/login/QrLogin.kt` 后，HarmonyOS 实现保持以下顺序和判定：

1. `GET https://www.zhihu.com/signin?next=%2F` 建立登录上下文；
2. 尽力执行 `POST https://www.zhihu.com/udid` 和 `GET https://www.zhihu.com/api/v3/oauth/captcha/v2?type=captcha_sign_in` 预热；
3. `POST https://www.zhihu.com/api/v3/account/api/login/qrcode` 获取二维码链接、token 和期限；
4. 产品层按 500 ms 节奏请求 `GET .../qrcode/{token}/scan_info`；
5. `status=1` 表示已扫码、等待用户在知乎 App 确认；`status=2` 或 `EXPIRED` 表示过期；403 且错误码 `40352` 或 `need_login=true` 进入风控；
6. 轮询响应 Cookie、`cookie`/`cookies` 字段和 `z_c0` 字段汇入临时 Cookie 容器；
7. 取得 `z_c0` 后仍需调用 `/api/v4/me` 验证身份，验证并保存成功才算登录完成。

`expires_at` 沿用 Android Lite 的兼容规则，可识别 TTL 秒、TTL 毫秒、绝对秒和绝对毫秒；缺失、非数值、非有限值、异常旧值或超过 24 小时上限的值回退到 120 秒。

## 安全边界

- 二维码协议使用独立的精确 URL 策略，只接受 HTTPS、精确 `www.zhihu.com`、无 userinfo、无显式端口；即使通用游客客户端允许 `api.zhihu.com`，二维码、风控跳转和临时 Cookie 也不会扩到该主机。
- NetworkKit `maxRedirects=0`，避免登录 Cookie 随重定向离开已验证主机。
- 响应体最大 1 MiB，请求连接和读取超时均为 10 秒，不启用缓存。
- 响应 `cookies`、轮询体中的 Cookie 字段仅在内存解析，不写日志，不出现在状态消息中；空值 Set-Cookie 会删除同名临时 Cookie，持久化 JSON 中畸形 Cookie 会被拒绝。
- `QrLoginState` 只向二维码渲染层提供必要的码链接和安全状态；token 不单独暴露为状态字段。
- 风控响应只显示固定文案。服务端 message、原始响应体、Cookie、二维码 token 和 ZSE 均不得记录。
- 风控 redirect 若不满足精确 `www.zhihu.com` 规则，回退到固定的 `https://www.zhihu.com/account/risk_control/`。
- 传输句柄销毁失败不会覆盖协议响应或已经结构化的网络错误。
- 同一客户端一次只允许一个创建或轮询操作；取消不依赖 transport Promise 自行结束，旧操作也不能覆盖取消后或新 generation 的状态。
- 本机扫描电脑端二维码的 Scan Kit 路径与“本机显示二维码供其他设备扫描”仍是两条独立链路；识码结果不自动提交，也不冒充登录完成。

## 自动化覆盖

会话与二维码当前共有 19 个 Hypium 用例，另在 AppStartup 套件增加 2 个生命周期合同：

- `SessionRepository.test.ets` 11 个：首次恢复发布门禁、profile 深拷贝、401/403 分流、临时失败保留密文、已有认证态回退、退出部分失败仍清运行时凭据、校验后保存、load/logout 串行化、owner 单例/恢复去重，以及销毁只取消验证、不清凭据并允许下次 Ability 生命周期重新恢复；
- `ZhihuQrLoginClient.test.ets` 8 个：四步请求顺序与临时 Cookie 汇入、句柄清理异常隔离、`z_c0` 门禁、扫码/确认状态、终态停止轮询、过期和风控、有效期运行时校验、重叠 start/poll 的 BUSY 合同、取消不依赖 transport settle、旧响应禁止回写，以及恶意域名和二维码链接拒绝。
- `AppStartup.test.ets` 增加 2 个：关键数据库/深链阶段结束前不运行 `session-restore`；Ability 销毁使异步启动 generation 失效，不能继续 loadContent 或 deferred。

`data/Index.ets` 已导出 owner；现有 `SessionRepository.test.ets` 与 `AppStartup.test.ets` 已在共享 `List.test.ets` 注册，因此无需新增测试入口。

## 本地构建

使用仓库统一 API 24 门禁构建四模块并运行测试；`ExpectedTestCount` 应使用共享入口当时的最新数值：

```powershell
./scripts/verify-harmony.ps1 -ExpectedTestCount <当前用例数> -SkipDependencyInstall
```

最终执行 `./scripts/verify-harmony.ps1 -ExpectedTestCount 128 -SkipDependencyInstall`：四模块 API 24 Debug HAP `BUILD SUCCESSFUL`，共享 Hypium `128/128`，其中会话 `11/11`、二维码 `8/8` 和启动生命周期用例全部通过，失败、错误和忽略均为 0。新增实现没有 ArkTS 编译错误；构建仍显示仓库已有 RDB 异常处理告警和 NetworkKit INTERNET 权限提示。

## API 24 产品化剩余门禁

1. 将 P0 技术实验页的手动 Cookie 操作迁入正式登录页面。页面通过 `getAppSessionOwner(context).getRepository()` 取得同一仓库；输入框继续使用密码类型，提交时立即清空页面字符串，只消费安全状态文案。
2. 为二维码链接接入 HarmonyOS 码图生成与正式登录 UI，按 500 ms 调 `pollOnce()`，在后台、离页、过期和取消时停止轮询。
3. 收到 `CREDENTIAL_READY` 后调用全局仓库的 `loginWithCookies(client.getCandidateCookies())`；只有返回 `AUTHENTICATED` 才展示成功并离开登录页。
4. 风控页必须采用受限原生流程或单独安全评审的 ArkWeb 容器，限定 `www.zhihu.com`、禁任意跳转，并将通过验证取得的 Cookie 只汇回二维码临时容器。当前实现不会自动打开风控页面。
5. 使用真实 Cookie 在 API 24 DevEco 虚拟机复测延迟冷启动恢复、退出清理、401/403 过期和弱网保留；销毁 Ability 时只取消在途校验，不调用 `logout()` 或 `CookieSessionStore.clear()`。
6. 使用另一台已登录知乎的设备扫描 API 24 虚拟机二维码，验证“已扫码→待确认→`z_c0`→身份校验→加密保存”的完整闭环；补测过期、取消、前后台和 40352 风控。虚拟机无法代表真实手机相机质量，本机扫描电脑端码仍需真实 HarmonyOS 手机补测。

本批没有引入端侧 AI、模型、推理依赖，也没有把 P0 Scan Kit 识码结果当作账号登录结果。
