import {
  DeepLinkType,
  isSafeDecimalContentId,
  isSafePinContentId,
  JsonArrayValue,
  jsonBoolean,
  JsonNullValue,
  jsonNumber,
  jsonObject,
  JsonObjectValue,
  jsonString,
  JsonValue,
  parseStrictJson,
  resolveZhihuLink,
  StrictJsonError
} from 'core';
import { PageCursor } from './DomainModels';
import { OnlineHistoryEntry, OnlineHistoryKind, OnlineHistoryPage } from './OnlineHistoryModels';

export enum OnlineHistoryDecodeFailureKind {
  INVALID_JSON = 'invalid_json',
  MALFORMED_RESPONSE = 'malformed_response',
  UPSTREAM_ERROR = 'upstream_error'
}

export class OnlineHistoryDecodeError extends Error {
  readonly kind: OnlineHistoryDecodeFailureKind;

  constructor(kind: OnlineHistoryDecodeFailureKind, message: string) {
    super(message);
    this.name = 'OnlineHistoryDecodeError';
    this.kind = kind;
  }
}

export function decodeOnlineHistoryPage(json: string): OnlineHistoryPage {
  const envelope = root(json);
  const errorValue = envelope.get('error');
  if (errorValue !== undefined && !(errorValue instanceof JsonNullValue)) {
    const error = jsonObject(errorValue);
    const code = error === undefined ? undefined : jsonNumber(error.get('code'));
    throw new OnlineHistoryDecodeError(OnlineHistoryDecodeFailureKind.UPSTREAM_ERROR,
      `知乎在线历史接口返回错误（${code === undefined ? 'unknown' : code.toString()}）`);
  }
  const data = envelope.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw malformed('read_history.data 不能为空');
  }
  const entries: Array<OnlineHistoryEntry> = [];
  data.items.forEach((value: JsonValue): void => {
    const entry = decodeEntry(value);
    if (entry !== undefined) {
      entries.push(entry);
    }
  });
  const pagingValue = envelope.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) &&
    !(pagingValue instanceof JsonObjectValue)) {
    throw malformed('read_history.paging 结构无效');
  }
  const paging = pagingValue instanceof JsonObjectValue ? pagingValue : undefined;
  return { items: entries, cursor: historyCursor(paging) };
}

function decodeEntry(value: JsonValue): OnlineHistoryEntry | undefined {
  const card = jsonObject(value);
  if (card === undefined) {
    return undefined;
  }
  const data = jsonObject(card.get('data'));
  if (data === undefined) {
    return undefined;
  }
  const header = jsonObject(data.get('header'));
  const title = header === undefined ? undefined : optionalText(header.get('title'),
    'read_history.item.data.header.title');
  if (title === undefined || title.length === 0) {
    return undefined;
  }
  const action = jsonObject(data.get('action'));
  const actionUrl = action === undefined ? undefined : optionalText(action.get('url'),
    'read_history.item.data.action.url');
  if (actionUrl === undefined || actionUrl.length === 0) {
    return undefined;
  }
  const destination = resolveZhihuLink(actionUrl);
  if (destination === undefined) {
    return undefined;
  }
  const kind = historyKind(destination.type);
  if (kind === undefined || !historyIdValid(kind, destination.id)) {
    return undefined;
  }
  const content = jsonObject(data.get('content'));
  const extra = jsonObject(data.get('extra'));
  return {
    contentKey: `${kind}:${destination.id}`,
    kind: kind,
    id: destination.id,
    title: title,
    summary: content === undefined ? '' : textOrEmpty(content.get('summary'),
      'read_history.item.data.content.summary'),
    authorName: content === undefined ? undefined : optionalText(content.get('author_name'),
      'read_history.item.data.content.author_name'),
    readTime: normalizeReadTime(extra === undefined ? undefined : jsonNumber(extra.get('read_time')))
  };
}

function historyKind(type: DeepLinkType): OnlineHistoryKind | undefined {
  if (type === DeepLinkType.QUESTION) {
    return OnlineHistoryKind.QUESTION;
  }
  if (type === DeepLinkType.ANSWER) {
    return OnlineHistoryKind.ANSWER;
  }
  if (type === DeepLinkType.ARTICLE) {
    return OnlineHistoryKind.ARTICLE;
  }
  if (type === DeepLinkType.PIN) {
    return OnlineHistoryKind.PIN;
  }
  return undefined;
}

function historyIdValid(kind: OnlineHistoryKind, id: string): boolean {
  if (kind === OnlineHistoryKind.PIN) {
    return isSafePinContentId(id);
  }
  return isSafeDecimalContentId(id);
}

function normalizeReadTime(value: number | undefined): number {
  if (value === undefined || !Number.isSafeInteger(value) || value < 0) {
    return 0;
  }
  // 知乎 read_time 是秒级 Unix 时间戳，本地已读记录统一使用毫秒，这里放大为毫秒。
  return value < 100000000000 ? value * 1000 : value;
}

function historyCursor(object: JsonObjectValue | undefined): PageCursor {
  return {
    isEnd: booleanOrDefault(object?.get('is_end'), true, 'read_history.paging.is_end'),
    isStart: booleanOrDefault(object?.get('is_start'), true, 'read_history.paging.is_start'),
    page: numberOrDefault(object?.get('page'), -1, 'read_history.paging.page'),
    total: numberOrDefault(object?.get('totals'), 0, 'read_history.paging.totals')
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
      throw new OnlineHistoryDecodeError(OnlineHistoryDecodeFailureKind.INVALID_JSON,
        '在线历史响应不是有效 JSON');
    }
  }
  throw malformed('在线历史响应结构无效');
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

function malformed(message: string): OnlineHistoryDecodeError {
  return new OnlineHistoryDecodeError(OnlineHistoryDecodeFailureKind.MALFORMED_RESPONSE, message);
}
