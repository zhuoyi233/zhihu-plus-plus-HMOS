import {
  JsonArrayValue,
  JsonBooleanValue,
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
  CommentAuthor,
  CommentItem,
  CommentPage,
  CommentTag
} from './CommentModels';
import { PageCursor } from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

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

function id(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && /^[1-9][0-9]{0,29}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

/** 评论作者 ID 与知乎 people ID 一致，可能是 32 位十六进制串或数字；仅接受安全字符。 */
function authorId(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && /^[A-Za-z0-9_-]{1,200}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[A-Za-z0-9_-]{1,200}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
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

function number(value: JsonValue | undefined, field: string): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return 0;
  }
  const result = jsonNumber(value);
  if (result === undefined || !Number.isFinite(result) || result < 0) {
    throw invalid(`${field} 类型无效`);
  }
  return result;
}

function booleanValue(value: JsonValue | undefined, field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return false;
  }
  if (value instanceof JsonBooleanValue) {
    return value.value;
  }
  throw invalid(`${field} 类型无效`);
}

function optionalText(value: JsonValue | undefined, field: string): string | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  const result = jsonString(value);
  if (result === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return result.trim().length === 0 ? undefined : result;
}

function cursor(object: JsonObjectValue | undefined, label: string): PageCursor {
  const isEnd = object === undefined ? true : object.get('is_end');
  const end = isEnd === undefined || isEnd instanceof JsonNullValue ? true :
    isEnd instanceof JsonBooleanValue ? isEnd.value : true;
  if (isEnd !== undefined && !(isEnd instanceof JsonNullValue) && !(isEnd instanceof JsonBooleanValue)) {
    throw invalid(`${label} paging.is_end 类型无效`);
  }
  const nextValue = object?.get('next');
  const next = nextValue === undefined || nextValue instanceof JsonNullValue
    ? undefined
    : text(nextValue, `${label} paging.next`);
  return {
    isEnd: end,
    isStart: true,
    next: next,
    page: 0,
    total: 0
  };
}

function author(value: JsonValue | undefined, field: string): CommentAuthor {
  const object = jsonObject(value);
  if (object === undefined) {
    throw invalid(`${field}.author 结构无效`);
  }
  return {
    id: authorId(object.get('id'), `${field}.author.id`),
    urlToken: text(object.get('url_token'), `${field}.author.url_token`),
    name: requiredText(object.get('name'), `${field}.author.name`),
    avatarUrl: text(object.get('avatar_url'), `${field}.author.avatar_url`),
    headline: text(object.get('headline'), `${field}.author.headline`)
  };
}

function commentTags(value: JsonValue | undefined, field: string): Array<CommentTag> {
  if (value === undefined || value instanceof JsonNullValue) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    throw invalid(`${field}.comment_tag 类型无效`);
  }
  const result: Array<CommentTag> = [];
  value.items.forEach((entry: JsonValue): void => {
    const object = jsonObject(entry);
    if (object === undefined) {
      return;
    }
    const type = text(object.get('type'), `${field}.comment_tag.type`);
    const tagText = text(object.get('text'), `${field}.comment_tag.text`);
    if (type.trim().length > 0 && tagText.trim().length > 0) {
      result.push({ type: type, text: tagText });
    }
  });
  return result;
}

function firstAuthorTag(value: JsonValue | undefined, field: string): string | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (!(value instanceof JsonArrayValue)) {
    throw invalid(`${field}.author_tag 类型无效`);
  }
  for (const entry of value.items) {
    const object = jsonObject(entry);
    if (object === undefined) {
      continue;
    }
    const tagText = text(object.get('text'), `${field}.author_tag.text`);
    if (tagText.trim().length > 0) {
      return tagText;
    }
  }
  return undefined;
}

function children(value: JsonValue | undefined, field: string): Array<CommentItem> {
  if (value === undefined || value instanceof JsonNullValue) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    throw invalid(`${field}.child_comments 类型无效`);
  }
  const result: Array<CommentItem> = [];
  value.items.forEach((entry: JsonValue): void => {
    const object = jsonObject(entry);
    if (object === undefined) {
      return;
    }
    result.push(decodeCommentObject(object, `${field}.child_comments`));
  });
  return result;
}

/** 解码单条评论对象；root_comment / child_comment / 发表响应共用。 */
export function decodeCommentObject(object: JsonObjectValue, field: string): CommentItem {
  return {
    id: id(object.get('id'), `${field}.id`),
    contentHtml: requiredText(object.get('content'), `${field}.content`),
    createdAt: number(object.get('created_time'), `${field}.created_time`),
    liked: booleanValue(object.get('liked'), `${field}.liked`),
    likeCount: number(object.get('like_count'), `${field}.like_count`),
    collapsed: booleanValue(object.get('collapsed'), `${field}.collapsed`),
    reviewing: booleanValue(object.get('reviewing'), `${field}.reviewing`),
    isDelete: booleanValue(object.get('is_delete'), `${field}.is_delete`),
    isAuthor: booleanValue(object.get('is_author'), `${field}.is_author`),
    isAuthorTop: booleanValue(object.get('is_author_top'), `${field}.is_author_top`),
    replyCommentId: optionalText(object.get('reply_comment_id'), `${field}.reply_comment_id`),
    replyRootCommentId: optionalText(object.get('reply_root_comment_id'), `${field}.reply_root_comment_id`),
    author: author(object.get('author'), field),
    replyToAuthor: jsonObject(object.get('reply_to_author')) === undefined
      ? undefined
      : author(object.get('reply_to_author'), `${field}.reply_to_author`),
    authorTag: firstAuthorTag(object.get('author_tag'), field),
    commentTags: commentTags(object.get('comment_tag'), field),
    childCommentCount: number(object.get('child_comment_count'), `${field}.child_comment_count`),
    childComments: children(object.get('child_comments'), field)
  };
}

interface CollectedCommentPage {
  items: Array<JsonObjectValue>;
  paging: JsonObjectValue | undefined;
}

function collectComments(json: string, label: string): CollectedCommentPage {
  const object = root(json, label);
  const error = object.get('error');
  if (error !== undefined && !(error instanceof JsonNullValue)) {
    throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR, `${label}接口返回错误`);
  }
  const data = object.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw invalid(`${label} data 不能为空`);
  }
  const pagingValue = object.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) &&
    !(pagingValue instanceof JsonObjectValue)) {
    throw invalid(`${label} paging 结构无效`);
  }
  const items: Array<JsonObjectValue> = [];
  data.items.forEach((value: JsonValue): void => {
    const item = jsonObject(value);
    if (item !== undefined) {
      items.push(item);
    }
  });
  return { items: items, paging: pagingValue instanceof JsonObjectValue ? pagingValue : undefined };
}

/** 解码 root_comment 分页响应（顶评列表）。 */
export function decodeRootCommentPage(json: string): CommentPage {
  const collected = collectComments(json, '评论列表');
  return {
    items: collected.items.map((item: JsonObjectValue): CommentItem => decodeCommentObject(item, '评论')),
    cursor: cursor(collected.paging, '评论列表')
  };
}

/** 解码 child_comment 分页响应（子评论列表）。 */
export function decodeChildCommentPage(json: string): CommentPage {
  const collected = collectComments(json, '子评论列表');
  return {
    items: collected.items.map((item: JsonObjectValue): CommentItem => decodeCommentObject(item, '子评论')),
    cursor: cursor(collected.paging, '子评论列表')
  };
}

/** 解码发表评论/回复的响应体（单条评论对象）。 */
export function decodeCommentResponse(json: string): CommentItem {
  return decodeCommentObject(root(json, '发表评论'), '发表评论');
}
