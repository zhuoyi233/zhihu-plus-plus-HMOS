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

第 5 项证明 INTERNET 权限、DNS、TLS 和 HTTP 请求路径在两个 API 基线上可用，但公开请求尚未满足知乎接口的鉴权/反爬要求。P0-NET-01 需在 Cookie 会话和 ZSE96 签名接入后复测，不能因获得 403 标记为通过。

第 6–10 项在 API 20 和 API 24 上均通过，证明 P0 会话方案可以跨应用进程重启恢复，且最低兼容版本具备所需 Asset Store、Crypto Architecture Kit 和 Preferences 能力。

第 11–12 项在 API 20 和 API 24 上均通过。登录原型的完整结果和真实 Cookie 尚未完成的边界见 `login-validation.md`。

第 13–15 项证明原生长正文路径在 API 20 和 API 24 上可滚动。原生 `Image` 在 API 20 无法加载知乎返回的远程 SVG；受限 `RichText` 仅验证了块公式候选路线，真实长文公式仍未完整渲染，因此 `P0-MATH-01` 不标记通过。详细实验边界见 `reader-validation.md`。

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
