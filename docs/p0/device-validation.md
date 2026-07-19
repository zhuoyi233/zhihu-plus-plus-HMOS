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

第 5 项证明 INTERNET 权限、DNS、TLS 和 HTTP 请求路径在两个 API 基线上可用，但公开请求尚未满足知乎接口的鉴权/反爬要求。P0-NET-01 需在 Cookie 会话和 ZSE96 签名接入后复测，不能因获得 403 标记为通过。

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
