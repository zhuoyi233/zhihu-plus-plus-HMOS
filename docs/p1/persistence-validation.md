# P1 Preferences 与 RDB 生产基础设施验证

## 实现范围

- `AppPreferencesStore` 使用独立的 `app_preferences` Preferences 文件保存轻量外观配置。
- 主题对外契约固定为 `AppThemeMode.SYSTEM/LIGHT/DARK`；首次启动、旧值损坏或未知值均回退为跟随系统。
- `AppDatabase` 打开生产数据库 `zhihu_plus.db`，复用 P0 已验证的 `RdbSchema`，按 `0 → 1 → 2` 顺序逐版本事务迁移。
- 数据库版本高于当前版本、版本非法或迁移来源版本不匹配时直接拒绝打开；迁移失败关闭连接并保留原库，不执行删除重建。
- `getAppDatabase()` 以 `ApplicationContext` 创建进程内唯一数据库 owner，`closeAppDatabase()` 关闭但不替换 owner，避免多个实例并行迁移同一文件。
- `AppDatabase` 合并并发 open；close 开始时立即摘除缓存连接，open 必须等待 closing。关闭失败不会把旧连接放回缓存，迁移 rollback 失败也不会覆盖首个迁移错误。
- `OpenedContentStore` 直接承载 `opened_content` 表的 upsert、按主键查询和删除，不增加只转发调用的 Repository 层。
- `AppPreferencesStore` 串行执行 save/flush，快速连续保存时仍以调用顺序落盘；读取会等待此前写队列结束。普通 Error、BusinessError、null/undefined 均生成不泄漏对象内容的稳定错误信息。

生产路径没有调用 `deleteRdbStore`。`DatabaseProbe` 只对 `p0_rdb_probe.db` 使用删除重建来隔离 P0 故障迁移；生产探针不会删除 `zhihu_plus.db`。

## 纯逻辑测试

`P1Persistence.test.ets` 覆盖以下不依赖系统运行时的契约：

1. 主题值 `LIGHT/DARK` 正确解码。
2. 缺省值和未知主题值回退为 `SYSTEM`。
3. schema v0、v1、v2 分别得到连续的待执行迁移序列。
4. 负数、非整数和未来数据库版本被拒绝。
5. closing 优先于返回缓存连接或等待 opening，关闭期间不会交出即将失效的连接。
6. 普通 Error 与 null/undefined 偏好错误都能安全归一化。

测试文件由 P1 统一测试注册任务加入 `List.test.ets`；本任务不修改统一入口。

## API 24 设备验证清单

平台持久化行为不在 Hypium 本地桩环境中伪造。现有数据库探针页面会先运行隔离故障迁移，再调用生产 `AppDatabase` 与 `OpenedContentStore` 完成以下项目：

1. 首次启动读取主题为 `SYSTEM`，保存 `DARK` 后重启进程仍可恢复。
2. 写入非法旧主题值后读取安全回退为 `SYSTEM`。
3. 首次打开空数据库自动执行 v1、v2，并达到 `CURRENT_SCHEMA_VERSION`。
4. upsert 同一探针 `content_key` 两次后只有一条记录，且时间与类型为最后一次写入值。
5. 关闭并重新打开数据库后仍可查询最新记录，删除后查询为空。
6. 注入故障 migration 时版本和原数据保持不变，且生产数据库文件不被删除。
7. 应用生命周期结束时调用 `AppDatabase.close()`，后续再次 `open()` 可重新建立连接。

生产探针无论成功失败都会再次删除固定 marker 并关闭连接；不删除生产数据库，也不留下探针记录。Preferences 的主题切换、保存和进程重启恢复已在下述 API 24 设备回归中闭环。

## API 24 设备结果

在 DevEco 虚拟机 `ZhihuPlus_API24`（HarmonyOS 6.1.1 / API 24）完成真实平台验证：

- 保存深色主题后强制停止并重启应用，首页仍恢复为深色；浅色和跟随系统也能保存，状态文本为“主题设置已保存”。
- `p0_run_database_probe` 返回：故障迁移回滚到 v1，隔离库升级并重开为 v2，保留记录默认类型为 `unknown`。
- 同一次探针通过生产 `AppDatabase` 与 `OpenedContentStore` 完成双 upsert、close/reopen、查询最新 `article@2000`、删除后空查询，最终状态明确显示探针记录已删除。
- 启动日志显示关键阶段先完成 `database-migration`，随后完成 `deep-link-routing`；应用可正常进入首页和深链目的地。

## 安全与数据边界

- Preferences 仅保存非敏感轻量配置；Cookie 仍由既有 Asset Store 数据密钥与加密会话信封处理。
- `opened_content` 只保存内容键、打开时间和内容类型，不保存正文、Cookie 或账号令牌。
- 数据库使用 `SecurityLevel.S1`，符合当前非敏感阅读记录的数据等级。
