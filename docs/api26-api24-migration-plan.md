# DevEco Studio 26 / API 26 编译与 API 24 兼容迁移方案

> 制定日期：2026-08-13<br>
> 当前分支：`dev`<br>
> 当前工程基线：DevEco Studio 6.1.1 Release、HarmonyOS 6.1.1（API 24）<br>
> 新编译环境：DevEco Studio 26.0.0 Beta2、HarmonyOS 26.0.0 Beta2（API 26）<br>
> 最低兼容版本：HarmonyOS 6.1.1（API 24）<br>
> Bundle Name：`com.github.zhuoyi233.zhplus`<br>
> 范围：工具链、SDK、编译兼容与回归验证；不增加端侧 AI

## 1. 迁移结论

项目采用“API 26 编译、API 24 最低兼容、API 24 目标行为”的过渡路线：

| 维度 | 迁移后配置 | 说明 |
| --- | --- | --- |
| DevEco Studio | 26.0.0 Beta2 | 使用当前已安装的新 Studio |
| 编译 SDK | HarmonyOS 26.0.0 Beta2（API 26） | 由 DevEco Studio 配套 SDK 决定，不在工程中硬编码个人 SDK 路径 |
| `targetSdkVersion` | `6.1.1(24)` | 迁移工具链期间保持 API 24 行为；升级目标行为另行立项 |
| `compatibleSdkVersion` | `6.1.1(24)` | API 24 仍为最低安装与运行版本 |
| 运行验证 | API 24 + API 26 | API 24 验证最低兼容，API 26 验证新系统行为 |
| 发布 | 暂不使用 Beta 工具链发布正式版 | Beta 阶段只做开发、邀请测试和兼容验证 |

华为官方对工程字段的定义是：`compileSdkVersion` 表示编译 SDK；新版本 DevEco Studio 默认使用配套 SDK，若显式配置也只能配置为当前 Studio 的配套版本；`compatibleSdkVersion` 表示应用可运行的最低 SDK；`targetSdkVersion` 是系统提供的前向兼容手段，用于在新系统上保留旧版本 API 行为。参见 [build-profile.json5 配置说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/ide-hvigor-build-profile-V5)。

因此第一阶段不修改当前 `build-profile.json5` 中的两项 API 24 配置，也不新增显式 `compileSdkVersion`。切换到 DevEco Studio 26 后，实际编译 SDK 自然变为 API 26；最低兼容和目标行为继续由工程中的 API 24 配置约束。

## 2. 当前状态

### 2.1 已确认环境

本机新工具链元数据：

| 项目 | 当前值 |
| --- | --- |
| DevEco Studio | `26.0.0.621` |
| Build Number | `DS-261.23567.138.36.2600621` |
| HarmonyOS SDK | `26.0.0.32` |
| API Version | `26` |
| SDK Stage | `Beta2` |
| Node.js | `v24.14.1` |
| ohpm | `26.0.0.410` |

新 Studio 的 HarmonyOS SDK 随 IDE 配套提供，当前 SDK Manager 只显示 API 26 Beta2。OpenHarmony SDK 不是 HarmonyOS API 24 SDK，不能用来代替本项目的 HarmonyOS API 24 编译或兼容验证。

### 2.2 本轮执行证据

2026-08-13 已在新工具链取得以下新鲜证据：

| 门禁 | 结果 |
| --- | --- |
| 四模块 Debug HAP | `BUILD SUCCESSFUL` |
| 编译 SDK | SDK 元数据为 HarmonyOS 26.0.0 / API 26 |
| 产物 API 元数据 | `targetApiVersion=24`、`compatibleApiVersion=24` |
| Hypium | `237/237`，Failure、Error、Ignore 均为 0 |
| API 24 安装 | 已安装到 `ZhihuPlus_API24`，API 24 Release / 6.1.0.125 |
| API 24 启动与导航烟测 | `EntryAbility`、`pages/Index`、首页、显示设置、搜索页均已通过 HDC UI 树确认 |
| 签名边界 | 本机调试签名仅用于安装，验证后已恢复仓库空 `signingConfigs` |

当前 `devecocli emulator image list --all` 只提供至 HarmonyOS 6.1.1（API 24），没有 API 26 系统镜像。因此 API 26 运行时设备回归不能由本机虚拟机完成，必须在该镜像可用或接入 API 26 真机后补做；这不影响已验证的 API 24 最低兼容安装与冷启动。

本次 API 26 编译没有 ArkTS error。警告已分类如下：HAR 模块不能独立安装是 `core`、`data`、`reader` 的预期模块属性；RDB 调用的“可能抛出异常”来自既有数据访问边界；`SessionCipher` 的系统能力提示需要继续在 API 24 与 API 26 设备测试加密会话路径。此前相册权限结果字段的 phone 端系统能力提示已改为权限请求后直接检查 AccessToken，不再出现在本次构建输出。

### 2.3 当前工程约束

- 根 `build-profile.json5` 的 `targetSdkVersion` 与 `compatibleSdkVersion` 均为 `6.1.1(24)`。
- `compileSdkVersion` 未显式配置，符合新版 DevEco Studio 使用配套 SDK 的规则。
- `signingConfigs` 为空，本地调试签名材料不得提交。
- 工程包含 `entry`、`core`、`data`、`reader` 四个模块。
- `entry/src/test/List.test.ets` 当前静态注册 34 个测试套件、237 个 Hypium 用例。
- `scripts/verify-harmony.ps1` 已分别校验编译 SDK、`targetSdkVersion` 与 `compatibleSdkVersion`，不再混淆这三个版本概念。
- 237 项 Hypium 已在新工具链重新执行，静态注册、逐项报告和汇总均一致。

### 2.4 仍保留的产品边界

- 不迁移端侧模型、向量化、NLP 推理、MindSpore、NNRT 或 NPU 推理。
- 不因为 API 26 出现新的 AI/Agent 能力而引入相关模块、权限或配置。
- Android Lite 仍是产品行为规格；`Android-master` 继续作为上游功能参考分支。
- API 24 是最低兼容版本，不恢复 API 20 适配。

## 3. 迁移目标与非目标

### 3.1 目标

1. 工程能被 DevEco Studio 26.0.0 Beta2 正常同步。
2. 使用配套 API 26 SDK 完成四模块 Debug HAP 构建。
3. 237 个 Hypium 用例在 API 26 工具链全部通过，且报告不是历史缓存。
4. API 26 编译产物能安装并运行在 API 24 虚拟机。
5. 同一源码能在 API 26 虚拟机启动，并完成新系统行为回归。
6. 新增代码继续只使用 API 24 可用能力；确需 API 25/26 能力时必须有显式版本隔离和 API 24 等价路径。
7. CI 与本地脚本能区分“编译 SDK”与“最低运行 SDK”，不再把两者误判为同一个版本。

### 3.2 非目标

- 本次不把 `targetSdkVersion` 提升到 API 26。
- 本次不采用 API 26 独有 UI、Agent Framework、动态图标或其他新能力。
- 本次不改变 Bundle Name、应用数据格式或签名身份。
- 本次不重写已完成的 P0、P1、P2 功能。
- 本次不发布正式商店版本。

## 4. 目标配置

### 4.1 工程配置

第一阶段保持以下产品配置：

```json5
{
  "name": "default",
  "signingConfig": "default",
  "targetSdkVersion": "6.1.1(24)",
  "compatibleSdkVersion": "6.1.1(24)",
  "runtimeOS": "HarmonyOS"
}
```

不显式添加 `compileSdkVersion`。实际编译 SDK 通过新 Studio 的 `sdk/default/sdk-pkg.json` 验证为 API 26。构建产物验收时还要读取 HAP 元数据，确认：

- 本次编译 SDK 为 API 26（由 SDK 元数据证明）；
- `targetApiVersion` 为 24；
- `compatibleApiVersion` 为 24；
- Bundle Name 未变化；
- Debug/Release 与签名状态符合构建模式。

HAP 元数据字段可由官方拆包工具读取，参见 [拆包工具](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/unpacking-tool-0000001821000457)。

### 4.2 环境变量

开发机只允许通过本机环境或命令参数指定工具路径：

```text
HARMONY_DEVECO_HOME=<DevEco Studio 26 安装目录>
HARMONY_SDK_ROOT=<DevEco Studio 26 安装目录>\sdk
```

不得把个人绝对路径写入受版本控制的配置。工程中继续保持空 `signingConfigs`，本地证书、Profile、密码密文和 `.ohos` 路径不得提交。

### 4.3 双运行基线

| 运行基线 | 主要目的 | 必须覆盖 |
| --- | --- | --- |
| API 24 虚拟机 | 证明最低兼容真实成立 | 安装、冷启动、页面导航、登录恢复、网络、RDB、正文、公式、图片、权限 |
| API 26 虚拟机或真机 | 发现新系统行为与 UI 变化 | 冷/热启动、前后台、导航、安全区、大字体、权限、相册、分享、后台任务 |

API 24 兼容不能只由配置字段或 API 26 上运行结果推断，必须安装到 API 24 运行时验证。

## 5. 实施阶段

### M26-00：冻结与备份

优先级：P0。

- 记录迁移前提交、分支、237 项静态测试数和签名清理状态。
- 保留现有 API 24 虚拟机、镜像和旧验收文档，不删除旧 Studio 或旧 SDK，直到迁移完成。
- 确认工作区不含未说明的构建产物、签名材料或真实 Cookie。
- 迁移期间每个独立修复单独提交，不推送，便于回滚和二分。

退出条件：旧 API 24 基线可恢复，工作区状态明确。

### M26-01：新工具链同步

优先级：P0。

- 用 DevEco Studio 26 打开工程并执行 ohpm 同步。
- 记录 Node、ohpm、Hvigor、ArkTS 编译器和 SDK 元数据。
- 检查四模块 file 依赖与 lockfile 是否仍能解析。
- 不接受 IDE 自动把 `compatibleSdkVersion` 或 `targetSdkVersion` 提升到 API 26。
- 不接受 IDE 把本机签名配置写入 Git 改动。

退出条件：工程模型同步成功，四模块均被识别，无隐式配置漂移。

### M26-02：拆分验证脚本的版本概念

优先级：P0。

重构 `scripts/verify-harmony.ps1`：

- 将原来的单一 `ExpectedApiVersion=24` 拆为 `ExpectedCompileApiVersion=26`、`ExpectedTargetSdkVersion=6.1.1(24)`、`ExpectedCompatibleSdkVersion=6.1.1(24)`。
- SDK 元数据门禁验证 API 26 Beta2，不再因编译 SDK 不是 API 24而拒绝。
- 工程配置门禁继续要求 target/compatible API 24。
- 构建后解析 HAP 元数据，验证 target/compatible 版本没有串位；编译 API 由本次 SDK 元数据单独验证。
- 测试前删除旧 `test_result.txt`，继续检查生成时间、逐项结果和汇总数。
- 默认测试数从源码聚合入口计算；当前预期为 237，不把该数字永久硬编码在脚本里。
- 兼容检查能力单独作为可选门禁；当前 `devecocli check compat` 对本机 Studio build 有更高版本要求时，应记录为“工具暂不可用”，不能伪装为通过。

退出条件：同一脚本能清楚报告“API 26 编译、API 24 目标、API 24 最低兼容”。

### M26-03：API 26 严格编译适配

优先级：P0。

按模块依赖顺序处理：

1. `core`
2. `data`
3. `reader`
4. `entry`

每个修改文件先运行 `arkts_check`，再运行全工程 `build_project`。修复范围包括：

- 新 ArkTS 编译器收紧的类型推断、名义类型和可空值规则；
- Kit 导出路径、弃用 API 和签名变化；
- `Navigation`、生命周期、窗口、安全区和应用状态回调；
- Network Kit 请求、响应头、取消、超时和重定向选项；
- ArkData RDB/Preferences/Asset Store；
- Image Kit、PixelMap、相册写入、系统分享和二维码组件；
- 测试框架与 Hypium 生成报告格式。

修复原则：

- 优先使用 API 24 已存在的稳定 API，不为了消除 API 26 警告而改用 API 26 独有能力。
- 不通过 `any`、`unknown`、`as`、动态属性访问或关闭严格检查绕过错误。
- 不改 `BuildProfile.ets`。
- 不在日志中输出 Cookie、二维码 token、响应体、请求头或原始外部 URL。

退出条件：API 26 工具链四模块构建成功，错误为 0；警告逐条分类并有明确处理结论。

### M26-04：API 24 可用性审计

优先级：P0。

对所有生产 ArkTS import 和调用检查 API 起始版本：

- 直接使用的 API 必须自 API 24 或更早可用。
- API 25/26 调用必须封装在明确的版本判断后，并提供 API 24 等价路径。
- 模块配置、权限字段和资源限定也必须兼容 API 24，不能只检查 TypeScript 声明。
- HAR 对外导出不得泄漏 API 26 独有类型，否则 entry 即使不调用也可能无法在 API 24 正常装载。

重点清单：

| 子系统 | API 24 兼容风险 |
| --- | --- |
| 启动与导航 | `UIAbility` 生命周期、`onNewWant`、`NavPathStack` 行为变化 |
| 登录与会话 | Asset Store、Preferences、应用前后台监听、二维码组件 |
| 网络 | Network Kit 错误码、重定向、响应大小、取消后的 Promise 收敛 |
| 数据库 | v1→v2→v3 连续迁移、事务、关闭重开、已有用户数据保留 |
| Reader | SVG→PixelMap、行内公式、迟到资源释放、GIF 与大图 |
| 图片交互 | `WRITE_IMAGEVIDEO` 权限用途、相册写入、分享面板 |
| 后台任务 | 短时任务与延迟任务在目标 API 24 行为下的限制 |
| UI | 安全区、大字体、折叠屏/窄屏、深浅色资源 |

当前状态：API 26 编译和 API 24 安装启动已通过；完整 API 起始版本审计表与 API 24 产品链路回归仍待补齐。

退出条件：形成 API 起始版本审计表，没有未隔离的 API 25/26 调用。

### M26-05：自动化测试

优先级：P0。

必须取得新鲜报告：

- 四模块 Debug HAP：`BUILD SUCCESSFUL`。
- Hypium：`237/237`。
- `Failure=0`、`Error=0`、`Ignore=0`。
- 报告时间晚于本次测试开始时间。
- 34 个套件的导入、调用、默认导出一一对应。
- 测试结果不能沿用原第二批 `172/172` 或历史缓存。

若迁移过程中测试数变化，必须同时更新聚合入口、验证脚本计算结果和 `docs/p1/test-registration.md`，并解释增减原因。

### M26-06：API 26 虚拟机或真机验收

优先级：P0。

至少验证：

- 安装、冷启动、热启动、前后台切换和进程重启；
- 首页 Feed、关注、热榜、日报、搜索、用户页和各类详情；
- 游客、手动 Cookie、退出、加密恢复与失败保留策略；
- 深链冷/热启动、登录成功后的原目的地重建；
- RDB v3 数据、主题和屏蔽配置重启恢复；
- 正文、图片、GIF、块公式、行内公式、预览缩放和返回；
- 相册权限同意/拒绝、保存、系统分享取消；
- 200% 字体、深浅色、状态栏和底部手势区。

当前状态：本机 DevEco CLI 的镜像目录没有 API 26，尚未执行。

退出条件：API 26 上没有崩溃、空白页、不可恢复错误或行为回退。

### M26-07：API 24 最低兼容验收

优先级：P0。

将 API 26 编译产物安装到既有 `ZhihuPlus_API24` / Pura 90 虚拟机，验证：

1. HAP 可安装，不因 API 或签名元数据被系统拒绝。
2. 冷启动进入首页，所有首屏依赖完成。
3. 237 项自动化保持通过。
4. P0 设备门禁继续成立：网络、数据库、深链、扫码、正文、公式、GIF、会话和后台任务。
5. P2 主链路继续成立：登录、首页、关注/热榜/日报、搜索、详情、用户内容、屏蔽和历史。
6. 图片保存权限、相册写入和分享在 API 24 按声明工作。
7. 升级安装保留 RDB、Preferences 和加密会话；失败时不得删除生产数据库或凭据。

当前状态：安装、冷启动、首页、显示设置和搜索导航已完成；网络、RDB、会话、Reader、媒体权限、升级保留和全部 P2 主链路仍待 API 24 设备回归。

退出条件：API 26 编译产物在 API 24 运行时完成全量产品回归。

### M26-08：CI、文档与收口

优先级：P1。

- CI runner 切换到 DevEco Studio 26 / API 26 SDK。
- runner 标签从只表达 `harmonyos-api24` 调整为同时表达编译与运行能力，例如 `harmonyos-compile-api26`；API 24 设备门禁保留独立标签。
- 更新 `docs/p0/environment-baseline.md`、`docs/p1/ci-validation.md`、`docs/p2/final-acceptance-audit.md` 和总迁移方案。
- 旧 API 24 构建证据保留为历史记录，不覆盖或改写。
- 新增 API 26 编译与 API 24/API 26 双运行报告、设备信息和日期。
- 最终再次扫描签名材料、个人路径、真实 Cookie、token 和构建产物。

退出条件：文档、脚本、CI 与工程实际版本矩阵一致。

## 6. 验收矩阵

| 门禁 | API 26 编译 | API 26 运行 | API 24 运行 | 通过条件 |
| --- | --- | --- | --- | --- |
| 工程同步 | 必须 | 不适用 | 不适用 | 四模块与依赖解析成功 |
| ArkTS 严格检查 | 必须 | 不适用 | 不适用 | 0 error |
| HAP 构建 | 必须 | 不适用 | 不适用 | `BUILD SUCCESSFUL` |
| Hypium | 必须 | 可选设备补充 | 可选设备补充 | 237/237，新鲜报告 |
| 安装启动 | 不适用 | 必须 | 必须 | 可安装、可冷启动、无崩溃 |
| 目标行为 | 不适用 | 必须 | 必须 | 两端均符合 API 24 既有产品合同 |
| 数据升级 | 不适用 | 必须 | 必须 | v3 数据与设置保留 |
| 媒体/权限 | 编译门禁 | 必须 | 必须 | 保存、分享、拒绝路径正确 |
| 登录安全 | 编译门禁 | 必须 | 必须 | Cookie 不外带、不泄漏、可清理 |
| 签名安全 | 必须 | 必须 | 必须 | 仓库 signingConfigs 空、无材料入库 |

## 7. 风险与应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| Beta2 编译器或 SDK 缺陷 | 工程无法构建或行为不稳定 | 保留 API 24 基线；最小复现后记录，禁止用不安全类型绕过 |
| API 26 编译掩盖 API 24 不可用调用 | API 24 安装后崩溃 | API 起始版本审计 + API 24 真机/虚拟机运行门禁 |
| `targetSdkVersion` 被自动提升 | 新系统行为提前变化 | 配置差异门禁，迁移阶段固定 target 24 |
| 验证脚本仍假定编译 SDK=最低 SDK | 新 Studio 被错误拒绝 | 拆分 compile/target/compatible 三项检查 |
| 新 Hypium/Hvigor 报告格式变化 | 假通过或误失败 | 同时检查任务输出、文件时间、逐项记录和汇总 |
| 权限或系统 UI 行为变化 | 保存、分享、后台任务失败 | API 24/API 26 双端人工验收 |
| Beta 工具链签名变化 | 无法安装或泄漏本机配置 | 本地重新生成调试签名，Git 永远保留空 signingConfigs |
| 第三方接口不稳定 | 真实网络用例偶发失败 | 协议单测与真实网络门禁分开，固定错误分类，不记录响应体 |
| API 26 新 AI 能力误入范围 | 偏离 Lite 产品目标 | 继续执行 AI 排除清单和依赖扫描 |

## 8. 回滚方案

出现以下任一情况，停止 API 26 迁移并回到最后一个 API 24 通过提交：

- API 24 设备无法安装 API 26 编译产物；
- 必须把 `compatibleSdkVersion` 提升到 25/26 才能构建；
- 核心能力只能依赖 API 25/26 且没有 API 24 等价路径；
- RDB、Preferences 或加密会话升级导致数据丢失；
- Beta 工具链出现无法隔离、无法复现或无法安全规避的问题；
- 为通过编译必须关闭严格模式、引入不安全类型或提交签名材料。

回滚只恢复工程和工具链配置，不删除用户数据、虚拟机镜像或本地签名材料。不得使用破坏性 Git 重置处理迁移失败；以独立提交逐项 revert。

## 9. 完成定义

只有同时满足以下条件，才能把默认开发基线从“Studio 6.1.1 / API 24 编译”改为“Studio 26 / API 26 编译、API 24 最低兼容”：

- [ ] 新 Studio 工程同步无隐式配置漂移。
- [ ] API 26 四模块构建通过。
- [ ] 34 个测试套件、237 个 Hypium 用例全部通过。
- [ ] SDK 元数据为 compile API 26，HAP 元数据为 target 24、compatible 24。
- [ ] API 26 虚拟机完整回归通过。
- [ ] API 24 虚拟机完整回归通过。
- [ ] API 24 既有数据升级和登录恢复通过。
- [ ] 图片保存、分享、公式、扫码和后台任务完成双端验证。
- [ ] CI 能区分编译 API 与最低运行 API。
- [ ] `signingConfigs` 为空，仓库无证书、密钥、密码密文和个人 SDK 路径。
- [ ] 无端侧 AI 代码、依赖、模型、权限或资源。
- [ ] 总迁移方案、环境基线、CI 和 P2 验收文档同步完成。

在上述门禁全部通过前，`docs/harmonyos-migration-plan.md` 中的 API 24 基线仍是有效发布基线；本文件只定义下一次工具链迁移，不提前宣称迁移完成。

## 10. 官方参考

- [build-profile.json5 配置说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/ide-hvigor-build-profile-V5)
- [HarmonyOS 6.1.1（API 24）版本说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-611)
- [HarmonyOS 26.0.0 Beta 版本能力与变更中心](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/changelogs-600)
- [DevEco Studio 预览版](https://developer.huawei.com/consumer/cn/deveco-studio/preview/)
- [HarmonyOS 文档中心](https://developer.huawei.com/consumer/cn/doc/)
- [ArkTS 概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-overview)
- [拆包工具](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/unpacking-tool-0000001821000457)
