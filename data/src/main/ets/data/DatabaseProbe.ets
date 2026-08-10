import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { CURRENT_SCHEMA_VERSION, schemaMigrationTo, SchemaMigration } from './RdbSchema';

const DATABASE_NAME = 'p0_rdb_probe.db';
const TABLE_NAME = 'opened_content';
const PROBE_KEY = 'answer:2035661632110585441';

export interface DatabaseProbeResult {
  rollbackVersion: number;
  finalVersion: number;
  recordCount: number;
  restoredType: string;
}

export class DatabaseProbe {
  private readonly context: common.UIAbilityContext;
  private readonly config: relationalStore.StoreConfig = {
    name: DATABASE_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async run(): Promise<DatabaseProbeResult> {
    await relationalStore.deleteRdbStore(this.context, this.config);
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await relationalStore.getRdbStore(this.context, this.config);

      await this.applyMigration(store, schemaMigrationTo(1));
      await store.executeSql(
        `INSERT INTO ${TABLE_NAME} (content_key, opened_at) VALUES (?, ?)`,
        [PROBE_KEY, Date.now()]
      );

      const versionTwo = schemaMigrationTo(2);
      let migrationFailed = false;
      try {
        await this.applyMigration(store, {
          fromVersion: versionTwo.fromVersion,
          toVersion: versionTwo.toVersion,
          statements: [versionTwo.statements[0], 'INSERT INTO missing_migration_table VALUES (1)']
        });
      } catch (_error) {
        migrationFailed = true;
      }
      if (!migrationFailed) {
        throw new Error('故障迁移未按预期失败');
      }

      const rollbackVersion = store.version;
      const rolledBackColumn = await this.hasColumn(store, TABLE_NAME, 'content_type');
      const rollbackCount = await this.recordCount(store);
      if (rollbackVersion !== 1 || rolledBackColumn || rollbackCount !== 1) {
        throw new Error('迁移失败后 schema、版本或原数据没有完整回滚');
      }

      await this.applyMigration(store, versionTwo);
      await store.close();
      store = undefined;

      store = await relationalStore.getRdbStore(this.context, this.config);
      const finalVersion = store.version;
      const recordCount = await this.recordCount(store);
      const restoredType = await this.contentType(store, PROBE_KEY);

      if (finalVersion !== CURRENT_SCHEMA_VERSION || recordCount !== 1 || restoredType !== 'unknown') {
        throw new Error('升级后的版本、数据或默认字段重开验证失败');
      }
      return {
        rollbackVersion: rollbackVersion,
        finalVersion: finalVersion,
        recordCount: recordCount,
        restoredType: restoredType
      };
    } finally {
      if (store !== undefined) {
        await store.close();
      }
      await relationalStore.deleteRdbStore(this.context, this.config);
    }
  }

  private async applyMigration(store: relationalStore.RdbStore, migration: SchemaMigration): Promise<void> {
    if (store.version !== migration.fromVersion) {
      throw new Error(`Schema version mismatch: expected ${migration.fromVersion}, got ${store.version}`);
    }
    store.beginTransaction();
    try {
      for (let index = 0; index < migration.statements.length; index += 1) {
        await store.executeSql(migration.statements[index]);
      }
      store.version = migration.toVersion;
      store.commit();
    } catch (error) {
      store.rollBack();
      const message = error instanceof Error ? error.message : 'Unknown migration error';
      throw new Error(message);
    }
  }

  private async hasColumn(store: relationalStore.RdbStore, table: string, column: string): Promise<boolean> {
    const resultSet = await store.querySql(`PRAGMA table_info(${table})`);
    try {
      const nameIndex = resultSet.getColumnIndex('name');
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(nameIndex) === column) {
          return true;
        }
      }
      return false;
    } finally {
      resultSet.close();
    }
  }

  private async recordCount(store: relationalStore.RdbStore): Promise<number> {
    const resultSet = await store.querySql(`SELECT COUNT(*) AS total FROM ${TABLE_NAME}`);
    try {
      return resultSet.goToFirstRow() ? resultSet.getLong(resultSet.getColumnIndex('total')) : 0;
    } finally {
      resultSet.close();
    }
  }

  private async contentType(store: relationalStore.RdbStore, contentKey: string): Promise<string> {
    const resultSet = await store.querySql(
      `SELECT content_type FROM ${TABLE_NAME} WHERE content_key = ?`,
      [contentKey]
    );
    try {
      return resultSet.goToFirstRow() ? resultSet.getString(resultSet.getColumnIndex('content_type')) : '';
    } finally {
      resultSet.close();
    }
  }
}
