# 方案 B：游客态公式请求携带设备 Cookie 评估

> 制定日期：2026-08-14
> 范围：正文公式渲染在游客态（未登录）下被知乎 equation 端点风控的问题
> 关联：`docs/p0/reader-validation.md`、`reader/src/main/ets/reader/FormulaPixelMapLoader.ets`

## 1. 背景

HarmonyOS 正文公式走「请求知乎 `https://www.zhihu.com/equation?tex=...` 的 SVG → `ImageSource` 解码 → PixelMap」路线（P0 决策，见 `docs/p0/reader-validation.md`）。

2026-08-14 已修复**登录态**公式渲染：`FormulaPixelMapLoader` 的请求携带应用会话 Cookie（含 `z_c0`）与桌面 UA，返回 `200 image/svg+xml`，登录态下 74 个公式全部原生解码。

但**游客态**仍失败：`formulaCookieHeader` 读取的是 `SessionRepository.getCookies()`，未登录时为空，公式请求变成「无 Cookie 的裸请求」，被知乎 302 重定向到 `account/unhuman` 安全验证页。

## 2. 探测证据（决定方案 B 有效性的关键）

用真实 `ZHIHU_COOKIE` 分拆探测 equation 端点（当前开发机出口 IP）：

| Cookie 组合 | 结果 |
| --- | --- |
| 无 Cookie | 302 → unhuman |
| 仅 `d_c0` | 302 → unhuman |
| `d_c0` + `_zap` + `__zse_ck` | 302 → unhuman |
| 完整（含 `z_c0`） | 200 `image/svg+xml` |

结论：**在风控 IP 下，设备指纹 Cookie（不含 `z_c0`）不足以绕过 unhuman 验证，只有登录态 `z_c0` 能拿到 SVG。**

## 3. 方案 B 设计

让游客态公式请求携带**设备指纹 Cookie**（`d_c0` / `_zap` / `__zse_ck`），不含登录凭据 `z_c0`：

- 设备 Cookie 来源：知乎访问 `/signin`（下发 `sec_token`、`_xsrf`、`BEC`、`_zap`）与 `POST /udid`（下发 `d_c0`）时通过 Set-Cookie 下发。
- 当前鸿蒙端游客态不维护这些 Cookie（`d_c0` 只出现在二维码登录的临时流程与登录态中）。
- 需要新增：游客态获取并持久化设备 Cookie，`formulaCookieHeader` 在游客态返回设备 Cookie。

## 4. 安全边界

方案 B 不引入登录凭据泄露风险：

| 项 | 结论 |
| --- | --- |
| 是否含 `z_c0` | 否，仅设备指纹 |
| 泄露后果 | 最多把「设备」与「知乎匿名标识」关联，不能冒用账号 |
| 发送目标 | `isTrustedFormulaUrl` 锁定 `https://www.zhihu.com/equation`，无第三方 |
| 重定向 | `maxRedirects: 0`，Cookie 只发单跳，不随重定向转发 |
| 日志 | 不写 Cookie 值，沿用现有脱敏 |

## 5. 有效性边界（重要）

方案 B 是**渐进改善**，不是彻底解决：

- 探测证据显示：**风控 IP 下设备 Cookie 仍 302 unhuman**，只有 `z_c0` 能绕过。
- 因此方案 B 只能在「正常 IP」下降低被风控的概率（让知乎视请求为「有设备标识」），不能保证风控 IP 下成功。
- 若产品要求游客态公式**完全稳定**（含风控 IP），方案 B 不满足，需方案 C（本地 LaTeX 渲染，见评估）。

## 6. 实施要点

1. 游客态获取 `d_c0`：调用 `POST https://www.zhihu.com/udid`（可复用 `ZhihuQrLoginClient` 已有的 `parseCookieJarEntries` 解析 NetworkKit 返回的 Netscape cookie-jar）。
2. 持久化设备 Cookie：新增独立的游客设备 Cookie 存储，或扩展 `CookieSessionStore` 区分「登录态」与「设备态」，避免污染登录会话。
3. `formulaCookieHeader` 逻辑：登录态返回完整会话 Cookie；游客态返回设备指纹 Cookie。
4. 保持 `z_c0` 不混入游客态，且严格沿用 `isTrustedFormulaUrl` + `maxRedirects: 0`。

## 7. 工作量与建议

- 工作量：约 0.5 天（获取 + 持久化 + 公式请求接入）。
- 风险：低（不含登录凭据，只发受信域）。
- **建议**：作为低成本尝试可接受，但不应预期它解决「风控 IP 下的游客态公式」。立项前建议先用真实设备在目标网络验证「带设备 Cookie 的游客态公式请求」是否真的能拿到 SVG；若目标网络下仍 302，则方案 B 收益有限，应直接评估方案 C（本地 LaTeX 渲染）。
