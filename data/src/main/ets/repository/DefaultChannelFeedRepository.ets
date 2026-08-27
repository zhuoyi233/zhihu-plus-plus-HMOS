import {
  channelFeedItemIdentity,
  ChannelFeedItem,
  ChannelFeedItemKind,
  ChannelFeedPage,
  ChannelFeedSource,
  isDailyFeedDateCursor
} from '../domain/ChannelFeedModels';
import {
  BlockableContentSummary,
  ContentBlockingMatcher,
  ContentBlockingSession
} from '../data/BlockingRuleStore';
import { decodeChannelContentPage, decodeDailyFeedPage } from '../domain/ZhihuChannelFeedDecoder';
import { PageCursor } from '../domain/DomainModels';
import { HttpFailure, HttpFailureKind } from '../network/HttpFailure';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { HOME_FEED_INCLUDE } from './DefaultFeedRepository';
import { ChannelFeedRepository } from './ChannelFeedRepository';

const CHANNEL_INCLUDE_QUERY = `include=${encodeURIComponent(HOME_FEED_INCLUDE).replace(/\*/g, '%2A')}`;
export const FOLLOWING_FEED_BASE_URL = 'https://www.zhihu.com/api/v3/moments?limit=10&desktop=true';
export const FOLLOWING_RECOMMEND_FEED_BASE_URL = 'https://api.zhihu.com/moments_v3?feed_type=recommend';
export const HOT_FEED_BASE_URL =
  'https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total?limit=50&mobile=true';
export const DAILY_PRIMARY_BASE_URL = 'https://daily.zhihu.com/api/4/stories';
export const DAILY_FALLBACK_BASE_URL = 'https://news-at.zhihu.com/api/4/stories';
export const DAILY_HOST_RESOLUTION_ERROR_CODE = 2300006;

export enum ChannelFeedRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  SOURCE_CHANGED = 'source_changed',
  CANCELLED = 'cancelled'
}

export class ChannelFeedRepositoryFailure extends Error {
  readonly kind: ChannelFeedRepositoryFailureKind;

  constructor(kind: ChannelFeedRepositoryFailureKind) {
    let message = '频道请求已取消';
    if (kind === ChannelFeedRepositoryFailureKind.INVALID_CURSOR) {
      message = '频道返回了不受信任的分页游标';
    } else if (kind === ChannelFeedRepositoryFailureKind.REPEATED_CURSOR) {
      message = '频道分页游标已被请求';
    } else if (kind === ChannelFeedRepositoryFailureKind.SOURCE_CHANGED) {
      message = '分页请求与当前频道不一致';
    }
    super(message);
    this.name = 'ChannelFeedRepositoryFailure';
    this.kind = kind;
  }
}

function contentBaseUrl(source: ChannelFeedSource): string {
  if (source === ChannelFeedSource.FOLLOWING) {
    return FOLLOWING_FEED_BASE_URL;
  }
  if (source === ChannelFeedSource.FOLLOWING_RECOMMEND) {
    return FOLLOWING_RECOMMEND_FEED_BASE_URL;
  }
  return HOT_FEED_BASE_URL;
}

export function isChannelFeedCursorUrl(source: ChannelFeedSource, cursor: string): boolean {
  if (source === ChannelFeedSource.DAILY || /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  if (source === ChannelFeedSource.FOLLOWING) {
    return /^https:\/\/www\.zhihu\.com\/api\/v3\/moments(?:\?[^#]*)?$/.test(cursor);
  }
  if (source === ChannelFeedSource.FOLLOWING_RECOMMEND) {
    return /^https:\/\/api\.zhihu\.com\/moments_v3(?:\?[^#]*)?$/.test(cursor);
  }
  return /^https:\/\/www\.zhihu\.com\/api\/v3\/feed\/topstory\/hot-lists\/total(?:\?[^#]*)?$/.test(cursor);
}

export function buildChannelFeedRequestUrl(source: ChannelFeedSource, cursor?: string): string {
  if (source === ChannelFeedSource.DAILY) {
    if (cursor === undefined) {
      return `${DAILY_PRIMARY_BASE_URL}/latest`;
    }
    if (!isDailyFeedDateCursor(cursor)) {
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
    }
    return `${DAILY_PRIMARY_BASE_URL}/before/${cursor}`;
  }
  const sourceUrl = cursor ?? contentBaseUrl(source);
  if (cursor !== undefined && !isChannelFeedCursorUrl(source, cursor)) {
    throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
  }
  const queryStart = sourceUrl.indexOf('?');
  const baseUrl = queryStart < 0 ? sourceUrl : sourceUrl.substring(0, queryStart);
  const sourceQuery = queryStart < 0 ? '' : sourceUrl.substring(queryStart + 1);
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
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name.length === 0) {
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name !== 'include') {
      preservedParts.push(`${encodeURIComponent(name)}=${encodeURIComponent(value)}`);
    }
  });
  preservedParts.push(CHANNEL_INCLUDE_QUERY);
  return `${baseUrl}?${preservedParts.join('&')}`;
}

export function canonicalChannelFeedCursorKey(source: ChannelFeedSource, cursor?: string): string {
  if (source === ChannelFeedSource.DAILY) {
    return `${source}:${cursor ?? 'latest'}`;
  }
  const requestUrl = buildChannelFeedRequestUrl(source, cursor);
  const queryStart = requestUrl.indexOf('?');
  const baseUrl = requestUrl.substring(0, queryStart);
  const parts = requestUrl.substring(queryStart + 1).split('&');
  parts.sort();
  return `${source}:${baseUrl}?${parts.join('&')}`;
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

export class DefaultChannelFeedRepository implements ChannelFeedRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly blockingMatcher?: ContentBlockingMatcher;
  private activeSource?: ChannelFeedSource;
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

  async loadPage(source: ChannelFeedSource, cursor?: string, reset: boolean = false): Promise<ChannelFeedPage> {
    if (cursor !== undefined && !reset && this.activeSource !== source) {
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.SOURCE_CHANGED);
    }
    const requestGeneration = this.generation;
    const requestUrl = buildChannelFeedRequestUrl(source, cursor);
    const cursorKey = canonicalChannelFeedCursorKey(source, cursor);
    if (cursor !== undefined && !reset && this.requestedCursors.has(cursorKey)) {
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.REPEATED_CURSOR);
    }

    const response = source === ChannelFeedSource.DAILY
      ? await this.executeDailyWithDnsFallback(requestUrl, requestGeneration)
      : await this.httpClient.execute({
        url: requestUrl,
        accept: 'application/json',
        useSession: true,
        signWithZse: true
      });
    if (requestGeneration !== this.generation) {
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.CANCELLED);
    }
    const decodedPage = source === ChannelFeedSource.DAILY
      ? decodeDailyFeedPage(response.body)
      : decodeChannelContentPage(response.body);
    const visibleItems = await this.filterBlockedItems(decodedPage.items);
    if (requestGeneration !== this.generation) {
      throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.CANCELLED);
    }
    const next = decodedPage.cursor.next;
    if (next !== undefined) {
      if (source === ChannelFeedSource.DAILY) {
        if (!isDailyFeedDateCursor(next)) {
          throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
        }
      } else if (!isChannelFeedCursorUrl(source, next)) {
        throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
      }
    }
    const nextKey = next === undefined ? undefined : canonicalChannelFeedCursorKey(source, next);
    const requested = cursor === undefined || reset ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const delivered = cursor === undefined || reset ? new Set<string>() : cloneStringSet(this.deliveredItemIdentities);
    requested.add(cursorKey);
    const items = visibleItems.filter((item: ChannelFeedItem): boolean => {
      const identity = channelFeedItemIdentity(item);
      if (delivered.has(identity)) {
        return false;
      }
      delivered.add(identity);
      return true;
    });
    const cursorLoops = (next === undefined && !decodedPage.cursor.isEnd) || nextKey === cursorKey ||
      (nextKey !== undefined && requested.has(nextKey));
    this.activeSource = source;
    this.requestedCursors = requested;
    this.deliveredItemIdentities = delivered;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(decodedPage.cursor) : decodedPage.cursor
    };
  }

  private async executeDailyWithDnsFallback(primaryUrl: string, requestGeneration: number):
    Promise<ZhihuHttpResponse> {
    try {
      return await this.httpClient.execute({ url: primaryUrl, accept: 'application/json' });
    } catch (error) {
      if (!(error instanceof HttpFailure)) {
        throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.CANCELLED);
      }
      if (error.kind !== HttpFailureKind.NETWORK || error.transportCode !== DAILY_HOST_RESOLUTION_ERROR_CODE) {
        throw error;
      }
      if (requestGeneration !== this.generation) {
        throw new ChannelFeedRepositoryFailure(ChannelFeedRepositoryFailureKind.CANCELLED);
      }
      const fallbackUrl = primaryUrl.replace(DAILY_PRIMARY_BASE_URL, DAILY_FALLBACK_BASE_URL);
      return this.httpClient.execute({ url: fallbackUrl, accept: 'application/json' });
    }
  }

  private async filterBlockedItems(items: Array<ChannelFeedItem>): Promise<Array<ChannelFeedItem>> {
    const matcher = this.blockingMatcher;
    if (matcher === undefined) {
      return items;
    }
    const session: ContentBlockingSession = await matcher.createSession();
    const visible: Array<ChannelFeedItem> = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      let summary: BlockableContentSummary;
      if (item.kind === ChannelFeedItemKind.CONTENT) {
        const authorId = item.feedItem.target.author?.id;
        summary = authorId === undefined ? {
          title: item.feedItem.target.title,
          excerpt: item.feedItem.target.excerpt,
          topicIds: item.topicIds
        } : {
          title: item.feedItem.target.title,
          excerpt: item.feedItem.target.excerpt,
          authorId: authorId,
          topicIds: item.topicIds
        };
      } else {
        summary = {
          title: item.story.title,
          excerpt: item.story.hint,
          topicIds: []
        };
      }
      if (session.match(summary) === undefined) {
        visible.push(item);
      }
    }
    return visible;
  }
}
