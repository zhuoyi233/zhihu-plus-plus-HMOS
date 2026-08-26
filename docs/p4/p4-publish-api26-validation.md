# P4 发布与草稿恢复 API 26 验收

> 本文原为 2026-08-25 的阶段快照；当前 P4 最终状态、API 26 回归和人工外部状态门禁见
> [`p4-api26-final-validation.md`](p4-api26-final-validation.md)。

## 本切片范围

- 回答新建、已有回答编辑预填、想法创作和想法本地草稿恢复均使用 API 26 编译的 ArkUI 组合根。
- 想法草稿箱仅枚举当前认证账号的 `PIN`、`dirty` 元数据；路由只携带规范化 UUID。正文只在打开编辑页后由加密 `DraftRepository` 恢复，列表和路由不携带 HTML、Cookie 或上传凭证。
- 当前组合根为回答、想法和图片上传分别创建独立生产仓储。只有用户经过页面最终确认后，才会上传图片、同步远端草稿或正式发布；自动化和本次设备回归均不执行这些外部写入。
- 退出时发布控制器失活并取消迟到操作；想法页“取消”和回答页“退出”均回到上级导航目的地，不会暗中保存或发布。

## 自动化与构建

在 `feature/p4-publish-final` worktree 执行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

结果：SDK API 26 编译成功，签名 Debug HAP 构建成功，Hypium `516/516` 通过。

覆盖包含：

- 登录态和账号摘要门禁、最终确认前不触发外部写入；
- 本地草稿先于图片上传，上传成功才允许远端草稿与正式发布，上传失败保留本地引用；
- 想法草稿只过滤当前账号元数据中的有效脏 `PIN` 草稿；
- 回答编辑预填只消费一次，且本地草稿优先时不会残留临时正文；
- `PIN_DRAFTS` 无参数导航 decoder、登录后刷新和非法参数拒绝；
- 回答编辑页面失活会释放注入的发布控制器。

## API 26 模拟器冒烟

已安装主线签名 HAP 并启动 `EntryAbility`。使用已有登录态刷新首页；没有选择图片、保存草稿或发出知乎写请求。

1. 首页显示 `p2_home_feed_list`，不显示 `p2_home_error_login` 或 `p2_home_error_retry`。
2. 切换到根底部导航的“我的”，打开 `p4_open_pin_publish` 后出现
   `p4_pin_publish_page`、`p4_pin_publish_title`、`p4_pin_publish_body`、
   `p4_image_picker_select` 与 `p4_pin_publish_submit`，且不显示登录 CTA。

本次生成的本地和设备端 `layout_*.json` 临时 dump 已全部删除，未进入 Git。

## 认证后的手动门禁

以下动作只能由用户在 API 26 模拟器、专用测试账号与可丢弃内容上手动执行；不要在 CI、脚本或无人值守 Agent 中执行。

1. 在应用登录页手工输入 Cookie，确认回跳后只刷新当前目的地。
2. 新建想法，输入非敏感测试文本，点击 `p4_pin_publish_save_draft`，退出后从
   `p4_open_pin_drafts` 打开同一条草稿，确认标题/正文恢复且不会串到另一账号。
3. 打开自己的回答详情，确认 `p4_answer_edit_existing` 只在作者和当前登录账号一致时出现；进入编辑页确认一次性预填，并用 `p4_answer_page_exit` 退出。
4. 生产仓储已经接入：用户主动点击 `p4_answer_page_publish` 或
   `p4_pin_publish_submit` 后仍须在最终确认卡片再次点击，才允许对专用测试目标执行一次真实写入。验收记录只保留脱敏内容 ID、时间和结果，绝不记录 Cookie、正文、上传凭证或原始响应。

## 当前边界

- `targetSdkVersion` 与 `compatibleSdkVersion` 均为 `26.0.0`；签名配置保持本地 `skip-worktree`，不进入提交。
- 真实远端发布、真实图片上传和电脑端登录确认只由用户手动执行；本地草稿成功不能冒充这些外部动作成功。
