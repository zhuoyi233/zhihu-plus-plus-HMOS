# P2 最终验收静态审计

审计日期：2026-08-14。

## 静态结论

- `entry/src/test` 共 34 个测试套件，源码中共有 240 个 `it(...)`。
- 34 个套件均有默认导出，并在 `List.test.ets` 中恰好导入一次、调用一次；没有漏注册或重复注册。
- 2026-08-14 已在 DevEco Studio 26.0.0 Beta2 / API 26 工具链取得新的 Hypium 报告：`240/240`，Failure、Error、Ignore 均为 0。
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

API 26 编译工具链与 API 24 工程基线验证已完成：四模块 HAP 构建成功，已签名调试 HAP 在 `ZhihuPlus_API26` 虚拟机安装、启动并通过首页 UI 树验证。手动 Cookie 登录后应用自动返回首页并加载推荐流；强制停止进程后重新启动仍能恢复会话并自动加载推荐流；连续滚动可见新的回答与文章卡片，未出现分页错误。相册保存和分享的交互分支仍需设备人工回归。

## 当前工具与外部阻塞

本次使用 Studio 26 内置 Node、Hvigor、devecocli 与 HDC 完成了“API 26 编译 → Hypium → API 26 虚拟机安装启动”验证，工程 `targetSdkVersion` 与 `compatibleSdkVersion` 均继续保持 `6.1.1(24)`。

待 DevEco Code 工具可用后，最终门禁顺序为：

1. 在 API 26 虚拟机或真机验证图片关闭、缩放、双击复位、权限拒绝、相册保存和系统分享；
2. 验证断网、非知乎图床、超限图片和分享取消均安全返回正文；
3. 使用另一台已登录设备执行真实二维码挑战；
4. 对搜索、详情、关注、热榜、日报、屏蔽规则和已读历史执行完整产品回归；
5. 构建或签名后再次确认 `build-profile.json5` 与签名材料没有进入提交。

## P2 完成状态

可静态判定完成：241 测试注册（2026-08-14 新增 cookie-jar 解析用例）、API 24 工程基线、图片预览安全边界、日报原生跳转、用户内容列表、签名材料排除、P2 功能源码与验收清单。

外部条件未闭环：图片预览设备交互、相册权限/写入、系统分享面板、知乎真实二维码挑战，以及除首页外的完整产品回归。真实 Cookie 登录、登录成功回跳、会话冷启动恢复和首页推荐流滚动已在 API 26 虚拟机闭环。

2026-08-14 追加：二维码登录（挑战链接查询串、NetworkKit `maxRedirects`、Netscape cookie-jar 解析）与公式渲染（公式 SVG 请求携带会话 Cookie 与桌面 UA）均已修复。API 26 虚拟机登录态下，原生长文 74 个公式全部原生解码（`API 24 原生公式已解码 74/74`），不再降级为 TeX。P2 代码完成判定成立，可进入 P3。

本轮没有引入端侧 AI、模型、推理依赖或 WebView 正文路径。
