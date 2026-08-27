import {
  Answer,
  Article,
  FeedItem,
  FeedPage,
  FeedTargetKind,
  FeedTargetSummary,
  PageCursor,
  Question,
  UserProfile
} from './DomainModels';
import {
  JsonArrayValue,
  jsonBoolean,
  jsonIntegerLiteral,
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

export enum DomainDecodeFailureKind {
  INVALID_JSON = 'invalid_json',
  MISSING_FIELD = 'missing_field',
  UPSTREAM_ERROR = 'upstream_error',
  UNSUPPORTED_CONTENT = 'unsupported_content'
}

export class DomainDecodeError extends Error {
  readonly kind: DomainDecodeFailureKind;

  constructor(kind: DomainDecodeFailureKind, message: string) {
    super(message);
    this.name = 'DomainDecodeError';
    this.kind = kind;
  }
}

function root(json: string): JsonObjectValue {
  try {
    const value = parseStrictJson(json);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, '响应不是有效 JSON');
    }
  }
  throw invalid('响应结构无效');
}

function requiredId(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && value.value.trim().length > 0) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && integerLiteral.length <= 30) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function requiredText(value: JsonValue | undefined, field: string): string {
  const text = jsonString(value);
  if (text !== undefined && text.trim().length > 0) {
    return text;
  }
  throw invalid(`${field} 不能为空`);
}

function optionalText(value: JsonValue | undefined): string | undefined {
  const text = jsonString(value);
  return text !== undefined && text.trim().length > 0 ? text : undefined;
}

function optionalTextStrict(value: JsonValue | undefined, field: string): string | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  const text = jsonString(value);
  if (text === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return text.trim().length === 0 ? undefined : text;
}

function textOrEmpty(value: JsonValue | undefined, field: string): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  const text = jsonString(value);
  if (text === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return text;
}

function numberOrDefault(value: JsonValue | undefined, fallback: number, field: string): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return fallback;
  }
  const numberValue = jsonNumber(value);
  if (numberValue === undefined || !Number.isFinite(numberValue)) {
    throw invalid(`${field} 类型无效`);
  }
  return numberValue;
}

function booleanOrDefault(value: JsonValue | undefined, fallback: boolean, field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return fallback;
  }
  const booleanValue = jsonBoolean(value);
  if (booleanValue === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return booleanValue;
}

function userFromObject(object: JsonObjectValue): UserProfile {
  const followerCount = object.get('follower_count') ?? object.get('followers_count');
  return {
    id: requiredId(object.get('id'), 'user.id'),
    name: requiredText(object.get('name'), 'user.name'),
    urlToken: optionalText(object.get('url_token')),
    headline: textOrEmpty(object.get('headline'), 'user.headline'),
    avatarUrl: optionalText(object.get('avatar_url')),
    followerCount: numberOrDefault(followerCount, 0, 'user.follower_count'),
    isFollowing: booleanOrDefault(object.get('is_following'), false, 'user.is_following'),
    isOrganization: booleanOrDefault(object.get('is_org'), false, 'user.is_org')
  };
}

function optionalUser(value: JsonValue | undefined): UserProfile | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  const object = jsonObject(value);
  if (object === undefined) {
    throw invalid('user 结构无效');
  }
  return userFromObject(object);
}

function topicIdsFromObject(target: JsonObjectValue): Array<string> {
  const values: Array<JsonValue> = [];
  appendArrayValues(target.get('bound_topic_ids'), values, 'feed.target.bound_topic_ids');
  const question = jsonObject(target.get('question'));
  if (question !== undefined) {
    appendArrayValues(question.get('bound_topic_ids'), values, 'feed.target.question.bound_topic_ids');
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

function appendArrayValues(value: JsonValue | undefined, result: Array<JsonValue>, field: string): void {
  if (value === undefined) {
    return;
  }
  if (!(value instanceof JsonArrayValue)) {
    throw invalid(`${field} 类型无效`);
  }
  value.items.forEach((item: JsonValue): void => {
    result.push(item);
  });
}

export function decodeUser(json: string): UserProfile {
  return userFromObject(root(json));
}

export function decodeQuestion(json: string): Question {
  const object = root(json);
  return {
    id: requiredId(object.get('id'), 'question.id'),
    title: requiredText(object.get('title') ?? object.get('name'), 'question.title'),
    detailHtml: textOrEmpty(object.get('detail'), 'question.detail'),
    url: textOrEmpty(object.get('url'), 'question.url'),
    answerCount: numberOrDefault(object.get('answer_count'), 0, 'question.answer_count'),
    commentCount: numberOrDefault(object.get('comment_count'), 0, 'question.comment_count'),
    followerCount: numberOrDefault(object.get('follower_count'), 0, 'question.follower_count'),
    createdAt: numberOrDefault(object.get('created'), 0, 'question.created'),
    updatedAt: numberOrDefault(object.get('updated_time'), 0, 'question.updated_time'),
    author: optionalUser(object.get('author'))
  };
}

export function decodeAnswer(json: string): Answer {
  const object = root(json);
  const question = jsonObject(object.get('question'));
  return {
    id: requiredId(object.get('id'), 'answer.id'),
    questionId: requiredId(question?.get('id'), 'answer.question.id'),
    questionTitle: optionalText(question?.get('title') ?? question?.get('name')),
    contentHtml: textOrEmpty(object.get('content'), 'answer.content'),
    excerpt: textOrEmpty(object.get('excerpt'), 'answer.excerpt'),
    url: textOrEmpty(object.get('url'), 'answer.url'),
    voteupCount: numberOrDefault(object.get('voteup_count'), 0, 'answer.voteup_count'),
    commentCount: numberOrDefault(object.get('comment_count'), 0, 'answer.comment_count'),
    createdAt: numberOrDefault(object.get('created_time'), 0, 'answer.created_time'),
    updatedAt: numberOrDefault(object.get('updated_time'), 0, 'answer.updated_time'),
    author: optionalUser(object.get('author'))
  };
}

export function decodeArticle(json: string): Article {
  const object = root(json);
  return {
    id: requiredId(object.get('id'), 'article.id'),
    title: requiredText(object.get('title'), 'article.title'),
    contentHtml: textOrEmpty(object.get('content'), 'article.content'),
    excerpt: textOrEmpty(object.get('excerpt'), 'article.excerpt'),
    url: textOrEmpty(object.get('url'), 'article.url'),
    voteupCount: numberOrDefault(object.get('voteup_count'), 0, 'article.voteup_count'),
    commentCount: numberOrDefault(object.get('comment_count'), 0, 'article.comment_count'),
    createdAt: numberOrDefault(object.get('created'), 0, 'article.created'),
    updatedAt: numberOrDefault(object.get('updated'), 0, 'article.updated'),
    author: optionalUser(object.get('author'))
  };
}

function feedTargetFromObject(object: JsonObjectValue): FeedTargetSummary {
  const type = requiredText(object.get('type'), 'feed.target.type');
  let kind: FeedTargetKind;
  let title: string;
  if (type === FeedTargetKind.ANSWER) {
    const question = jsonObject(object.get('question'));
    if (question === undefined) {
      throw invalid('feed.target.question 结构无效');
    }
    kind = FeedTargetKind.ANSWER;
    title = requiredText(question.get('title') ?? question.get('name'), 'feed.target.question.title');
  } else if (type === FeedTargetKind.ARTICLE) {
    kind = FeedTargetKind.ARTICLE;
    title = requiredText(object.get('title'), 'feed.target.title');
  } else if (type === FeedTargetKind.QUESTION) {
    kind = FeedTargetKind.QUESTION;
    title = requiredText(object.get('title') ?? object.get('name'), 'feed.target.title');
  } else {
    throw new DomainDecodeError(DomainDecodeFailureKind.UNSUPPORTED_CONTENT,
      `不支持的 Feed 内容类型：${type}`);
  }
  return {
    kind: kind,
    id: requiredId(object.get('id'), 'feed.target.id'),
    title: title,
    excerpt: textOrEmpty(object.get('excerpt'), 'feed.target.excerpt'),
    url: textOrEmpty(object.get('url'), 'feed.target.url'),
    voteupCount: numberOrDefault(object.get('voteup_count'), 0, 'feed.target.voteup_count'),
    commentCount: numberOrDefault(object.get('comment_count'), 0, 'feed.target.comment_count'),
    author: optionalUser(object.get('author')),
    topicIds: topicIdsFromObject(object)
  };
}

function pageCursorFromObject(object: JsonObjectValue | undefined): PageCursor {
  return {
    isEnd: booleanOrDefault(object?.get('is_end'), true, 'feed.paging.is_end'),
    isStart: booleanOrDefault(object?.get('is_start'), true, 'feed.paging.is_start'),
    next: optionalText(object?.get('next')),
    previous: optionalText(object?.get('previous')) ?? optionalText(object?.get('prev')),
    page: numberOrDefault(object?.get('page'), -1, 'feed.paging.page'),
    total: numberOrDefault(object?.get('totals'), 0, 'feed.paging.totals')
  };
}

export function decodeFeedPage(json: string): FeedPage {
  const object = root(json);
  const errorValue = object.get('error');
  if (errorValue !== undefined && !(errorValue instanceof JsonNullValue)) {
    const error = jsonObject(errorValue);
    const code = error === undefined ? undefined : jsonNumber(error.get('code'));
    throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR,
      `知乎接口返回错误（${code === undefined ? 'unknown' : code.toString()}）`);
  }
  const data = object.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw invalid('feed.data 不能为空');
  }
  const pagingValue = object.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) &&
    !(pagingValue instanceof JsonObjectValue)) {
    throw invalid('feed.paging 结构无效');
  }
  const items: Array<FeedItem> = [];
  data.items.forEach((value: JsonValue): void => {
    const item = jsonObject(value);
    if (item === undefined) {
      throw invalid('feed.item 结构无效');
    }
    const typeValue = item.get('type');
    if (typeValue !== undefined && !(typeValue instanceof JsonStringValue)) {
      throw invalid('feed.item.type 类型无效');
    }
    const type = jsonString(typeValue);
    if (type === 'invited_answer' || type === 'tab_list' || type === 'feed_item_index_group') {
      return;
    }
    const target = jsonObject(item.get('target'));
    if (target === undefined) {
      // 关注流（api/v3/moments）存在无 target 的聚合/辅助条目（如好友动态、赞等），
      // 对齐上游可空 target 语义：跳过而非使整页失败。
      return;
    }
    try {
      items.push({
        id: requiredId(item.get('id'), 'feed.id'),
        verb: textOrEmpty(item.get('verb'), 'feed.verb'),
        actionText: optionalTextStrict(item.get('action_text'), 'feed.action_text') ??
          optionalTextStrict(item.get('moment_desc'), 'feed.moment_desc') ??
          optionalTextStrict(item.get('detail_text'), 'feed.detail_text'),
        createdAt: numberOrDefault(item.get('created_time'), 0, 'feed.created_time'),
        updatedAt: numberOrDefault(item.get('updated_time'), 0, 'feed.updated_time'),
        target: feedTargetFromObject(target)
      });
    } catch (error) {
      if (error instanceof DomainDecodeError && error.kind === DomainDecodeFailureKind.UNSUPPORTED_CONTENT) {
        return;
      }
      if (error instanceof DomainDecodeError) {
        throw error;
      }
      throw invalid('feed.item 结构无效');
    }
  });
  const paging = pagingValue instanceof JsonObjectValue ? pagingValue : undefined;
  return { items: items, cursor: pageCursorFromObject(paging) };
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
