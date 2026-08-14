import {
  JsonArrayValue,
  jsonBoolean,
  jsonIntegerLiteral,
  JsonNullValue,
  jsonNumber,
  jsonObject,
  JsonObjectValue,
  jsonString,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import {
  NotificationActor,
  NotificationCategory,
  NotificationItem,
  NotificationPage,
  NotificationTarget,
  NotificationTargetKind,
  NotificationUnreadCounts
} from './NotificationModels';
import { PageCursor } from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

const NOTIFICATION_ID_MAX_LENGTH = 200;
const NOTIFICATION_TARGET_ID_MAX_LENGTH = 200;

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}

function root(json: string, label: string): JsonObjectValue {
  try {
    const value = parseStrictJson(json);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, `${label}响应不是有效 JSON`);
    }
  }
  throw invalid(`${label}响应结构无效`);
}

function checkUpstreamError(object: JsonObjectValue, label: string): void {
  const error = object.get('error');
  if (error !== undefined && !(error instanceof JsonNullValue)) {
    const code = jsonNumber(jsonObject(error)?.get('code'));
    throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR,
      `${label}接口返回错误（${code === undefined ? 'unknown' : code.toString()}）`);
  }
}

function text(value: JsonValue | undefined, field: string): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  const result = jsonString(value);
  if (result === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return result;
}

function requiredText(value: JsonValue | undefined, field: string): string {
  const result = text(value, field);
  if (result.trim().length === 0) {
    throw invalid(`${field} 不能为空`);
  }
  return result;
}

function identifier(value: JsonValue | undefined, field: string, maxLength: number): string {
  if (value === undefined || value instanceof JsonNullValue) {
    throw invalid(`${field} 缺少有效 ID`);
  }
  let result: string | undefined;
  if (value instanceof JsonStringValue) {
    result = value.value;
  } else {
    result = jsonIntegerLiteral(value);
  }
  if (result === undefined || result.trim().length === 0 || result.length > maxLength ||
    /[\u0000-\u001F\u007F-\u009F]/.test(result)) {
    throw invalid(`${field} 缺少有效 ID`);
  }
  return result;
}

function number(value: JsonValue | undefined, field: string, fallback: number): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return fallback;
  }
  const result = jsonNumber(value);
  if (result === undefined || !Number.isFinite(result) || result < 0) {
    throw invalid(`${field} 类型无效`);
  }
  return result;
}

function booleanValue(value: JsonValue | undefined, field: string, fallback: boolean): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return fallback;
  }
  const result = jsonBoolean(value);
  if (result === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return result;
}

function actor(value: JsonValue): NotificationActor | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const name = text(object.get('name'), 'notification.actor.name');
  if (name.trim().length === 0) {
    return undefined;
  }
  const urlToken = text(object.get('url_token'), 'notification.actor.url_token');
  return {
    name: name,
    type: text(object.get('type'), 'notification.actor.type'),
    link: text(object.get('link'), 'notification.actor.link'),
    urlToken: urlToken.trim().length === 0 ? undefined : urlToken
  };
}

function target(value: JsonValue | undefined): NotificationTarget | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const type = text(object.get('type'), 'notification.target.type');
  let kind: NotificationTargetKind | undefined;
  if (type === 'question') {
    kind = NotificationTargetKind.QUESTION;
  } else if (type === 'answer') {
    kind = NotificationTargetKind.ANSWER;
  } else if (type === 'article') {
    kind = NotificationTargetKind.ARTICLE;
  } else if (type === 'people') {
    kind = NotificationTargetKind.PEOPLE;
  } else if (type === 'comment') {
    kind = NotificationTargetKind.COMMENT;
  } else if (type === 'pin') {
    kind = NotificationTargetKind.PIN;
  }
  if (kind === undefined) {
    return undefined;
  }
  const question = jsonObject(object.get('question'));
  const title = text(question?.get('title') ?? object.get('title'), 'notification.target.title')
    .trim();
  const rawId = identifier(object.get('id'), 'notification.target.id', NOTIFICATION_TARGET_ID_MAX_LENGTH);
  return {
    kind: kind,
    id: rawId,
    title: title,
    url: text(object.get('url'), 'notification.target.url')
  };
}

function notificationItem(value: JsonValue, category: NotificationCategory): NotificationItem | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const id = identifier(object.get('id'), 'notification.id', NOTIFICATION_ID_MAX_LENGTH);
  const content = jsonObject(object.get('content'));
  if (content === undefined) {
    throw invalid('notification.content 结构无效');
  }
  const verb = requiredText(content.get('verb'), 'notification.content.verb');
  const actorsValue = content.get('actors');
  const actors: Array<NotificationActor> = [];
  if (actorsValue instanceof JsonArrayValue) {
    actorsValue.items.forEach((itemValue: JsonValue): void => {
      const entry = actor(itemValue);
      if (entry !== undefined) {
        actors.push(entry);
      }
    });
  } else if (actorsValue !== undefined && !(actorsValue instanceof JsonNullValue)) {
    const entry = actor(actorsValue);
    if (entry !== undefined) {
      actors.push(entry);
    }
  }
  const contentTarget = jsonObject(content.get('target'));
  const extend = jsonObject(content.get('extend'));
  return {
    id: id,
    category: category,
    isRead: booleanValue(object.get('is_read'), 'notification.is_read', false),
    createTime: number(object.get('create_time'), 'notification.create_time', 0),
    mergeCount: number(object.get('merge_count'), 'notification.merge_count', 1),
    verb: verb,
    actors: actors,
    contentText: text(contentTarget?.get('text'), 'notification.content.target.text'),
    contentLink: text(contentTarget?.get('link'), 'notification.content.target.link'),
    extendText: text(extend?.get('text'), 'notification.content.extend.text'),
    target: target(object.get('target'))
  };
}

function pageCursor(object: JsonObjectValue | undefined, label: string): PageCursor {
  const isEndValue = object?.get('is_end');
  let isEnd = true;
  if (isEndValue !== undefined && !(isEndValue instanceof JsonNullValue)) {
    const end = jsonBoolean(isEndValue);
    if (end === undefined) {
      throw invalid(`${label} paging.is_end 类型无效`);
    }
    isEnd = end;
  }
  const nextValue = object?.get('next');
  const next = nextValue === undefined || nextValue instanceof JsonNullValue
    ? undefined
    : text(nextValue, `${label} paging.next`);
  return {
    isEnd: isEnd,
    isStart: true,
    next: next,
    page: 0,
    total: 0
  };
}

export function decodeNotificationPage(json: string, category: NotificationCategory): NotificationPage {
  const object = root(json, '通知列表');
  checkUpstreamError(object, '通知列表');
  const data = object.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw invalid('通知列表 data 不能为空');
  }
  const items: Array<NotificationItem> = [];
  data.items.forEach((value: JsonValue): void => {
    // 单条坏数据跳过不阻断整页（对齐上游 mapNotNull 语义）
    try {
      const item = notificationItem(value, category);
      if (item !== undefined) {
        items.push(item);
      }
    } catch (_error) {
    }
  });
  const pagingValue = object.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) &&
    !(pagingValue instanceof JsonObjectValue)) {
    throw invalid('通知列表 paging 结构无效');
  }
  return {
    items: items,
    cursor: pageCursor(pagingValue instanceof JsonObjectValue ? pagingValue : undefined, '通知列表')
  };
}

export function decodeUnreadCounts(json: string): NotificationUnreadCounts {
  const object = root(json, '未读数');
  checkUpstreamError(object, '未读数');
  return {
    defaultCount: number(object.get('default_notifications_count'), 'default_notifications_count', 0),
    followCount: number(object.get('follow_notifications_count'), 'follow_notifications_count', 0),
    voteThankCount: number(object.get('vote_thank_notifications_count'), 'vote_thank_notifications_count', 0)
  };
}
