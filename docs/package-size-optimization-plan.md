# HarmonyOS 安装包体积优化计划

> 制定日期：2026-09-29  
> 目标分支：`codex/phase-prefix-removal`  
> 检查时 HEAD：`ace78dc586643ea7b4a9a4e7bcf2ce50f4cd0045`  
> 应用版本：`0.5.6`  
> 状态：阶段一（体积基线）与阶段二（Release 出包分离）已完成（2026-09-29）；阶段三起待实施

## 1. 目标与实施顺序

优先修正发行包的构建方式，再通过混淆和排除诊断功能缩小字节码。保持正式功能、用户数据兼容性，以及 HarmonyOS 6.1.0（API 23）最低运行要求。

实施顺序：

1. 建立可复现的包体积报告。
2. 分开 Debug 验证与 Release 出包流程，保存新的体积基线。
3. 逐步开启代码混淆，测量收益并验证运行行为。
4. 按收益决定是否将技术实验室与诊断功能从发行包排除。
5. 最后评估资源精简，并加入持续体积检查。

每个阶段单独比较前后产物。第一轮以完成步骤 1、2 为范围，不预先承诺最终缩包比例。

## 2. 现状与证据

### 2.1 测量口径

本次直接读取工作树中的现有 HAP ZIP 目录与包内元数据，没有重新构建。检查时源码工作树没有改动，但现有产物与 HEAD 的严格对应关系尚未通过重新构建确认。

测量对象：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

- 文件大小：7,891,004 字节，约 **7.53 MiB**。
- 包内版本：`0.5.6`，`versionCode = 1000506`。
- 包内构建属性：`buildMode = debug`、`debug = true`。
- 已检查条目的 `CompressedLength` 与 `Length` 相同。
- 以下体积表示安装包文件大小，不表示安装后的磁盘占用或运行内存。

| 内容 | 字节数 | 占 HAP 比例 |
| --- | ---: | ---: |
| `ets/modules.abc` | 5,376,664 | 68.1% |
| `ets/sourceMaps.map` | 2,415,539 | 30.6% |
| 其他内容与 ZIP 开销 | 98,801 | 1.3% |
| 合计 | 7,891,004 | 100% |

其中更新清单共 36,483 字节，应用图标 28,395 字节，`reader_probe.html` 为 19,414 字节，fixtures 合计 3,908 字节。

### 2.2 已确认的问题

- `scripts/verify-harmony.ps1` 将 `$script:BuildMode` 固定为 `debug`，完整验证构建 Debug HAP，并复制为带版本号的产物。
- 脚本在测试结束后调用 `Copy-ReleaseArtifacts`，`-SkipBuild` 路径也会走到此处。改造时需避免把旧包误作为本次构建结果。
- `entry/build-profile.json5` 的 Release 混淆配置为 `enable: false`；`entry/obfuscation-rules.txt` 只有占位注释。
- `Index.ets` 静态引用多个 Probe 页面；现有包的源码映射确认相关诊断代码已经参与编译。
- `entry/src/main/module.json5` 注册了 `WorkSchedulerProbeExtensionAbility`。
- 当前生产依赖是本地 `core`、`data`、`reader` 三个 HAR，没有发现大型第三方运行库或 `.so` 文件。
- 四模块已设置 `copyCodeResource.enable = false`，不是本轮新增优化点。

## 3. 阶段一：建立体积基线

### 工作项

- [x] 新增或扩展 PowerShell 7 分析脚本，读取 HAP ZIP 目录和 `module.json`。（`scripts/analyze-hap-size.ps1`）
- [x] 报告总字节数、条目原始/存储大小、字节码、映射、资源分类及最大文件。
- [x] 记录源码 SHA、工作区是否有改动、工具链版本、构建模式、应用版本、产物 SHA-256。
- [x] 使用同一源码和工具链重新构建 Debug 基线；构建前归档需要比较的现有包，避免输出目录覆盖。
- [x] 将报告保存在构建产物目录；文档只保留摘要，不提交 HAP、缓存或映射文件。

### 实施与验证记录（2026-09-29）

- 新增 `scripts/analyze-hap-size.ps1`：读取 HAP ZIP 条目与包内 `module.json`/`pack.info`，按字节码、映射、
  包元数据、更新清单、诊断资源、其余资源分类汇总；记录产物 SHA-256、源码 commit 与已跟踪改动状态、
  工具链版本（DevEco/SDK/Node/Hvigor）与包内 `buildMode`/`debug` 字段；`-CompareWith` 与历史报告逐条目
  对比并按大小排序列出变化、新增、移除条目；脚本内置"分项合计 + ZIP 开销 = 文件总字节数"自校验。
- 现有包报告：`entry/build/default/outputs/default/size-reports/existing-debug-ace78dc5.size-report.json`
  （另存同名 `.summary.txt`），各项数字与第 2 节手工盘点一致。
- 重建前将输出目录 4 个 HAP（含 `ZhihuPlusPlus-HMOS-v0.5.6-*.hap` 版本命名副本）归档至
  `entry/build/default/outputs/default/archive-stage1-baseline-20260929-195319/`。
- 重建：以与 `verify-harmony.ps1` 相同的参数直接调用 hvigor（`assembleHap --mode module -p
  module=entry@default -p product=default -p buildMode=debug --no-daemon`；SDK 26.0.0，Node v24.14.1），
  实际为增量构建（39 执行 / 18 复用，35 秒）。重建包报告：`size-reports/rebuilt-debug-ace78dc5.size-report.json`。
- 对比结果：总大小 7,891,004 字节不变，20 个条目的大小与内容哈希逐项一致；文件级 SHA-256 不同
  （`701f9eea…` → `2a67b7a8…`），经逐条目核对差异仅来自 ZIP 本地头时间戳（20/20 条目时间戳不同）。
  即 Debug 构建在内容级可复现，不可复现部分只有打包时间戳。
- 补充事实：包内全部条目为 Stored 存储（未压缩），ZIP 开销仅 2,812 字节，包内压缩改造无收益空间；
  重建后版本命名副本 `ZhihuPlusPlus-HMOS-v0.5.6-*.hap` 不会自动重新生成（该复制属于
  `verify-harmony.ps1` 的 `Copy-ReleaseArtifacts`，阶段二重构出包流程时统一处理）。
- Hypium 与 API 23 回归本阶段未执行（阶段一不含），见第 8 节登记表。

### 验收标准

报告能指出具体由哪些条目造成体积变化；分项统计加上 ZIP 开销能与文件总字节数对应。后续均以未签名 HAP 比较，签名包只用于设备运行验证。

阶段一验收情况：对比模式逐条目列出变化、新增与移除（本次均为 0）；分项合计 7,888,192 + ZIP 开销
2,812 = 7,891,004，与文件总字节数吻合，脚本断言通过。

## 4. 阶段二：Release 出包与调试验证分离

### 工作项

主要涉及 `scripts/verify-harmony.ps1`，必要时新增独立的发行构建脚本。

- [x] 保持日常 Debug 验证入口，提供显式的 Release 出包入口或构建模式参数。（新增 `-BuildMode`，默认 `debug`）
- [x] 将测试使用的构建参数与发行 HAP 使用的参数分离，核实当前工具链的 Hypium 模式支持。
  （核实结果：`hvigor test` 支持 `buildMode=release`，实测 704/704 通过，**无需分离**，测试与发行 HAP 共用同一模式参数）
- [x] 第一轮保持混淆关闭，只测量 Debug → Release 本身的效果。
- [x] 用明确的 unsigned/signed 产物路径校验结果，避免仅按目录内最新修改时间挑选 HAP。（固定校验 `entry-default-unsigned.hap`）
- [x] `-SkipBuild` 仅执行相应验证，不把旧 HAP 复制或标记为本次发行结果。（复制逻辑移入"本次有构建且为 Release"分支）
- [x] 仅在本次 Release 构建和验证成功后，复制 `ZhihuPlusPlus-HMOS-v<version>-unsigned.hap`。（Debug 验证不再产出/覆盖版本命名产物）
- [x] 检查最终 HAP 的版本号、bundleName、API 版本、`buildMode` 与 `debug` 字段。（版本号与 `AppScope/app.json5` 核对）
- [x] 确认发行 HAP 不包含 `ets/sourceMaps.map`；按版本和产物哈希单独归档映射，供崩溃定位使用。
  （实测 release 构建本就不打包映射；脚本新增断言防回归，映射归档至 `mapping-archive/v<version>-<SHA前8位>/`）
- [x] 防止后续测试或 Debug 构建覆盖已验证的发行产物，交付前再次核对哈希。（复制时与交付前各核对一次）

### 实施与验证记录（2026-09-29）

- `verify-harmony.ps1` 改造：新增 `-BuildMode`（`debug`/`release`，默认 `debug`，原行为不变）；构建产物改按
  `entry-default-unsigned.hap` 明确路径校验；`Assert-HapApiVersions` 扩展为同时校验包内 `module.json` 的
  `buildMode`/`debug`/`versionName`/`versionCode`（与 `AppScope/app.json5` 核对）；Release 模式增加
  `Assert-HapNoSourceMap` 断言与 `Copy-ReleaseMappingArchive` 映射归档；`Copy-ReleaseArtifacts` 仅在
  Release 构建且 Hypium 通过后调用，复制前后核对 SHA-256，流程末尾再次核对版本命名产物与本次构建产物一致；
  `-SkipBuild` 不再触发任何复制。AGENTS.md 的构建命令与发布产物说明已同步更新。
- Hypium 模式核实：`hvigor test -p buildMode=release` 实测通过（704/704），测试与发行 HAP 使用同一
  `buildMode` 参数，无需拆分。
- Release 出包全流程（`verify-harmony.ps1 -SkipDependencyInstall -BuildMode release`）通过：
  构建 → 无映射断言 → 元数据断言 → 映射归档 → Hypium 704/704 → 版本命名产物复制与交付前哈希核对。
- 实测体积（`size-reports/release-obfoff-3d4e3f2d.size-report.json`，对比 Debug 基线）：
  **7,891,004 → 3,106,172 字节，减少 4,784,832 字节（-60.6%）**，约 2.96 MiB。条目级差异干净：
  `ets/modules.abc` 5,376,664 → 3,007,480（Release 字节码 -2,369,184），`ets/sourceMaps.map` 2,415,539 → 0
  （移出包外），`module.json` 仅 +3 字节（"debug"→"release"）。发行产物 SHA-256：
  `4ada8c666fbf64184f2a21a9ade6d22a5f79db6b86a88303cfddb0619b86fc29`。
- API 23 模拟器（`ZhihuPlus_API23`，`127.0.0.1:5555`）烟测通过：覆盖安装 Release 签名包（未清数据）→
  冷启动首页 `home_feed_list` 正常加载且无登录错误节点（登录态保留）→ 底栏切日报
  （`top_level_daily_content` 及日报内容可见）→ 深链热启动直达问题详情页（`question_detail`）。

### 收益与验收

规划时仅从现有 HAP 扣除源码映射，估算为 5,475,465 字节（约 5.22 MiB，-30.6%）。该估算未计入 Release
字节码变化；实测 Release（混淆关闭）为 **3,106,172 字节（约 2.96 MiB，-60.6%）**，收益远超估算——
Release 字节码本身比 Debug 缩小 2,369,184 字节。估算值已被实测值取代，详见上方实施与验证记录。

验收要求（2026-09-29 全部满足）：

- [x] Release 元数据正确（`buildMode=release`、`debug=false`、版本与 bundleName 与清单一致），映射文件在包外归档。
- [x] 与新构建的 Debug 基线相比体积下降（-60.6%，条目级差异干净，无需进一步解释）。
- [x] API 23 上安装、冷启动、登录态恢复及主要页面烟测通过。
- [x] 记录真正生成的 Release 体积，替换估算值。

## 5. 阶段三：逐步启用混淆

### 工作项

主要涉及 `entry/build-profile.json5` 与 `entry/obfuscation-rules.txt`。

- [ ] 先核实当前 SDK/ArkGuard 支持的混淆方式和选项，选择一条明确的配置路线。
- [ ] 从基础混淆开始，再逐项评估顶层名称、文件名、导出名称和属性名混淆。
- [ ] 为外部 JSON 字段、序列化/持久化字段、动态属性访问、系统入口与字符串引用补齐保留规则。
- [ ] 结合 `core/Index.ets`、`data/Index.ets`、`reader/Index.ets` 检查跨模块导出边界。
- [ ] 将名称映射与源码映射一起归档，并确认能够用于还原错误堆栈。
- [ ] 对照阶段二的未混淆 Release，记录字节码与总包大小变化。

### 验收标准

Hypium 全量通过，并用实际混淆后的 Release HAP 完成设备回归。重点覆盖登录、接口解码、偏好设置恢复、数据库读写、搜索、详情、评论和发布流程；涉及外发操作的验证使用测试替身或停在发送前，实际发送另行取得授权。

不以“编译通过”代替运行验证。混淆收益尚未测量；某组选项出现行为异常时，保留此前通过验证的配置，定位缺失的保留规则。

## 6. 阶段四：按构建配置排除诊断功能

### 候选范围

- `TechnicalLabPage` 及专用于诊断的 Reader、Image、Database、DeepLink、QrScan、BackgroundTask、DomainFixture Probe 页面。
- `DatabaseProbe`、`HttpProbeClient`、`DomainFixtureValidator`、`QrScanFixture` 等专用支持代码。
- `WorkSchedulerProbeExtensionAbility` 及其模块声明。
- `rawfile/reader_probe.html` 和 `rawfile/fixtures/`。

### 工作项

- [ ] 梳理候选代码的实际引用，区分正式功能与诊断专用功能。
- [ ] 保留 Debug 诊断能力，通过构建配置或独立入口，使发行构建不再引用诊断实现。
- [ ] 同步处理 `Index.ets`、`AppShell.ets`、路由、HAR 导出和 `module.json5`，消除残留入口。
- [ ] 常用手动 Cookie 登录能力独立保留；正式扫码登录、链接直达、阅读和后台业务能力不随 Probe 一并删除。
- [ ] 将仅用于测试的资源移至适当的测试或开发构建资源集，并验证对应工具链支持。
- [ ] 检查构建依赖清单/映射及最终 HAP，确认诊断代码与资源确实不再入包。

### 收益与验收

已知诊断 HTML 与 fixtures 共 23,322 字节，约 22.8 KiB；诊断代码的字节码贡献尚未单独测量。仅隐藏开发者菜单不算完成裁剪。

正式入口没有失效路由，Debug 仍能运行诊断功能，Release 主要功能回归通过。若实际收益不足以支持增加的维护成本，记录结论并暂缓此阶段。

## 7. 阶段五：资源精简与持续检查

- [ ] 在前述措施完成后，再评估图标无损优化和更新清单格式精简。
- [ ] 保留离线“本版本更新内容”体验，以及两份更新清单的同步生成机制。
- [ ] 发布构建输出体积报告，比较上一版及本次基线。
- [ ] 先对体积增长发出提示，积累实测数据后制定合理阈值；Release 模式错误、映射误入包、版本/API 不匹配则直接阻止出包。

当前图片和更新清单合计不足 65 KiB，优先级较低。现有包没有原生库，暂不投入 `.so` 压缩或 ABI 裁剪；只有一个 HAP，也没有证据支持为缩包将三个 HAR 改为 HSP。暂不通过手工重压 HAP 或改为按需分发改变安装方式。

## 8. 验证与交付

### 执行顺序

实施代码或构建脚本变更后，按项目要求先执行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

随后使用阶段二实现的发行入口构建、校验 Release HAP：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -BuildMode release
```

该入口已实现并实测通过（见第 4 节记录）；上面现有命令生成 Debug 验证包，不产出版本命名发行产物。

- Hypium 用例数由 `entry/src/test/List.test.ets` 动态统计，记录实际通过数。
- 默认设备为 `ZhihuPlus_API23`（`127.0.0.1:5555`）；多设备时显式指定目标。
- 按阶段覆盖安装/升级、冷启动、登录态恢复、首页、搜索、详情、评论、主题和更新说明；混淆阶段补充数据兼容与相关功能回归。
- 用本机签名包做设备测试；分发产物保持未签名 HAP。
- 本轮计划不包含版本升级、提交、推送或发布 Release。

### 结果登记

| 阶段 | 未签名 HAP 字节数 | 相对上阶段变化 | Hypium | API 23 回归 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| 检查时现有 Debug 包 | 7,891,004 | — | 本轮未执行 | 本轮未执行 | 已读取产物，重建前已归档 |
| 重新构建 Debug 基线 | 7,891,004 | 0 字节（条目级一致） | 未执行（阶段一不含） | 未执行（阶段一不含） | 已完成（2026-09-29） |
| Release，混淆关闭 | 3,106,172 | -60.6%（相对 Debug 基线） | 704/704（release 模式） | 通过（烟测） | 已完成（2026-09-29） |
| Release，开启混淆 | 待测 | 待测 | 待执行 | 待执行 | 待实施 |
| Release，排除诊断功能 | 待测 | 待测 | 待执行 | 待执行 | 待评估 |

## 9. 依据

- 工作树构建脚本、模块配置、依赖清单、页面引用，以及现有 HAP 的 ZIP 条目与 `module.json`。
- 通过 `devecocli docs read` 核对的本地华为文档：
  - `最佳实践/性能场景优化案例/资源与存储优化/应用包体积优化/bpta-decrease_pakage_size`。
  - `开发指南/ArkTS_方舟编程语言/ArkTS编译工具链/ArkGuard字节码混淆工具/ArkGuard字节码混淆工具概述/bytecode-obfuscation-overview`。

当前证据足以确定优化优先级。除现有 Debug 包分项统计外，所有优化效果均需实施后重新构建确认。
