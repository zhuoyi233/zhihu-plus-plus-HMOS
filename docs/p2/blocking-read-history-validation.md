# P2 屏蔽规则与本地已读历史验证

> 工具链目标：DevEco Studio 6.1.1 Release、HarmonyOS API 24；本批不包含端侧 AI、NLP 语义屏蔽、屏蔽历史或配置导入导出。

## Android Lite 行为证据

只读核对 `Android-master` 后，本批复用以下合同：

- `BlockedKeyword` 保存关键词、是否区分大小写和是否为正则；普通关键词按对应大小写语义做包含匹配，正则编译失败按未命中处理。
- `BlockedUser` 与 `BlockedTopic` 使用稳定 ID 作为主键，同时保留仅供管理页展示的名称；三类规则均支持新增、单项删除和分类清空。
- `FeedFilterSettings` 的关键词、用户和话题屏蔽默认开启，话题命中阈值默认 1。
- Android `HistoryStorage` 按目的地去重，再次打开会移动到最新位置，只保留最近 1000 条并支持整体清理。

P2 只迁移规则型精确屏蔽。Android 的 `NLP_SEMANTIC`、已屏蔽内容详情记录、Feed 屏蔽记录、备份导入导出分别属于端侧 AI 或 P3/P5，不进入本批。

## HarmonyOS 持久化

RDB schema 从 v2 连续迁移至 v3，新增 `blocked_keywords`、`blocked_users` 和 `blocked_topics` 三张本地表及时间索引。迁移不读取网络、不写 Cookie，也不保存被过滤内容的标题、摘要或正文。

`BlockingRuleStore` 提供三类规则的查询、新增、删除和分类清空：

- 写操作通过实例内 Promise 队列串行化，失败不会阻断后续写；读取等待先前写结束。
- 每类最多保留最近 1000 条，用户和话题按 ID 替换；所有 ResultSet 都在 `finally` 中关闭。
- 关键词总长 1–200，ID 只允许 1–128 位 ASCII 字母、数字、下划线或连字符，显示名 1–200；控制字符在数据边界拒绝。
- API 24 JavaScript RegExp 没有可中断超时。本批因此采用保守安全子集：拒绝 lookaround、反向引用、嵌套量词和重复通配回溯结构，并把待匹配标题与摘要限制为 8192 字符。损坏或旧数据中的非法正则按未命中处理。

`AppPreferencesStore` 复用同一个 Preferences 文件，持久化三类开关和 1–100 的话题阈值；读写与主题设置共用保存队列，避免后完成的旧写覆盖新值。

详情页已经通过 `OpenedContentStore.upsert()` 写入 `type:id`、打开时间和类型。本批直接扩展该 Store：

- upsert 后裁剪为最近 1000 个稳定键，再次打开同一键只更新时间；
- `queryRecent()` 按打开时间和稳定键倒序返回；
- 单项删除与整体清理同其他写操作串行；
- 产品页只接受 `question`、`answer`、`article`、`pin` 和 1–30 位非零十进制 ID。损坏行会被跳过，不会成为导航参数；Pin 使用强类型 `ReadHistoryContentKind.PIN` 与 `ReadHistoryOpenTarget` 打开，不从展示文字反推目的地。

## 可注入过滤合同

生产数据链不能只依赖规则管理页。`ContentBlockingMatcher` 是 repository/controller 可注入的批次接口：

```text
createSession(): Promise<ContentBlockingSession>
ContentBlockingSession.match(content: BlockableContentSummary): BlockingMatch | undefined
```

输入固定为 `title`、`excerpt`、可选 `authorId` 和 `topicIds`。每次首屏或分页解码只创建一个 session；生产 `BlockingRuleMatcher` 此时读取一次规则快照与开关，批内所有内容同步调用纯函数 `matchBlockingRules()`。session 深拷贝快照，规则并发更新不会让同一页出现前后不一致；下一页或刷新创建新 session 后生效。这里没有全局长期缓存，也不会按 50 条内容重复执行约 200 次数据库查询。匹配顺序与 Lite 主链一致：用户、关键词、话题阈值。错误统一为固定分类，不发网络请求，不读取会话 Cookie。

`FeedTargetSummary` 与搜索结果模型已扩展稳定作者 ID 和话题 ID，Home、Channel、Search 的 include、decoder 与测试均从真实协议字段提取这些 ID 后传给 matcher；不存在可靠 ID 时传空数组，不用名称、URL 或页面文字猜 ID。

## 原生 ArkUI 与状态

`BlockingRulesPage` 提供三类开关、话题阈值、三分类切换、新增、单项删除和带确认的分类清空。`BlockingRulesController` 使用 busy 与 generation 门禁，拒绝重叠写，离页后不接收迟到状态；错误只显示固定文案，不拼接数据库错误或规则值。

`ReadHistoryPage` 展示问题、回答、文章或想法类型、数字 ID 和打开时间，支持重新读取、强类型打开回调、单项删除与带确认的整体清空。页面明确提示历史只保存在本机，不保存正文、Cookie、搜索词或账号信息。离页会使 generation 失效，迟到读取不能回写已销毁页面。

## 自动化覆盖

子任务 C 增加 17 个独立 Hypium 用例，并在既有 RDB suite 增加 1 个迁移用例，共贡献 18 项：

- `BlockingRuleMatcher.test.ets` 7 个：输入边界、安全正则、大小写、固定关键词原因、用户优先级、开关、话题阈值，以及单批只读取一次不可变快照。
- `BlockingRulesState.test.ets` 5 个：三类加载与防御性快照、新增/分类清空、开关持久化、固定错误和离页拒绝操作。
- `ReadHistoryState.test.ets` 5 个：严格键解码（含 Pin 展示和强类型打开目标）、损坏行过滤、Pin 单删/整体清空、固定错误和离页拒绝操作。
- `RdbSchema.test.ets` 新增 1 个：v3 三表迁移且不包含正文/Cookie 字段；`P1Persistence.test.ets` 同步连续版本断言。

## 集成状态

共享导出、三个 suite、BLOCKING_RULES/READ_HISTORY 目的地、设置入口、Pin 历史映射、应用级数据库与 Preferences 组合均已接入。Home、Channel、Search 共用生产 matcher，并在每次首屏或分页中只创建一次 session。第三批接入后统一静态注册为 32 组、223 项。

## 尚未执行的门禁

当前会话没有暴露 DevEco Code 的 `arkts_check`、`build_project` 与 `start_app` 工具，属于工具缺失而非编译失败。工具可用后必须依次执行单文件严格检查、API 24 工程构建和虚拟机启动，并验证三类规则管理、过滤生效、历史重开/去重、单删/清空、重启持久化和大字体布局。本批未修改 `build-profile.json5`，也没有执行 Git 写操作。
