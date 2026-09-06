import { PageCursor } from '../domain/DomainModels';
import { ContentBlockingMatcher, ContentBlockingSession } from '../data/BlockingRuleStore';
import {
  areDefaultSearchFilters,
  defaultSearchFilters,
  SearchEntity,
  SearchEntityKind,
  SearchResultPage,
  searchEntityIdentity,
  SearchFilters,
  SearchHotItem,
  SearchSortOption,
  SearchTab,
  SearchTimeRange
} from '../domain/SearchModels';
import { decodeSearchHotList, decodeSearchResultPage } from '../domain/ZhihuSearchDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { SearchRepository } from './SearchRepository';

export const SEARCH_INCLUDE =
  'data[*].highlight,object,type,object.author,object.topics,object.bound_topic_ids,object.question.topics,' +
    'object.question.bound_topic_ids';
const SEARCH_INCLUDE_QUERY = `include=${encodeURIComponent(SEARCH_INCLUDE).replace(/\*/g, '%2A')}`;
const SEARCH_BASE_URL = 'https://www.zhihu.com/api/v4/search_v3';
const HOT_SEARCH_URL = 'https://www.zhihu.com/api/v4/search/hot_search';
const SEARCH_QUERY_MAX_LENGTH = 200;
const SEARCH_CURSOR_MAX_LENGTH = 4096;
/** 对齐上游 SEARCH_VERTICAL_INFO：vertical 筛选的固定伴随参数。 */
const SEARCH_VERTICAL_INFO = '0,0,0,0,0,0,0,0,0,0,0,0';

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

/** t 参数：回答/文章 tab 复用 general 接口，由 vertical 区分内容类型（对齐上游）。 */
export function searchTabParameter(tab: SearchTab): string {
  if (tab === SearchTab.PEOPLE) {
    return 'people';
  }
  if (tab === SearchTab.TOPIC) {
    return 'topic';
  }
  return 'general';
}

export function searchVerticalParameter(tab: SearchTab): string {
  if (tab === SearchTab.ANSWER) {
    return 'answer';
  }
  if (tab === SearchTab.ARTICLE) {
    return 'article';
  }
  return '';
}

export function searchSortParameter(sort: SearchSortOption): string {
  if (sort === SearchSortOption.LATEST) {
    return 'created_time';
  }
  if (sort === SearchSortOption.MOST_VOTED) {
    return 'upvoted_count';
  }
  return '';
}

export function searchTimeRangeParameter(range: SearchTimeRange): string {
  if (range === SearchTimeRange.DAY) {
    return 'a_day';
  }
  if (range === SearchTimeRange.WEEK) {
    return 'a_week';
  }
  if (range === SearchTimeRange.MONTH) {
    return 'a_month';
  }
  if (range === SearchTimeRange.THREE_MONTHS) {
    return 'three_months';
  }
  if (range === SearchTimeRange.HALF_YEAR) {
    return 'half_a_year';
  }
  if (range === SearchTimeRange.YEAR) {
    return 'a_year';
  }
  return '';
}

export function buildInitialSearchUrl(query: string, filters: SearchFilters = defaultSearchFilters(),
  tab: SearchTab = SearchTab.GENERAL): string {
  const normalized = normalizeSearchQuery(query);
  // 对齐上游：排序/时间筛选只在内容类 tab 生效，用户/话题 tab 忽略（服务端不支持该组合）。
  const activeFilters = isContentSearchTab(tab) ? filters : defaultSearchFilters();
  const parameters: Array<string> = [
    'gk_version=gz-gaokao',
    `t=${searchTabParameter(tab)}`,
    `q=${encodeSearchValue(normalized)}`,
    'correction=1',
    'offset=0',
    'limit=20',
    `search_source=${areDefaultSearchFilters(activeFilters) && searchVerticalParameter(tab).length === 0
      ? 'Normal' : 'Filter'}`,
    `show_all_topics=${tab === SearchTab.TOPIC ? '1' : '0'}`
  ];
  const vertical = searchVerticalParameter(tab);
  if (vertical.length > 0) {
    parameters.push(`vertical=${vertical}`, `vertical_info=${SEARCH_VERTICAL_INFO}`);
  }
  const sort = searchSortParameter(activeFilters.sort);
  if (sort.length > 0) {
    parameters.push(`sort=${sort}`);
  }
  const timeInterval = searchTimeRangeParameter(activeFilters.timeRange);
  if (timeInterval.length > 0) {
    parameters.push(`time_interval=${timeInterval}`);
  }
  parameters.push(SEARCH_INCLUDE_QUERY);
  return `${SEARCH_BASE_URL}?${parameters.join('&')}`;
}

/** 内容类 tab（综合/回答/文章）：t=general，支持排序与时间筛选。 */
export function isContentSearchTab(tab: SearchTab): boolean {
  return searchTabParameter(tab) === 'general';
}

export function isSearchCursorUrl(url: string): boolean {
  if (url.length === 0 || url.length > SEARCH_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  return /^https:\/\/www\.zhihu\.com\/api\/v4\/search_v3\?[^#]+$/.test(url) ||
    /^https:\/\/api\.zhihu\.com\/search_v3\?[^#]+$/.test(url);
}

export function buildSearchRequestUrl(query: string, filters: SearchFilters = defaultSearchFilters(),
  tab: SearchTab = SearchTab.GENERAL, cursor?: string): string {
  const normalizedQuery = normalizeSearchQuery(query);
  if (cursor === undefined) {
    return buildInitialSearchUrl(normalizedQuery, filters, tab);
  }
  const parameters = decodeSearchCursor(cursor);
  const queryValues = parameters.filter((entry: SearchQueryEntry): boolean => entry.name === 'q');
  const typeValues = parameters.filter((entry: SearchQueryEntry): boolean => entry.name === 't');
  if (queryValues.length !== 1 || queryValues[0].value !== normalizedQuery ||
    typeValues.length !== 1 || typeValues[0].value !== searchTabParameter(tab)) {
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

export function canonicalSearchCursorKey(query: string, filters: SearchFilters = defaultSearchFilters(),
  tab: SearchTab = SearchTab.GENERAL, cursor?: string): string {
  const requestUrl = buildSearchRequestUrl(query, filters, tab, cursor);
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

  async search(query: string, filters: SearchFilters = defaultSearchFilters(),
    tab: SearchTab = SearchTab.GENERAL, cursor?: string): Promise<SearchResultPage> {
    const normalizedQuery = normalizeSearchQuery(query);
    if (cursor !== undefined && this.activeQuery !== normalizedQuery) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.INVALID_CURSOR);
    }
    const requestGeneration = this.generation;
    const requestUrl = buildSearchRequestUrl(normalizedQuery, filters, tab, cursor);
    const cursorKey = canonicalSearchCursorKey(normalizedQuery, filters, tab, cursor);
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
    let visibleEntities = decoded.entities;
    if (this.blockingMatcher !== undefined) {
      const blockingSession: ContentBlockingSession = await this.blockingMatcher.createSession();
      visibleEntities = decoded.entities.filter((entity: SearchEntity): boolean => {
        // 内容实体参与屏蔽匹配；用户/话题结果不作为内容屏蔽对象（对齐上游仅过滤内容 feed）。
        if (entity.kind !== SearchEntityKind.CONTENT || entity.content === undefined) {
          return true;
        }
        const item = entity.content;
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
    const nextKey = next === undefined ? undefined : canonicalSearchCursorKey(normalizedQuery, filters,
      tab, next);
    const requested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const delivered = cursor === undefined ? new Set<string>() : cloneStringSet(this.deliveredIdentities);
    requested.add(cursorKey);
    const entities = visibleEntities.filter((entity: SearchEntity): boolean => {
      const identity = searchEntityIdentity(entity);
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
      entities: entities,
      cursor: cursorLoops ? terminalCursor(decoded.cursor) : decoded.cursor
    };
  }

  async hotSearch(): Promise<Array<SearchHotItem>> {
    const requestGeneration = this.generation;
    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: HOT_SEARCH_URL,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new SearchRepositoryFailure(SearchRepositoryFailureKind.CANCELLED);
    }
    return decodeSearchHotList(response.body);
  }
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}
