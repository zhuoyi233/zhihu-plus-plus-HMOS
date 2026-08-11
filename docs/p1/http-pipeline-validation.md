# P1 统一 HTTP、Cookie 与 ZSE 链路验证

## 范围与结论

本批次将 P0 的匿名 HTTP 探针和真实 Cookie 登录校验收敛到 `ZhihuHttpClient`。目标版本固定为 HarmonyOS 6.1.1（API 24），不引入端侧 AI，也不提前实现 P2 Feed endpoint 或空转 Repository。

统一链路承担以下职责：

- 统一桌面 User-Agent、默认 `Accept`、10 秒连接超时、15 秒读取超时、字符串响应和禁用缓存配置；
- 通过窄接口 `SessionCookieProvider.getCookies()` 获取当前 Cookie，不让 HTTP 层依赖会话持久化或加密实现；
- 仅为显式会话请求生成 `Cookie`，仅在显式签名时添加 `x-zse-93` 与动态 `x-zse-96`；签名请求必然同时携带 Cookie；
- 所有请求在创建 transport 前都必须通过可信绝对 URL 校验；当前最小白名单只有精确主机 `www.zhihu.com`，要求 HTTPS、无 userinfo、无显式端口，不接受 suffix 匹配或尚未使用的 `api.zhihu.com`；
- NetworkKit 固定 `maxRedirects: 0`，300–399 响应以及禁重定向产生的 transport code `2300047` 都映射为不可重试的客户端错误，避免 Cookie/ZSE 随跨域重定向外带；
- NetworkKit 固定响应体上限 `maxLimit: 1 MiB`，登录和探针不会无界接收响应；
- 一个客户端实例只允许一个活动请求；取消绑定具体 transport，取消和正常结束都保证销毁 NetworkKit `HttpRequest`，不会由旧回调清理新请求；
- HTTP 状态、NetworkKit transport code 和重试语义统一进入结构化 `HttpFailure`。

`HttpProbeClient` 只保留匿名问题探针的 URL 与返回模型，`ZhihuLoginClient` 只保留 Cookie 完整性校验、账号响应解析和登录状态文案。两者不再自行创建 NetworkKit 请求，实际请求都经过 `ZhihuHttpClient.execute()`。登录客户端持有单个执行器，因此并发校验会被本地拒绝，页面离开时可调用 `cancel()` 终止当前验证。

取消由客户端自己的 cancellation Promise 与 transport Promise 竞速，不依赖 `destroy()` 是否触发底层 reject。取消后活动槽立即释放，新请求可以开始；旧请求的 `finally` 只清理自己的 token，不会清空新请求。`destroy()` 抛出的清理异常会被隔离，不能覆盖成功响应或原始结构化失败。

## 错误契约

`HttpFailure` 只公开以下安全字段：

| 字段 | 语义 |
| --- | --- |
| `kind` | authentication、rate limited、client、server、timeout、network、cancelled 或 busy |
| `status` | 可选 HTTP 状态码 |
| `transportCode` | 可选 NetworkKit 数字错误码 |
| `retryable` | 限流、服务端、超时和网络错误为 `true`，其他为 `false` |

错误消息由本地枚举和数字状态生成，不拼接上游响应正文、`BusinessError.message`、请求头、Cookie 或 ZSE 原文。登录适配继续保持 P0 行为：401/403 为凭证失效；429、5xx、超时和普通网络异常为临时失败；只有 HTTP 200 且账号字段完整才认证成功。

## 自动化覆盖

- `HttpProbeClient.test.ets`：原 P0 HTTP 状态/transport 分类继续保留，并补充结构化字段、重试语义和安全消息断言。
- `ZhihuLoginClient.test.ets`：原 Cookie、账号解析和登录分类继续保留；新增 fake transport，证明 `verify()` 经过统一 Cookie/ZSE/禁重定向链路，并覆盖单活动请求和取消。
- `ZhihuHttpClient.test.ets`：覆盖匿名请求不携带 Cookie/ZSE、会话签名请求统一添加 Cookie/ZSE、1 MiB 响应上限、成功路径销毁 transport、HTTP 503 安全错误、provider/factory 异常安全收敛、清理异常隔离，以及 HTTP、evil suffix、userinfo、显式端口和未列入白名单主机在读取 Cookie 前被拒绝。
- 取消测试使用 `destroy()` 后仍永久 pending 的 fake transport，验证客户端仍返回 `CANCELLED`、只销毁一次，并可立即完成后一条请求。
- 重定向契约覆盖 `maxRedirects: 0` 和 302 转不可重试结构化错误；测试 fixture 只使用虚构 Cookie 值。

测试文件由 P1 统一测试注册任务加入 `List.test.ets`；本并行任务按文件边界不修改统一入口。

## 定向构建记录

执行：

```powershell
devecocli build --product default --modules data --build-mode debug
```

结果：`BUILD SUCCESSFUL`。`ZhihuHttpClient` 无严格 ArkTS 编译错误；HAR 单独编译出现的 INTERNET 权限提示由最终 `entry` HAP 清单声明处理。

API 24 汇总验证使用 `scripts/verify-harmony.ps1 -ExpectedTestCount 89`，四模块构建与 Hypium `89/89` 通过。设备上的匿名探针实际到达知乎并收到 HTTP 403；客户端将其归类为 `AUTHENTICATION`，UI 仅显示本地生成的“需要有效登录态”文案，没有回显响应正文、请求头或 Cookie。该结果证明真实 NetworkKit 与结构化错误路径可用，但不把外部服务当前的 403 表述为匿名接口业务成功。

## 后续边界

- Session Repository 落地时实现 `SessionCookieProvider`，不要把 `CookieSessionStore` 或 `SessionCipher` 注入 HTTP 层。
- Feed、搜索和详情 endpoint 在对应 P2 任务中以请求描述接入本客户端；本批次不创建仅转发请求的 Repository 实现。
- 真实 Cookie 不进入测试 fixture、日志或文档。P0 已验证的手动 Cookie 登录、加密恢复、退出清理和匿名探针交互应在 API 24 汇总回归中继续通过。
