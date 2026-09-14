import { JsonArrayValue, jsonBoolean, jsonIntegerLiteral, JsonNullValue, jsonNumber, jsonObject,
  JsonObjectValue, jsonString, JsonStringValue, JsonValue, parseStrictJson, StrictJsonError } from 'core';
import {
  MobileNotificationAdditionalInfo,
  MobileNotificationAuthor,
  MobileNotificationColumnHead,
  MobileNotificationContent,
  MobileNotificationEmptyInfo,
  MobileNotificationHead,
  MobileNotificationHeadEntry,
  MobileNotificationLabel,
  MobileNotificationMessageOverview,
  MobileNotificationMessagePage,
  MobileNotificationTarget,
  MobileNotificationTargetSource,
  MobileNotificationTimelineItem,
  MobileNotificationTimelinePage,
  ZhihuPrivateMessage,
  ZhihuPrivateMessagePage
} from './MobileNotificationModels';
import { PageCursor } from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

const MOBILE_NOTIFICATION_ID_MAX_LENGTH = 300;

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

function text(value: JsonValue | undefined): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  const result = jsonString(value);
  return result ?? '';
}

function identifier(value: JsonValue | undefined, maxLength: number): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  let result: string | undefined;
  if (value instanceof JsonStringValue) {
    result = value.value;
  } else {
    result = jsonIntegerLiteral(value);
  }
  if (result === undefined || result.length > maxLength || /[\u0000-\u001F\u007F-\u009F]/.test(result)) {
    return '';
  }
  return result;
}

function count(value: JsonValue | undefined): number {
  const result = jsonNumber(value);
  if (result === undefined || !Number.isFinite(result) || result < 0) {
    return 0;
  }
  return result;
}

function booleanOr(value: JsonValue | undefined, fallback: boolean): boolean {
  const result = jsonBoolean(value);
  return result ?? fallback;
}

function stringArray(value: JsonValue | undefined): Array<string> {
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const result: Array<string> = [];
  value.items.forEach((item: JsonValue): void => {
    const text = jsonString(item);
    if (text !== undefined && text.length > 0) {
      result.push(text);
    }
  });
  return result;
}

function author(value: JsonValue | undefined): MobileNotificationAuthor | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const name = text(object.get('name'));
  const id = identifier(object.get('id'), MOBILE_NOTIFICATION_ID_MAX_LENGTH);
  if (name.trim().length === 0 && id.length === 0) {
    return undefined;
  }
  return {
    id: id,
    name: name,
    urlToken: text(object.get('url_token')),
    headline: text(object.get('headline')),
    avatarUrl: text(object.get('avatar_url'))
  };
}

function labels(value: JsonValue | undefined): Array<MobileNotificationLabel> {
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const result: Array<MobileNotificationLabel> = [];
  value.items.forEach((item: JsonValue): void => {
    const labelObject = jsonObject(item);
    const label = labelObject === undefined ? undefined : text(labelObject.get('text'));
    if (label !== undefined && label.length > 0) {
      result.push({ text: label });
    }
  });
  return result;
}

function head(value: JsonValue | undefined): MobileNotificationHead | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  return {
    author: author(object.get('author')),
    avatarUrl: text(object.get('avatar_url')),
    targetLink: text(object.get('target_link')),
    labels: labels(object.get('labels'))
  };
}

function content(value: JsonValue | undefined): MobileNotificationContent | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  return {
    title: text(object.get('title')),
    subTitle: text(object.get('sub_title')),
    text: text(object.get('text')),
    subText: text(object.get('sub_text')),
    abstractText: text(object.get('abstract_text')),
    targetLink: text(object.get('target_link')),
    subTargetLink: text(object.get('sub_target_link')),
    subIcon: text(object.get('sub_icon')),
    isDeleted: booleanOr(object.get('is_deleted'), false)
  };
}

function targetSource(value: JsonValue | undefined): MobileNotificationTargetSource | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  return {
    text: text(object.get('text')),
    subText: text(object.get('sub_text')),
    targetLink: text(object.get('target_link')),
    isDeleted: booleanOr(object.get('is_deleted'), false)
  };
}

function target(value: JsonValue | undefined): MobileNotificationTarget | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  return {
    id: identifier(object.get('id'), MOBILE_NOTIFICATION_ID_MAX_LENGTH),
    type: text(object.get('type')),
    name: text(object.get('name')),
    title: text(object.get('title')),
    urlToken: text(object.get('url_token')),
    avatarUrl: text(object.get('avatar_url')),
    url: text(object.get('url')),
    myAnswerUrl: text(object.get('my_answer_url')),
    hasAnswer: booleanOr(object.get('has_answer'), false)
  };
}

function emptyInfo(value: JsonValue | undefined): MobileNotificationEmptyInfo | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  return {
    text: text(object.get('text')),
    number: count(object.get('number'))
  };
}

function additionalInfo(value: JsonValue | undefined): Array<MobileNotificationAdditionalInfo> {
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const result: Array<MobileNotificationAdditionalInfo> = [];
  value.items.forEach((item: JsonValue): void => {
    const object = jsonObject(item);
    if (object === undefined) {
      return;
    }
    const infoText = text(object.get('text'));
    if (infoText.length > 0) {
      result.push({ id: count(object.get('id')), text: infoText });
    }
  });
  return result;
}

function timelineItem(value: JsonValue): MobileNotificationTimelineItem | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const item: MobileNotificationTimelineItem = {
    id: identifier(object.get('id'), MOBILE_NOTIFICATION_ID_MAX_LENGTH),
    uniqueId: identifier(object.get('unique_id'), MOBILE_NOTIFICATION_ID_MAX_LENGTH),
    type: text(object.get('type')),
    cardType: text(object.get('card_type')),
    detailTitle: text(object.get('detail_title')),
    isRead: booleanOr(object.get('is_read'), true),
    unreadCount: count(object.get('unread_count')),
    created: count(object.get('created')),
    createdStr: text(object.get('created_str')),
    head: head(object.get('head')),
    content: content(object.get('content')),
    targetSource: targetSource(object.get('target_source')),
    target: target(object.get('target')),
    emptyInfo: emptyInfo(object.get('empty_info')),
    additionalInfo: additionalInfo(object.get('additional_info'))
  };
  if (item.id.length === 0 && item.uniqueId.length === 0 && item.content === undefined &&
    item.target === undefined && item.head === undefined) {
    return undefined;
  }
  return item;
}

function timelineItems(value: JsonValue | undefined): Array<MobileNotificationTimelineItem> {
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const items: Array<MobileNotificationTimelineItem> = [];
  value.items.forEach((entry: JsonValue): void => {
    try {
      const item = timelineItem(entry);
      if (item !== undefined) {
        items.push(item);
      }
    } catch (_error) {
      // 单条坏数据跳过不阻断整页
    }
  });
  return items;
}

function paging(value: JsonValue | undefined, label: string): PageCursor {
  if (value === undefined || value instanceof JsonNullValue) {
    return { isEnd: true, isStart: false, next: undefined, previous: undefined, page: 0, total: 0 };
  }
  const object = jsonObject(value);
  if (object === undefined) {
    throw invalid(`${label} paging 结构无效`);
  }
  const next = text(object.get('next'));
  return {
    isEnd: booleanOr(object.get('is_end'), next.length === 0),
    isStart: false,
    next: next.length > 0 ? next : undefined,
    previous: undefined,
    page: 0,
    total: 0
  };
}

function headEntries(value: JsonValue | undefined): Array<MobileNotificationHeadEntry> {
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const entries: Array<MobileNotificationHeadEntry> = [];
  value.items.forEach((item: JsonValue): void => {
    const object = jsonObject(item);
    if (object === undefined) {
      return;
    }
    entries.push({
      detailTitle: text(object.get('detail_title')),
      unreadCount: count(object.get('unread_count'))
    });
  });
  return entries;
}

function columnHeads(value: JsonValue | undefined): Array<MobileNotificationColumnHead> {
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const entries: Array<MobileNotificationColumnHead> = [];
  value.items.forEach((item: JsonValue): void => {
    const object = jsonObject(item);
    if (object === undefined) {
      return;
    }
    const id = identifier(object.get('id'), MOBILE_NOTIFICATION_ID_MAX_LENGTH);
    const title = text(object.get('title'));
    if (id.length === 0 && title.trim().length === 0) {
      return;
    }
    entries.push({
      id: id,
      title: title,
      textPrefix: text(object.get('text_prefix')),
      text: text(object.get('text')),
      targetLink: text(object.get('target_link')),
      unreadCount: count(object.get('unread_count')),
      created: count(object.get('created'))
    });
  });
  return entries;
}

/** 解码 message/v3 消息中心首屏（head 未读数 + columnHead 邀请回答 + data 会话列表 + paging）。 */
export function decodeMobileMessagePage(json: string): MobileNotificationMessagePage {
  const object = root(json, '消息中心');
  const overview: MobileNotificationMessageOverview = {
    head: headEntries(object.get('head')),
    columnHead: columnHeads(object.get('column_head'))
  };
  return {
    overview: overview,
    items: timelineItems(object.get('data')),
    cursor: paging(object.get('paging'), '消息中心')
  };
}

/** 解码 timeline/entry/{entry} 分类时间线页（单条坏数据跳过）。 */
export function decodeMobileTimelinePage(json: string): MobileNotificationTimelinePage {
  const object = root(json, '通知时间线');
  return {
    items: timelineItems(object.get('data')),
    cursor: paging(object.get('paging'), '通知时间线')
  };
}

function privateMessage(value: JsonValue): ZhihuPrivateMessage | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const id = identifier(object.get('id'), MOBILE_NOTIFICATION_ID_MAX_LENGTH);
  const messageContent = text(object.get('content'));
  if (id.length === 0 && messageContent.length === 0) {
    return undefined;
  }
  const contentType = jsonNumber(object.get('content_type'));
  const plugin = jsonObject(object.get('plugin'));
  return {
    id: id,
    type: text(object.get('type')),
    contentType: contentType === undefined || !Number.isFinite(contentType) ? 0 : contentType,
    content: messageContent,
    createdTime: count(object.get('created_time')),
    pluginExcerpt: plugin === undefined ? '' : text(plugin.get('excerpt')),
    sender: author(object.get('sender')),
    receiver: author(object.get('receiver'))
  };
}

/** 解码私信会话分页（GET /messages?sender_id=...）。 */
export function decodePrivateMessagePage(json: string): ZhihuPrivateMessagePage {
  const object = root(json, '私信会话');
  const data = object.get('data');
  const items: Array<ZhihuPrivateMessage> = [];
  if (data instanceof JsonArrayValue) {
    data.items.forEach((entry: JsonValue): void => {
      try {
        const message = privateMessage(entry);
        if (message !== undefined) {
          items.push(message);
        }
      } catch (_error) {
      }
    });
  }
  return {
    items: items,
    cursor: paging(object.get('paging'), '私信会话')
  };
}

/** 解码私信对象信息（GET /messages/user/{id}）。 */
export function decodePrivateMessagePeer(json: string): MobileNotificationAuthor {
  const object = root(json, '私信对象');
  const peer = author(object);
  if (peer === undefined) {
    throw invalid('私信对象信息无效');
  }
  return peer;
}

/** 解码发送私信的服务端回执（POST /messages 响应为单条消息对象）。 */
export function decodePrivateMessageReceipt(json: string): ZhihuPrivateMessage {
  const object = root(json, '私信回执');
  const message = privateMessage(object);
  if (message === undefined) {
    throw invalid('私信回执无效');
  }
  return message;
}
