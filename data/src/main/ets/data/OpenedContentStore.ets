import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';

const TABLE_NAME = 'opened_content';
export const MAX_READ_HISTORY_ITEMS: number = 1000;

export interface OpenedContent {
  contentKey: string;
  openedAt: number;
  contentType: string;
}

export interface ReadHistoryGateway {
  queryRecent(limit?: number): Promise<Array<OpenedContent>>;
  delete(contentKey: string): Promise<boolean>;
  clear(): Promise<void>;
}

export class OpenedContentStore implements ReadHistoryGateway {
  private readonly database: AppDatabase;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(database: AppDatabase) {
    this.database = database;
  }

  upsert(content: OpenedContent): Promise<void> {
    this.validateContent(content);
    const operation = this.mutationQueue.then(async (): Promise<void> => {
      const store = await this.database.open();
      const values: relationalStore.ValuesBucket = {
        content_key: content.contentKey,
        opened_at: content.openedAt,
        content_type: content.contentType
      };
      const rowId = await store.insert(TABLE_NAME, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (rowId === -1) {
        throw new Error('Opened content upsert failed');
      }
      await store.executeSql('DELETE FROM opened_content WHERE content_key NOT IN (' +
        'SELECT content_key FROM opened_content ORDER BY opened_at DESC, content_key DESC LIMIT 1000)');
    });
    this.mutationQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async query(contentKey: string): Promise<OpenedContent | undefined> {
    this.validateContentKey(contentKey);
    await this.mutationQueue;
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME).equalTo('content_key', contentKey);
    const resultSet = await store.query(predicates, ['content_key', 'opened_at', 'content_type']);
    try {
      if (!resultSet.goToFirstRow()) {
        return undefined;
      }
      return {
        contentKey: resultSet.getString(resultSet.getColumnIndex('content_key')),
        openedAt: resultSet.getLong(resultSet.getColumnIndex('opened_at')),
        contentType: resultSet.getString(resultSet.getColumnIndex('content_type'))
      };
    } finally {
      resultSet.close();
    }
  }

  async queryRecent(limit: number = MAX_READ_HISTORY_ITEMS): Promise<Array<OpenedContent>> {
    if (!Number.isSafeInteger(limit) || limit <= 0 || limit > MAX_READ_HISTORY_ITEMS) {
      throw new Error('Read history limit must be between 1 and 1000');
    }
    await this.mutationQueue;
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      .orderByDesc('opened_at').orderByDesc('content_key').limitAs(limit);
    const resultSet = await store.query(predicates, ['content_key', 'opened_at', 'content_type']);
    const result: Array<OpenedContent> = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          result.push({
            contentKey: resultSet.getString(resultSet.getColumnIndex('content_key')),
            openedAt: resultSet.getLong(resultSet.getColumnIndex('opened_at')),
            contentType: resultSet.getString(resultSet.getColumnIndex('content_type'))
          });
        } while (resultSet.goToNextRow());
      }
      return result;
    } finally {
      resultSet.close();
    }
  }

  delete(contentKey: string): Promise<boolean> {
    this.validateContentKey(contentKey);
    const operation = this.mutationQueue.then(async (): Promise<boolean> => {
      const store = await this.database.open();
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME).equalTo('content_key', contentKey);
      return await store.delete(predicates) > 0;
    });
    this.mutationQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  clear(): Promise<void> {
    const operation = this.mutationQueue.then(async (): Promise<void> => {
      const store = await this.database.open();
      await store.delete(new relationalStore.RdbPredicates(TABLE_NAME));
    });
    this.mutationQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private validateContent(content: OpenedContent): void {
    this.validateContentKey(content.contentKey);
    if (!Number.isSafeInteger(content.openedAt) || content.openedAt < 0) {
      throw new Error('Opened timestamp must be a non-negative safe integer');
    }
    if (content.contentType.trim().length === 0) {
      throw new Error('Content type must not be blank');
    }
  }

  private validateContentKey(contentKey: string): void {
    if (contentKey.trim().length === 0) {
      throw new Error('Content key must not be blank');
    }
  }
}
