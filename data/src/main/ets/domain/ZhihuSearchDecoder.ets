import { FeedTargetKind, PageCursor } from './DomainModels';
import { SearchResultItem, SearchResultPage } from './SearchModels';

interface WireSearchAuthor {
  name?: string;
}

interface WireSearchQuestion {
  title?: string;
  name?: string;
}

interface WireSearchObject {
  type?: string;
  id?: string | number;
  title?: string;
  name?: string;
  excerpt?: string;
  voteup_count?: number;
  comment_count?: number;
  author?: WireSearchAuthor | null;
  question?: WireSearchQuestion | null;
}

interface WireSearchItem {
  type?: string;
  id?: string | number;
  object?: WireSearchObject | null;
}

interface WireSearchPaging {
  is_end?: boolean;
  is_start?: boolean;
  next?: string;
  previous?: string;
  page?: number;
  totals?: number;
}

interface WireSearchError {
  code?: number;
}

interface WireSearchEnvelope {
  data?: Array<WireSearchItem>;
  paging?: WireSearchPaging | null;
  error?: WireSearchError | null;
}

export enum SearchDecodeFailureKind {
  INVALID_JSON = 'invalid_json',
  MALFORMED_RESPONSE = 'malformed_response',
  UPSTREAM_ERROR = 'upstream_error'
}

export class SearchDecodeError extends Error {
  readonly kind: SearchDecodeFailureKind;

  constructor(kind: SearchDecodeFailureKind, message: string) {
    super(message);
    this.name = 'SearchDecodeError';
    this.kind = kind;
  }
}

export function decodeSearchResultPage(json: string): SearchResultPage {
  let parsed: Object | string | number | boolean | null;
  try {
    parsed = JSON.parse(json) as Object | string | number | boolean | null;
  } catch (_error) {
    throw new SearchDecodeError(SearchDecodeFailureKind.INVALID_JSON, '搜索响应不是有效 JSON');
  }
  if (!isRecord(parsed)) {
    throw malformed('搜索响应结构无效');
  }
  const wire = parsed as WireSearchEnvelope;
  if (wire.error !== undefined && wire.error !== null) {
    const code = typeof wire.error.code === 'number' ? wire.error.code.toString() : 'unknown';
    throw new SearchDecodeError(SearchDecodeFailureKind.UPSTREAM_ERROR, `知乎搜索接口返回错误（${code}）`);
  }
  if (!Array.isArray(wire.data)) {
    throw malformed('search.data 不能为空');
  }
  if (wire.paging !== undefined && wire.paging !== null && !isRecord(wire.paging)) {
    throw malformed('search.paging 结构无效');
  }

  const items: Array<SearchResultItem> = [];
  wire.data.forEach((candidate: WireSearchItem): void => {
    if (!isRecord(candidate)) {
      throw malformed('search.item 结构无效');
    }
    if (typeof candidate.type !== 'string' || candidate.type.trim().length === 0) {
      throw malformed('search.item.type 不能为空');
    }
    if (candidate.type !== 'search_result') {
      return;
    }
    if (!isRecord(candidate.object)) {
      throw malformed('search.item.object 结构无效');
    }
    const object = candidate.object as WireSearchObject;
    if (typeof object.type !== 'string' || object.type.trim().length === 0) {
      throw malformed('search.item.object.type 不能为空');
    }
    const kind = searchKind(object.type);
    if (kind === undefined) {
      return;
    }
    items.push({
      wrapperId: requiredId(candidate.id, 'search.item.id'),
      kind: kind,
      contentId: requiredId(object.id, 'search.item.object.id'),
      title: searchTitle(object, kind),
      excerpt: textOrEmpty(object.excerpt, 'search.item.object.excerpt'),
      authorName: authorName(object.author),
      voteupCount: numberOrDefault(object.voteup_count, 0, 'search.item.object.voteup_count'),
      commentCount: numberOrDefault(object.comment_count, 0, 'search.item.object.comment_count')
    });
  });
  return {
    items: items,
    cursor: searchCursor(wire.paging)
  };
}

function searchKind(type: string): FeedTargetKind | undefined {
  if (type === FeedTargetKind.QUESTION) {
    return FeedTargetKind.QUESTION;
  }
  if (type === FeedTargetKind.ANSWER) {
    return FeedTargetKind.ANSWER;
  }
  if (type === FeedTargetKind.ARTICLE) {
    return FeedTargetKind.ARTICLE;
  }
  return undefined;
}

function searchTitle(object: WireSearchObject, kind: FeedTargetKind): string {
  if (kind === FeedTargetKind.ANSWER) {
    const question = object.question;
    if (question === undefined || question === null || !isRecord(question)) {
      throw malformed('search.item.object.question 结构无效');
    }
    return requiredText(question.title ?? question.name, 'search.item.object.question.title');
  }
  return requiredText(object.title ?? object.name, 'search.item.object.title');
}

function searchCursor(wire?: WireSearchPaging | null): PageCursor {
  return {
    isEnd: booleanOrDefault(wire?.is_end, true, 'search.paging.is_end'),
    isStart: booleanOrDefault(wire?.is_start, true, 'search.paging.is_start'),
    next: optionalText(wire?.next, 'search.paging.next'),
    previous: optionalText(wire?.previous, 'search.paging.previous'),
    page: numberOrDefault(wire?.page, -1, 'search.paging.page'),
    total: numberOrDefault(wire?.totals, 0, 'search.paging.totals')
  };
}

function authorName(author?: WireSearchAuthor | null): string | undefined {
  if (author === undefined || author === null) {
    return undefined;
  }
  if (!isRecord(author)) {
    throw malformed('search.item.object.author 结构无效');
  }
  return optionalText(author.name, 'search.item.object.author.name');
}

function isRecord(value: Object | string | number | boolean | null | undefined): boolean {
  return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requiredId(value: string | number | undefined, field: string): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value;
  }
  if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) {
    return value.toString();
  }
  throw malformed(`${field} 缺少有效 ID`);
}

function requiredText(value: string | undefined, field: string): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value;
  }
  throw malformed(`${field} 不能为空`);
}

function textOrEmpty(value: string | undefined, field: string): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value !== 'string') {
    throw malformed(`${field} 类型无效`);
  }
  return value;
}

function optionalText(value: string | undefined, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw malformed(`${field} 类型无效`);
  }
  return value.trim().length > 0 ? value : undefined;
}

function numberOrDefault(value: number | undefined, fallback: number, field: string): number {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw malformed(`${field} 类型无效`);
  }
  return value;
}

function booleanOrDefault(value: boolean | undefined, fallback: boolean, field: string): boolean {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== 'boolean') {
    throw malformed(`${field} 类型无效`);
  }
  return value;
}

function malformed(message: string): SearchDecodeError {
  return new SearchDecodeError(SearchDecodeFailureKind.MALFORMED_RESPONSE, message);
}
