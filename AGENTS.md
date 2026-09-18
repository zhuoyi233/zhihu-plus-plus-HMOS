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

- 本机已安装 `devecocli`（npm 全局，`devecocli --version` 可查），可替代 DevEco Studio 执行
  命令行操作：`build`/`run`/`signature`/`device`/`emulator`/`auth`/`log`/`ui`/`check`/`docs`
  等（`devecocli --help` 查看全量）；沙箱会话中同样按上一条提权。

## 设备调试（默认模拟器 ZhihuPlus\_API23，127.0.0.1:5555）

默认测试目标为模拟器 **ZhihuPlus\_API23**（API 23，最低兼容线，connectKey `127.0.0.1:5555`），
除非用户当次明确指定其他设备/模拟器；多设备时先 `hdc list targets` 确认。

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

- 本机 `python`/`python3` 是 Windows 商店占位符（执行即失败，exit 49），**不要尝试**；
  解析 dumpLayout 等 JSON/文本处理一律用 `node -e`（hvigor 已装 node，Git Bash 直接可用）。

- Git Bash 下 `hdc file recv` 的远程路径会被 MSYS 改写，加 `MSYS_NO_PATHCONV=1` 前缀；
  接收目录用仓库内临时目录（如 `.tmp_shots/`，用完删除）。

- 应用支持知乎链接直达：`aa start -a EntryAbility -b com.github.zhuoyi233.zhplus -U <zhihu url>`
  （经 `resolveZhihuLink` 路由），可跳过手动导航直接进入问题/回答/文章页。

- 登录：重装/清数据后登录态丢失，首页出现 `p2_home_error_login` → 设置页“开发者选项”手动 Cookie 输入
  （`ZHIHU_COOKIE` 环境变量）→ `developer_cookie_submit` → 首页 `p2_home_error_retry`。普通登录页只保留
  手机号、扫码、网页三种面向用户的登录方式。

## 提交规范

- **严格禁止 push**：所有提交仅本地，远端落后属正常。仅当用户**当次明确要求**时才允许 push，
  且一次要求只执行**单次** push（只推用户指定的分支/tag，不顺势推送其他分支、tag 或 `--tags`），
  该许可不延续到后续任务。

- **禁止自动提交**：改动（含修复、重构、文档）完成后一律不主动 commit，仅当用户**当次明确要求**
  提交时才执行。用户要求提交但未说明提交内容/拆分方式时，agent 按 git diff 的实际变更与本节
  规范自行生成 commit message 并做合理的提交拆分，无需逐次询问；与任务无关的未跟踪文件不得
  顺势带入。

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

## PR 撰写规范（标题与正文模板）

以 PR #2 的四段式正文为标准模板（参考 PR #1 的经验教训），生成/整理 PR 时按此结构撰写：

- **标题**：沿用提交风格 `<type>(harmony): <中文摘要>`；版本合入类 PR 摘要中带版本号，
  如 `feat(harmony): v0.2.1 沉浸光效适配与全量修复合入 main`。

- **正文固定四节**（简体中文，`##` 二级标题，顺序不变）：
  1. `## 概述`——1~3 句：本 PR 做了什么、合并范围/分支关系（如"dev 相对 main 的累计变更一次性合入"）。
  2. `## 主要内容`——无序列表**按主题分组**，每条以**加粗引导词**开头（如
     `**窗口全屏布局**：`），一条一个主题，具体改动点到文件/行为粒度，不逐文件流水账。
  3. `## 验证`——只写**实际做过**的验证：模拟器/真机回归范围、Hypium 通过数（如 `532/532`）、
     构建产物校验等；不得宣称未验证的内容。
  4. `## 关联`——引用关联 issue/PR（`#编号`），注明包含/依赖关系（如"包含已合并的 #1"）。

- **诚实原则**（PR #1 先例）：已知问题如实单列（可加 `## 已知问题` 节），明确"本次提交不宣称
  该问题已修复"；验证状态未完成就写未完成，不夸大。

- **截图/附件**：UI 改动附截图，统一放 `docs/ui-screenshots/` 后在正文中以表格引用
  （文件名 `ui-adaptation-NN.jpg` 类推），不外链临时地址。

- **分支方向**：功能分支（`feature/<name>`）或累计分支（`dev`）→ `main`；创建/推送 PR 属外发
  操作，仅当用户**当次明确要求**时执行（对齐"严格禁止 push"节）。

## 发版说明（Release Notes）框架

以 `HMOSv0.5.0` 的实际发版说明为标准模板（GitHub Release），生成新版本说明时按此结构撰写：

- **标题**：`# ZhihuPlusPlus-HMOS v<version>`，与 tag `HMOSv<version>` 对应。

- **导语段**（标题后 1~2 句）：概括本版本主题（"本次更新以**主题词**为…：…升级"），
  末尾给出提交数（`git rev-list HMOSv<上一版本>..HEAD --count` 统计），如"共 62 个提交"。

- **正文主题节**：若干 `## <emoji> <主题>` 二级标题，每节内为无序列表，一条一句、点到
  行为粒度（不逐文件流水账）；按功能主题分组，与 PR 正文"主要内容"的分组风格一致。
  常用主题 emoji 参考：🪪 应用名称与图标 / 📨 消息 / 📖 阅读 / 🛡️ 过滤与屏蔽 /
  🎨 外观与导航 / 🔐 登录与账户 / ✨ 详情与首页 / 🐛 问题修复（按当期实际内容取舍增删，
  大版本主题多可 6~8 节，小版本可合并为 2~3 节 + 修复）。

- **固定节 `## 📥 下载与安装`**（三步，文案固定）：
  1. 下载下方附件 `ZhihuPlusPlus-HMOS-v<version>-unsigned.hap`
  2. 使用 [小白调试助手](https://github.com/likuai2010/auto-installer) 或
     [HoKit](https://github.com/yabi-zzh/HoKit/releases) 自行签名
  3. 覆盖安装即可升级，原有登录状态、设置与历史数据会保留

- **末尾固定 `> [!IMPORTANT]` 提示块**：
  - 要求设备系统为 **HarmonyOS 6.1.0（API 23）及以上**（若最低兼容线变更则同步更新）；
  - 视当期特性补充一句相关说明（如 v0.5.0 注明"离线朗读可用音色取决于设备中的
    HarmonyOS Core Speech Kit 服务与资源"）；
  - 固定声明："本项目非知乎官方产品，内容来自知乎网站，服务端接口变化可能导致部分功能失效。"

- **诚实原则**：与 PR 撰写规范一致——已知问题如实列出，不宣称未修复、未验证的内容。

- **发布流程**：发版说明**只能以草稿形式**经 `gh` 写入（`gh release create HMOSv<version>
  --draft --notes-file <file> -R zhuoyi233/zhihu-plus-plus-HMOS`，或对已有草稿
  `gh release edit --draft=false` 前再次确认）；**严格禁止直接发布正式 Release**。
  仅当用户**当次明确确认草稿内容并要求发布**时，才可将草稿转为正式发版（去除 `--draft`），
  该确认不延续到后续任务。

## ArkTS / ArkUI 代码约束

- 显式类型：禁 `any`/`unknown`（用 `Object`）、对象字面量不能作为 `Promise<T>` 返回
  （用 interface）；`catch (e)` 后不能 `throw e`（包装成具体 Error 再抛）。

- 禁解构参数；`Object.entries(...).forEach` 的元组回调改用 `Object.keys`。

- 跨页面状态通道：P1Shell 各 feed 页经 `@Builder` 参数传值（如 reloadToken）在 HdsTabs 的
  TabContent 构建树下**不会触发已挂载子组件更新**，`@Provide`/`@Consume` 在该树形下也实测
  **不链接**（页面各持本地兜底实例）。跨页面信号一律走 AppStorage 广播 + `@StorageProp`+`@Watch`
  （如 `loginFeedReloadTick`，同 `bottomRectHeight` 模式）；signal 处理需容忍控制器失活态
  （refresh/reloadNow 对 inactive 自行 no-op）。

- `@BuilderParam` 传入的箭头闭包体内**只能直接调用 @Builder 方法**，不得再包 `if` 等语句——
  否则编译器不转换 builder 调用，运行时**静默不渲染**（无报错）；条件守卫写在 @Builder 内部
  （UI 层 `if` 合法）。@Builder 体内禁止非 UI 语句（含 hilog），否则编译错误
  "does not meet UI component syntax"。

- `SegmentButton` 的 `options` 是 `@ObjectLink`：必须存 `@State` 字段再传入，内联对象字面量
  在真机上会丢点击回调；并需显式 `.width()`，否则两键段控会溢出父边距。

- 无 `TextEncoder`：用 `data` 模块 `Utf8.ets` 的 `utf8Encode`。

- 最低兼容 API 23：`uiMaterial` 全家族（`@ohos.arkui.uiMaterial`，含 `ImmersiveMaterial`/
  `systemMaterial`/`getMaterialInfo`）是 API 26 专属，**禁止 import**，否则 API 23 设备载入
  即崩；普通组件玻璃效果用 `backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)` 兜底，
  系统材质只能走 HDS 组件（`hdsMaterial`/`HdsTabs` 等，自 6.1.0(23) 起可用）。
  新 API 起始版本可在 SDK `hms/ets/api/device-define/api-version/*.json` 查表核实。

- 图标用鸿蒙官方 Symbol：`SymbolGlyph($r('sys.symbol.xxx'))`（如 `more`/`arrow_up`/
  `bookmark`/`message`），名称以官方符号库为准，勿猜（`ellipsis` 等不存在）。
  符号库：<https://developer.huawei.com/consumer/cn/design/harmonyos-symbol> ；
  使用说明：<https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962> 。

- ArkWeb（Web 组件）：`setUserAgentForHosts` 是**静态方法**；清 cookie 用
  `WebCookieManager.clearAllCookiesSync()`；登录/风控页用默认移动 UA（桌面 UA 会让页面
  按桌面视口渲染、字体过小）。

## 并行开发

- **新建分支必须验证非 unborn**：本会话环境实测（Git for Windows 2.54）`git checkout -b`
  可能**不写 loose ref 文件**，HEAD 立即变 unborn（孤儿分支）——表现为 `git status` 把全库
  文件显示为暂存态 "A"、`git log` 报 "does not have any commits yet"。创建后必须校验：

  ```bash
  git rev-parse --verify HEAD   # 必须成功输出 SHA
  ```

  若命中，**不要** `git reset`/`checkout` 补救（本环境 `git reset` 也会删 ref，加重问题），
  直接用 node 写 ref 文件恢复（SHA 取基线分支）：

  ```bash
  mkdir -p ".git/refs/heads/$(dirname <branch>)"   # 分支无 / 时可省
  node -e "require('fs').writeFileSync('.git/refs/heads/<branch>', '<SHA>\n')"
  ```

  恢复后 reflog 与对象库均完好，`git status` 即恢复正常。

- 用 git worktree：`git worktree add .worktrees/<name> -b feature/<name>`（`.worktrees/`
  已被 .gitignore 忽略），完成后 `git worktree remove` + `git branch -D`。

- 上游参考：保留 `refs/remotes/upstream/master` 与本地 `Android-master`
  （跟踪 upstream/master），需要看安卓实现时
  `git worktree add --detach .worktrees/_ref refs/remotes/upstream/master`。

## 文档与行为基线

- 阶段文档在 `docs/p0`–`docs/p5`；清理/迁移分析在 `docs/cleanup/`。

- 行为对齐安卓 Lite：登录三模式（手机号/扫码/网页）、信息流屏蔽、风控 ArkWeb 验证等。
