import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { CURRENT_SCHEMA_VERSION, schemaMigrationTo, SchemaMigration } from './RdbSchema';

const DATABASE_NAME = 'zhihu_plus.db';

export enum DatabaseOpenPlan {
  RETURN_STORE,
  WAIT_FOR_OPEN,
  WAIT_FOR_CLOSE,
  START_OPEN
}

export interface DatabaseLifecycleSnapshot {
  hasStore: boolean;
  hasOpening: boolean;
  hasClosing: boolean;
}

export function planDatabaseOpen(snapshot: DatabaseLifecycleSnapshot): DatabaseOpenPlan {
  if (snapshot.hasClosing) {
    return DatabaseOpenPlan.WAIT_FOR_CLOSE;
  }
  if (snapshot.hasStore) {
    return DatabaseOpenPlan.RETURN_STORE;
  }
  if (snapshot.hasOpening) {
    return DatabaseOpenPlan.WAIT_FOR_OPEN;
  }
  return DatabaseOpenPlan.START_OPEN;
}

export function pendingSchemaVersions(currentVersion: number): Array<number> {
  if (!Number.isInteger(currentVersion) || currentVersion < 0 || currentVersion > CURRENT_SCHEMA_VERSION) {
    throw new Error(`Unsupported schema version: ${currentVersion}`);
  }

  const versions: Array<number> = [];
  for (let version = currentVersion + 1; version <= CURRENT_SCHEMA_VERSION; version += 1) {
    versions.push(version);
  }
  return versions;
}

export class AppDatabase {
  private readonly context: common.Context;
  private readonly config: relationalStore.StoreConfig = {
    name: DATABASE_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };
  private store: relationalStore.RdbStore | undefined = undefined;
  private opening: Promise<relationalStore.RdbStore> | undefined = undefined;
  private closing: Promise<void> | undefined = undefined;

  constructor(context: common.Context) {
    this.context = context;
  }

  async open(): Promise<relationalStore.RdbStore> {
    while (true) {
      const plan = planDatabaseOpen({
        hasStore: this.store !== undefined,
        hasOpening: this.opening !== undefined,
        hasClosing: this.closing !== undefined
      });
      if (plan === DatabaseOpenPlan.WAIT_FOR_CLOSE) {
        const closing = this.closing;
        if (closing !== undefined) {
          await closing;
        }
        continue;
      }
      if (plan === DatabaseOpenPlan.RETURN_STORE) {
        const store = this.store;
        if (store !== undefined) {
          return store;
        }
        continue;
      }
      if (plan === DatabaseOpenPlan.WAIT_FOR_OPEN) {
        const opening = this.opening;
        if (opening !== undefined) {
          const openedStore = await opening;
          if (this.closing === undefined) {
            this.store = openedStore;
            return openedStore;
          }
        }
        continue;
      }

      const opening = this.openAndMigrate();
      this.opening = opening;
      try {
        const openedStore = await opening;
        if (this.closing === undefined) {
          this.store = openedStore;
          return openedStore;
        }
      } finally {
        if (this.opening === opening) {
          this.opening = undefined;
        }
      }
    }
  }

  async close(): Promise<void> {
    if (this.closing !== undefined) {
      return this.closing;
    }

    const store = this.store;
    const opening = this.opening;
    this.store = undefined;
    const closing = this.closeConnections(store, opening);
    this.closing = closing;
    try {
      await closing;
    } finally {
      if (this.closing === closing) {
        this.closing = undefined;
      }
    }
  }

  private async openAndMigrate(): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(this.context, this.config);
    try {
      const versions = pendingSchemaVersions(store.version);
      for (let index = 0; index < versions.length; index += 1) {
        await this.applyMigration(store, schemaMigrationTo(versions[index]));
      }
      return store;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Database open failed';
      try {
        await store.close();
      } catch (_closeError) {
      }
      throw new Error(message);
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
      await store.commit();
    } catch (error) {
      try {
        await store.rollBack();
      } catch (_rollbackError) {
      }
      const message = error instanceof Error ? error.message : 'Database migration failed';
      throw new Error(message);
    }
  }

  private async closeConnections(store: relationalStore.RdbStore | undefined,
    opening: Promise<relationalStore.RdbStore> | undefined): Promise<void> {
    let openingStore: relationalStore.RdbStore | undefined = undefined;
    if (opening !== undefined) {
      try {
        openingStore = await opening;
      } catch (_openError) {
      }
    }
    let failure: Error | undefined = undefined;
    if (store !== undefined) {
      try {
        await store.close();
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Database close failed';
        failure = new Error(message);
      }
    }
    if (openingStore !== undefined && openingStore !== store) {
      try {
        await openingStore.close();
      } catch (error) {
        if (failure === undefined) {
          const message = error instanceof Error ? error.message : 'Opening database close failed';
          failure = new Error(message);
        }
      }
    }
    if (failure !== undefined) {
      throw failure;
    }
  }
}

let appDatabase: AppDatabase | undefined = undefined;

export function getAppDatabase(context: common.Context): AppDatabase {
  if (appDatabase === undefined) {
    appDatabase = new AppDatabase(context.getApplicationContext());
  }
  return appDatabase;
}

export async function closeAppDatabase(): Promise<void> {
  if (appDatabase !== undefined) {
    await appDatabase.close();
  }
}
