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
  detail?: string;
  url?: string;
  answer_count?: number;
  comment_count?: number;
  follower_count?: number;
  created?: number;
  updated_time?: number;
  author?: WireUser;
}

interface WireAnswer {
  id?: string | number;
  question?: WireQuestion;
  content?: string;
  excerpt?: string;
  url?: string;
  voteup_count?: number;
  comment_count?: number;
  created_time?: number;
  updated_time?: number;
  author?: WireUser;
}

interface WireArticle {
  id?: string | number;
  title?: string;
  content?: string;
  excerpt?: string;
  url?: string;
  voteup_count?: number;
  comment_count?: number;
  created?: number;
  updated?: number;
  author?: WireUser;
}

interface WireFeedTarget {
  type?: string;
  id?: string | number;
  title?: string;
  name?: string;
  excerpt?: string;
  url?: string;
  voteup_count?: number;
  comment_count?: number;
  author?: WireUser;
  question?: WireQuestion;
}

interface WireFeedItem {
  id?: string | number;
  verb?: string;
  action_text?: string;
  created_time?: number;
  updated_time?: number;
  target?: WireFeedTarget;
}

interface WirePaging {
  is_end?: boolean;
  is_start?: boolean;
  next?: string;
  previous?: string;
  prev?: string;
  page?: number;
  totals?: number;
}

interface WireApiError {
  code?: number;
  message?: string;
}

interface WireFeedPage {
  data?: Array<WireFeedItem>;
  paging?: WirePaging;
  error?: WireApiError;
}

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

function parseJson<T>(json: string): T {
  try {
    return JSON.parse(json) as T;
  } catch (_error) {
    throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, '响应不是有效 JSON');
  }
}

function requiredId(value: string | number | undefined, field: string): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value;
  }
  if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) {
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

function optionalText(value: string | undefined): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value : undefined;
}

function userFromWire(wire: WireUser): UserProfile {
  return {
    id: requiredId(wire.id, 'user.id'),
    name: requiredText(wire.name, 'user.name'),
    urlToken: optionalText(wire.url_token),
    headline: wire.headline ?? '',
    avatarUrl: optionalText(wire.avatar_url),
    followerCount: wire.follower_count ?? wire.followers_count ?? 0,
    isFollowing: wire.is_following ?? false,
    isOrganization: wire.is_org ?? false
  };
}

function optionalUser(wire?: WireUser): UserProfile | undefined {
  return wire === undefined ? undefined : userFromWire(wire);
}

export function decodeUser(json: string): UserProfile {
  return userFromWire(parseJson<WireUser>(json));
}

export function decodeQuestion(json: string): Question {
  const wire = parseJson<WireQuestion>(json);
  return {
    id: requiredId(wire.id, 'question.id'),
    title: requiredText(wire.title ?? wire.name, 'question.title'),
    detailHtml: wire.detail ?? '',
    url: wire.url ?? '',
    answerCount: wire.answer_count ?? 0,
    commentCount: wire.comment_count ?? 0,
    followerCount: wire.follower_count ?? 0,
    createdAt: wire.created ?? 0,
    updatedAt: wire.updated_time ?? 0,
    author: optionalUser(wire.author)
  };
}

export function decodeAnswer(json: string): Answer {
  const wire = parseJson<WireAnswer>(json);
  return {
    id: requiredId(wire.id, 'answer.id'),
    questionId: requiredId(wire.question?.id, 'answer.question.id'),
    contentHtml: wire.content ?? '',
    excerpt: wire.excerpt ?? '',
    url: wire.url ?? '',
    voteupCount: wire.voteup_count ?? 0,
    commentCount: wire.comment_count ?? 0,
    createdAt: wire.created_time ?? 0,
    updatedAt: wire.updated_time ?? 0,
    author: optionalUser(wire.author)
  };
}

export function decodeArticle(json: string): Article {
  const wire = parseJson<WireArticle>(json);
  return {
    id: requiredId(wire.id, 'article.id'),
    title: requiredText(wire.title, 'article.title'),
    contentHtml: wire.content ?? '',
    excerpt: wire.excerpt ?? '',
    url: wire.url ?? '',
    voteupCount: wire.voteup_count ?? 0,
    commentCount: wire.comment_count ?? 0,
    createdAt: wire.created ?? 0,
    updatedAt: wire.updated ?? 0,
    author: optionalUser(wire.author)
  };
}

function feedTargetFromWire(wire: WireFeedTarget): FeedTargetSummary {
  let kind: FeedTargetKind;
  let title: string;
  if (wire.type === FeedTargetKind.ANSWER) {
    kind = FeedTargetKind.ANSWER;
    title = requiredText(wire.question?.title ?? wire.question?.name, 'feed.target.question.title');
  } else if (wire.type === FeedTargetKind.ARTICLE) {
    kind = FeedTargetKind.ARTICLE;
    title = requiredText(wire.title, 'feed.target.title');
  } else if (wire.type === FeedTargetKind.QUESTION) {
    kind = FeedTargetKind.QUESTION;
    title = requiredText(wire.title ?? wire.name, 'feed.target.title');
  } else {
    throw new DomainDecodeError(
      DomainDecodeFailureKind.UNSUPPORTED_CONTENT,
      `不支持的 Feed 内容类型：${wire.type ?? '<empty>'}`
    );
  }
  return {
    kind: kind,
    id: requiredId(wire.id, 'feed.target.id'),
    title: title,
    excerpt: wire.excerpt ?? '',
    url: wire.url ?? '',
    voteupCount: wire.voteup_count ?? 0,
    commentCount: wire.comment_count ?? 0,
    author: optionalUser(wire.author)
  };
}

function pageCursorFromWire(wire?: WirePaging): PageCursor {
  return {
    isEnd: wire?.is_end ?? true,
    isStart: wire?.is_start ?? true,
    next: optionalText(wire?.next),
    previous: optionalText(wire?.previous) ?? optionalText(wire?.prev),
    page: wire?.page ?? -1,
    total: wire?.totals ?? 0
  };
}

export function decodeFeedPage(json: string): FeedPage {
  const wire = parseJson<WireFeedPage>(json);
  if (wire.error !== undefined) {
    throw new DomainDecodeError(
      DomainDecodeFailureKind.UPSTREAM_ERROR,
      `知乎接口返回错误（${wire.error.code ?? 'unknown'}）`
    );
  }
  if (wire.data === undefined) {
    throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, 'feed.data 不能为空');
  }
  const sourceItems = wire.data;
  const items: Array<FeedItem> = sourceItems.map((item: WireFeedItem): FeedItem => {
    if (item.target === undefined) {
      throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, 'feed.target 不能为空');
    }
    return {
      id: requiredId(item.id, 'feed.id'),
      verb: item.verb ?? '',
      actionText: optionalText(item.action_text),
      createdAt: item.created_time ?? 0,
      updatedAt: item.updated_time ?? 0,
      target: feedTargetFromWire(item.target)
    };
  });
  return {
    items: items,
    cursor: pageCursorFromWire(wire.paging)
  };
}
