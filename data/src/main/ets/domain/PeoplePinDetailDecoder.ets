import { PeopleProfile, PinDetail, PinTopic, UserProfile } from './DomainModels';
import {
  jsonIntegerLiteral,
  JsonArrayValue,
  JsonBooleanValue,
  JsonNullValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

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
  throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${label}响应结构无效`);
}

function optionalString(object: JsonObjectValue, name: string, field: string): string | undefined {
  const value = object.get(name);
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (value instanceof JsonStringValue) {
    return value.value;
  }
  throw invalid(`${field} 类型无效`);
}

function optionalNumber(object: JsonObjectValue, name: string, field: string): number | undefined {
  const value = object.get(name);
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (value instanceof JsonNumberValue) {
    return value.value;
  }
  throw invalid(`${field} 类型无效`);
}

function optionalBoolean(object: JsonObjectValue, name: string, field: string): boolean | undefined {
  const value = object.get(name);
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (value instanceof JsonBooleanValue) {
    return value.value;
  }
  throw invalid(`${field} 类型无效`);
}

function optionalObject(object: JsonObjectValue, name: string, field: string): JsonObjectValue | undefined {
  const value = object.get(name);
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (value instanceof JsonObjectValue) {
    return value;
  }
  throw invalid(`${field} 结构无效`);
}

function rejectUpstreamError(object: JsonObjectValue, label: string): void {
  const error = optionalObject(object, 'error', `${label}.error`);
  if (error === undefined) {
    return;
  }
  const value = error.get('code');
  let code = 'unknown';
  if (value instanceof JsonNumberValue) {
    code = `${value.value}`;
  } else if (value instanceof JsonStringValue) {
    code = value.value;
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR,
    `${label}接口返回错误（${code.slice(0, 24)}）`);
}

function requiredText(value: string | undefined, field: string, maxLength: number): string {
  if (value === undefined || value.trim().length === 0 || value.length > maxLength) {
    throw invalid(`${field} 不能为空或过长`);
  }
  return value;
}

function textOrEmpty(value: string | undefined, field: string, maxLength: number): string {
  if (value === undefined) {
    return '';
  }
  if (value.length > maxLength) {
    throw invalid(`${field} 类型无效或过长`);
  }
  return value;
}

function nonNegativeInteger(value: number | undefined, field: string): number {
  if (value === undefined) {
    return 0;
  }
  if (!Number.isSafeInteger(value) || value < 0) {
    throw invalid(`${field} 类型无效`);
  }
  return value;
}

function identifier(value: string | undefined, field: string): string {
  if (value === undefined || !/^[A-Za-z0-9_-]{1,200}$/.test(value)) {
    throw invalid(`${field} 缺少有效标识`);
  }
  return value;
}

function decimalId(value: JsonValue | undefined, expectedId: string, field: string): string {
  if (value instanceof JsonStringValue && value.value === expectedId) {
    return expectedId;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral) && integerLiteral === expectedId) {
    return expectedId;
  }
  throw invalid(`${field} 缺少有效 ID 或与请求不一致`);
}

function topicId(value: JsonValue | undefined): string {
  if (value instanceof JsonStringValue && /^[1-9][0-9]{0,29}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid('topic.id 缺少有效 ID');
}

function safeAvatarUrl(value: string | undefined): string | undefined {
  if (value === undefined || value.length === 0 || value.length > 2048 ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(value) ||
    !/^https:\/\/[A-Za-z0-9.-]+\.zhimg\.com(?:[/?#]|$)/.test(value)) {
    return undefined;
  }
  return value;
}

function peopleFromObject(object: JsonObjectValue, expectedIdentifier?: string): PeopleProfile {
  const id = identifier(optionalString(object, 'id', 'people.id'), 'people.id');
  const tokenValue = optionalString(object, 'url_token', 'people.url_token');
  const urlToken = tokenValue === undefined || tokenValue.length === 0 ? undefined :
    identifier(tokenValue, 'people.url_token');
  if (expectedIdentifier !== undefined && expectedIdentifier !== id && expectedIdentifier !== urlToken) {
    throw invalid('people.id 与请求不一致');
  }
  const canonicalIdentifier = urlToken ?? id;
  return {
    id: id,
    name: requiredText(optionalString(object, 'name', 'people.name'), 'people.name', 200),
    urlToken: urlToken,
    headline: textOrEmpty(optionalString(object, 'headline', 'people.headline'), 'people.headline', 4000),
    avatarUrl: safeAvatarUrl(optionalString(object, 'avatar_url', 'people.avatar_url')),
    followerCount: nonNegativeInteger(optionalNumber(object, 'follower_count', 'people.follower_count'),
      'people.follower_count'),
    followingCount: nonNegativeInteger(optionalNumber(object, 'following_count', 'people.following_count'),
      'people.following_count'),
    answerCount: nonNegativeInteger(optionalNumber(object, 'answer_count', 'people.answer_count'),
      'people.answer_count'),
    articleCount: nonNegativeInteger(optionalNumber(object, 'articles_count', 'people.articles_count'),
      'people.articles_count'),
    isFollowing: optionalBoolean(object, 'is_following', 'people.is_following') ?? false,
    isOrganization: optionalBoolean(object, 'is_org', 'people.is_org') ?? false,
    canonicalUrl: `https://www.zhihu.com/people/${encodeURIComponent(canonicalIdentifier)}`
  };
}

function compactAuthor(object: JsonObjectValue | undefined): UserProfile {
  if (object === undefined) {
    throw invalid('pin.author 结构无效');
  }
  const profile = peopleFromObject(object);
  return {
    id: profile.id,
    name: profile.name,
    urlToken: profile.urlToken,
    headline: profile.headline,
    avatarUrl: profile.avatarUrl,
    followerCount: profile.followerCount,
    isFollowing: profile.isFollowing,
    isOrganization: profile.isOrganization
  };
}

export function decodePeopleDetail(json: string, expectedIdentifier: string): PeopleProfile {
  const object = root(json, '用户');
  rejectUpstreamError(object, '用户');
  return peopleFromObject(object, expectedIdentifier);
}

export function decodePinDetail(json: string, expectedId: string): PinDetail {
  const object = root(json, '想法');
  rejectUpstreamError(object, '想法');
  const id = decimalId(object.get('id'), expectedId, 'pin.id');
  const topicsValue = object.get('topics');
  const topics: Array<PinTopic> = [];
  if (topicsValue !== undefined && !(topicsValue instanceof JsonNullValue)) {
    if (!(topicsValue instanceof JsonArrayValue) || topicsValue.items.length > 100) {
      throw invalid('pin.topics 结构无效');
    }
    topicsValue.items.forEach((value: JsonValue): void => {
      if (!(value instanceof JsonObjectValue)) {
        throw invalid('pin.topic 结构无效');
      }
      topics.push({
        id: topicId(value.get('id')),
        name: requiredText(optionalString(value, 'name', 'topic.name'), 'topic.name', 200)
      });
    });
  }
  return {
    id: id,
    contentHtml: textOrEmpty(optionalString(object, 'content_html', 'pin.content_html'), 'pin.content_html',
      1024 * 1024),
    url: `https://www.zhihu.com/pin/${id}`,
    likeCount: nonNegativeInteger(optionalNumber(object, 'like_count', 'pin.like_count'), 'pin.like_count'),
    commentCount: nonNegativeInteger(optionalNumber(object, 'comment_count', 'pin.comment_count'),
      'pin.comment_count'),
    createdAt: nonNegativeInteger(optionalNumber(object, 'created', 'pin.created'), 'pin.created'),
    updatedAt: nonNegativeInteger(optionalNumber(object, 'updated', 'pin.updated'), 'pin.updated'),
    author: compactAuthor(optionalObject(object, 'author', 'pin.author')),
    topics: topics
  };
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
