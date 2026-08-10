# P0 环境基线

> 首次检查：2026-07-20；基线更新：2026-08-11

## 已确认

| 项目 | 结果 | 状态 |
| --- | --- | --- |
| DevEco Studio | 6.1.1.280 Release | 通过 |
| HarmonyOS SDK | 6.1.1.125 Release / API 24 | 通过 |
| `targetSdkVersion` | 6.1.1（API 24） | 通过 |
| `compatibleSdkVersion` | 6.1.1（API 24） | 通过 |
| 工程模型 | Stage / Empty Ability | 通过 |
| Node.js | 18.20.1（DevEco 内置） | 通过 |
| ohpm | 6.1.2.268 | 通过 |
| Hvigor | 6.24.2 | 通过 |
| HDC | 3.2.0d | 通过 |
| 命令行签名 Debug HAP 构建 | `devecocli build` / `BUILD SUCCESSFUL` | 通过 |
| ArkTS 单元测试 | 46 个 Hypium 用例，失败 0 | 通过 |

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

本地 Hypium 任务可由 DevEco 内置 Node 与 Hvigor 执行；`DEVECO_SDK_HOME` 必须指向 `sdk` 根目录，不能指向 `sdk/default`：

```powershell
$env:DEVECO_SDK_HOME = '<DevEco Studio>/sdk'
& '<DevEco Studio>/tools/node/node.exe' `
  '<DevEco Studio>/tools/hvigor/bin/hvigorw.js' `
  test --mode module `
  -p 'module=entry@default' `
  -p 'product=default' `
  -p 'buildMode=debug'
```

2026-08-11 P0 收口结果为 `UnitTestArkTS`、`GenerateUnitTestResult` 和 `entry:test` 全部完成，46 个用例无断言失败；测试任务耗时 33.997 秒，其中 ArkTS 用例执行 26.719 秒。Hvigor 历史版本可能在断言失败时仍返回退出码 0，CI 必须同时检查测试报告内容。

同一次 `devecocli build --modules entry --build-mode debug` 完成 `SignHap` 并在 28.750 秒内构建成功。该数字包含 Hvigor daemon 启动且多数任务命中缓存，只作为本机增量构建烟测，不承诺 CI 或全量构建时延。

## 门禁状态

| 项目 | 当前情况 | 后续动作 |
| --- | --- | --- |
| Bundle Name | `com.github.zhuoyi233.zhplus` | 通过 |
| HAP 签名 | `devecocli` 本机调试签名，仓库保留空 `signingConfigs` | 通过 |
| API 24 设备 | `Pura 90`，HarmonyOS 6.1.1（API 24） | 通过 |
| 安装与启动 | API 24 DevEco 虚拟机可安装并启动签名 Debug HAP | 通过 |

## 发现与决定

- DevEco Studio 6.1.1 官方模板不写 `compileSdkVersion` 字段；实际编译 SDK 由构建环境中的 API 24 SDK 决定。
- 工程显式配置 `targetSdkVersion` 和 `compatibleSdkVersion` 均为 API 24。
- 从 2026-08-10 起，新增功能、缺陷修复和验收只考虑 API 24，不再为 API 20 编写版本判断、降级实现或回归用例。
- 正式 Bundle Name 固定为 `com.github.zhuoyi233.zhplus`，后续签名、应用市场和深链配置统一使用该标识。
- `P0-ID-01` 已用 `entry-default-signed.hap` 完成 API 24 虚拟机安装和启动；发布证书与 AppGallery Connect 流程仍属于 P6。
- 根据 HarmonyOS 官方多人协作 FAQ，Git 只保留空 `signingConfigs`；每台开发机通过 `devecocli signature generate` 生成自己的本地调试配置。生成后的绝对路径、密码密文、私钥、证书和 Profile 均不得提交。
- HarmonyOS 签名材料扩展名和 `external-signing-config.json` 已加入 `.gitignore`，本机材料保存在用户目录而非仓库。完整命令、验证证据和边界见 `signing-validation.md`。
- API 20 的既有验证记录仅作为历史证据保留，不再构成发布或维护门禁。设备详细记录见 `device-validation.md`。
