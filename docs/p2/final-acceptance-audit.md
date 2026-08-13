# P2 最终验收静态审计

审计日期：2026-08-13。

## 静态结论

- `entry/src/test` 共 32 个测试套件，源码中共有 223 个 `it(...)`。
- 32 个套件均有默认导出，并在 `List.test.ets` 中恰好导入一次、调用一次；没有漏注册或重复注册。
- 本轮仅确认静态注册，不能替代新的 Hypium 执行报告。最近已执行的报告仍是第二批的 `172/172`。
- `build-profile.json5` 仍为 API 24：`targetSdkVersion` 和 `compatibleSdkVersion` 均为 `6.1.1(24)`，且 `signingConfigs` 为空。
- 仓库工作区未发现 `p12`、`cer`、`p7b`、`csr` 或 `external-signing-config.json`；Git 索引也未跟踪这些材料。
- `.gitignore` 已覆盖 HarmonyOS 构建产物、`BuildProfile.ets` 和签名材料。
- 根目录 `AGENTS.md` 仍是已跟踪且未修改的 `CLAUDE.md` 引用；本次任务使用的新 HarmonyOS 指令来自会话上下文，尚未落入仓库文件。

## 图片预览审计

`NativeContentDocument.ets` 的图片预览静态具备以下边界：

- 仅接受 HTTPS 知乎图床域名，非受信 URL 不进入保存或分享流程；
- 支持 1x 到 4x 双指缩放、双击复位、长按保存和显式关闭；
- 保存前请求 `ohos.permission.WRITE_IMAGEVIDEO`，模块配置已声明该权限；但当前声明缺少用户授权权限通常要求的 `reason` 与 `usedScene`，须由 API 24 `build_project` 确认，并在构建失败时补齐多语种权限理由与 `EntryAbility`/`inuse` 使用场景；
- 下载限制 8 MiB，10 秒连接超时、15 秒读取超时、禁用缓存和重定向；
- 只接受非空 `ArrayBuffer`，请求对象在 `finally` 中销毁；
- 相册写入使用 `MediaAssetChangeRequest`，分享只发送受信图片 URL，不附带 Cookie 或请求头；
- 所有失败路径显示固定提示，不输出系统异常、响应体或敏感数据；
- `UIAbilityContext` 使用运行时检查，没有通过类型断言绕过严格模式。

这些 API 和交互仍需由 DevEco Code 的 `arkts_check`、`build_project` 和 API 24 `start_app` 验证。官方文档中，Media Library Kit 提供相册资源保存能力，Share Kit 提供系统分享能力；最终以 API 24 SDK 的实际编译结果为准。

## 当前工具与外部阻塞

本会话未暴露 DevEco Code 的 `arkts_check`、`build_project` 或 `start_app` 工具，因此无法按仓库规定执行“静态检查 → 构建 → 启动”。Windows 终端同时因系统错误 1920 无法创建进程，不能使用终端替代完成 Git 状态查询、构建或测试。

图片保存还有一项构建前风险：`ohos.permission.WRITE_IMAGEVIDEO` 当前只有 `name`，没有 `reason` 和 `usedScene`。该权限若在 API 24 被判定为用户授权权限，当前配置会被构建或上架校验拒绝；此项必须在最终门禁中优先确认。

待 DevEco Code 工具可用后，最终门禁顺序为：

1. 对本批修改的 `.ets` 执行 `arkts_check`；
2. 检查 `WRITE_IMAGEVIDEO` 权限声明；若 API 24 要求，补齐 `$string:` 权限理由和 `EntryAbility`/`inuse` 使用场景；
3. 执行 `build_project`，确认 entry、core、data、reader 均通过 API 24 编译；
4. 运行 Hypium，取得新的 `223/223` 且 Failure、Error、Ignore 均为 0 的报告；
5. 通过 API 24 `start_app` 验证冷启动、导航和图片预览；
6. 验证图片关闭、缩放、双击复位、权限拒绝、相册保存和系统分享；
7. 验证断网、非知乎图床、超限图片和分享取消均安全返回正文；
8. 构建或签名后再次确认 `build-profile.json5` 与签名材料没有进入提交。

## P2 完成状态

可静态判定完成：223 测试注册、API 24 工程基线、图片预览安全边界、签名材料排除、P2 功能源码与验收清单。

外部条件未闭环：新的 223 项 Hypium 执行报告、API 24 构建与启动、图片预览设备交互、相册权限/写入、系统分享面板，以及知乎真实二维码挑战和真实登录会话回归。

本轮没有引入端侧 AI、模型、推理依赖或 WebView 正文路径。
