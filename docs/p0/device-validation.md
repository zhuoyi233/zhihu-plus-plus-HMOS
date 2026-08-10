# P0 DevEco 虚拟机验证记录

> 验证日期：2026-07-20

## 设备矩阵

| 虚拟机 | DevEco 显示版本 | HDC 系统版本 | API | 结果 |
| --- | --- | --- | --- | --- |
| `ZhihuPlus_API20` | HarmonyOS 6.0.0（20） | `emulator 6.0.0.48(SP1DEVC00E47R4P11)` | 20 | 通过 |
| `ZhihuPlus_API24` | HarmonyOS 6.1.1（24） | `emulator 6.1.0.125(SP9DEVC00E120R4P11)` | 24 | 通过 |

两台设备均使用 DevEco Studio 设备管理器提供的 Huawei Phone x86 镜像，配置为 4 GB RAM、6 GB ROM、1320 × 2856、560 dpi。

## 验证结果

两台虚拟机均完成以下检查：

1. 首次冷启动并通过 HDC 暴露为 `127.0.0.1:5555`。
2. 安装 `entry-default-unsigned.hap`。
3. 启动 `com.github.zhuoyi233.zhplus/EntryAbility`。
4. 正确显示 P0 页面以及“目标 API 24 · 最低兼容 API 20”。
5. 发起 HTTPS 请求后收到知乎 `HTTP 403 (client)`。
6. 使用 AES-256-GCM 加密测试 Cookie，并将数据密钥保存到 Asset Store。
7. 将仅含 IV、密文和认证标签的信封写入 Preferences。
8. 强制停止并重新启动应用进程。
9. 成功恢复 Cookie，同时清除已过期的测试 Cookie。
10. 清除会话密文和 Asset Store 数据密钥。
11. 显示游客模式、密码型 Cookie 输入、验证保存和退出清理入口。
12. Cookie 输入只显示掩码，提交后立即清空；缺少 `z_c0` 或 `d_c0` 时在本地拒绝。
13. 打开真实长回答样本，解析为 112 个原生块并通过 `LazyForEach` 滚动。
14. 对块公式节点实验性使用受限 `RichText` 加载知乎 SVG，整篇正文不使用 ArkWeb。
15. API 20 滚动到公式区域，API 24 连续滚动到文章结尾；列表无空白或崩溃，但真实长文公式尚未完整渲染。
16. 加载真实知乎 JPEG 和 GIF，两个 API 基线均收到成功回调。
17. 对 GIF 可见区域间隔两秒取样，API 20 与 API 24 均检测到非零像素变化。
18. 无效图片地址显示失败状态，点击重试后恢复为有效图片。
19. 静态图片可打开并关闭原生全屏预览。
20. 创建 v1 RDB，写入一条回答打开记录并注入一次 v2 迁移失败。
21. 失败事务完整回滚 schema、版本和数据，随后正确升级到 v2。
22. 关闭并重开数据库后仍为 v2，原记录和新增字段默认值保持正确。
23. 运行 19 条知乎网页、跳转链接和 `zhihu://` 完整映射矩阵，保留 19 位内容 ID 精度。
24. 使用 `ohos.want.action.viewData` 隐式 Want 冷启动应用，并解析 `Want.uri`。
25. 在应用已运行时再次发送深链，由 `UIAbility.onNewWant()` 完成热启动分发。
26. 拉起 Scan Kit 系统默认扫码页面，确认安全相机说明与系统图库入口存在。
27. 从系统扫码页返回后，应用正确显示“用户取消扫码”。
28. 使用 `detectBarcode.decode` 识别固定 600 × 600 QR 码图，并通过知乎电脑端登录 URL 策略。
29. 页面和应用日志不显示固定码图中的测试 token。

第 5 项证明 INTERNET 权限、DNS、TLS 和 HTTP 请求路径在两个 API 基线上可用，但公开请求尚未满足知乎接口的鉴权/反爬要求。P0-NET-01 需在 Cookie 会话和 ZSE96 签名接入后复测，不能因获得 403 标记为通过。

第 6–10 项在 API 20 和 API 24 上均通过，证明 P0 会话方案可以跨应用进程重启恢复，且最低兼容版本具备所需 Asset Store、Crypto Architecture Kit 和 Preferences 能力。

第 11–12 项在 API 20 和 API 24 上均通过。登录原型的完整结果和真实 Cookie 尚未完成的边界见 `login-validation.md`。

第 13–15 项证明原生长正文路径在 API 20 和 API 24 上可滚动。原生 `Image` 在 API 20 无法加载知乎返回的远程 SVG；受限 `RichText` 仅验证了块公式候选路线，真实长文公式仍未完整渲染，因此 `P0-MATH-01` 不标记通过。详细实验边界见 `reader-validation.md`。

第 16–19 项证明普通 JPEG、GIF 动画、失败恢复和原生预览在 API 20 与 API 24 上可用，`P0-IMG-01` 标记通过。公式 SVG 不计入普通图片结论，详细记录见 `image-validation.md`。

第 20–22 项证明 API 20 与 API 24 的 RDB 建库、连续版本升级、故障事务回滚和关闭重开路径可用，`P0-DB-01` 标记通过。详细 schema 和边界见 `database-validation.md`。

第 23–25 项证明 API 20 与 API 24 的纯 ArkTS URL 解析、19 位 ID 保真、`zhihu://` 系统冷启动和 `onNewWant()` 热启动路径可用，`P0-LINK-01` 标记通过。知乎 HTTPS 域名无法由本项目完成所有权校验，不计入已验证 App Linking；详细边界见 `deep-link-validation.md`。

第 26–29 项证明 API 20 与 API 24 的 Scan Kit 默认界面、取消返回和固定图片识码可用，`P0-SCAN-01` 标记通过。该结论只覆盖扫码辅助路径，不代表二维码登录会话闭环；详细边界见 `scan-kit-validation.md`。

2026-08-10 增量复测最终 Debug HAP：API 20 与 API 24 均安装启动成功，二维码 URL 安全策略矩阵为 `8/8`，固定码图识别通过且页面未显示测试 token。该次只复测本次收紧的 URL 策略与固定码图路径；系统默认扫码页和取消返回仍以 2026-07-20 的可视化记录为准。

2026-08-10 起维护基线调整为 API 24 单一版本；以上 API 20 结果仅作为历史证据保留。API 24 最终 Debug HAP 的后台任务原型完成增量验证：短时任务获批 180 秒、读取时当日剩余配额 600 秒并主动释放；延迟任务 `24001` 登记成功，最早 60 秒后触发，停止后再次枚举确认无残留。页面结果完整可读且无崩溃，`P0-BG-01` 标记通过，详细边界见 `background-task-validation.md`。

2026-08-10 签名增量复测使用 `Pura 90`（HarmonyOS 6.1.1 / API 24，系统镜像软件版本 6.1.0.126）。`devecocli build --modules entry --build-mode debug` 生成 `entry-default-signed.hap`，`SignHap` 与整体构建成功；`devecocli run --device 127.0.0.1:5555 --skip-build` 安装成功并启动 `com.github.zhuoyi233.zhplus/EntryAbility`。随后读取 UI 树，确认显示“Zhihu++ HarmonyOS”和“目标与最低兼容 API 24”，`P0-ID-01` 标记通过。详见 `signing-validation.md`。

## 复测命令

```powershell
$hdc = '<DevEco Studio>/sdk/default/openharmony/toolchains/hdc.exe'
& $hdc list targets
& $hdc shell param get const.product.software.version
& $hdc shell param get const.ohos.apiversion
& $hdc install entry/build/default/outputs/default/entry-default-unsigned.hap
& $hdc shell aa start -a EntryAbility -b com.github.zhuoyi233.zhplus
```

DevEco 本地虚拟机允许安装未签名 Debug HAP。该结果不能代替真机、发布证书和 AppGallery Connect 签名验证。

当前 P0 已额外完成本地调试签名 HAP 的安装启动；它证明调试签名链路可用，但仍不能替代 P6 的发布签名、上架和升级连续性验证。
