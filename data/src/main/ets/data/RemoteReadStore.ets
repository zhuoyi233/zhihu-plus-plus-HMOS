import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';
import { RemoteReadGateway, RemoteReadRecord } from '../repository/RemoteHistorySync';

export function remoteReadQuerySql(keyCount: number): string {
  if (!Number.isInteger(keyCount) || keyCount < 1 || keyCount > 500) {
    throw new Error('Remote read query requires 1 to 500 keys');
  }
  const placeholders: Array<string> = [];
  for (let index = 0; index < keyCount; index += 1) placeholders.push('?');
  return 'SELECT content_key FROM remote_read_content WHERE account_key = ? AND content_key IN (' +
    placeholders.join(',') + ')';
}

/** 独立保存远端已读身份，避免本地浏览列表的 1000 条展示上限丢失去重信息。 */
export class RemoteReadStore implements RemoteReadGateway {
  private readonly database: AppDatabase;
  private queue: Promise<void> = Promise.resolve();

  constructor(database: AppDatabase) { this.database = database; }

  claimSync(account: string, now: number): Promise<boolean> {
    const operation = this.queue.then(async (): Promise<boolean> => {
      const store = await this.database.open();
      await store.insert('remote_history_sync', { account_key: account, read_time: 0 },
        relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
      const eligible = new relationalStore.RdbPredicates('remote_history_sync').equalTo('account_key', account)
        .beginWrap().isNull('last_attempt').or().lessThanOrEqualTo('last_attempt', now - 60000).endWrap();
      return await store.update({ last_attempt: now }, eligible) > 0;
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async watermark(account: string): Promise<number> {
    await this.queue;
    const store = await this.database.open();
    const result = await store.query(new relationalStore.RdbPredicates('remote_history_sync')
      .equalTo('account_key', account), ['read_time']);
    try { return result.goToFirstRow() ? result.getLong(0) : 0; } finally { result.close(); }
  }

  importPage(account: string, records: Array<RemoteReadRecord>): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const store = await this.database.open();
      for (const record of records) {
        // 身份只存一次；不覆盖本机阅读时间、标题，也不计入曝光次数。
        await store.insert('remote_read_content', { account_key: account, content_key: record.contentKey },
          relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
      }
    });
  }

  saveWatermark(account: string, time: number): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const store = await this.database.open();
      await store.insert('remote_history_sync', { account_key: account, read_time: 0 },
        relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
      await store.update({ read_time: time },
        new relationalStore.RdbPredicates('remote_history_sync').equalTo('account_key', account));
    });
  }

  async readKeys(account: string, keys: Array<string>): Promise<Array<string>> {
    await this.queue;
    if (keys.length === 0) return [];
    const store = await this.database.open();
    const found: Array<string> = [];
    const unique = Array.from(new Set<string>(keys));
    for (let offset = 0; offset < unique.length; offset += 500) {
      const batch = unique.slice(offset, offset + 500);
      const args: Array<relationalStore.ValueType> = [account];
      batch.forEach((key: string): void => { args.push(key); });
      const result = await store.querySql(remoteReadQuerySql(batch.length), args);
      try {
        if (result.goToFirstRow()) {
          do { found.push(result.getString(0)); } while (result.goToNextRow());
        }
      } finally { result.close(); }
    }
    return found;
  }

  clear(account: string): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const store = await this.database.open();
      await store.delete(new relationalStore.RdbPredicates('remote_history_sync').equalTo('account_key', account));
      await store.delete(new relationalStore.RdbPredicates('remote_read_content').equalTo('account_key', account));
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const result = this.queue.then(operation);
    this.queue = result.catch((): void => {});
    return result;
  }
}
