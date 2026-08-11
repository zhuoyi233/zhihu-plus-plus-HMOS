# P2 第二批纵向切片汇总

## 已完成

- 正式账号与登录页：手动 Cookie 密码输入、原生 ArkUI `QRCode`、500 ms 轮询、风控/过期/取消和退出状态。
- 会话操作所有权：每次页面登录持有独立 operation handle，取消不会误伤启动恢复或其他请求。
- 搜索：Android Lite 对齐的 `/api/v4/search_v3`、会话/ZSE、严格游标、三类内容与登录恢复。
- 问题、回答和文章详情：会话请求、严格解码、原生 Reader、图片/公式降级、打开记录和登录恢复。
- 强类型导航：新增无参数 Login 目的地，Search 与三类详情由单一 `NavPathStack` 管理。
- 登录恢复闭环：用户验证成功后自动返回，并只重建栈顶问题、回答或文章详情以使用新会话重新请求。

## 自动门禁

2026-08-11 使用 DevEco Studio 6.1.1、HarmonyOS API 24 执行：

```powershell
./scripts/verify-harmony.ps1 -ExpectedTestCount 172 -SkipDependencyInstall
```

四模块 Debug HAP 构建成功；新鲜 Hypium 报告为 `172/172`，Failure、Error、Ignore 均为 0。

## API 24 虚拟机证据

`ZhihuPlus_API24` 已验证：

1. 冷启动后真实游客 Feed 正常显示；
2. Search 目的地显示输入、提交和空态，返回栈正常；
3. 设置页可见账号与登录入口，正式登录页显示游客态、密码输入、二维码入口和返回操作；
4. 从真实 Feed 打开回答可进入详情；最终签名包又以公开回答深链复测，游客认证错误显示 `p2_answer_detail_login`，点击后进入 `p2_login_top_start_container`；
5. 二维码请求失败时只显示“二维码获取失败，请重试”，不显示 token、响应体或 URL。

## 尚未闭环

- 本次知乎二维码接口未返回可绘制挑战，因此真实 QRCode 图形、扫码确认和 `z_c0` 汇入仍待有效外部条件复测。
- 自动化遵守浏览器控制安全边界，不读取 Chrome Cookie；真实会话搜索、问题/回答/文章正文和退出清理留待用户提供会话或二维码条件后复测。
- 关注、热榜、日报、用户页、想法、屏蔽规则和完整已读产品页属于后续 P2 切片。

本批未引入端侧 AI、模型、推理依赖或 WebView 正文路径。
