# P0 环境基线

> 检查日期：2026-07-20

## 已确认

| 项目 | 结果 | 状态 |
| --- | --- | --- |
| DevEco Studio | 6.1.1.280 Release | 通过 |
| HarmonyOS SDK | 6.1.1.125 Release / API 24 | 通过 |
| `targetSdkVersion` | 6.1.1（API 24） | 通过 |
| `compatibleSdkVersion` | 6.0.0（API 20） | 通过 |
| 工程模型 | Stage / Empty Ability | 通过 |
| Node.js | 18.20.1（DevEco 内置） | 通过 |
| ohpm | 6.1.2.268 | 通过 |
| Hvigor | 6.24.2 | 通过 |
| HDC | 3.2.0d | 通过 |
| 命令行 Debug HAP 构建 | `BUILD SUCCESSFUL` | 通过 |
| ArkTS 单元测试 | 21 个用例，失败 0 | 通过 |

## 构建环境要求

本机 DevEco Studio 可以在 IDE 内自动定位 SDK，但外部终端没有配置有效的 `DEVECO_SDK_HOME`。命令行构建必须让该变量指向 HarmonyOS SDK 根目录，然后运行：

```powershell
$env:DEVECO_SDK_HOME = '<DevEco Studio>/sdk'
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' `
  --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  assembleHap `
  --no-daemon
```

不得把个人机器绝对路径写入受版本控制的 `local.properties`。CI 后续通过 Secret/Runner 环境配置 SDK 根目录。

## 尚未通过的门禁

| 项目 | 当前情况 | 后续动作 |
| --- | --- | --- |
| Bundle Name | `com.github.zhuoyi233.zhplus` | 通过 |
| HAP 签名 | 尚无 `signingConfigs` | Bundle Name 确认后由用户在 DevEco 完成华为账号授权和签名配置 |
| API 20 设备 | `ZhihuPlus_API20`，HarmonyOS 6.0.0（API 20） | 通过 |
| API 24 设备 | `ZhihuPlus_API24`，HarmonyOS 6.1.1（API 24） | 通过 |
| 安装与启动 | 两个 DevEco 虚拟机均可安装并启动 Debug HAP | 通过 |

## 发现与决定

- DevEco Studio 6.1.1 官方模板不写 `compileSdkVersion` 字段；实际编译 SDK 由构建环境中的 API 24 SDK 决定。
- 工程显式配置 `targetSdkVersion` 为 API 24、`compatibleSdkVersion` 为 API 20。
- API 21–24 专属能力必须有运行时版本判断和 API 20 降级路径。
- 正式 Bundle Name 固定为 `com.github.zhuoyi233.zhplus`，后续签名、应用市场和深链配置统一使用该标识。
- 当前产物为 `entry-default-unsigned.hap`；未签名产物不能计入签名门禁通过。
- DevEco 虚拟机允许安装未签名 Debug HAP，因此虚拟机安装启动门禁已通过；真机和发布签名仍需单独验证。
- 两台本地虚拟机的详细记录见 `device-validation.md`。
