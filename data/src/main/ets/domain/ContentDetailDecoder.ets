import {
  jsonIntegerLiteral,
  JsonBooleanValue,
  JsonNullValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import { Answer, Article, Question, UserProfile } from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

function parseRoot(json: string, contentName: string): JsonObjectValue {
  try {
    const parsed = parseStrictJson(json);
    if (parsed instanceof JsonObjectValue) {
      return parsed;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, `${contentName}响应不是有效 JSON`);
    }
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${contentName}响应结构无效`);
}

function rejectUpstreamError(value: JsonValue | undefined, contentName: string): void {
  if (value === undefined || value instanceof JsonNullValue) {
    return;
  }
  if (!(value instanceof JsonObjectValue)) {
    throw invalid(`${contentName}.error 结构无效`);
  }
  const codeValue = value.get('code');
  let code = 'unknown';
  if (codeValue instanceof JsonNumberValue) {
    code = codeValue.value.toString();
  } else if (codeValue instanceof JsonStringValue) {
    code = codeValue.value;
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR,
    `${contentName}接口返回错误（${code.slice(0, 24)}）`);
}

function checkedExpectedId(value: JsonValue | undefined, expectedId: string, field: string): string {
  if (value instanceof JsonStringValue) {
    if (value.value !== expectedId) {
      throw invalid(`${field} 与请求不一致`);
    }
    return expectedId;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    if (integerLiteral !== expectedId) {
      throw invalid(`${field} 与请求不一致`);
    }
    return expectedId;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function requiredRelatedId(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && /^[1-9][0-9]{0,29}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function requiredText(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && value.value.trim().length > 0) {
    return value.value;
  }
  throw invalid(`${field} 不能为空`);
}

function textOrEmpty(value: JsonValue | undefined, field: string): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  if (!(value instanceof JsonStringValue)) {
    throw invalid(`${field} 类型无效`);
  }
  return value.value;
}

function nonNegativeInteger(value: JsonValue | undefined, field: string): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return 0;
  }
  if (!(value instanceof JsonNumberValue) || !Number.isSafeInteger(value.value) || value.value < 0) {
    throw invalid(`${field} 类型无效`);
  }
  return value.value;
}

function optionalText(value: JsonValue | undefined): string | undefined {
  return value instanceof JsonStringValue && value.value.trim().length > 0 ? value.value : undefined;
}

function optionalBoolean(value: JsonValue | undefined, field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return false;
  }
  if (!(value instanceof JsonBooleanValue)) {
    throw invalid(`${field} 类型无效`);
  }
  return value.value;
}

function optionalObject(value: JsonValue | undefined, field: string): JsonObjectValue | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (!(value instanceof JsonObjectValue)) {
    throw invalid(`${field} 结构无效`);
  }
  return value;
}

function authorFromWire(wire: JsonObjectValue | undefined): UserProfile | undefined {
  if (wire === undefined) {
    return undefined;
  }
  const idValue = wire.get('id');
  let id: string;
  if (idValue instanceof JsonStringValue && idValue.value.trim().length > 0 && idValue.value.length <= 200) {
    id = idValue.value;
  } else {
    const integerLiteral = jsonIntegerLiteral(idValue);
    if (integerLiteral === undefined || integerLiteral.length > 30) {
      throw invalid('author.id 缺少有效 ID');
    }
    id = integerLiteral;
  }
  return {
    id: id,
    name: requiredText(wire.get('name'), 'author.name'),
    urlToken: optionalText(wire.get('url_token')),
    headline: textOrEmpty(wire.get('headline'), 'author.headline'),
    avatarUrl: optionalText(wire.get('avatar_url')),
    followerCount: nonNegativeInteger(wire.get('follower_count') ?? wire.get('followers_count'),
      'author.follower_count'),
    isFollowing: optionalBoolean(wire.get('is_following'), 'author.is_following'),
    isOrganization: optionalBoolean(wire.get('is_org'), 'author.is_org')
  };
}

export function decodeQuestionDetail(json: string, expectedId: string): Question {
  const wire = parseRoot(json, '问题');
  rejectUpstreamError(wire.get('error'), '问题');
  const id = checkedExpectedId(wire.get('id'), expectedId, 'question.id');
  return {
    id: id,
    title: requiredText(wire.get('title') ?? wire.get('name'), 'question.title'),
    detailHtml: textOrEmpty(wire.get('detail'), 'question.detail'),
    url: `https://www.zhihu.com/question/${id}`,
    answerCount: nonNegativeInteger(wire.get('answer_count'), 'question.answer_count'),
    commentCount: nonNegativeInteger(wire.get('comment_count'), 'question.comment_count'),
    followerCount: nonNegativeInteger(wire.get('follower_count'), 'question.follower_count'),
    createdAt: nonNegativeInteger(wire.get('created'), 'question.created'),
    updatedAt: nonNegativeInteger(wire.get('updated_time'), 'question.updated_time'),
    author: authorFromWire(optionalObject(wire.get('author'), 'author'))
  };
}

export function decodeAnswerDetail(json: string, expectedId: string): Answer {
  const wire = parseRoot(json, '回答');
  rejectUpstreamError(wire.get('error'), '回答');
  const id = checkedExpectedId(wire.get('id'), expectedId, 'answer.id');
  const question = optionalObject(wire.get('question'), 'answer.question');
  const questionId = requiredRelatedId(question?.get('id'), 'answer.question.id');
  return {
    id: id,
    questionId: questionId,
    contentHtml: textOrEmpty(wire.get('content'), 'answer.content'),
    excerpt: textOrEmpty(wire.get('excerpt'), 'answer.excerpt'),
    url: `https://www.zhihu.com/question/${questionId}/answer/${id}`,
    voteupCount: nonNegativeInteger(wire.get('voteup_count'), 'answer.voteup_count'),
    commentCount: nonNegativeInteger(wire.get('comment_count'), 'answer.comment_count'),
    createdAt: nonNegativeInteger(wire.get('created_time'), 'answer.created_time'),
    updatedAt: nonNegativeInteger(wire.get('updated_time'), 'answer.updated_time'),
    author: authorFromWire(optionalObject(wire.get('author'), 'author'))
  };
}

export function decodeArticleDetail(json: string, expectedId: string): Article {
  const wire = parseRoot(json, '文章');
  rejectUpstreamError(wire.get('error'), '文章');
  const id = checkedExpectedId(wire.get('id'), expectedId, 'article.id');
  return {
    id: id,
    title: requiredText(wire.get('title'), 'article.title'),
    contentHtml: textOrEmpty(wire.get('content'), 'article.content'),
    excerpt: textOrEmpty(wire.get('excerpt'), 'article.excerpt'),
    url: `https://zhuanlan.zhihu.com/p/${id}`,
    voteupCount: nonNegativeInteger(wire.get('voteup_count'), 'article.voteup_count'),
    commentCount: nonNegativeInteger(wire.get('comment_count'), 'article.comment_count'),
    createdAt: nonNegativeInteger(wire.get('created'), 'article.created'),
    updatedAt: nonNegativeInteger(wire.get('updated'), 'article.updated'),
    author: authorFromWire(optionalObject(wire.get('author'), 'author'))
  };
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
