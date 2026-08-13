import { PageCursor } from '../domain/DomainModels';
import { ContentBlockingMatcher, ContentBlockingSession } from '../data/BlockingRuleStore';
import { SearchResultItem, SearchResultPage, searchResultIdentity } from '../domain/SearchModels';
import { decodeSearchResultPage } from '../domain/ZhihuSearchDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { SearchRepository } from './SearchRepository';

export const SEARCH_INCLUDE =
  'data[*].highlight,object,type,object.author,object.topics,object.bound_topic_ids,object.question.topics,' +
    'object.question.bound_topic_ids';
const SEARCH_INCLUDE_QUERY = `include=${encodeURIComponent(SEARCH_INCLUDE).replace(/\*/g, '%2A')}`;
const SEARCH_BASE_URL = 'https://www.zhihu.com/api/v4/search_v3';
const SEARCH_QUERY_MAX_LENGTH = 200;
const SEARCH_CURSOR_MAX_LENGTH = 4096;

export enum SearchRepositoryFailureKind {
  INVALID_QUERY = 'invalid_query',
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class SearchRepositoryFailure extends Error {
  readonly kind: SearchRepositoryFailureKind;

  constructor(kind: SearchRepositoryFailureKind) {
    let message = '搜索请求已取消';
    if (kind === SearchRepositoryFailureKind.INVALID_QUERY) {
      message = '搜索关键词不能为空或过长';
    } else if (kind === SearchRepositoryFailureKind.INVALID_CURSOR) {
      message = '知乎搜索返回了不受信任的分页地址';
    } else if (kind === SearchRepositoryFailureKind.REPEATED_CURSOR) {
      message = '知乎搜索分页游标已被请求';
    }
    super(message);
    this.name = 'SearchRepositoryFailure';
    this.kind = kind;
  }
}

export function normalizeSearchQuery(query: string): string {
  const normalized = query.trim();
  if (normalized.length === 0 || normalized.length > SEARCH_QUERY_MAX_LENGTH ||
    /[\u0000-\u001F\u007F]/.test(normalized)) {
    throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_QUERY);
  }
  return normalized;
}

export function buildInitialSearchUrl(query: string): string {
  const normalized = normalizeSearchQuery(query);
  const parameters: Array<string> = [
    'gk_version=gz-gaokao',
    't=general',
    `q=${encodeSearchValue(normalized)}`,
    'correction=1',
    'offset=0',
    'limit=20',
    'search_source=Normal',
    'show_all_topics=0',
    SEARCH_INCLUDE_QUERY
  ];
  return `${SEARCH_BASE_URL}?${parameters.join('&')}`;
}

export function isSearchCursorUrl(url: string): boolean {
  if (url.length === 0 || url.length > SEARCH_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  return /^https:\/\/www\.zhihu\.com\/api\/v4\/search_v3\?[^#]+$/.test(url) ||
    /^https:\/\/api\.zhihu\.com\/search_v3\?[^#]+$/.test(url);
}

export function buildSearchRequestUrl(query: string, cursor?: string): string {
  const normalizedQuery = normalizeSearchQuery(query);
  if (cursor === undefined) {
    return buildInitialSearchUrl(normalizedQuery);
  }
  const parameters = decodeSearchCursor(cursor);
  const queryValues = parameters.filter((entry: SearchQueryEntry): boolean => entry.name === 'q');
  const typeValues = parameters.filter((entry: SearchQueryEntry): boolean => entry.name === 't');
  if (queryValues.length !== 1 || queryValues[0].value !== normalizedQuery ||
    typeValues.length !== 1 || typeValues[0].value !== 'general') {
    throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
  }
  const preserved: Array<string> = [];
  parameters.forEach((entry: SearchQueryEntry): void => {
    if (entry.name !== 'include') {
      preserved.push(`${encodeURIComponent(entry.name)}=${encodeSearchValue(entry.value)}`);
    }
  });
  preserved.push(SEARCH_INCLUDE_QUERY);
  return `${SEARCH_BASE_URL}?${preserved.join('&')}`;
}

export function canonicalSearchCursorKey(query: string, cursor?: string): string {
  const requestUrl = buildSearchRequestUrl(query, cursor);
  const parts = requestUrl.substring(requestUrl.indexOf('?') + 1).split('&');
  parts.sort();
  return `${SEARCH_BASE_URL}?${parts.join('&')}`;
}

interface SearchQueryEntry {
  readonly name: string;
  readonly value: string;
}

function decodeSearchCursor(cursor: string): Array<SearchQueryEntry> {
  if (!isSearchCursorUrl(cursor)) {
    throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
  }
  const rawQuery = cursor.substring(cursor.indexOf('?') + 1);
  const entries: Array<SearchQueryEntry> = [];
  rawQuery.split('&').forEach((part: string): void => {
    if (part.length === 0) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
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
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
    }
    if (!/^[A-Za-z0-9_.~-]+$/.test(name) || /[\u0000-\u001F\u007F]/.test(value)) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
    }
    entries.push({ name: name, value: value });
  });
  return entries;
}

function encodeSearchValue(value: string): string {
  return encodeURIComponent(value).replace(/%20/g, '+');
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

export class DefaultSearchRepository implements SearchRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly blockingMatcher?: ContentBlockingMatcher;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredIdentities: Set<string> = new Set<string>();
  private activeQuery?: string;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient, blockingMatcher?: ContentBlockingMatcher) {
    this.httpClient = httpClient;
    this.blockingMatcher = blockingMatcher;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async search(query: string, cursor?: string): Promise<SearchResultPage> {
    const normalizedQuery = normalizeSearchQuery(query);
    if (cursor !== undefined && this.activeQuery !== normalizedQuery) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
    }
    const requestGeneration = this.generation;
    const requestUrl = buildSearchRequestUrl(normalizedQuery, cursor);
    const cursorKey = canonicalSearchCursorKey(normalizedQuery, cursor);
    if (cursor !== undefined && this.requestedCursors.has(cursorKey)) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: requestUrl,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.CANCELLED);
    }
    const decoded = decodeSearchResultPage(response.body);
    let visibleItems = decoded.items;
    if (this.blockingMatcher !== undefined) {
      const blockingSession: ContentBlockingSession = await this.blockingMatcher.createSession();
      visibleItems = decoded.items.filter((item: SearchResultItem): boolean => {
        return blockingSession.match(item.authorId === undefined ? {
          title: item.title,
          excerpt: item.excerpt,
          topicIds: item.topicIds
        } : {
          title: item.title,
          excerpt: item.excerpt,
          authorId: item.authorId,
          topicIds: item.topicIds
        }) === undefined;
      });
    }
    if (requestGeneration !== this.generation) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.CANCELLED);
    }
    const next = decoded.cursor.next;
    const nextKey = next === undefined ? undefined : canonicalSearchCursorKey(normalizedQuery, next);
    const requested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const delivered = cursor === undefined ? new Set<string>() : cloneStringSet(this.deliveredIdentities);
    requested.add(cursorKey);
    const items = visibleItems.filter((item: SearchResultItem): boolean => {
      const identity = searchResultIdentity(item);
      if (delivered.has(identity)) {
        return false;
      }
      delivered.add(identity);
      return true;
    });
    const cursorLoops = (next === undefined && !decoded.cursor.isEnd) || nextKey === cursorKey ||
      (nextKey !== undefined && requested.has(nextKey));
    this.activeQuery = normalizedQuery;
    this.requestedCursors = requested;
    this.deliveredIdentities = delivered;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(decoded.cursor) : decoded.cursor
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
