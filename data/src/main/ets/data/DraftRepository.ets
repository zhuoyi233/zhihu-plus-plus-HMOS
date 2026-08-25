import {
  ContentDraftIdentity,
  ContentDraftMetadata,
  ContentDraftSaveInput,
  validateContentDraftIdentity,
  validateContentDraftSaveInput
} from './DraftModels';
import { ContentDraftMetadataStore } from './ContentDraftStore';
import { DraftBodyStore } from './EncryptedDraftBodyStore';

export enum ContentDraftLoadStatus {
  NOT_FOUND = 'not_found',
  FOUND = 'found',
  CORRUPT = 'corrupt'
}

export interface LoadedContentDraft {
  readonly metadata: ContentDraftMetadata;
  readonly html: string;
}

export interface ContentDraftLoadResult {
  readonly status: ContentDraftLoadStatus;
  readonly draft?: LoadedContentDraft;
}

/**
 * 草稿仓储串行化同进程写入：正文信封先原子落盘，再更新 RDB 元数据。
 * 任何失败均不记录 HTML、账号标识、密钥或上游请求内容。
 */
export class DraftRepository {
  private readonly metadataStore: ContentDraftMetadataStore;
  private readonly bodyStore: DraftBodyStore;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(metadataStore: ContentDraftMetadataStore, bodyStore: DraftBodyStore) {
    this.metadataStore = metadataStore;
    this.bodyStore = bodyStore;
  }

  async load(identity: ContentDraftIdentity): Promise<ContentDraftLoadResult> {
    validateContentDraftIdentity(identity);
    await this.mutationQueue;
    const metadata = await this.metadataStore.find(identity);
    if (metadata === undefined) {
      return { status: ContentDraftLoadStatus.NOT_FOUND };
    }
    try {
      const html = await this.bodyStore.load(identity.draftKey);
      if (html === undefined) {
        return { status: ContentDraftLoadStatus.CORRUPT };
      }
      return {
        status: ContentDraftLoadStatus.FOUND,
        draft: { metadata: metadata, html: html }
      };
    } catch (_error) {
      return { status: ContentDraftLoadStatus.CORRUPT };
    }
  }

  /** 只读已加密正文之外的恢复元数据；调用方不得借此跨账号枚举草稿。 */
  async listMetadataForAccount(accountKey: string): Promise<Array<ContentDraftMetadata>> {
    if (accountKey.length === 0 || accountKey.length > 160) {
      return [];
    }
    await this.mutationQueue;
    return this.metadataStore.listForAccount(accountKey);
  }

  save(input: ContentDraftSaveInput, now: number = Date.now()): Promise<ContentDraftMetadata> {
    validateContentDraftSaveInput(input);
    if (!isSafeTimestamp(now)) {
      return Promise.reject(new Error('Draft save timestamp is invalid'));
    }
    return this.enqueueMutation(async (): Promise<ContentDraftMetadata> => {
      const existing = await this.metadataStore.find(input);
      const metadata = toMetadata(input, existing, now);
      await this.bodyStore.save(input.draftKey, input.html);
      await this.metadataStore.upsert(metadata);
      return metadata;
    });
  }

  discard(identity: ContentDraftIdentity): Promise<void> {
    validateContentDraftIdentity(identity);
    return this.enqueueMutation(async (): Promise<void> => {
      await this.bodyStore.remove(identity.draftKey);
      await this.metadataStore.remove(identity);
    });
  }

  private enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.mutationQueue.then(operation, operation);
    this.mutationQueue = result.then((): void => {}, (): void => {});
    return result;
  }
}

function toMetadata(input: ContentDraftSaveInput, existing: ContentDraftMetadata | undefined,
  now: number): ContentDraftMetadata {
  return {
    draftKey: input.draftKey,
    accountKey: input.accountKey,
    kind: input.kind,
    targetId: input.targetId,
    remoteContentId: input.remoteContentId,
    title: input.title,
    plainTextLength: input.plainTextLength,
    tocEnabled: input.tocEnabled,
    imageRefsJson: input.imageRefsJson,
    topicRefsJson: input.topicRefsJson,
    dirty: input.dirty,
    version: existing === undefined ? 1 : existing.version + 1,
    createdAt: existing === undefined ? now : existing.createdAt,
    updatedAt: now
  };
}

function isSafeTimestamp(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0 && value <= 8640000000000000;
}
