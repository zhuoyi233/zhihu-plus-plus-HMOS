# P4-1 安全草稿存储验证

## 交付范围

- RDB schema 从 v4 连续迁移到 v5，新增 `content_drafts` 元数据表及账号/更新时间索引；迁移沿用 `AppDatabase` 的事务与回滚路径。
- 草稿身份为 `answer:{sha256-account-key}:{questionId}` 或 `pin:{sha256-account-key}:{localUuid}`。账号键由稳定账号标识 SHA-256 得到，不接收 Cookie。
- RDB 仅保存类型、目标、远端内容 ID、标题、文本长度、目录开关、图片/话题引用、dirty、版本和时间；不保存 HTML、Cookie、上传凭证或图片字节。
- HTML 使用独立 `zhihu-plus-content-draft-key-v1` Asset Store alias 的 AES-GCM 信封保存到应用 `filesDir/content-drafts-v1`。写入先落临时文件并关闭，再通过 `moveFile(..., 0)` 覆盖目标。
- `DraftRepository` 串行化写入，读取时将缺失或损坏信封收敛为 `CORRUPT`，只在显式丢弃时删除正文和元数据。

## 自动化覆盖

- v4→v5 连续迁移和敏感列门禁；
- 回答/想法键的账号隔离、UUID/内容 ID 格式门禁、稳定账号摘要；
- 元数据版本递增、同问题跨账号不串草稿、损坏信封收敛、显式丢弃清理；
- 独立草稿 key alias 不等于 Cookie session alias。

## 本次验证

执行日期：2026-08-20。

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

结果：Hypium `416/416`；完整签名 HAP 构建成功，已校验 `target=24`、`compatible=24` 与 bundle
`com.github.zhuoyi233.zhplus`。签名配置仅存在于 worktree 的 skip-worktree 本地文件，未进入提交。

## API 24 设备清单（待人工验收）

- 新建回答并强制停止后恢复；
- 同问题切换两个账号，确认仅显示当前账号草稿；
- 新建想法、保存、显式丢弃，确认正文与元数据均清理；
- 升级 v4 安装包后确认旧本地数据不丢失、新草稿可恢复；
- 损坏草稿信封后确认页面给出安全恢复入口且不显示正文或底层错误。

## 已知限制

- 本切片只交付数据层；编辑器状态机、1500 ms debounce、离页确认和原生预览属于下一 P4-1 子切片。
- 草稿 key 和正文目录为应用私有路径，未进入备份或分享流程；临时图片引用清理在 P4-2 选择/上传链路落地后接入。
