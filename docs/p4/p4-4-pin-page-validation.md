# P4-4 想法创作页验证

验证日期：2026-08-20

## 交付范围

- 新增可注入 `PinPublishPage` 与 `PinPublishPageController`，不改动 `P1Shell`、`Index` 或全局目的地；页面仅通过 `onBack`、`onLoginRequired`、`onPublished(contentId)` 三个强类型回调交给组合根处理导航。
- 页面协调器沿用 `EditorDraftController` 的 activate/deactivate 门禁，但不叠加 autosave：`PinPublishController` 是唯一可写入 `DraftRepository` 的创作状态机，避免两个控制器对同一草稿并发写入。
- 发布仍遵循本地加密草稿→远端草稿→正式发布。访客、空内容和取消路径在进入任何本地或远端写入前终止；离开后可观察状态清空正文，状态文案不包含正文、Cookie 或上游错误。
- UI 提供标题、正文、话题建议/选择、保存草稿、发布和取消；图片数组保留为注入接口，等待 P4-2 选择器组合根接入。

## 自动化覆盖

`PinPublishPageState.test.ets` 使用 fake 覆盖：

- 游客编辑、保存和发布全部无写入，且固定登录文案不含正文；
- 已登录空内容不触发本地草稿或远端写入；
- 取消后不写入、取消仓储请求、并从 released 状态移除正文；
- 已登录非空内容经 `PinPublishState` 的草稿→远端草稿→发布链路，并仅通过 `onPublished(contentId)` 返回内容 ID。

## 待组合根与设备验收

- 待 P4 创作目的地统一落位后，组合根注入已验证的账号身份、发布仓储、加密草稿仓储、trace ID 和话题防抖 scheduler；当前切片不创建这些依赖，也不发起真实写请求。
- 在 API 24 设备使用专用测试账号验收：游客点击、空标题/正文、软键盘下取消、保存后重进、发布成功回调、403 风控提示；不得在日志、截图或回调中记录正文与 Cookie。
