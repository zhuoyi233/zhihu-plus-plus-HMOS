import { FeedTargetKind, PageCursor } from './DomainModels';
import { SearchResultItem, SearchResultPage } from './SearchModels';
import {
  JsonArrayValue,
  jsonIntegerLiteral,
  jsonBoolean,
  JsonNullValue,
  jsonNumber,
  JsonNumberValue,
  jsonObject,
  JsonObjectValue,
  jsonString,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';

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
  const envelope = root(json);
  const errorValue = envelope.get('error');
  if (errorValue !== undefined && !(errorValue instanceof JsonNullValue)) {
    const error = jsonObject(errorValue);
    const code = error === undefined ? undefined : jsonNumber(error.get('code'));
    throw new SearchDecodeError(SearchDecodeFailureKind.UPSTREAM_ERROR,
      `知乎搜索接口返回错误（${code === undefined ? 'unknown' : code.toString()}）`);
  }
  const data = envelope.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw malformed('search.data 不能为空');
  }
  const pagingValue = envelope.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) &&
    !(pagingValue instanceof JsonObjectValue)) {
    throw malformed('search.paging 结构无效');
  }
  const items: Array<SearchResultItem> = [];
  data.items.forEach((value: JsonValue): void => {
    const candidate = jsonObject(value);
    if (candidate === undefined) {
      throw malformed('search.item 结构无效');
    }
    const wrapperType = requiredText(candidate.get('type'), 'search.item.type');
    if (wrapperType !== 'search_result') {
      return;
    }
    const object = jsonObject(candidate.get('object'));
    if (object === undefined) {
      throw malformed('search.item.object 结构无效');
    }
    const kind = searchKind(requiredText(object.get('type'), 'search.item.object.type'));
    if (kind === undefined) {
      return;
    }
    const contentId = requiredId(object.get('id'), 'search.item.object.id');
    const author = optionalObject(object.get('author'), 'search.item.object.author');
    items.push({
      wrapperId: searchWrapperId(candidate.get('id'), contentId),
      kind: kind,
      contentId: contentId,
      title: searchTitle(object, kind),
      excerpt: textOrEmpty(object.get('excerpt'), 'search.item.object.excerpt'),
      authorId: authorId(author),
      authorName: author === undefined ? undefined : optionalText(author.get('name'),
        'search.item.object.author.name'),
      topicIds: searchTopicIds(object),
      voteupCount: numberOrDefault(object.get('voteup_count'), 0, 'search.item.object.voteup_count'),
      commentCount: numberOrDefault(object.get('comment_count'), 0, 'search.item.object.comment_count')
    });
  });
  const paging = pagingValue instanceof JsonObjectValue ? pagingValue : undefined;
  return { items: items, cursor: searchCursor(paging) };
}

function root(json: string): JsonObjectValue {
  try {
    const value = parseStrictJson(json);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new SearchDecodeError(SearchDecodeFailureKind.INVALID_JSON, '搜索响应不是有效 JSON');
    }
  }
  throw malformed('搜索响应结构无效');
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

function searchTitle(object: JsonObjectValue, kind: FeedTargetKind): string {
  if (kind === FeedTargetKind.ANSWER) {
    const question = jsonObject(object.get('question'));
    if (question === undefined) {
      throw malformed('search.item.object.question 结构无效');
    }
    return requiredText(question.get('title') ?? question.get('name'), 'search.item.object.question.title');
  }
  return requiredText(object.get('title') ?? object.get('name'), 'search.item.object.title');
}

function searchCursor(object: JsonObjectValue | undefined): PageCursor {
  return {
    isEnd: booleanOrDefault(object?.get('is_end'), true, 'search.paging.is_end'),
    isStart: booleanOrDefault(object?.get('is_start'), true, 'search.paging.is_start'),
    next: optionalText(object?.get('next'), 'search.paging.next'),
    previous: optionalText(object?.get('previous'), 'search.paging.previous'),
    page: numberOrDefault(object?.get('page'), -1, 'search.paging.page'),
    total: numberOrDefault(object?.get('totals'), 0, 'search.paging.totals')
  };
}

function authorId(author: JsonObjectValue | undefined): string | undefined {
  if (author === undefined) {
    return undefined;
  }
  const value = author.get('id');
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && integerLiteral.length <= 30) {
    return integerLiteral;
  }
  if (value instanceof JsonStringValue && /^[A-Za-z0-9_-]{1,128}$/.test(value.value)) {
    return value.value;
  }
  return undefined;
}

function searchTopicIds(object: JsonObjectValue): Array<string> {
  const question = jsonObject(object.get('question'));
  const topics = object.get('topics') ?? question?.get('topics');
  const boundIds = object.get('bound_topic_ids') ?? question?.get('bound_topic_ids');
  const values: Array<JsonValue> = [];
  if (topics !== undefined) {
    if (!(topics instanceof JsonArrayValue)) {
      throw malformed('search.item.object.topics 类型无效');
    }
    topics.items.forEach((value: JsonValue): void => {
      const topic = jsonObject(value);
      const id = topic?.get('id');
      if (id !== undefined) {
        values.push(id);
      }
    });
  }
  if (boundIds !== undefined) {
    if (!(boundIds instanceof JsonArrayValue)) {
      throw malformed('search.item.object.bound_topic_ids 类型无效');
    }
    boundIds.items.forEach((value: JsonValue): void => {
      values.push(value);
    });
  }
  const result: Array<string> = [];
  values.forEach((value: JsonValue): void => {
    let id: string | undefined;
    const integerLiteral = jsonIntegerLiteral(value);
    if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
      id = integerLiteral;
    } else if (value instanceof JsonStringValue && /^[1-9][0-9]{0,29}$/.test(value.value)) {
      id = value.value;
    }
    if (id !== undefined && !result.includes(id)) {
      result.push(id);
    }
  });
  return result;
}

function optionalObject(value: JsonValue | undefined, field: string): JsonObjectValue | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  const object = jsonObject(value);
  if (object === undefined) {
    throw malformed(`${field} 结构无效`);
  }
  return object;
}

function requiredId(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && value.value.trim().length > 0) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && integerLiteral.length <= 30) {
    return integerLiteral;
  }
  throw malformed(`${field} 缺少有效 ID`);
}

/** search_result 包裹层 id：服务端新版可能不返回，缺失时用对象 id 兜底（对齐上游容忍性）。 */
function searchWrapperId(value: JsonValue | undefined, fallback: string): string {
  if (value instanceof JsonStringValue && value.value.trim().length > 0) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && integerLiteral.length <= 30) {
    return integerLiteral;
  }
  return fallback;
}

function requiredText(value: JsonValue | undefined, field: string): string {
  const text = jsonString(value);
  if (text !== undefined && text.trim().length > 0) {
    return text;
  }
  throw malformed(`${field} 不能为空`);
}

function textOrEmpty(value: JsonValue | undefined, field: string): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  const text = jsonString(value);
  if (text === undefined) {
    throw malformed(`${field} 类型无效`);
  }
  return text;
}

function optionalText(value: JsonValue | undefined, field: string): string | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  const text = jsonString(value);
  if (text === undefined) {
    throw malformed(`${field} 类型无效`);
  }
  return text.trim().length > 0 ? text : undefined;
}

function numberOrDefault(value: JsonValue | undefined, fallback: number, field: string): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return fallback;
  }
  const numberValue = jsonNumber(value);
  if (numberValue === undefined || !Number.isFinite(numberValue)) {
    throw malformed(`${field} 类型无效`);
  }
  return numberValue;
}

function booleanOrDefault(value: JsonValue | undefined, fallback: boolean, field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return fallback;
  }
  const booleanValue = jsonBoolean(value);
  if (booleanValue === undefined) {
    throw malformed(`${field} 类型无效`);
  }
  return booleanValue;
}

function malformed(message: string): SearchDecodeError {
  return new SearchDecodeError(SearchDecodeFailureKind.MALFORMED_RESPONSE, message);
}
