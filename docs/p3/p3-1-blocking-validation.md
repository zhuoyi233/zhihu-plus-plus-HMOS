# P3-1 屏蔽操作闭环验证

> 工具链目标：DevEco Studio 6.1.1 Release、HarmonyOS API 26 编译 / target+compatible API 24；本批只做本地屏蔽，不发网络写请求，不读取会话 Cookie。
> 验证命令：`verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`（本机 PowerShell 执行策略限制脚本执行，实际以 `-ExecutionPolicy Bypass` 运行；worktree 首次构建前先 `ohpm install --all` 重建模块链接）。

## 范围

P3-1 在 P2 的 `BlockingRuleStore` / `BlockingRuleMatcher` / `BlockingRulesPage` 基础上补齐屏蔽操作闭环：

1. **屏蔽操作触发点**：首页 Feed 卡片、关注/热榜/日报内容卡片提供「屏蔽作者 / 屏蔽关键词」菜单；问题/回答/文章详情提供「屏蔽作者 / 屏蔽关键词」；用户主页提供「屏蔽该用户」；想法详情提供「屏蔽作者 / 屏蔽关键词 / 屏蔽话题」。触发后写入规则库并写入屏蔽记录，Feed 卡片会立即从当前列表移除。
2. **屏蔽记录页**：`BlockedFeedHistoryPage` 展示被屏蔽的作者/关键词/话题、来源内容标题与时间，支持单项删除与带确认的整体清空；入口在设置页「屏蔽记录」。
3. **屏蔽词导入导出**：屏蔽规则管理页底部新增备份面板，按上游 `BlocklistBackup` v2 JSON 格式导出（复制到剪贴板 / 弹窗查看）与导入（无效条目跳过、关键词去重）。

## 数据与持久化

- RDB schema 由 v3 连续迁移至 v4，新增 `blocked_feed_history` 表（`kind/rule_id/rule_name/content_title/content_kind/content_id/blocked_at`）及时间索引。迁移不读写 Cookie、不保存正文 HTML。
- `BlockedFeedHistoryStore` 复用 `AppDatabase` 的打开/迁移生命周期与实例内写队列，最多保留最近 500 条，单项删除与整体清空与其他写操作串行；字段长度与控制字符在数据边界拒绝。
- `BlocklistBackup.ets` 提供纯函数 `encodeBlocklistBackup` / `decodeBlocklistBackup` 与 `importBlocklistBackup`；解析走 `core` 的有界名义 AST（`parseStrictJson`），文本上限 1 MiB、每类条目上限 1000；版本只接受 1–2，未知字段忽略；导入时逐条复用 P2 的校验器，非法关键词/用户/话题跳过并计数，重复关键词在单次导入内去重。

## 状态机与安全边界

- `BlockingActionController` 持有规则网关与记录网关：`blockUser / blockKeyword / blockTopic` 先写规则再写记录（记录失败不阻塞屏蔽主流程），busy 门禁拒绝重叠操作，成功/失败只发布固定文案（失败文案不拼接数据库错误或规则值）。
- 各页面按 P2 的 Controller 模式自建控制器并在离页时释放；Feed 移除通过 `HomeFeedController.removeItem / ChannelFeedController.removeItem` 按稳定身份过滤，屏蔽成功后才移除。
- 关键词屏蔽只支持普通文本（不区分大小写），不提供正则输入，避免把管理页的「安全正则」能力复制到弹窗；屏蔽话题只在有话题名的地方（想法详情）提供，Feed 只有话题 ID 时不提供话题屏蔽。
- 日志与记录均不输出 Cookie、token 或响应体；屏蔽记录页文案明确「只保存在本机」。

## 自动化覆盖

本批新增 3 个套件共 18 个用例（241 → 260），并更新既有套件以匹配 schema v4：

- `BlockingActionState.test.ets` 6 个：屏蔽用户写规则+记录、关键词校验、非法关键词拒绝且不写、屏蔽话题、busy 门禁、reset。
- `BlockedFeedHistoryState.test.ets` 6 个：防御性快照、单项删除、清空进入空态、固定失败文案、离页拒绝操作、分类文案。
- `BlocklistBackup.test.ets` 6 个：编码/解码往返、缺省字段、拒绝畸形/超版本 JSON、导入跳过无效条目、关键词去重、不支持的版本拒绝。
- `RdbSchema.test.ets` 更新为 v4 并新增 v4 表结构断言；`P1Persistence.test.ets` 与 `P1Navigation.test.ets` 同步 v4 与新增目的地。

验证结果：`Hypium 260/260` 通过（API 26 编译，target=6.1.1(24)，compatible=6.1.1(24)）。

## 未闭环 / 延后项

- Feed 卡片「屏蔽话题」未提供：Feed 模型只有话题 ID 没有话题名，无法给出可读确认文案；待 P3-2/后续模型补话题名后再接入。
- 导出目前为「复制到剪贴板 + 弹窗查看」，未接系统文件 Picker 保存为文件（迁移计划把文件导出归入 P4/P5）。
- 上游 `BlockByKeywordsDialogContent` 的 NLP 语义关键词提取为端侧 AI 能力，鸿蒙端不迁移，改用普通关键词输入。
- 真机/虚拟机交互回归（点击屏蔽菜单、确认弹窗、列表移除、记录页删除、导入导出粘贴）依赖登录态与 DevEco 设备通道，本次未在设备上闭环，需在 P3-1 验收清单中补充。
