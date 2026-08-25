# P4 发布与草稿恢复 API 26 验收

执行日期：2026-08-25。设备：`ZhihuPlus_API26`（`127.0.0.1:5555`）。

## 本切片范围

- 回答新建、已有回答编辑预填、想法创作和想法本地草稿恢复均使用 API 26 编译的 ArkUI 组合根。
- 想法草稿箱仅枚举当前认证账号的 `PIN`、`dirty` 元数据；路由只携带规范化 UUID。正文只在打开编辑页后由加密 `DraftRepository` 恢复，列表和路由不携带 HTML、Cookie 或上传凭证。
- 默认回答和想法发布仓储是本地安全实现：远端话题推荐、远端草稿和正式发布均不会创建 `ZhihuHttpClient`，并以固定失败状态收敛。真实外部写入不是自动化或本次设备测试的一部分。
- 退出时发布控制器失活并取消迟到操作；想法页“取消”和回答页“退出”均回到上级导航目的地，不会暗中保存或发布。

## 自动化与构建

在 `feature/p4-publish-final` worktree 执行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

结果：SDK API 26 编译成功，签名 Debug HAP 构建成功，Hypium `489/489` 通过。

覆盖包含：

- 登录态和账号摘要门禁、默认发布仓储不触网；
- 想法草稿只过滤当前账号元数据中的有效脏 `PIN` 草稿；
- 回答编辑预填只消费一次，且本地草稿优先时不会残留临时正文；
- `PIN_DRAFTS` 无参数导航 decoder、登录后刷新和非法参数拒绝；
- 回答编辑页面失活会释放注入的发布控制器。

## API 26 模拟器冒烟

已安装本分支签名 HAP 并启动 `EntryAbility`。没有输入 Cookie、没有点击登录、没有发出知乎写请求。

1. 首页点击 `p2_home_settings`，设置页确认 `p4_open_pin_publish`；点击后出现：
   `p4_pin_publish_page`、`p4_pin_publish_login_required`、`p4_pin_publish_login`、
   `p4_pin_publish_cancel`、`p4_pin_publish_status`。
2. 未登录状态下点击 `p4_pin_publish_cancel`，页面返回设置页，且重新可见
   `p4_open_pin_publish`。
3. 设置页向下滚动，确认 `p4_open_pin_drafts`；点击后出现：
   `p4_pin_drafts_page`、`p4_pin_drafts_title`、`p4_pin_drafts_status`、
   `p4_pin_drafts_login`。

本次生成的本地和设备端 `layout_*.json` 临时 dump 已全部删除，未进入 Git。

## 认证后的手动门禁

以下动作只能由用户在 API 26 模拟器、专用测试账号与可丢弃内容上手动执行；不要在 CI、脚本或无人值守 Agent 中执行。

1. 在应用登录页手工输入 Cookie，确认回跳后只刷新当前目的地。
2. 新建想法，输入非敏感测试文本，点击 `p4_pin_publish_save_draft`，退出后从
   `p4_open_pin_drafts` 打开同一条草稿，确认标题/正文恢复且不会串到另一账号。
3. 打开自己的回答详情，确认 `p4_answer_edit_existing` 只在作者和当前登录账号一致时出现；进入编辑页确认一次性预填，并用 `p4_answer_page_exit` 退出。
4. 如未来接入经过合同审计的真实发布仓储，先在页面明确展示最终确认；用户主动点击
   `p4_answer_page_publish` 或 `p4_pin_publish_submit` 后，才允许对专用测试目标执行一次真实写入。验收记录只保留脱敏内容 ID、时间和结果，绝不记录 Cookie、正文、上传凭证或原始响应。

## 集成前待办

- 当前受控 `build-profile.json5` 仍声明 `targetSdkVersion` 与 `compatibleSdkVersion` 为
  `6.1.1(24)`；本切片只在 API 26 SDK 和 `ZhihuPlus_API26` 模拟器上构建/测试。若主线要把
  产品基线改成 API 26，须由主线统一修改并重新生成签名、完整构建和回归，避免各 P4 worktree
  各自改动该高冲突文件。
- 签名配置是 worktree 本地 `skip-worktree` 配置，不能提交；合并所有 P4 子域后应在主线重新
  签名、构建、安装，并按本清单重跑设备验收。
- 真实远端发布仍被默认安全仓储刻意拒绝，必须在协议、风控、图片上传和人工确认门禁均合并后
  才可替换；本切片不能以本地草稿成功冒充真实发布成功。
