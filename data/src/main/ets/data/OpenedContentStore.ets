import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';

const TABLE_NAME = 'opened_content';

export interface OpenedContent {
  contentKey: string;
  openedAt: number;
  contentType: string;
}

export class OpenedContentStore {
  private readonly database: AppDatabase;

  constructor(database: AppDatabase) {
    this.database = database;
  }

  async upsert(content: OpenedContent): Promise<void> {
    this.validateContent(content);
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
  }

  async query(contentKey: string): Promise<OpenedContent | undefined> {
    this.validateContentKey(contentKey);
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

  async delete(contentKey: string): Promise<boolean> {
    this.validateContentKey(contentKey);
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME).equalTo('content_key', contentKey);
    return await store.delete(predicates) > 0;
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
