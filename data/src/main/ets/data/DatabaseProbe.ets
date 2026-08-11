import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { AppDatabase, getAppDatabase } from './AppDatabase';
import { OpenedContent, OpenedContentStore } from './OpenedContentStore';
import { CURRENT_SCHEMA_VERSION, schemaMigrationTo, SchemaMigration } from './RdbSchema';

const DATABASE_NAME = 'p0_rdb_probe.db';
const TABLE_NAME = 'opened_content';
const PROBE_KEY = 'answer:2035661632110585441';
const PRODUCTION_PROBE_KEY = 'probe:p1-production-opened-content';

export interface DatabaseProbeResult {
  rollbackVersion: number;
  finalVersion: number;
  recordCount: number;
  restoredType: string;
  productionVersion: number;
  productionRestoredAt: number;
  productionRestoredType: string;
  productionDeleted: boolean;
}

interface MigrationProbeResult {
  rollbackVersion: number;
  finalVersion: number;
  recordCount: number;
  restoredType: string;
}

interface ProductionProbeResult {
  version: number;
  restoredAt: number;
  restoredType: string;
  deleted: boolean;
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
    const migration = await this.runMigrationProbe();
    const production = await this.runProductionProbe();
    return {
      rollbackVersion: migration.rollbackVersion,
      finalVersion: migration.finalVersion,
      recordCount: migration.recordCount,
      restoredType: migration.restoredType,
      productionVersion: production.version,
      productionRestoredAt: production.restoredAt,
      productionRestoredType: production.restoredType,
      productionDeleted: production.deleted
    };
  }

  private async runMigrationProbe(): Promise<MigrationProbeResult> {
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

  private async runProductionProbe(): Promise<ProductionProbeResult> {
    const database: AppDatabase = getAppDatabase(this.context);
    const openedContent = new OpenedContentStore(database);
    let result: ProductionProbeResult | undefined = undefined;
    let failure: Error | undefined = undefined;
    try {
      const initialStore = await database.open();
      if (initialStore.version !== CURRENT_SCHEMA_VERSION) {
        throw new Error(`生产数据库首次打开版本错误：v${initialStore.version}`);
      }
      await openedContent.delete(PRODUCTION_PROBE_KEY);
      const first: OpenedContent = {
        contentKey: PRODUCTION_PROBE_KEY,
        openedAt: 1000,
        contentType: 'answer'
      };
      const latest: OpenedContent = {
        contentKey: PRODUCTION_PROBE_KEY,
        openedAt: 2000,
        contentType: 'article'
      };

      await openedContent.upsert(first);
      await openedContent.upsert(latest);
      await database.close();

      const reopenedStore = await database.open();
      const restored = await openedContent.query(PRODUCTION_PROBE_KEY);
      if (reopenedStore.version !== CURRENT_SCHEMA_VERSION || restored === undefined ||
        restored.openedAt !== latest.openedAt || restored.contentType !== latest.contentType) {
        throw new Error('生产数据库升级、覆盖写或关闭重开验证失败');
      }

      const deleted = await openedContent.delete(PRODUCTION_PROBE_KEY);
      const deletedRecord = await openedContent.query(PRODUCTION_PROBE_KEY);
      if (!deleted || deletedRecord !== undefined) {
        throw new Error('生产数据库探针记录删除验证失败');
      }
      result = {
        version: reopenedStore.version,
        restoredAt: restored.openedAt,
        restoredType: restored.contentType,
        deleted: true
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : '生产数据库验证发生未知错误';
      failure = new Error(message);
    }

    try {
      await openedContent.delete(PRODUCTION_PROBE_KEY);
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知清理错误';
      failure = failure === undefined ? new Error(`生产探针清理失败：${message}`) :
        new Error(`${failure.message}；生产探针清理失败：${message}`);
    }
    try {
      await database.close();
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知关闭错误';
      failure = failure === undefined ? new Error(`生产数据库关闭失败：${message}`) :
        new Error(`${failure.message}；生产数据库关闭失败：${message}`);
    }

    if (failure !== undefined) {
      throw failure;
    }
    if (result === undefined) {
      throw new Error('生产数据库验证未返回结果');
    }
    return result;
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
      await store.commit();
    } catch (error) {
      try {
        await store.rollBack();
      } catch (_rollbackError) {
      }
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
