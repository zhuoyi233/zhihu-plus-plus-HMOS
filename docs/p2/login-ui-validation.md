# P2 正式登录 UI 验证

> 工具链：DevEco Studio 6.1.1 Release，HarmonyOS API 24；验证不读取浏览器 Cookie，也不记录任何真实会话值。

## 范围

本批新增独立 `LoginPage` 与 `LoginController`，把首批会话仓库和二维码协议收敛为正式产品状态。页面已通过无参数强类型 `LOGIN` 目的地接入 `P1Shell`，设置页和搜索失效态可进入正式登录页。

正式状态包括游客、已登录、会话失效、手工验证中、二维码创建中、待扫码、待确认、账号验证中、二维码过期、取消、后台暂停、风控和可恢复错误。状态对象只包含安全文案、昵称、仅供 `QRCode` 绘制的本次受信挑战链接，以及经过协议层精确主机校验的风控 URL；不单独暴露 token，也不包含 Cookie、响应体或请求头。

## API 24 二维码图形证据

本机 DevEco Studio 自带 SDK 的 `sdk/default/sdk-pkg.json` 标明 `apiVersion=24`、`HarmonyOS 6.1.1`。同一 SDK 的 `openharmony/ets/component/qrcode.d.ts` 提供 ArkUI `QRCode(ResourceStr)`，系统能力为 `SystemCapability.ArkUI.ArkUI.Full`，自 API 7 可用，并提供 `color` 与 `backgroundColor` 属性。因此页面直接使用原生 `QRCode` 组件，黑色码点配白色背景，不需要网络码图服务、ArkWeb、PixelMap 或额外权限。

Scan Kit 的 `generateBarcode.createBarcode()` 也存在于本机 HMS SDK，但官方指南明确其码图生成当前不支持模拟器。项目验收目标是 DevEco 虚拟机，因此本批没有引入 Scan Kit，也没有生成需要在离页时 `release()` 的 PixelMap。

## 会话与输入安全

- 页面从 `getAppSessionOwner(context).getRepository()` 获取进程唯一的 `SessionRepository`，不会创建第二份生产 Cookie 容器。
- 手动 Cookie 输入使用密码类型，UI 限制总长度为 8192；数据边界同时限制最多 64 个字段、单值 4096 字符和名称 128 字符。点击提交时先复制一次局部字符串，立即把页面 `@State` 清空，再调用控制器；控制器和可观察状态从不保存或回显原始输入。
- 手工 Cookie 只有经过 `SessionRepository.beginLoginWithCookieHeader()` 返回的操作完成身份验证，且加密保存成功后才进入 `AUTHENTICATED`。
- 退出登录沿用仓库的“先清运行时凭据，再清持久层”合同；部分清理失败只显示固定错误状态，后续 HTTP 不再携带旧 Cookie。

## 二维码状态机

1. 用户主动请求二维码，控制器调用独立的 `ZhihuQrLoginClient.start()`；不会把已有应用会话 Cookie 注入二维码临时容器。
   服务端返回的挑战链接还必须有界、严格匹配 `https://www.zhihu.com/account/scan/login/{token}`，且末段与本次 token 完全一致，否则不进入状态或 `QRCode`。
2. 只有 `READY` 和 `WAITING_CONFIRMATION` 会安排下一次轮询，间隔固定使用协议常量 `500 ms`；同一时刻至多有一个 timer 和一个协议请求。
3. `EXPIRED`、`RISK_CONTROL`、`TEMPORARY_FAILURE`、取消和账号验证阶段都会停止轮询。临时失败由用户重新获取二维码，不进行无限自动重试。
4. `CREDENTIAL_READY` 只表示临时容器取得候选 Cookie。控制器必须把副本交给全局 `SessionRepository.loginWithCookies()`；仅仓库返回 `AUTHENTICATED` 才显示登录成功。
5. 风控只显示固定安全提示和协议客户端验证过的 `www.zhihu.com` URL，不自动打开 ArkWeb 或系统浏览器。

## 生命周期

页面通过 API 24 的 `ApplicationContext.on('applicationStateChange', callback)` 监听应用前后台。进入后台或页面离开时，控制器递增 generation、清除定时器、取消 QR NetworkKit 请求，并只调用自己持有的 `SessionLoginOperation.cancel()`。仓库在排队任务开始前识别取消；只有该操作正在使用 verifier 时才转发取消，因此不会误取消全局启动恢复。操作 token、Cookie 和迟到结果都不进入可观察状态或日志。回到前台只重新读取全局会话状态，不会在用户不知情时恢复旧二维码轮询。
若前后台监听注册失败，页面会立即进入暂停态并禁用手工登录、二维码与退出操作，不会在无法感知后台的情况下继续轮询或验证。

页面离开时会注销 application state callback、取消全部在途工作并清空密码输入。ArkUI `QRCode` 不持有需要业务层释放的 PixelMap。

手动 Cookie 或二维码验证从对应验证阶段进入 `AUTHENTICATED` 后，页面才通知导航层认证完成；已有登录态
首次展示不会误触发。导航层自动移除 Login，并对返回栈顶已通过强类型运行时解码的问题、回答或文章
目的地执行一次定向重建，使详情使用新会话自动重载，避免返回后仍停在旧登录 CTA。

## 自动化覆盖

`entry/src/test/LoginController.test.ets` 新增 7 个纯 Hypium 用例：

1. 已登录状态映射与退出登录；
2. 手动 Cookie 不进入可观察状态；
3. 500 ms 单定时器轮询，以及待确认时保持二维码可见；
4. 候选 Cookie 经过仓库认证后才成功；
5. `CREDENTIAL_READY` 后身份失败不能冒充登录；
6. 过期和风控终止轮询，只暴露安全 URL；
7. 后台与离页取消网络/定时器，拒绝迟到二维码结果；只取消页面自己发起的会话验证；
8. 认证完成判定拒绝已有登录态首次展示，只接受两条真实用户验证迁移；导航策略只重建三类详情。

该 suite 已在 `entry/src/test/List.test.ets` 注册一次。会话仓库另覆盖排队登录取消不影响启动恢复、活动登录只取消同一 operation；Cookie suite 覆盖长度/字段数/单值边界，QR suite 覆盖挑战路径与 token 一致性。第二批 P2 统一门禁最终为 172/172。

## 剩余验收

1. API 24 四模块构建和 172 项 Hypium 已通过。
2. DevEco 虚拟机已验证正式登录页、游客状态和二维码请求失败的安全可恢复文案；当前外部接口未返回可绘制挑战，真实码图与扫码闭环仍需另一台已登录知乎的设备复测。
