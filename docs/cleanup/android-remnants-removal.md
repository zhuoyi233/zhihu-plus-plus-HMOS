# 安卓残留清理分析：可删除文件清单

> 分析日期：2026-08-15
> 目标：识别 dev 分支工作区中「安卓项目需要、但鸿蒙移植无关」的文件，支持安全移除。
> 验证依据：`git ls-tree`（dev 树）、`.github/workflows`、`hvigorfile.ts`/`oh-package.json5`/
> `build-profile.json5`/`scripts/verify-harmony.ps1` 引用检查、`git worktree` 实测。

## 一、背景

本仓库（`zhihu-plus-plus-HMOS`）是从上游安卓项目（`zly2006/zhihu-plus-plus`）派生而来，
dev 工作区同时包含**安卓构建链残留**与**鸿蒙工程**。鸿蒙构建（`entry`/`core`/`data`/`reader`
四个模块 + `hvigor`）完全自包含：对 `hvigorfile.ts`、`oh-package.json5`、`build-profile.json5`、
`scripts/verify-harmony.ps1` 做了引用扫描，**没有一处引用** 下述安卓目录/文件，因此删除不影响
鸿蒙编译与测试。

## 二、结论摘要

| 类别 | 判定 | 说明 |
| --- | --- | --- |
| A：可直接删除 | 19 项 | 纯安卓构建链 / 上游附属，鸿蒙零引用 |
| B：按文件甄别 | 3 项 | `.github/workflows`、`.gitignore`、`.idea/` |
| C：需人工决定 | 7 项 | agent 指令/技能、README——内容源自安卓仓库但被本仓库开发流加载 |
| 保留 | 15 项 | 鸿蒙工程必需 + 通用许可/规范文件 |

## 三、A 类：纯安卓/上游附属，可直接删除

删除方式建议：`git rm -r <path>` 后一次性提交（本地，不推送）。

| 路径 | 内容 | 为什么是安卓专用 |
| --- | --- | --- |
| `app/` | Android 主应用模块（Jetpack Compose） | 鸿蒙入口是 `entry/` |
| `shared/` | Android KMP 共享代码（登录/数据/UI） | 鸿蒙对应 `core/`+`data/` |
| `shared-local-db/` | Android Room 本地数据库 | 鸿蒙用 ArkData RDB（`data/`） |
| `desktopApp/` | 上游桌面版（Compose Desktop） | 与鸿蒙无关 |
| `buildSrc/` | Android Gradle 约定插件 | 鸿蒙不用 Gradle |
| `gradle/`、`build.gradle.kts`、`settings.gradle.kts`、`gradlew`、`gradlew.bat`、`gradle.properties` | Android Gradle 构建链 | 鸿蒙用 hvigor + ohpm |
| `fastlane/` | Android 发布自动化（Play 商店） | 鸿蒙走 AppGallery，不用 fastlane |
| `sentence_embeddings/` | Rust 句向量（Android full 变体 NLP） | 鸿蒙无端侧 NLP |
| `rs-hf-tokenizer/` | Rust HuggingFace tokenizer | 同上 |
| `rs-zse-sign/` | Rust ZSE 签名服务 | 鸿蒙已有纯 ArkTS `ZseSigner.ets` |
| `aigc-vote-server/` | 上游配套服务器 | 与客户端无关 |
| `apk-recompress/` | APK 重压缩工具 | 只处理 APK |
| `reports/` | `androidTest-*` 失败根因报告 | 安卓测试报告 |
| `misc/` | 上游杂项：chrome 知乎过滤规则、`install-avd-system-cert.py`、`htk-inject-system-cert.sh`、`repack_release_apk.py`、`zse-ck-v4-*.js`、`emoji*`、`build-dmg.sh` 等 | 全部服务于安卓/上游桌面发布 |
| `.gitmodules` | 空文件（无子模块） | 无实际作用 |

## 四、B 类：按文件甄别

| 路径 | 判定 | 处理建议 |
| --- | --- | --- |
| `.github/workflows/` | `harmonyos.yml` 是鸿蒙 CI（路径含 AppScope/entry/core/data/reader），**保留**；`build.yml`（Nightly Gradle 构建）、`instrument-test.yml`、`pr.yml`、`my-build-action.yml`、`other-branches-test.yml`、`auto-label.yml`、`bump-version.yml` 为安卓/通用 | 删除 harmonyos.yml 之外的 workflow |
| `.gitignore` | 含大量 Gradle/Android Studio 条目（`.gradle/`、`*.apk`、`.externalNativeBuild`、`.cxx/`、`captures/` 等） | **保留文件**，清理安卓条目；确认保留 `.worktrees/`（57 行）、`oh_modules/`、`.hvigor/` |
| `.idea/` | `modules.xml` 无安卓模块引用（无 app.iml/shared/buildSrc/desktopApp）；`.gitignore` 默认忽略 `.idea/`（例外 codeStyles/dictionaries） | 可删（IDE 自动重建）；不删也无碍 |

## 五、C 类：需人工决定（内容源自安卓仓库，但被本仓库开发流加载）

| 路径 | 现状 | 风险 | 建议 |
| --- | --- | --- | --- |
| `CLAUDE.md`、`AGENTS.md` | 安卓仓库的 agent 指令（`./gradlew assembleLiteDebug`、AVD/UI 调试流程），对鸿蒙构建无效；`AGENTS.md` 仅一行 `CLAUDE.md` | 是当前会话实际加载的指令文件，删除会改变 agent 行为 | 另立任务：替换为鸿蒙版指令后再删 |
| `.agents/skills/` | 安卓技能（launch-on-device、ui-test、picky-user、ui-voyager、off-android-avd-ci-debug 等） | 当前会话可用技能来源 | 同上方，确认替换后处理 |
| `.claude/`、`.codex/`、`.mcp.json`、`.memory/` | 上游 agent 配置与记忆 | 鸿蒙开发可能仍在用部分工具链 | 逐个确认 |
| `README.md` | 上游安卓项目描述（徽章指向 `zly2006/zhihu-plus-plus`） | 直接删除会让仓库无 README | 建议替换为鸿蒙版说明而非裸删 |

## 六、保留清单（鸿蒙必需 / 通用）

- 工程：`AppScope/`、`entry/`、`core/`、`data/`、`reader/`、`hvigor/`、`hvigorfile.ts`、
  `oh-package.json5`、`oh-package-lock.json5`、`build-profile.json5`、`code-linter.json5`
- 脚本：`scripts/verify-harmony.ps1`（鸿蒙编译 + 401 测试）
- 文档：`docs/`（p0–p3 全为鸿蒙阶段文档）
- 通用：`LICENSE`、`CODE_OF_CONDUCT.md`、`.copyright`、`.editorconfig`、`.gitattributes`

## 七、删除后的访问与验证（重点）

1. **安卓项目仍可离线访问**：worktree 从 git 对象库检出，与 dev 工作区文件无关。
   - 保留 `refs/remotes/upstream/master`（0023163d）与本地分支 `refs/heads/Android-master`
     （e0856d27）即可 `git worktree add .worktrees/android-ref upstream/master` 随时拿到完整
     安卓工程（已实测：837 文件完整检出，主工作区无污染）。
   - **不要**同时删除这两个引用并跑 `git gc --prune=now`，否则需 `git fetch upstream` 重新拉取。
2. **鸿蒙回归**：删除后执行 `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall`
   全量编译 + Hypium 401/401。
3. **提交流程**：`git rm -r` 全部 A/B 类目标 → 提交（不推送）→ 推送前可先用
   `git worktree add --detach .worktrees/_check upstream/master` 复核上游可访问，随后移除。

## 八、参考命令

```powershell
# A 类一次性删除
git rm -r app shared shared-local-db desktopApp buildSrc gradle fastlane \
  sentence_embeddings rs-hf-tokenizer rs-zse-sign aigc-vote-server apk-recompress \
  reports misc build.gradle.kts settings.gradle.kts gradlew gradlew.bat \
  gradle.properties .gitmodules
# B 类：删除安卓 workflow（保留 harmonyos.yml）
git rm .github/workflows/build.yml .github/workflows/instrument-test.yml `
  .github/workflows/pr.yml .github/workflows/my-build-action.yml `
  .github/workflows/other-branches-test.yml .github/workflows/auto-label.yml `
  .github/workflows/bump-version.yml
# 删除后复核上游
git worktree add --detach .worktrees/_check refs/remotes/upstream/master
git worktree remove .worktrees/_check
```

## 九、注意事项：删除后可能"复活"安卓文件的路径

1. **feature/p3-\* 分支**：`.worktrees/` 下的 `feature/p3-1-blocking` … `p3-7-backstack`
   分支仍基于含安卓文件的旧 dev 快照。若删除后**再合并**这些分支，git 会把已删除的
   安卓文件**合并回来**。建议：这些分支若已完成使命，直接删除分支并清理对应 worktree
   （`git worktree remove` + `git branch -D`）；若还需保留，合并前先确认删除提交已在其历史中。
2. **origin/dev（e0856d27）**：远端 dev 仍是含安卓文件的旧基线。本地 dev 领先，
   正常 `push` 不受影响；但若从 origin **拉取/合并**（而非 push），需要处理文件冲突或
   以删除提交为准。
3. **`Android-master` / `upstream/master` 引用**：务必保留（见第七节），它们是离线访问
   安卓项目的唯一来源；删除后仅靠 reflog 保护，过期后 `git gc` 会回收对象。
