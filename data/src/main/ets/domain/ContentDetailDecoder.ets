import { Answer, Article, Question, UserProfile } from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

interface WireApiError {
  code?: number | string;
}

interface WireUser {
  id?: string | number;
  name?: string;
  url_token?: string;
  headline?: string;
  avatar_url?: string;
  follower_count?: number;
  followers_count?: number;
  is_following?: boolean;
  is_org?: boolean;
}

interface WireQuestion {
  id?: string | number;
  title?: string;
  name?: string;
  detail?: string | null;
  answer_count?: number | null;
  comment_count?: number | null;
  follower_count?: number | null;
  created?: number | null;
  updated_time?: number | null;
  author?: WireUser | null;
  error?: WireApiError | null;
}

interface WireAnswerQuestion {
  id?: string | number;
}

interface WireAnswer {
  id?: string | number;
  question?: WireAnswerQuestion | null;
  content?: string | null;
  excerpt?: string | null;
  voteup_count?: number | null;
  comment_count?: number | null;
  created_time?: number | null;
  updated_time?: number | null;
  author?: WireUser | null;
  error?: WireApiError | null;
}

interface WireArticle {
  id?: string | number;
  title?: string;
  content?: string | null;
  excerpt?: string | null;
  voteup_count?: number | null;
  comment_count?: number | null;
  created?: number | null;
  updated?: number | null;
  author?: WireUser | null;
  error?: WireApiError | null;
}

function parseRoot<T>(json: string, contentName: string): T {
  let parsed: Object | string | number | boolean | null;
  try {
    parsed = JSON.parse(json) as Object | string | number | boolean | null;
  } catch (_error) {
    throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, `${contentName}响应不是有效 JSON`);
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${contentName}响应结构无效`);
  }
  return parsed as T;
}

function rejectUpstreamError(error: WireApiError | null | undefined, contentName: string): void {
  if (error === undefined || error === null) {
    return;
  }
  const code = typeof error.code === 'number' || typeof error.code === 'string' ? `${error.code}` : 'unknown';
  throw new DomainDecodeError(
    DomainDecodeFailureKind.UPSTREAM_ERROR,
    `${contentName}接口返回错误（${code.slice(0, 24)}）`
  );
}

function checkedExpectedId(value: string | number | undefined, expectedId: string, field: string): string {
  if (typeof value === 'string') {
    if (value !== expectedId) {
      throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 与请求不一致`);
    }
    return expectedId;
  }
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    // JSON.parse cannot preserve a long Zhihu numeric ID. The trusted endpoint and caller-provided canonical
    // request ID remain authoritative; safe integers can still be compared exactly.
    if (Number.isSafeInteger(value) && value.toString() !== expectedId) {
      throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 与请求不一致`);
    }
    return expectedId;
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 缺少有效 ID`);
}

function requiredRelatedId(value: string | number | undefined, field: string): string {
  if (typeof value === 'string' && /^[1-9][0-9]{0,29}$/.test(value)) {
    return value;
  }
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) {
    return value.toString();
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 缺少有效 ID`);
}

function requiredText(value: string | undefined, field: string): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value;
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 不能为空`);
}

function textOrEmpty(value: string | null | undefined, field: string): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value !== 'string') {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 类型无效`);
  }
  return value;
}

function nonNegativeInteger(value: number | null | undefined, field: string): number {
  if (value === undefined || value === null) {
    return 0;
  }
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 类型无效`);
  }
  return value;
}

function optionalText(value: string | undefined): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value : undefined;
}

function optionalBoolean(value: boolean | undefined, field: string): boolean {
  if (value === undefined || value === null) {
    return false;
  }
  if (typeof value !== 'boolean') {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${field} 类型无效`);
  }
  return value;
}

function authorFromWire(wire: WireUser | null | undefined): UserProfile | undefined {
  if (wire === undefined || wire === null) {
    return undefined;
  }
  if (typeof wire !== 'object' || Array.isArray(wire)) {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, 'author 结构无效');
  }
  let id: string;
  if (typeof wire.id === 'string' && wire.id.trim().length > 0 && wire.id.length <= 200) {
    id = wire.id;
  } else if (typeof wire.id === 'number' && Number.isSafeInteger(wire.id) && wire.id >= 0) {
    id = wire.id.toString();
  } else {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, 'author.id 缺少有效 ID');
  }
  return {
    id: id,
    name: requiredText(wire.name, 'author.name'),
    urlToken: optionalText(wire.url_token),
    headline: textOrEmpty(wire.headline, 'author.headline'),
    avatarUrl: optionalText(wire.avatar_url),
    followerCount: nonNegativeInteger(wire.follower_count ?? wire.followers_count, 'author.follower_count'),
    isFollowing: optionalBoolean(wire.is_following, 'author.is_following'),
    isOrganization: optionalBoolean(wire.is_org, 'author.is_org')
  };
}

export function decodeQuestionDetail(json: string, expectedId: string): Question {
  const wire = parseRoot<WireQuestion>(json, '问题');
  rejectUpstreamError(wire.error, '问题');
  const id = checkedExpectedId(wire.id, expectedId, 'question.id');
  return {
    id: id,
    title: requiredText(wire.title ?? wire.name, 'question.title'),
    detailHtml: textOrEmpty(wire.detail, 'question.detail'),
    url: `https://www.zhihu.com/question/${id}`,
    answerCount: nonNegativeInteger(wire.answer_count, 'question.answer_count'),
    commentCount: nonNegativeInteger(wire.comment_count, 'question.comment_count'),
    followerCount: nonNegativeInteger(wire.follower_count, 'question.follower_count'),
    createdAt: nonNegativeInteger(wire.created, 'question.created'),
    updatedAt: nonNegativeInteger(wire.updated_time, 'question.updated_time'),
    author: authorFromWire(wire.author)
  };
}

export function decodeAnswerDetail(json: string, expectedId: string): Answer {
  const wire = parseRoot<WireAnswer>(json, '回答');
  rejectUpstreamError(wire.error, '回答');
  const id = checkedExpectedId(wire.id, expectedId, 'answer.id');
  const questionId = requiredRelatedId(wire.question?.id, 'answer.question.id');
  return {
    id: id,
    questionId: questionId,
    contentHtml: textOrEmpty(wire.content, 'answer.content'),
    excerpt: textOrEmpty(wire.excerpt, 'answer.excerpt'),
    url: `https://www.zhihu.com/question/${questionId}/answer/${id}`,
    voteupCount: nonNegativeInteger(wire.voteup_count, 'answer.voteup_count'),
    commentCount: nonNegativeInteger(wire.comment_count, 'answer.comment_count'),
    createdAt: nonNegativeInteger(wire.created_time, 'answer.created_time'),
    updatedAt: nonNegativeInteger(wire.updated_time, 'answer.updated_time'),
    author: authorFromWire(wire.author)
  };
}

export function decodeArticleDetail(json: string, expectedId: string): Article {
  const wire = parseRoot<WireArticle>(json, '文章');
  rejectUpstreamError(wire.error, '文章');
  const id = checkedExpectedId(wire.id, expectedId, 'article.id');
  return {
    id: id,
    title: requiredText(wire.title, 'article.title'),
    contentHtml: textOrEmpty(wire.content, 'article.content'),
    excerpt: textOrEmpty(wire.excerpt, 'article.excerpt'),
    url: `https://zhuanlan.zhihu.com/p/${id}`,
    voteupCount: nonNegativeInteger(wire.voteup_count, 'article.voteup_count'),
    commentCount: nonNegativeInteger(wire.comment_count, 'article.comment_count'),
    createdAt: nonNegativeInteger(wire.created, 'article.created'),
    updatedAt: nonNegativeInteger(wire.updated, 'article.updated'),
    author: authorFromWire(wire.author)
  };
}
