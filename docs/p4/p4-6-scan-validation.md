# P4-6 生产扫码首个切片验证

> 验证日期：2026-08-20  
> 范围：生产入口、Scan Kit 窄适配、URL 策略与用户确认交接模型  
> 自动化基线：52 个套件，Hypium `415/415`

## 本次交付

- `SystemQrScanner` 是唯一调用 `scanBarcode.startScanForResult` 的生产适配器；它固定为 `QR_CODE`、单码、系统相册入口。页面和状态机只依赖 P4-0 的 `QrScanner` 窄接口。
- 登录页“扫码”模式新增“扫描电脑端登录二维码”入口，并以强类型 `QrDesktopLoginScan` 目的地打开生产页；原 `QrScanProbePage` 保留为技术实验页，不再直接调用系统扫码入口。
- 扫描结果必须先通过 `QrLoginScanPolicy`：HTTPS、精确 `www.zhihu.com`、无端口和 userinfo、精确登录路径、受限 token 字符与长度；编码路径、fragment、相似域名、重复路径分隔符和超长值均拒绝。
- 合法结果只显示固定来源 `www.zhihu.com` 与“确认登录电脑 / 取消”。token 和原始 URL 不进入页面状态、日志或持久化。
- 确认请求的 CSRF、风控与成功判定合同尚未冻结。本切片没有写请求、Cookie 提交、自动确认或 ArkWeb 导航；确认后仅产生一次性、内存内的受限交接，供后续专用请求或受限 ArkWeb 适配器在合同冻结后取用。

## 自动化结果

`pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild` 在新 worktree 首次运行因缺少本地 `oh_modules` 停在依赖前置检查；执行 `ohpm install --all` 后，使用同一参数的 Hvigor `test` 完成：

```text
BUILD SUCCESSFUL
Tests run: 415, Failure: 0, Error: 0, Pass: 415, Ignore: 0
```

新增测试覆盖：

- fake scanner 的合法扫码、取消、服务不可用和重复点击；
- 扫描完成后必须显式确认，确认前和取消后不得取得交接 URL；
- 切后台后迟到结果被 generation 门禁忽略，回前台可重新扫描；
- 超长 token、percent-encoding 和 fragment 绕过拒绝；
- 新生产目的地的运行时参数只能为空对象。

## API 24 设备人工验收清单

本切片尚未进行真实电脑端登录确认；该动作会改变外部登录状态，须由用户在专用测试目标上显式触发。合并后在 `ZhihuPlus_API26`（API 24 运行基线）执行：

1. 进入“账号与登录 → 扫码 → 扫描电脑端登录二维码”，确认不申请 `CAMERA` 权限，系统 Scan Kit 页面仍有相册入口；
2. 验证扫码取消返回生产页，不产生登录态或网络确认；
3. 扫描合法电脑端码，确认只显示固定来源与确认/取消操作，不显示 token；
4. 在确认前离开页面、切后台再回前台，确认不能复用旧扫码结果；
5. 扫描相似域名、HTTP、端口、编码路径、超长 token 与普通知乎链接，确认不会进入确认态；
6. 仅在后续确认协议和受限 ArkWeb 导航策略冻结、并由用户再次确认后，才验证电脑端成功、风控和 Cookie 变化。

## 已知限制与后续

- 本切片不执行电脑端登录确认，因此不能宣称扫码已登录或电脑端已获得会话。
- `QrDesktopLoginHandoff.takeConfirmedUrl()` 是一次性内存边界；后续实现必须在调用前再次验证 URL，并限制为精确知乎主机，禁止外部 scheme 与任意重定向。
- 现有 API 24 兼容警告（`ContentDetailPages.ets` 的 `fill`）不属于本切片，仍需在 P4 总验收前处理。
