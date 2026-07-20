# P0 Preferences 与 RDB 验证记录

> 验证日期：2026-07-20

## 数据边界

- Preferences 继续只保存轻量配置和加密会话信封；Cookie 明文和数据密钥不进入 Preferences。
- RDB 保存可查询、需要索引和迁移的业务数据，例如已读/打开记录、历史、过滤记录和本地推荐数据。
- P0 使用独立的 `p0_rdb_probe.db`，不读取或转换 Android Room 数据库。

Preferences 的跨进程恢复、过期清理和清除已在 `session-validation.md` 验证。本项集中验证 RDB schema 生命周期。

## Schema 原型

| 版本 | 结构 | 迁移动作 |
| --- | --- | --- |
| v1 | `opened_content(content_key, opened_at)` | 建表，`content_key` 为主键 |
| v2 | 新增 `content_type`，默认 `unknown` | `ALTER TABLE` 并为 `opened_at` 建索引 |

版本迁移是连续、显式的 `0 → 1 → 2`。每一步持有来源版本、目标版本和 SQL 列表；打开数据库后必须先检查 `RdbStore.version`，禁止跳过未知版本或静默重建。

## 失败回滚验证

原型执行以下过程：

1. 创建 v1 schema 并写入一条真实形态的回答打开记录。
2. 开始 v1 → v2 事务，先增加 `content_type`，再故意访问不存在的迁移表。
3. 捕获失败并调用 `rollBack()`。
4. 验证数据库版本仍为 v1、新列不存在、原记录仍为 1 条。
5. 重新执行正确的 v2 迁移并提交。
6. 关闭数据库后重新打开，验证版本为 v2、原记录仍在且默认类型为 `unknown`。
7. 关闭并删除 P0 临时数据库。

迁移通过 `RdbStore.beginTransaction()`、`executeSql()`、`commit()` 和 `rollBack()` 完成，最低 API 20 已覆盖这些接口。参考：[关系型数据库持久化指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-rdb-store)、[`relationalStore` API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-relationalstore)。

## 双版本虚拟机结果

| 验证项 | API 20 / HarmonyOS 6.0.0 | API 24 / HarmonyOS 6.1.1 |
| --- | --- | --- |
| 新建 v1 数据库 | 通过 | 通过 |
| 写入测试记录 | 通过 | 通过 |
| 故障迁移触发 | 通过 | 通过 |
| schema/version/data 原子回滚 | 通过 | 通过 |
| 正确升级到 v2 | 通过 | 通过 |
| 关闭重开后版本和数据保留 | 通过 | 通过 |
| 临时数据库清理 | 通过 | 通过 |

两台设备最终均显示：`失败迁移回滚到 v1；升级并重开为 v2；保留 1 条记录，默认类型 unknown`。

## 构建与测试

- API 24 SDK 下 Debug HAP：`BUILD SUCCESSFUL`。
- 新增 3 个 schema 契约测试，覆盖版本连续性、v2 非破坏性字段/索引迁移和未知版本拒绝。
- 当前 ArkTS 测试定义总数为 30；DevEco CLI 暂未暴露 `src/test` 本地单元测试任务，CI 后续必须补可重复执行入口。

## 后续约束

- 生产数据库初始化必须复用同一套连续 migration 契约，不能使用删除重建作为升级策略。
- 应用升级时若 migration 失败，应保留旧数据库并阻止业务层继续写入，同时显示可恢复错误；不能部分升级后继续运行。
- `opened_content` 只是 P0 最小 schema。完整表结构在 P1 按领域拆分，并补唯一约束、外键取舍和查询索引基线。
- S1 适用于当前非敏感阅读记录原型；Cookie、令牌等秘密仍由 Asset Store 与加密信封管理，不写入普通 RDB。

建库、升级、失败回滚和重开验证均在 API 20/24 通过，因此 `P0-DB-01` 标记为通过。
