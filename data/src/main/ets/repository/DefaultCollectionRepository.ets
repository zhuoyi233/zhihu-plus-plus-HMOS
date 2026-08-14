import {
  CollectionContentPage,
  CollectionPage,
  CollectionSummary,
  collectionContentIdentity,
  collectionIdentity
} from '../domain/CollectionModels';
import {
  decodeCollectionDetail,
  decodeCollectionItemsPage,
  decodeCollectionsPage,
  decodeContentCollections
} from '../domain/CollectionDecoder';
import { PageCursor } from '../domain/DomainModels';
import { normalizeContentId } from './DefaultContentRepository';
import { normalizePeopleIdentifier } from './DefaultPeopleRepository';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { CollectionRepository, isSupportedCollectionContentType } from './CollectionRepository';

const COLLECTIONS_LIMIT = 20;
const COLLECTIONS_INCLUDE =
  'data[*].updated_time,answer_count,follower_count,item_count,like_count,comment_count,creator';
const CONTENT_COLLECTIONS_LIMIT = 50;
const COLLECTION_CURSOR_MAX_LENGTH = 4096;

export enum CollectionRepositoryFailureKind {
  INVALID_IDENTIFIER = 'invalid_identifier',
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class CollectionRepositoryFailure extends Error {
  readonly kind: CollectionRepositoryFailureKind;

  constructor(kind: CollectionRepositoryFailureKind) {
    let message = '收藏夹请求已取消';
    if (kind === CollectionRepositoryFailureKind.INVALID_IDENTIFIER) {
      message = '收藏夹标识无效';
    } else if (kind === CollectionRepositoryFailureKind.INVALID_CURSOR) {
      message = '收藏夹返回了不受信任的分页地址';
    } else if (kind === CollectionRepositoryFailureKind.REPEATED_CURSOR) {
      message = '收藏夹分页游标已被请求';
    }
    super(message);
    this.name = 'CollectionRepositoryFailure';
    this.kind = kind;
  }
}

function normalizeCollectionId(id: string): string {
  if (!/^[1-9][0-9]{0,29}$/.test(id)) {
    throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  return id;
}

export function buildCollectionsPageUrl(urlTokenValue: string, cursor?: string): string {
  const urlToken = normalizePeopleIdentifier(urlTokenValue);
  if (cursor === undefined) {
    return `https://www.zhihu.com/api/v4/people/${encodeURIComponent(urlToken)}/collections` +
      `?limit=${COLLECTIONS_LIMIT}&include=${encodeURIComponent(COLLECTIONS_INCLUDE).replace(/\*/g, '%2A')}`;
  }
  if (!isCollectionsCursorUrl(urlToken, cursor)) {
    throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.INVALID_CURSOR);
  }
  return cursor;
}

export function isCollectionsCursorUrl(urlTokenValue: string, cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > COLLECTION_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  const urlToken = normalizePeopleIdentifier(urlTokenValue);
  const prefix = `https://www.zhihu.com/api/v4/people/${encodeURIComponent(urlToken)}/collections?`;
  return cursor.startsWith(prefix) && !cursor.includes('#');
}

export function buildCollectionDetailUrl(collectionIdValue: string): string {
  const collectionId = normalizeCollectionId(collectionIdValue);
  return `https://www.zhihu.com/api/v4/collections/${collectionId}`;
}

export function buildCollectionItemsUrl(collectionIdValue: string, cursor?: string): string {
  const collectionId = normalizeCollectionId(collectionIdValue);
  if (cursor === undefined) {
    return `https://www.zhihu.com/api/v4/collections/${collectionId}/items` +
      `?limit=${COLLECTIONS_LIMIT}&include=${encodeURIComponent(
        'data[*].content,excerpt,created_time,updated_time,author'
      ).replace(/\*/g, '%2A')}`;
  }
  if (!isCollectionItemsCursorUrl(collectionId, cursor)) {
    throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.INVALID_CURSOR);
  }
  return cursor;
}

export function isCollectionItemsCursorUrl(collectionIdValue: string, cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > COLLECTION_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  const collectionId = normalizeCollectionId(collectionIdValue);
  const prefix = `https://www.zhihu.com/api/v4/collections/${collectionId}/items?`;
  return cursor.startsWith(prefix) && !cursor.includes('#');
}

export function buildContentCollectionsUrl(contentTypeValue: string, contentIdValue: string): string {
  const contentType = normalizeContentType(contentTypeValue);
  const contentId = normalizeContentId(contentIdValue);
  return `https://www.zhihu.com/api/v4/collections/contents/${contentType}/${contentId}` +
    `?limit=${CONTENT_COLLECTIONS_LIMIT}`;
}

export function buildCreateCollectionUrl(): string {
  return 'https://www.zhihu.com/api/v4/collections';
}

export function buildDeleteCollectionUrl(collectionIdValue: string): string {
  return buildCollectionDetailUrl(collectionIdValue);
}

export function buildContentCollectionToggleUrl(contentTypeValue: string, contentIdValue: string): string {
  const contentType = normalizeContentType(contentTypeValue);
  const contentId = normalizeContentId(contentIdValue);
  return `https://www.zhihu.com/api/v4/collections/contents/${contentType}/${contentId}`;
}

function normalizeContentType(value: string): string {
  if (!isSupportedCollectionContentType(value)) {
    throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  return value;
}

function terminalCursor(cursor: PageCursor): PageCursor {
  return {
    isEnd: true,
    isStart: cursor.isStart,
    previous: cursor.previous,
    page: cursor.page,
    total: cursor.total
  };
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}

export class DefaultCollectionRepository implements CollectionRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredCollectionIdentities: Set<string> = new Set<string>();
  private deliveredItemIdentities: Set<string> = new Set<string>();

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getCollectionsPage(urlToken: string, cursor?: string): Promise<CollectionPage> {
    const requestGeneration = this.generation;
    const requestUrl = buildCollectionsPageUrl(urlToken, cursor);
    if (cursor !== undefined && this.requestedCursors.has(requestUrl)) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response = await this.execute(requestUrl, ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
    const page = decodeCollectionsPage(response.body);
    const requested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const delivered = cursor === undefined
      ? new Set<string>()
      : cloneStringSet(this.deliveredCollectionIdentities);
    requested.add(requestUrl);
    const items = page.items.filter((collection: CollectionSummary): boolean => {
      const identity = collectionIdentity(collection);
      if (delivered.has(identity)) {
        return false;
      }
      delivered.add(identity);
      return true;
    });
    const next = page.cursor.next;
    const cursorLoops = (next === undefined && !page.cursor.isEnd) || next === requestUrl ||
      (next !== undefined && requested.has(next));
    this.requestedCursors = requested;
    this.deliveredCollectionIdentities = delivered;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(page.cursor) : page.cursor
    };
  }

  async getCollection(collectionId: string): Promise<CollectionSummary> {
    const requestGeneration = this.generation;
    const response = await this.execute(buildCollectionDetailUrl(collectionId), ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
    return decodeCollectionDetail(response.body);
  }

  async getCollectionItemsPage(collectionId: string, cursor?: string): Promise<CollectionContentPage> {
    const requestGeneration = this.generation;
    const requestUrl = buildCollectionItemsUrl(collectionId, cursor);
    if (cursor !== undefined && this.requestedCursors.has(requestUrl)) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response = await this.execute(requestUrl, ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
    const page = decodeCollectionItemsPage(response.body);
    const requested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const delivered = cursor === undefined ? new Set<string>() : cloneStringSet(this.deliveredItemIdentities);
    requested.add(requestUrl);
    const items = page.items.filter((item): boolean => {
      const identity = collectionContentIdentity(item);
      if (delivered.has(identity)) {
        return false;
      }
      delivered.add(identity);
      return true;
    });
    const next = page.cursor.next;
    const cursorLoops = (next === undefined && !page.cursor.isEnd) || next === requestUrl ||
      (next !== undefined && requested.has(next));
    this.requestedCursors = requested;
    this.deliveredItemIdentities = delivered;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(page.cursor) : page.cursor
    };
  }

  async getContentCollections(contentType: string, contentId: string): Promise<Array<CollectionSummary>> {
    const requestGeneration = this.generation;
    const response = await this.execute(
      buildContentCollectionsUrl(contentType, contentId),
      ZhihuHttpMethod.GET
    );
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
    return decodeContentCollections(response.body);
  }

  async createCollection(title: string, description: string, isPublic: boolean): Promise<void> {
    const requestGeneration = this.generation;
    const body = JSON.stringify({
      title: title,
      description: description,
      is_public: isPublic
    });
    await this.execute(buildCreateCollectionUrl(), ZhihuHttpMethod.POST, body);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
  }

  async deleteCollection(collectionId: string): Promise<void> {
    const requestGeneration = this.generation;
    await this.execute(buildDeleteCollectionUrl(collectionId), ZhihuHttpMethod.DELETE);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
  }

  async addContentToCollection(collectionId: string, contentType: string, contentId: string): Promise<void> {
    const requestGeneration = this.generation;
    const collection = normalizeCollectionId(collectionId);
    const body = `add_collections=${collection}`;
    await this.execute(buildContentCollectionToggleUrl(contentType, contentId), ZhihuHttpMethod.PUT, body);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
  }

  async removeContentFromCollection(collectionId: string, contentType: string, contentId: string): Promise<void> {
    const requestGeneration = this.generation;
    const collection = normalizeCollectionId(collectionId);
    const body = `remove_collections=${collection}`;
    await this.execute(buildContentCollectionToggleUrl(contentType, contentId), ZhihuHttpMethod.PUT, body);
    if (requestGeneration !== this.generation) {
      throw new CollectionRepositoryFailure(CollectionRepositoryFailureKind.CANCELLED);
    }
  }

  private async execute(url: string, method: ZhihuHttpMethod, body?: string): Promise<ZhihuHttpResponse> {
    return this.httpClient.execute({
      url: url,
      method: method,
      body: body,
      accept: 'application/json',
      useSession: true,
      signWithZse: true,
      contentType: body === undefined ? undefined : 'application/x-www-form-urlencoded'
    });
  }
}
