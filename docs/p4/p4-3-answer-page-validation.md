# P4-3 回答创作页面验证

## 本切片

- `WRITE_ANSWER` 已由 `P1Shell` 路由到 `AnswerPublishPage`，问题详情页增加“写回答”入口。
- 页面组合根注入 `AnswerPublishPageControllerFactory`；页面本身不持有知乎请求地址、Cookie 或发布 body。
- 游客点击入口直接前往登录；即使通过导航直达页面，也会在创建控制器前显示登录 CTA，因此不会创建草稿或执行网络写操作。
- 已登录组合根使用 `LocalDraftAnswerPublishControllerFactory`：草稿写入既有加密 `DraftRepository`，而远端草稿/正式发布由无网络占位仓储拒绝，确保当前切片不会意外发起真实知乎写请求。
- 编辑目的地携带的 `answerId` 传入 `AnswerPublishController`，优先作为既有回答编辑目标；同一草稿键只由该控制器写入，避免与 `EditorDraftController` 并发写入。

## 自动验证

- `AnswerPublishPage.test.ets` 覆盖：游客不创建控制器（从而无草稿/网络副作用）、已登录路径只通过 fake 注入控制器编辑/保存/发布，以及离页释放控制器。
- 执行顺序遵循 `AGENTS.md`：先 `verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`，再进行完整 HAP 构建与 Hypium 验证。

## 有意未覆盖的范围

- 本切片不实现真实回答写接口、远端草稿 API、富文本编辑器或图片上传；这些能力必须另行提供受测试的 `AnswerPublishRepository` 实现后再替换组合根注入。
