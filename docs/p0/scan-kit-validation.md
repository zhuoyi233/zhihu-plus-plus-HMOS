# P0-SCAN-01 Scan Kit 与二维码登录辅助验证

> 首次验证：2026-07-20；API 24 最终复测：2026-08-10
> 工具链：DevEco Studio 6.1.1 Release，HarmonyOS 6.1.1（API 24）

## 结论

`P0-SCAN-01` 通过。HarmonyOS 的 Scan Kit 可以在 API 24 上拉起系统默认扫码界面，也可以识别应用沙箱中的固定 QR 码图；因此“本机扫描电脑端知乎登录二维码”的技术路径成立。

这不是完整的二维码登录闭环。P0 原型不会向知乎发送登录确认请求，也没有实现“本机生成二维码并轮询登录状态”。后者仍需接入统一 HTTP 客户端、风控处理和 Session Repository；`P0-LOGIN-01` 已由真实手动 Cookie 路径独立完成。

## 官方能力依据

- [Scan Kit 官方介绍](https://developer.huawei.com/consumer/cn/sdk/scan-kit)列出默认扫码界面、图像识码、码图生成和验证登录等场景。
- DevEco 6.1.1 本地 SDK 中，`scanBarcode.startScanForResult` 与 `detectBarcode.decode` 均可用于本项目 API 24 基线。
- [华为 Scan Kit ArkTS 官方示例](https://gitee.com/harmonyos_samples/scan-kit_-sample-code_-clientdemo_-arkts)使用 `@kit.ScanKit` 的 `scanBarcode`、`scanCore` 和 `detectBarcode`。示例只为自定义扫码声明相机权限；默认界面扫码由系统安全扫码页面托管。

本项目使用默认界面扫码，不申请 `ohos.permission.CAMERA`。系统页面明确提示应用只能获得二维码/条形码生成的信息，无法访问取景内容。相册入口由系统扫码页提供。

Scan Kit 是 HarmonyOS 系统能力调用。本项目没有引入端侧 AI SDK、模型文件、推理代码或训练资产；二维码识别不扩展为 Android 版被移除的端侧 AI 功能。

## Android/Lite 行为拆分

Android 当前代码包含两个不同方向：

1. `QRCodeScanActivity` 使用 ZXing 扫描 `https://www.zhihu.com/account/scan/login/` 链接，再交给应用内 WebView 处理电脑端登录确认。
2. `QrLogin.kt` 请求知乎二维码、在本机显示码图、轮询 `scan_info`，成功后同步 `z_c0` 等 Cookie。

HarmonyOS 迁移必须保持这两个方向独立：

| 方向 | P0 状态 | 后续落点 |
| --- | --- | --- |
| 本机扫描电脑端登录码 | Scan Kit 默认界面与 URL 策略已验证 | 登录确认页/请求、风控、成功反馈 |
| 本机显示登录码供其他设备扫描 | 仅完成 Android 契约盘点 | QR 创建、轮询、超时、风控、Cookie 汇入 Session Repository |

不能用“已识别二维码”代替登录成功，也不能把扫描得到的 URL 直接当作任意网页打开。

## 原型实现

- `QrScanProbePage` 调用 `scanBarcode.startScanForResult`，只允许 `QR_CODE`，关闭多码，保留系统相册入口。
- `QrLoginScanPolicy` 对扫描内容进行纯 ArkTS 校验：只接受 HTTPS、精确主机 `www.zhihu.com`、精确路径 `/account/scan/login/{token}`。
- 固定 600 × 600 QR fixture 只包含非敏感 P0 测试 URL。应用将其写入沙箱缓存，再调用 `detectBarcode.decode`，不依赖网络或虚拟摄像头画面。
- 页面只显示成功、取消或错误摘要；不显示登录 token，不记录扫描原文。
- 取消错误码映射为“用户取消扫码”，其他错误仅显示错误码。

## API 24 验证矩阵

| 检查项 | 结果 |
| --- | --- |
| 安装并启动 Debug HAP | 通过 |
| 拉起 Scan Kit 系统默认扫码页 | 通过 |
| 系统页显示安全相机说明和图库入口 | 通过 |
| 返回键触发取消结果 | 通过 |
| `detectBarcode.decode` 识别固定 QR fixture | 通过 |
| 识别值通过知乎登录 URL 策略 | 通过 |
| 页面不显示 fixture token | 通过 |

API 24 虚拟机的固定码图识别为单个 QR 结果。P0 不把虚拟机识码耗时作为真机性能基线。

页面同时内置 8 条 URL 安全策略矩阵，Hypium 中保留相同规则的单元用例。2026-08-10 已找到并固化 DevEco 内置 Hvigor `test` 任务，46 个 Hypium 用例失败 0；二维码策略的 4 个用例全部通过。

2026-08-10 使用最终 Debug HAP 在 `ZhihuPlus_API24` 增量复测：页面显示 `8/8` 条策略通过，并成功识别固定码图。该次复测新增拒绝重复路径分隔符和尾随分隔符；系统默认扫码页及取消返回沿用 2026-07-20 的可视化验证结果，未因本次纯 URL 策略收紧重新计入结论。

同日将深链、二维码和公式来源统一切换到不依赖系统 URL Kit mock 的纯 ArkTS 绝对 URL 解析器；最终 HAP 在 API 24 复测仍显示深链 `19/19`、二维码策略 `8/8`。

## 安全与产品边界

- 不接受 HTTP、相似域名、普通知乎内容 URL、空值或超过 4096 字符的码值。
- 不在日志、页面、测试报告中保存真实登录 token。
- 不自动提交扫码确认；进入真实登录动作前必须提供明确的用户确认和取消路径。
- 默认扫码不新增相机权限。若未来改为自定义扫码，必须重新进行权限、隐私说明、前后台生命周期和虚拟机/真机验证。
- 虚拟机验证覆盖系统页面调用、取消和确定性图像识别，不代表真实设备的对焦、暗光、污损码或相机性能。

## P1/P2 后续任务

1. 将 Scan Kit 调用收敛到窄接口 `QrScanner`，页面不直接依赖平台 API。
2. 明确电脑端登录确认是使用受限 ArkWeb 还是专用网络请求；两种方案都必须校验域名、处理风控并禁止任意跳转。
3. 迁移 Android 的二维码创建/轮询协议，使用统一 Cookie 容器并接入加密 Session Repository。
4. 增加已扫描、待确认、已确认、过期、取消、风控和网络失败状态机测试。
5. 在真实 HarmonyOS 手机补测相机、相册、前后台切换和弱光场景。
