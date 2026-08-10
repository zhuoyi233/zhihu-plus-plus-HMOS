# P0 应用签名验证

> 验证日期：2026-08-10<br>
> 工具链：DevEco Studio 6.1.1 Release、devecocli 1.2.2<br>
> 目标与最低兼容版本：HarmonyOS 6.1.1（API 24）

## 结论

`P0-ID-01` 通过。

- Bundle Name 固定为 `com.github.zhuoyi233.zhplus`。
- `devecocli signature generate --product default` 成功生成本机调试签名材料和测试 Profile。
- `devecocli build --modules entry --build-mode debug` 完成 `SignHap`，生成 `entry-default-signed.hap`。
- 签名 HAP 在 API 24 `Pura 90` 模拟器安装成功，`EntryAbility` 启动成功。
- 启动后的 UI 树包含“Zhihu++ HarmonyOS”和“目标与最低兼容 API 24”。

本结论只覆盖本地调试签名，不代表发布证书、AppGallery Connect 上架或版本升级签名连续性已经通过。

## 版本管理与秘密边界

[HarmonyOS 官方多人协作签名 FAQ](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-signature-service-19)指出，多人开发时提交自动签名生成的绝对路径和本机加密值会造成 `signingConfigs` 冲突；签名的总体流程同时参考[配置应用签名](https://developer.huawei.com/consumer/cn/doc/App/signing-guide)。项目采用以下约束：

1. Git 跟踪 `build-profile.json5`，但 `signingConfigs` 始终提交为空数组。
2. 每台开发机自行执行 `devecocli auth login` 和 `devecocli signature generate --product default`。
3. `devecocli` 生成的 `.p12`、`.csr`、`.cer` 和 `.p7b` 保存在 `~/.ohos/config`，不复制进仓库。
4. 自动生成的本机绝对路径、密码密文和 `signingConfigs` 只在本地验证期间存在，验证后恢复仓库基线。
5. `.gitignore` 拒绝 HarmonyOS 签名材料和 `external-signing-config.json`，降低误提交风险。
6. 日志、文档和提交信息不得记录账号、口令、私钥、完整 Profile、密码密文或认证令牌。

本机密码即使以密文写入 `build-profile.json5`，仍属于机器相关签名配置，不进入版本库。

## API 24 验证证据

| 检查项 | 实测结果 | 状态 |
| --- | --- | --- |
| 模拟器 | `Pura 90` / HarmonyOS 6.1.1（API 24） | 通过 |
| 系统镜像 | phone / 软件版本 6.1.0.126 | 通过 |
| HDC | `127.0.0.1:5555` | 通过 |
| 签名生成 | p12、csr、cer、p7b 均生成到用户目录 | 通过 |
| Debug 构建 | `SignHap`、`BUILD SUCCESSFUL` | 通过 |
| 签名产物 | `entry-default-signed.hap`，469470 字节 | 通过 |
| 安装 | `App installed successfully` | 通过 |
| 启动 | `start ability successfully` | 通过 |
| UI | P0 首页与 API 24 基线文字可见 | 通过 |
| 仓库清理 | `build-profile.json5` 恢复空 `signingConfigs` | 通过 |

首次 `devecocli build` 曾把 DevEco 内置 `node.exe` 误报为未数字签名。使用 Windows Authenticode 复核为 `Valid` 后再次执行同一命令成功；若复现，应先独立校验证书状态，不应关闭 CLI 的工具链签名检查或替换不受信任的 Node 可执行文件。

## 本机复测流程

命令参数以 [deveco-cli README](https://gitcode.com/openharmony-sig/deveco-cli/blob/develop/README.md) 和本机 `devecocli <command> --help` 为准。

```powershell
devecocli auth login
devecocli emulator start "Pura 90"
devecocli device list --format json
devecocli signature generate --product default
devecocli build --modules entry --build-mode debug
devecocli run --module entry --device 127.0.0.1:5555 --skip-build
devecocli ui layout --device 127.0.0.1:5555 --format json --mode simplified
devecocli emulator stop "Pura 90"
```

运行 `signature generate` 后，提交前必须恢复 `build-profile.json5` 的空 `signingConfigs`，并检查：

```powershell
git status --short
git diff -- build-profile.json5
git ls-files "*.p12" "*.cer" "*.p7b" "*.csr" "external-signing-config.json"
```

最后一条命令应无输出。

## P6 后续门禁

- 申请和隔离发布证书，不复用个人调试证书。
- 在受保护的 CI/发布环境注入签名材料，禁止写入仓库和普通构建日志。
- 验证 release APP/HAP、AppGallery Connect 上架检查和发布权限。
- 验证同一发布身份下的覆盖安装、版本升级和回滚策略。
- 建立证书到期、轮换、吊销和应急恢复流程。
