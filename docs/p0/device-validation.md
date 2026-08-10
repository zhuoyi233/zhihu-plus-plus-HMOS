# P0 DevEco 虚拟机验证记录

> 首次验证：2026-07-20；API 24 最终复测：2026-08-11

## 当前设备基线

| 虚拟机 | HarmonyOS | API | 分辨率 | 结果 |
| --- | --- | --- | --- | --- |
| `ZhihuPlus_API24`（Pura 90） | 6.1.1，镜像软件版本 6.1.0.126 | 24 | 1320 × 2856 | 通过 |

从 2026-08-10 起，新增实现、缺陷修复和验收只使用 API 24。早期 API 20 结果仅保留在 Git 历史中，不再构成兼容、发布或维护门禁。

## 最终设备结果

API 24 虚拟机完成以下闭环：

1. `devecocli` 启动设备，并由 HDC 暴露为模拟器目标。
2. 构建、签名、安装并启动 `com.github.zhuoyi233.zhplus/EntryAbility`。
3. HTTPS 请求到达知乎并完成 403 认证分类；真实取消后页面保持“已取消”，没有旧回调覆盖。
4. 真实 Cookie 通过 `/api/v4/me` 校验后才写入 AES-256-GCM 加密会话。
5. 强制停止并重启应用后恢复登录态；退出后立即清理会话，再次重启保持游客态。
6. 真实长回答解析为 112 个原生块并滚动到文末，全程不使用整页 ArkWeb。
7. 11 个块公式与 63 个行内公式全部由 NetworkKit、ImageSource 和 PixelMap 原生链路解码，无节点降级或崩溃。
8. 真实 JPEG、GIF、失败重试和原生全屏预览通过。
9. RDB v1→v2 升级、故障事务回滚、关闭重开与数据保留通过。
10. 深链安全策略及映射矩阵 `19/19` 通过，冷启动和 `onNewWant()` 热启动分发通过。
11. Scan Kit 默认扫码、取消返回、固定图识码和二维码 URL 安全策略 `8/8` 通过。
12. 短时任务、延迟任务登记与停止清理通过，设备没有残留后台任务。

验证只读取必要的状态文案，不记录或导出 Cookie 值。真实登录会话已在最终复测结束时退出并清理。

## 门禁对应关系

| 范围 | 结论 | 记录 |
| --- | --- | --- |
| 工具链、签名、设备 | 通过 | `environment-baseline.md`、`signing-validation.md` |
| HTTP、ZSE、登录、会话 | 通过 | `network-validation.md`、`zse-validation.md`、`login-validation.md`、`session-validation.md` |
| 正文、公式、图片 | 通过 | `reader-validation.md`、`image-validation.md` |
| RDB、深链、扫码、后台 | 通过 | `database-validation.md`、`deep-link-validation.md`、`scan-kit-validation.md`、`background-task-validation.md` |

## 复测命令

```powershell
devecocli emulator start ZhihuPlus_API24
devecocli build --modules entry --build-mode debug
devecocli run --device 127.0.0.1:5555 --skip-build
devecocli ui layout --device 127.0.0.1:5555 --mode simplified
devecocli emulator stop ZhihuPlus_API24
```

本地调试签名和 DevEco 虚拟机结果不能替代 P6 的发布证书、AppGallery Connect、真机相机以及升级连续性验证。
