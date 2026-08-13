# HarmonyOS API 26 编译 / API 24 兼容本地与 CI 验证

## 验证入口

仓库使用同一个 PowerShell 入口完成本地和 CI 门禁：

```powershell
./scripts/verify-harmony.ps1
```

脚本按以下顺序执行：

1. 定位 DevEco Studio 根目录、`sdk` 根目录、内置 Node、Hvigor 和 ohpm。
2. 从 `sdk/default/sdk-pkg.json` 验证 HarmonyOS 26.0.0 / API 26，并检查工程的 `targetSdkVersion`、`compatibleSdkVersion` 均为 `6.1.1(24)`。
3. 缺少 Hypium 或 `entry` 到 `core/data/reader` 的本地模块链接时，执行内置 ohpm 的 `install --all`。
4. 使用 DevEco 内置 Node 调用 Hvigor `assembleHap`，先验证 API 26 编译的 Debug HAP；随后读取 HAP 元数据，确认 target/compatible API 均为 24。
5. 删除旧的 `test_result.txt`，再运行 Hvigor `test`，避免把上一次成功报告误判为本次结果。
6. 同时检查退出码、`BUILD SUCCESSFUL`、任务链输出和新生成的 Hypium 报告。
7. 将报告中的汇总数、逐条 `test/result` 数和 `List.test.ets` 已注册测试源码数交叉核对；失败、错误或忽略数必须全部为零。

Hvigor 的历史版本可能在测试断言失败时仍返回退出码 0，因此退出码只是门禁的一部分。权威测试汇总为：

```text
entry/.test/default/intermediates/test/coverage_data/test_result.txt
```

## 本地与 runner 参数

本地默认按以下顺序自动发现 DevEco Studio：

- `HARMONY_DEVECO_HOME`、`DEVECO_HOME` 或 `DEVECO_STUDIO_HOME` 环境变量；
- 当前用户目录下的标准安装候选；
- Windows LocalAppData 或 Program Files 下的标准安装候选。

SDK 可通过 `HARMONY_SDK_ROOT` 或 `DEVECO_SDK_HOME` 指定。该路径必须指向 `sdk` 根目录，不能指向 `sdk/default`。CI 推荐配置 runner 或 repository variable，不要把个人机器绝对路径写入仓库。

完整参数示例：

```powershell
./scripts/verify-harmony.ps1 `
  -DevEcoHome $env:HARMONY_DEVECO_HOME `
  -SdkRoot $env:HARMONY_SDK_ROOT `
  -ExpectedTestCount 0
```

`ExpectedTestCount=0` 表示从 `List.test.ets` 实际注册的测试函数计算应运行数量；传入正数会额外固定总数，源码注册数与显式值不同也会失败。`-SkipDependencyInstall` 只适合已经准备好 `oh_modules` 的离线 runner，`-SkipBuild` 只用于定位测试问题，不应作为正式 CI 门禁。

## 自托管 GitHub Actions runner

`.github/workflows/harmonyos.yml` 只调度带有以下标签的自托管 Windows runner：

```text
self-hosted, windows, x64, harmonyos-compile-api26
```

runner 前置条件：

- Windows x64 与 PowerShell 7；
- DevEco Studio 26.0.0 Beta2；
- HarmonyOS 26.0.0（API 26）SDK 完整安装；
- runner 账号可执行 DevEco 内置 Node、Hvigor 和 ohpm；
- 首次安装依赖时可以访问配置的 ohpm registry，或已有可用缓存；
- 工作目录有足够空间写入忽略的 `.hvigor/`、`oh_modules/`、`entry/build/` 和 `entry/.test/`。

workflow 实际使用 `self-hosted, windows, x64, harmonyos-compile-api26` 标签，只有 repository variable `ENABLE_HARMONYOS_API26_API24_CI` 精确等于 `true` 时 job 才会运行。应先注册并在线验证该标签的 runner，再启用变量；否则 PR job 会安全跳过，不会把没有 DevEco SDK 的 GitHub-hosted runner 置于永久失败状态。

自托管 runner 不执行来自外部 fork 的 PR 代码：PR job 还要求 head repository 与当前 repository 相同，外部贡献需由维护者审查后复制到受信分支或手动触发。workflow 权限固定为只读 contents，checkout 不持久化 GitHub token，降低自托管 runner 暴露面。

可选变量：

| 变量 | 含义 |
| --- | --- |
| `HARMONY_DEVECO_HOME` | DevEco Studio 安装根目录；留空时由脚本自动发现 |
| `HARMONY_SDK_ROOT` | HarmonyOS SDK 根目录；留空时使用 DevEco 根目录下的 `sdk` |

workflow 支持手动触发时填写 `expected_test_count`，PR 触发默认使用自动计算。路径过滤覆盖 HarmonyOS 应用源码、未来 `core/data/reader` 模块、资源、Hvigor/ohpm 配置、验证脚本和 workflow 自身。

## 签名边界

CI 的目标是编译和单元测试，不负责生成可安装发布包：

- 仓库继续保留空 `signingConfigs`，不得提交 `.p12`、`.cer`、`.p7b`、`.csr`、密码、Profile 或 `external-signing-config.json`。
- `assembleHap` 在无签名配置的 runner 上生成 unsigned HAP 即可满足编译门禁；workflow 不上传 HAP。
- 本地已有外置调试签名时，Hvigor 可能额外生成 signed HAP，但脚本不会读取、复制或打印签名配置。
- API 24 虚拟机安装验证仍由每台开发机使用自己的本地调试签名完成，与 CI 编译门禁分离。

workflow 只上传 Hypium 文本结果和覆盖率 HTML，保留 14 天；这些报告不得写入 Cookie、账号标识、原始请求或响应正文。

## 2026-08-13 本地验证结果

迁移脚本在 DevEco Studio 26.0.0 Beta2、HarmonyOS 26.0.0（API 26）环境完成完整运行：

- `entry/core/data/reader` 四模块 `assembleHap` 输出 `BUILD SUCCESSFUL`；SDK 元数据为 API 26，HAP 的 target/compatible API 元数据均为 24。
- 脚本先移除旧报告，再确认 `UnitTestArkTS`、`GenerateUnitTestResult` 和 `entry:test` 均执行完成。
- `List.test.ets` 源码注册数、报告逐条记录和报告汇总均为 237；最终 `Pass=237, Failure=0, Error=0, Ignore=0`。
- PowerShell AST、workflow YAML 和 `git diff --check` 静态验证通过。
