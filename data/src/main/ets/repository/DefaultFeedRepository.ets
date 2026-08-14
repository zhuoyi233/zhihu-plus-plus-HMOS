import { feedItemIdentity, FeedItem, FeedPage, PageCursor } from '../domain/DomainModels';
import { ContentBlockingMatcher, ContentBlockingSession } from '../data/BlockingRuleStore';
import { decodeFeedPage } from '../domain/ZhihuDomainDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { FeedRepository } from './FeedRepository';

export const HOME_FEED_INCLUDE =
  'data[*].content,excerpt,headline,target.author.badge_v2,target.bound_topic_ids,target.question.bound_topic_ids';
const HOME_FEED_INCLUDE_QUERY = `include=${encodeURIComponent(HOME_FEED_INCLUDE).replace(/\*/g, '%2A')}`;
export const HOME_FEED_URL =
  `https://www.zhihu.com/api/v3/feed/topstory/recommend?desktop=true&page_number=1&limit=10&action=down&` +
    HOME_FEED_INCLUDE_QUERY;

export enum FeedRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class FeedRepositoryFailure extends Error {
  readonly kind: FeedRepositoryFailureKind;

  constructor(kind: FeedRepositoryFailureKind) {
    let message = '首页 Feed 请求已取消';
    if (kind === FeedRepositoryFailureKind.INVALID_CURSOR) {
      message = '首页 Feed 返回了不受信任的分页地址';
    } else if (kind === FeedRepositoryFailureKind.REPEATED_CURSOR) {
      message = '首页 Feed 分页游标已被请求';
    }
    super(message);
    this.name = 'FeedRepositoryFailure';
    this.kind = kind;
  }
}

export function isHomeFeedCursorUrl(url: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  return /^https:\/\/www\.zhihu\.com\/api\/v3\/feed\/topstory\/recommend(?:\?[^#]*)?$/.test(url);
}

export function buildHomeFeedRequestUrl(cursor?: string): string {
  if (cursor === undefined) {
    return HOME_FEED_URL;
  }
  if (!isHomeFeedCursorUrl(cursor)) {
    throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
  }
  const queryStart = cursor.indexOf('?');
  const baseUrl = queryStart < 0 ? cursor : cursor.substring(0, queryStart);
  const sourceQuery = queryStart < 0 ? '' : cursor.substring(queryStart + 1);
  const queryParts = sourceQuery.length === 0 ? [] : sourceQuery.split('&');
  const preservedParts: Array<string> = [];
  queryParts.forEach((part: string): void => {
    if (part.length === 0) {
      return;
    }
    const separator = part.indexOf('=');
    const encodedName = separator < 0 ? part : part.substring(0, separator);
    const encodedValue = separator < 0 ? '' : part.substring(separator + 1);
    let name: string;
    let value: string;
    try {
      name = decodeURIComponent(encodedName.replace(/\+/g, '%20'));
      value = decodeURIComponent(encodedValue.replace(/\+/g, '%20'));
    } catch (_error) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name.length === 0) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name !== 'include') {
      preservedParts.push(`${encodeURIComponent(name)}=${encodeURIComponent(value)}`);
    }
  });
  preservedParts.push(HOME_FEED_INCLUDE_QUERY);
  return `${baseUrl}?${preservedParts.join('&')}`;
}

export function canonicalHomeFeedCursorKey(cursor?: string): string {
  const requestUrl = buildHomeFeedRequestUrl(cursor);
  const queryStart = requestUrl.indexOf('?');
  const baseUrl = requestUrl.substring(0, queryStart);
  const parts = requestUrl.substring(queryStart + 1).split('&');
  parts.sort();
  return `${baseUrl}?${parts.join('&')}`;
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

export class DefaultFeedRepository implements FeedRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly blockingMatcher?: ContentBlockingMatcher;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredItemIdentities: Set<string> = new Set<string>();
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient(), blockingMatcher?: ContentBlockingMatcher) {
    this.httpClient = httpClient;
    this.blockingMatcher = blockingMatcher;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async loadHomePage(cursor?: string): Promise<FeedPage> {
    if (cursor !== undefined && !isHomeFeedCursorUrl(cursor)) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }

    const requestGeneration = this.generation;
    const requestUrl = buildHomeFeedRequestUrl(cursor);
    const cursorKey = canonicalHomeFeedCursorKey(cursor);
    if (cursor !== undefined && this.requestedCursors.has(cursorKey)) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.REPEATED_CURSOR);
    }

    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: requestUrl,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.CANCELLED);
    }
    const decodedPage = decodeFeedPage(response.body);
    let visibleItems = decodedPage.items;
    if (this.blockingMatcher !== undefined) {
      const blockingSession: ContentBlockingSession = await this.blockingMatcher.createSession();
      visibleItems = decodedPage.items.filter((item: FeedItem): boolean => {
        const authorId = item.target.author?.id;
        return blockingSession.match(authorId === undefined ? {
          title: item.target.title,
          excerpt: item.target.excerpt,
          topicIds: item.target.topicIds
        } : {
          title: item.target.title,
          excerpt: item.target.excerpt,
          authorId: authorId,
          topicIds: item.target.topicIds
        }) === undefined;
      });
    }
    if (requestGeneration !== this.generation) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.CANCELLED);
    }
    const next = decodedPage.cursor.next;
    const nextKey = next === undefined ? undefined : canonicalHomeFeedCursorKey(next);
    const nextRequestedCursors = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const nextDeliveredIdentities = cursor === undefined
      ? new Set<string>()
      : cloneStringSet(this.deliveredItemIdentities);
    nextRequestedCursors.add(cursorKey);
    const items: Array<FeedItem> = visibleItems.filter((item: FeedItem): boolean => {
      const identity = feedItemIdentity(item);
      if (nextDeliveredIdentities.has(identity)) {
        return false;
      }
      nextDeliveredIdentities.add(identity);
      return true;
    });
    const cursorLoops = (next === undefined && !decodedPage.cursor.isEnd) || nextKey === cursorKey ||
      (nextKey !== undefined && nextRequestedCursors.has(nextKey));
    this.requestedCursors = nextRequestedCursors;
    this.deliveredItemIdentities = nextDeliveredIdentities;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(decodedPage.cursor) : decodedPage.cursor
    };
  }
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}
