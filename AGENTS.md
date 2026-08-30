# Zhihu++ HarmonyOS Agent Instructions

本项目是知乎客户端（`zly2006/zhihu-plus-plus`）的鸿蒙移植版：隐私增强、广告屏蔽、内容过滤，
行为基线对齐安卓 Lite 版。安卓上游代码只作行为参考，不参与鸿蒙构建。

## 工程结构

- 四模块架构：`entry`（HAP 主模块）+ `core`/`data`/`reader`（HAR 共享库）；
  `AppScope` 为应用壳（bundleName `com.github.zhuoyi233.zhplus`）。
- 编译：API 26，`targetSdkVersion` `26.0.0`、`compatibleSdkVersion` `6.1.0(23)`——最低支持
  HarmonyOS 6.1.0（API 23）设备（编译/兼容版本拆分背景见 `docs/api26-api24-migration-plan.md`；
  注意 API 10–25 的版本值必须用 `'X.Y.Z(N)'` 旧格式，`'26.0.0'` 新格式仅 API 26+ 合法）。
- 依赖：ohpm（`oh-package.json5`），构建工具 hvigor。

## 构建与验证（必须按顺序执行）

```powershell
# 编译 + Hypium 测试（最常用；跳过依赖安装与 HAP 构建）
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild

# 完整构建（assembleHap + 签名 + 测试）
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

- **必须用 pwsh 7**：Windows PowerShell 5.1 对 UTF-8 无 BOM 中文会乱码，导致脚本失败。
- 用例数由脚本解析 `entry/src/test/List.test.ets` 注册项动态统计，并校验全量通过；
  无需手动维护基线数字，必要时可用 `-ExpectedTestCount` 显式固定。
- 签名：已对 `build-profile.json5` 设置 `git update-index --skip-worktree`，本地签名配置
  （`devecocli signature generate` 写入）不会进入 `git status`/提交，**无需再还原**
  （提交前若出现需还原，说明 skip-worktree 失效，重新设置即可）。证书文件在项目外
  `~/.ohos/config/`；需要提交该文件真实变更（如 targetSdkVersion）时先
  `git update-index --no-skip-worktree build-profile.json5`。
- DevEco/hvigor 工具链需要读写工作区外的 `.hvigor` 缓存、SDK 与 `~/.ohos` 签名目录；
  在受沙箱限制的会话中跑完整构建或 `devecocli signature generate` 需相应提权
  （否则 node 子进程报 ENOENT/Access denied，devecocli 报"安装未找到"）。

## 设备调试（模拟器 ZhihuPlus_API26，127.0.0.1:5555）

```powershell
# hdc 路径因机器而异，建议加入 PATH 或改用环境变量；此处按 PATH 解析，不硬编码本机绝对路径。
$hdc = "hdc"
& $hdc -t 127.0.0.1:5555 install entry\build\default\outputs\default\entry-default-signed.hap
& $hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b com.github.zhuoyi233.zhplus"
& $hdc -t 127.0.0.1:5555 shell "uitest dumpLayout"   # 输出到 /data/local/tmp/layout_*.json
& $hdc -t 127.0.0.1:5555 file recv /data/local/tmp/layout_*.json .
& $hdc -t 127.0.0.1:5555 shell "uitest uiInput click X Y"
& $hdc -t 127.0.0.1:5555 shell "hilog -x | grep <关键字>"
```

- 多设备时 `hdc` 必须用 `-t <connectKey>` 指定目标，否则报 "need connect-key"。
- 截图：`hdc shell snapshot_display`（默认写到 `/data/local/tmp/snapshot_*.jpeg`）后 recv。
- UI dump 的节点字段是 `id`（不是 `resourceId`）；软键盘会遮挡底部按钮，操作前先
  `uitest uiInput keyEvent Back` 收起键盘。
- 登录：重装/清数据后登录态丢失，首页出现 `p2_home_error_login` → 登录页手动 Cookie 输入
  （`ZHIHU_COOKIE` 环境变量）→ `p2_login_cookie_submit` → 首页 `p2_home_error_retry`。

## 提交规范

- **严格禁止 push**：所有提交仅本地，远端落后属正常。仅当用户**当次明确要求**时才允许 push，
  且一次要求只执行**单次** push（只推用户指定的分支/tag，不顺势推送其他分支、tag 或 `--tags`），
  该许可不延续到后续任务。
- 提交风格：`<type>(harmony): <中文>`，如 `fix(harmony): 修复搜索响应解析`。
- 提交前检查：`git status` 干净（build-profile.json5 因 skip-worktree 不参与提交）、无临时文件（`.tmp_*` 等）。
- 版本号映射：`versionCode` 由 `versionName` 按固定公式推导，二者在 `AppScope/app.json5` 一并更新：
  `versionCode = (主版本号 + 1) × 1000000 + 次版本号 × 100 + 修订号`（如 `0.2.1 → 1000201`，
  `0.3.0 → 1000300`，`1.0.0 → 2000000`）。鸿蒙官方仅要求 versionCode 整数且逐版递增（AGC 规则），
  本公式为本仓库约定；历史 tag（HMOSv0.1.0/0.2.0）的 versionCode 是早期占位值，不回改。
  之后只需提供 versionName 时，agent 按此公式自行补全 versionCode，无需再询问。
- 版本 tag：仅用 `HMOSv<versionName>`（如 `HMOSv0.2.1`，与 `AppScope/app.json5` 的 `versionName` 一致）。
  发版顺序：改 `versionName`/`versionCode` → 完整验证 → 提交（`chore(harmony): 应用版本号升至 x.y.z`）→
  附注 tag（`git tag -a HMOSv0.2.1 -m "<一句里程碑中文摘要>"`）→ 推送仅在用户明确要求时执行
  （`git push origin dev` + 显式列出 HMOS tag）。仓库继承的上游 `0.x`/`nightly` tag 是 zly2006 的
  发布记录，**不要推送**，远端只保留 `HMOS*` tag。
- 发布产物命名：`ZhihuPlusPlus-HMOS-v<version>-unsigned.hap`（如 `ZhihuPlusPlus-HMOS-v0.2.0-unsigned.hap`）。
  `verify-harmony.ps1` 构建校验通过后会自动从 `entry-default-unsigned/signed.hap` 复制出该命名的
  产物（同目录，含 `-signed` 后缀版），无需手动重命名；签名包仅限本机调试，不要分发。

## ArkTS / ArkUI 代码约束

- 显式类型：禁 `any`/`unknown`（用 `Object`）、对象字面量不能作为 `Promise<T>` 返回
  （用 interface）；`catch (e)` 后不能 `throw e`（包装成具体 Error 再抛）。
- 禁解构参数；`Object.entries(...).forEach` 的元组回调改用 `Object.keys`。
- 跨页面状态通道：P1Shell 各 feed 页经 `@Builder` 参数传值（如 reloadToken）在 HdsTabs 的
  TabContent 构建树下**不会触发已挂载子组件更新**，`@Provide`/`@Consume` 在该树形下也实测
  **不链接**（页面各持本地兜底实例）。跨页面信号一律走 AppStorage 广播 + `@StorageProp`+`@Watch`
  （如 `loginFeedReloadTick`，同 `bottomRectHeight` 模式）；signal 处理需容忍控制器失活态
  （refresh/reloadNow 对 inactive 自行 no-op）。
- 无 `TextEncoder`：用 `data` 模块 `Utf8.ets` 的 `utf8Encode`。
- 最低兼容 API 23：`uiMaterial` 全家族（`@ohos.arkui.uiMaterial`，含 `ImmersiveMaterial`/
  `systemMaterial`/`getMaterialInfo`）是 API 26 专属，**禁止 import**，否则 API 23 设备载入
  即崩；普通组件玻璃效果用 `backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)` 兜底，
  系统材质只能走 HDS 组件（`hdsMaterial`/`HdsTabs` 等，自 6.1.0(23) 起可用）。
  新 API 起始版本可在 SDK `hms/ets/api/device-define/api-version/*.json` 查表核实。
- 图标用鸿蒙官方 Symbol：`SymbolGlyph($r('sys.symbol.xxx'))`（如 `more`/`arrow_up`/
  `bookmark`/`message`），名称以官方符号库为准，勿猜（`ellipsis` 等不存在）。
  符号库：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol ；
  使用说明：https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962 。
- ArkWeb（Web 组件）：`setUserAgentForHosts` 是**静态方法**；清 cookie 用
  `WebCookieManager.clearAllCookiesSync()`；登录/风控页用默认移动 UA（桌面 UA 会让页面
  按桌面视口渲染、字体过小）。

## 并行开发

- 用 git worktree：`git worktree add .worktrees/<name> -b feature/<name>`（`.worktrees/`
  已被 .gitignore 忽略），完成后 `git worktree remove` + `git branch -D`。
- 上游参考：保留 `refs/remotes/upstream/master` 与本地 `Android-master`
  （跟踪 upstream/master），需要看安卓实现时
  `git worktree add --detach .worktrees/_ref refs/remotes/upstream/master`。

## 文档与行为基线

- 阶段文档在 `docs/p0`–`docs/p5`；清理/迁移分析在 `docs/cleanup/`。
- 行为对齐安卓 Lite：登录三模式（手机号/扫码/网页）、信息流屏蔽、风控 ArkWeb 验证等。
