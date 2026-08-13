# P2 最终验收静态审计

审计日期：2026-08-13。

## 静态结论

- `entry/src/test` 共 34 个测试套件，源码中共有 237 个 `it(...)`。
- 34 个套件均有默认导出，并在 `List.test.ets` 中恰好导入一次、调用一次；没有漏注册或重复注册。
- 2026-08-13 已在 DevEco Studio 26.0.0 Beta2 / API 26 工具链取得新的 Hypium 报告：`237/237`，Failure、Error、Ignore 均为 0。
- `build-profile.json5` 仍为 API 24：`targetSdkVersion` 和 `compatibleSdkVersion` 均为 `6.1.1(24)`，且 `signingConfigs` 为空。
- 仓库工作区未发现 `p12`、`cer`、`p7b`、`csr` 或 `external-signing-config.json`；Git 索引也未跟踪这些材料。
- `.gitignore` 已覆盖 HarmonyOS 构建产物、`BuildProfile.ets` 和签名材料。
- 根目录 `AGENTS.md` 仍是已跟踪且未修改的 `CLAUDE.md` 引用；本次任务使用的新 HarmonyOS 指令来自会话上下文，尚未落入仓库文件。

## 图片预览审计

`NativeContentDocument.ets` 的图片预览静态具备以下边界：

- 仅接受 HTTPS 知乎图床域名，非受信 URL 不进入保存或分享流程；
- 支持 1x 到 4x 双指缩放、双击复位、长按保存和显式关闭；
- 保存前请求 `ohos.permission.WRITE_IMAGEVIDEO`，模块配置已声明用途资源和 `EntryAbility`/`inuse` 使用场景；
- 下载限制 8 MiB，10 秒连接超时、15 秒读取超时、禁用缓存和重定向；
- 只接受非空 `ArrayBuffer`，请求对象在 `finally` 中销毁；
- 相册写入使用 `MediaAssetChangeRequest`，分享只发送受信图片 URL，不附带 Cookie 或请求头；
- 所有失败路径显示固定提示，不输出系统异常、响应体或敏感数据；
- `UIAbilityContext` 使用运行时检查，没有通过类型断言绕过严格模式。

API 26 编译与 API 24 安装启动已完成：四模块 HAP 构建成功，已签名调试 HAP 在 API 24 虚拟机安装、冷启动并通过首页、显示设置、搜索页 UI 树验证。相册保存和分享的交互分支仍需设备人工回归。

## 当前工具与外部阻塞

本次使用 Studio 26 内置 Node、Hvigor、devecocli 与 HDC 完成了“构建 → Hypium → API 24 安装启动”验证。API 26 虚拟机镜像当前不在本机 CLI 可用目录中，因此只能把 API 26 运行时回归保留为外部设备门禁。

待 DevEco Code 工具可用后，最终门禁顺序为：

1. 在 API 24 设备验证图片关闭、缩放、双击复位、权限拒绝、相册保存和系统分享；
2. 验证断网、非知乎图床、超限图片和分享取消均安全返回正文；
3. 在 API 24 设备执行真实二维码挑战和已登录会话回归；
4. 在 API 26 虚拟机或真机执行完整新系统行为回归；
5. 构建或签名后再次确认 `build-profile.json5` 与签名材料没有进入提交。

## P2 完成状态

可静态判定完成：237 测试注册、API 24 工程基线、图片预览安全边界、日报原生跳转、用户内容列表、签名材料排除、P2 功能源码与验收清单。

外部条件未闭环：图片预览设备交互、相册权限/写入、系统分享面板，以及知乎真实二维码挑战和真实登录会话回归；另需在 API 26 虚拟机或真机完成完整产品回归。

本轮没有引入端侧 AI、模型、推理依赖或 WebView 正文路径。
