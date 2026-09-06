import { FeedTargetKind, PageCursor } from './DomainModels';
import {
  SearchEntity,
  SearchHotItem,
  searchEntityOfContent,
  searchEntityOfPerson,
  searchEntityOfTopic,
  SearchResultItem,
  SearchResultPage
} from './SearchModels';
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

interface IndexedEntry {
  readonly order: number;
  readonly index: number;
  readonly value: JsonObjectValue;
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
  // 对齐上游：search_result 包裹层带 index 字段时按其重排序（服务端顺序信号），缺失时保持响应顺序。
  const entries: Array<IndexedEntry> = [];
  data.items.forEach((value: JsonValue, order: number): void => {
    const candidate = jsonObject(value);
    if (candidate === undefined) {
      throw malformed('search.item 结构无效');
    }
    entries.push({ order: order, index: wrapperIndex(candidate), value: candidate });
  });
  entries.sort((left: IndexedEntry, right: IndexedEntry): number => {
    return left.index !== right.index ? left.index - right.index : left.order - right.order;
  });
  const entities: Array<SearchEntity> = [];
  entries.forEach((entry: IndexedEntry): void => {
    const candidate = entry.value;
    const wrapperType = requiredText(candidate.get('type'), 'search.item.type');
    if (wrapperType !== 'search_result') {
      return;
    }
    const object = jsonObject(candidate.get('object'));
    if (object === undefined) {
      throw malformed('search.item.object 结构无效');
    }
    const objectType = requiredText(object.get('type'), 'search.item.object.type');
    let entity: SearchEntity | undefined;
    if (objectType === 'people') {
      entity = decodePerson(object);
    } else if (objectType === 'topic') {
      entity = decodeTopic(object);
    } else {
      const item = decodeContent(object, candidate.get('id'), objectType);
      entity = item === undefined ? undefined : searchEntityOfContent(item);
    }
    if (entity !== undefined) {
      entities.push(entity);
    }
  });
  const paging = pagingValue instanceof JsonObjectValue ? pagingValue : undefined;
  return { entities: entities, cursor: searchCursor(paging) };
}

/** 热搜接口：`hot_search_queries` 缺失或为空时返回空数组（对齐上游失败静默降级）。 */
export function decodeSearchHotList(json: string): Array<SearchHotItem> {
  const envelope = root(json);
  const queries = envelope.get('hot_search_queries');
  if (queries === undefined || queries instanceof JsonNullValue) {
    return [];
  }
  if (!(queries instanceof JsonArrayValue)) {
    throw malformed('search.hot_search_queries 结构无效');
  }
  const items: Array<SearchHotItem> = [];
  queries.items.forEach((value: JsonValue): void => {
    const object = jsonObject(value);
    if (object === undefined) {
      throw malformed('search.hot_search_queries.item 结构无效');
    }
    const query = requiredText(object.get('query'), 'search.hot_search_queries.item.query');
    items.push({
      query: query,
      hotShow: textOrEmpty(object.get('hot_show'), 'search.hot_search_queries.item.hot_show'),
      label: textOrEmpty(object.get('label'), 'search.hot_search_queries.item.label')
    });
  });
  return items;
}

/** 包裹层 index 排序键：服务端返回数字或数字字符串（对齐上游 toIntOrNull 容忍），无效时保持响应顺序。 */
function wrapperIndex(candidate: JsonObjectValue): number {
  const value = candidate.get('index');
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && integerLiteral.length <= 7) {
    return parseInt(integerLiteral, 10);
  }
  if (value instanceof JsonStringValue && /^[0-9]{1,7}$/.test(value.value.trim())) {
    return parseInt(value.value.trim(), 10);
  }
  return -1;
}

function decodePerson(object: JsonObjectValue): SearchEntity {
  const id = requiredId(object.get('id'), 'search.item.object.id');
  return searchEntityOfPerson({
    id: id,
    name: requiredText(object.get('name'), 'search.item.object.name'),
    urlToken: optionalText(object.get('url_token'), 'search.item.object.url_token'),
    avatarUrl: optionalText(object.get('avatar_url'), 'search.item.object.avatar_url'),
    headline: textOrEmpty(object.get('headline'), 'search.item.object.headline'),
    followerCount: numberOrDefault(object.get('follower_count'), 0, 'search.item.object.follower_count'),
    answerCount: numberOrDefault(object.get('answer_count'), 0, 'search.item.object.answer_count')
  });
}

function decodeTopic(object: JsonObjectValue): SearchEntity {
  const id = requiredId(object.get('id'), 'search.item.object.id');
  return searchEntityOfTopic({
    id: id,
    name: requiredText(object.get('name'), 'search.item.object.name'),
    avatarUrl: optionalText(object.get('avatar_url'), 'search.item.object.avatar_url'),
    excerpt: textOrEmpty(object.get('excerpt'), 'search.item.object.excerpt'),
    visitCount: numberOrDefault(object.get('visit_count'), 0, 'search.item.object.visit_count'),
    discussCount: numberOrDefault(object.get('top_answer_count'), 0, 'search.item.object.top_answer_count'),
    isFollowing: booleanOrDefault(object.get('is_following'), false, 'search.item.object.is_following')
  });
}

function decodeContent(object: JsonObjectValue, wrapperIdValue: JsonValue | undefined,
  objectType: string): SearchResultItem | undefined {
  const kind = searchKind(objectType);
  if (kind === undefined) {
    return undefined;
  }
  const contentId = requiredId(object.get('id'), 'search.item.object.id');
  const author = optionalObject(object.get('author'), 'search.item.object.author');
  return {
    wrapperId: searchWrapperId(wrapperIdValue, contentId),
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
  };
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
