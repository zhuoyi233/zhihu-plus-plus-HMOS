# P4-1 编辑器草稿协调验证

## 交付范围

- `EditorDraftController` 位于 `entry/pages`，不触碰 `P1Shell`、目的地注册或真实发布链路。
- 新草稿使用调用方提供的初始标题、正文、目录开关及图片/话题引用；已有草稿优先从 `DraftRepository` 恢复。
- 任意编辑使用 1500 ms 本地 autosave；显式 `flush()` 取消等待并将最新 revision 交给加密草稿仓储。
- 写入进行时仍可编辑。若出现新 revision，协调器只在显式 flush 后连续写入最新内容；离页时 generation 门禁阻止迟到异步结果回写 UI。
- 损坏草稿只显示固定恢复失败文案，并提供显式 `discard()`；不展示或记录正文、Cookie、密钥或底层错误。

## 自动化覆盖

- 新建内容与已有草稿恢复优先级；
- 标题、正文、目录开关、图片/话题引用的 debounce 保存；
- 写入中编辑后的显式 flush，及离页迟到写入门禁；
- 损坏信封的安全丢弃路径。

## 本次验证

执行日期：2026-08-20。

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

结果：首次依赖安装后，编译与 Hypium `463/463` 通过；完整 HAP 构建成功，校验
`target=24`、`compatible=24` 与 bundle `com.github.zhuoyi233.zhplus`。独立 worktree 未复制主工作树的
skip-worktree 本地签名配置，因此仅产出 unsigned HAP；签名材料与配置均未进入本提交。

## API 24 设备清单（待人工验收）

- 新建回答/想法，连续编辑后 1500 ms 内退出重进，确认标题、正文、目录与引用恢复；
- 编辑时立即离页，选择“保存草稿并退出”调用 `flush()` 后强制停止并确认恢复；
- 模拟写入失败和损坏正文信封，确认只显示固定文案且可显式丢弃；
- 200% 字体和软键盘状态下确认后续页面接线不会遮挡保存/离页选择。

## 已知限制

- 本切片只交付独立控制器和 fake 测试；真实编辑器 UI、原生预览、离页三选项弹窗及远端草稿 30 秒同步仍由后续组合根接线。
- 该控制器不创建账号身份，也不发起发布、上传或网络请求；调用方必须提供已验证的 `ContentDraftIdentity`。
