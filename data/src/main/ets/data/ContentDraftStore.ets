import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';
import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftMetadata,
  isSafeDraftAccountKey,
  validateContentDraftIdentity,
  validateContentDraftMetadata
} from './DraftModels';

const TABLE_NAME: string = 'content_drafts';

export interface ContentDraftMetadataStore {
  find(identity: ContentDraftIdentity): Promise<ContentDraftMetadata | undefined>;
  listForAccount(accountKey: string): Promise<Array<ContentDraftMetadata>>;
  upsert(metadata: ContentDraftMetadata): Promise<void>;
  remove(identity: ContentDraftIdentity): Promise<void>;
}

/** RDB 只保存可恢复元数据；加密 HTML 由 EncryptedDraftBodyStore 持有。 */
export class ContentDraftStore implements ContentDraftMetadataStore {
  private readonly database: AppDatabase;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(database: AppDatabase) {
    this.database = database;
  }

  async find(identity: ContentDraftIdentity): Promise<ContentDraftMetadata | undefined> {
    validateContentDraftIdentity(identity);
    await this.mutationQueue;
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME).equalTo('draft_key', identity.draftKey);
    const resultSet = await store.query(predicates, draftColumns());
    try {
      if (!resultSet.goToFirstRow()) {
        return undefined;
      }
      const metadata = readDraftMetadata(resultSet);
      return sameIdentity(metadata, identity) ? metadata : undefined;
    } finally {
      resultSet.close();
    }
  }

  async listForAccount(accountKey: string): Promise<Array<ContentDraftMetadata>> {
    if (!isSafeDraftAccountKey(accountKey)) {
      throw new Error('Draft account key is invalid');
    }
    await this.mutationQueue;
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME).equalTo('account_key', accountKey)
      .orderByDesc('updated_at').orderByDesc('draft_key');
    const resultSet = await store.query(predicates, draftColumns());
    const result: Array<ContentDraftMetadata> = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          result.push(readDraftMetadata(resultSet));
        } while (resultSet.goToNextRow());
      }
      return result;
    } finally {
      resultSet.close();
    }
  }

  upsert(metadata: ContentDraftMetadata): Promise<void> {
    validateContentDraftMetadata(metadata);
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const values: relationalStore.ValuesBucket = {
        draft_key: metadata.draftKey,
        account_key: metadata.accountKey,
        draft_kind: metadata.kind,
        target_id: metadata.targetId,
        remote_content_id: metadata.remoteContentId === undefined ? null : metadata.remoteContentId,
        title: metadata.title,
        plain_text_length: metadata.plainTextLength,
        toc_enabled: metadata.tocEnabled ? 1 : 0,
        image_refs: metadata.imageRefsJson,
        topic_refs: metadata.topicRefsJson,
        dirty: metadata.dirty ? 1 : 0,
        version: metadata.version,
        created_at: metadata.createdAt,
        updated_at: metadata.updatedAt
      };
      const rowId = await store.insert(TABLE_NAME, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (rowId === -1) {
        throw new Error('Draft metadata upsert failed');
      }
    });
  }

  remove(identity: ContentDraftIdentity): Promise<void> {
    validateContentDraftIdentity(identity);
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
        .equalTo('draft_key', identity.draftKey)
        .equalTo('account_key', identity.accountKey)
        .equalTo('draft_kind', identity.kind)
        .equalTo('target_id', identity.targetId);
      await store.delete(predicates);
    });
  }

  private enqueueMutation(operation: () => Promise<void>): Promise<void> {
    const result = this.mutationQueue.then(operation, operation);
    this.mutationQueue = result.then((): void => {}, (): void => {});
    return result;
  }
}

function draftColumns(): Array<string> {
  return [
    'draft_key', 'account_key', 'draft_kind', 'target_id', 'remote_content_id', 'title',
    'plain_text_length', 'toc_enabled', 'image_refs', 'topic_refs', 'dirty', 'version',
    'created_at', 'updated_at'
  ];
}

function readDraftMetadata(resultSet: relationalStore.ResultSet): ContentDraftMetadata {
  const remoteContentIndex = resultSet.getColumnIndex('remote_content_id');
  const remoteContentId = resultSet.isColumnNull(remoteContentIndex)
    ? undefined : resultSet.getString(remoteContentIndex);
  const metadata: ContentDraftMetadata = {
    draftKey: resultSet.getString(resultSet.getColumnIndex('draft_key')),
    accountKey: resultSet.getString(resultSet.getColumnIndex('account_key')),
    kind: resultSet.getString(resultSet.getColumnIndex('draft_kind')) as ContentDraftKind,
    targetId: resultSet.getString(resultSet.getColumnIndex('target_id')),
    remoteContentId: remoteContentId,
    title: resultSet.getString(resultSet.getColumnIndex('title')),
    plainTextLength: resultSet.getLong(resultSet.getColumnIndex('plain_text_length')),
    tocEnabled: resultSet.getLong(resultSet.getColumnIndex('toc_enabled')) === 1,
    imageRefsJson: resultSet.getString(resultSet.getColumnIndex('image_refs')),
    topicRefsJson: resultSet.getString(resultSet.getColumnIndex('topic_refs')),
    dirty: resultSet.getLong(resultSet.getColumnIndex('dirty')) === 1,
    version: resultSet.getLong(resultSet.getColumnIndex('version')),
    createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
    updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
  };
  validateContentDraftMetadata(metadata);
  return metadata;
}

function sameIdentity(first: ContentDraftIdentity, second: ContentDraftIdentity): boolean {
  return first.draftKey === second.draftKey && first.accountKey === second.accountKey &&
    first.kind === second.kind && first.targetId === second.targetId;
}
