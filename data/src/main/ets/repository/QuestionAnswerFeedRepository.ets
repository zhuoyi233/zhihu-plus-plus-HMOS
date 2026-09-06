import { PageCursor, feedItemIdentity } from '../domain/DomainModels';
import {
  ChannelContentItem,
  ChannelFeedItem,
  ChannelFeedItemKind
} from '../domain/ChannelFeedModels';
import { decodeQuestionAnswerFeedPage } from '../domain/ZhihuChannelFeedDecoder';
import {
  BlockableContentSummary,
  ContentBlockingMatcher,
  ContentBlockingSession
} from '../data/BlockingRuleStore';
import { normalizeContentId } from './DefaultContentRepository';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';

/** 问题回答信息流排序：对齐上游 QuestionFeedViewModel 的 order 参数。 */
export enum QuestionAnswerSortOrder {
  DEFAULT = 'default',
  UPDATED = 'updated'
}

export const QUESTION_ANSWER_FEED_BASE_URL = 'https://www.zhihu.com/api/v4/questions';
export const QUESTION_ANSWER_FEED_LIMIT = 20;

export enum QuestionAnswerFeedFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class QuestionAnswerFeedFailure extends Error {
  readonly kind: QuestionAnswerFeedFailureKind;

  constructor(kind: QuestionAnswerFeedFailureKind) {
    let message = '回答请求已取消';
    if (kind === QuestionAnswerFeedFailureKind.INVALID_CURSOR) {
      message = '回答信息流返回了不受信任的分页游标';
    } else if (kind === QuestionAnswerFeedFailureKind.REPEATED_CURSOR) {
      message = '回答信息流分页游标已被请求';
    }
    super(message);
    this.name = 'QuestionAnswerFeedFailure';
    this.kind = kind;
  }
}

/** 问题回答信息流分页结果（条目恒为内容型，target 为回答）。 */
export interface QuestionAnswerFeedPage {
  readonly items: Array<ChannelContentItem>;
  readonly cursor: PageCursor;
}

export interface QuestionAnswerFeedRepository {
  loadPage(questionId: string, order: QuestionAnswerSortOrder, cursor?: string, reset?: boolean):
    Promise<QuestionAnswerFeedPage>;
  cancel(): void;
}

export function isQuestionAnswerFeedCursorUrl(questionId: string, cursor: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  return new RegExp(`^https://www\\.zhihu\\.com/api/v4/questions/${questionId}/feeds(?:\\?[^#]*)?$`)
    .test(cursor);
}

export function buildQuestionAnswerFeedRequestUrl(questionId: string, order: QuestionAnswerSortOrder,
  cursor?: string): string {
  const id = normalizeContentId(questionId);
  if (cursor !== undefined) {
    if (!isQuestionAnswerFeedCursorUrl(id, cursor)) {
      throw new QuestionAnswerFeedFailure(QuestionAnswerFeedFailureKind.INVALID_CURSOR);
    }
    return cursor;
  }
  return `${QUESTION_ANSWER_FEED_BASE_URL}/${id}/feeds?limit=${QUESTION_ANSWER_FEED_LIMIT}&order=${order}`;
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}

export class DefaultQuestionAnswerFeedRepository implements QuestionAnswerFeedRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly blockingMatcher?: ContentBlockingMatcher;
  private generation: number = 0;
  private requestedCursorKeys: Set<string> = new Set<string>();
  private deliveredIdentities: Set<string> = new Set<string>();

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient(), blockingMatcher?: ContentBlockingMatcher) {
    this.httpClient = httpClient;
    this.blockingMatcher = blockingMatcher;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async loadPage(questionId: string, order: QuestionAnswerSortOrder, cursor?: string, reset: boolean = false):
    Promise<QuestionAnswerFeedPage> {
    const requestGeneration = this.generation;
    const requestUrl = buildQuestionAnswerFeedRequestUrl(questionId, order, cursor);
    if (cursor !== undefined && !reset && this.requestedCursorKeys.has(requestUrl)) {
      throw new QuestionAnswerFeedFailure(QuestionAnswerFeedFailureKind.REPEATED_CURSOR);
    }

    const response = await this.httpClient.execute({
      url: requestUrl,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new QuestionAnswerFeedFailure(QuestionAnswerFeedFailureKind.CANCELLED);
    }
    const decoded = decodeQuestionAnswerFeedPage(response.body);
    if (requestGeneration !== this.generation) {
      throw new QuestionAnswerFeedFailure(QuestionAnswerFeedFailureKind.CANCELLED);
    }
    const contentItems: Array<ChannelContentItem> = [];
    decoded.items.forEach((item: ChannelFeedItem): void => {
      if (item.kind === ChannelFeedItemKind.CONTENT) {
        contentItems.push(item);
      }
    });
    const visible = await this.filterBlockedItems(contentItems);
    if (requestGeneration !== this.generation) {
      throw new QuestionAnswerFeedFailure(QuestionAnswerFeedFailureKind.CANCELLED);
    }
    const next = decoded.cursor.next;
    if (next !== undefined && !isQuestionAnswerFeedCursorUrl(normalizeContentId(questionId), next)) {
      throw new QuestionAnswerFeedFailure(QuestionAnswerFeedFailureKind.INVALID_CURSOR);
    }
    const requested = cursor === undefined || reset ? new Set<string>() : cloneStringSet(this.requestedCursorKeys);
    const delivered = cursor === undefined || reset ? new Set<string>() : cloneStringSet(this.deliveredIdentities);
    requested.add(requestUrl);
    const items: Array<ChannelContentItem> = [];
    visible.forEach((item: ChannelContentItem): void => {
      const identity = feedItemIdentity(item.feedItem);
      if (delivered.has(identity)) {
        return;
      }
      delivered.add(identity);
      items.push(item);
    });
    this.requestedCursorKeys = requested;
    this.deliveredIdentities = delivered;
    const nextRepeated = next !== undefined && requested.has(next);
    const cursorLoops = (next === undefined && !decoded.cursor.isEnd) || nextRepeated;
    return {
      items: items,
      cursor: cursorLoops ? {
        isEnd: true,
        isStart: decoded.cursor.isStart,
        previous: decoded.cursor.previous,
        page: decoded.cursor.page,
        total: decoded.cursor.total
      } : decoded.cursor
    };
  }

  private async filterBlockedItems(items: Array<ChannelContentItem>): Promise<Array<ChannelContentItem>> {
    const matcher = this.blockingMatcher;
    if (matcher === undefined) {
      return items;
    }
    const session: ContentBlockingSession = await matcher.createSession();
    const visible: Array<ChannelContentItem> = [];
    items.forEach((item: ChannelContentItem): void => {
      const authorId = item.feedItem.target.author?.id;
      const summary: BlockableContentSummary = authorId === undefined ? {
        title: item.feedItem.target.title,
        excerpt: item.feedItem.target.excerpt,
        topicIds: item.topicIds
      } : {
        title: item.feedItem.target.title,
        excerpt: item.feedItem.target.excerpt,
        authorId: authorId,
        topicIds: item.topicIds
      };
      if (session.match(summary) === undefined) {
        visible.push(item);
      }
    });
    return visible;
  }
}
