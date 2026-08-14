import {
  CommentContentKind,
  CommentItem,
  CommentPage,
  CommentSortOrder,
  SubmitCommentInput
} from '../domain/CommentModels';
import {
  decodeChildCommentPage,
  decodeCommentResponse,
  decodeRootCommentPage
} from '../domain/CommentDecoder';
import { PageCursor } from '../domain/DomainModels';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { normalizeContentId } from './DefaultContentRepository';
import { CommentRepository, isSupportedCommentContentType } from './CommentRepository';

const COMMENT_CURSOR_MAX_LENGTH = 4096;

/** 发表评论/回复的请求体结构（content 已转义并包装为 `<p>`）。 */
interface SubmitCommentWire {
  content: string;
  reply_comment_id?: string;
}

export enum CommentRepositoryFailureKind {
  INVALID_IDENTIFIER = 'invalid_identifier',
  INVALID_CONTENT = 'invalid_content',
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class CommentRepositoryFailure extends Error {
  readonly kind: CommentRepositoryFailureKind;

  constructor(kind: CommentRepositoryFailureKind) {
    let message = '评论请求已取消';
    if (kind === CommentRepositoryFailureKind.INVALID_IDENTIFIER) {
      message = '评论标识无效';
    } else if (kind === CommentRepositoryFailureKind.INVALID_CONTENT) {
      message = '评论内容不能为空';
    } else if (kind === CommentRepositoryFailureKind.INVALID_CURSOR) {
      message = '评论返回了不受信任的分页地址';
    } else if (kind === CommentRepositoryFailureKind.REPEATED_CURSOR) {
      message = '评论分页游标已被请求';
    }
    super(message);
    this.name = 'CommentRepositoryFailure';
    this.kind = kind;
  }
}

function normalizeContentType(value: string): string {
  if (!isSupportedCommentContentType(value)) {
    throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  return value;
}

function normalizeCommentId(id: string): string {
  // 评论 ID 与内容 ID 同为正整数；斜杠/查询串/前导零在网络前拒绝。
  if (!/^[1-9][0-9]{0,29}$/.test(id)) {
    throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  return id;
}

function isTrustedCommentCursor(cursor: string): boolean {
  return cursor.length > 0 && cursor.length <= COMMENT_CURSOR_MAX_LENGTH &&
    !/[\u0000-\u0020\u007F-\uFFFF]/.test(cursor) && !cursor.includes('#');
}

/** 构造顶评列表 URL；cursor 缺省时返回带排序参数的初始地址，否则仅校验并原样返回游标。 */
export function buildRootCommentsUrl(contentTypeValue: string, contentIdValue: string,
  orderBy?: CommentSortOrder, cursor?: string): string {
  const contentType = normalizeContentType(contentTypeValue);
  const contentId = normalizeContentId(contentIdValue);
  if (cursor !== undefined) {
    if (!isRootCommentsCursorUrl(contentType, contentId, cursor)) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_CURSOR);
    }
    return cursor;
  }
  const order = orderBy ?? CommentSortOrder.SCORE;
  return `https://www.zhihu.com/api/v4/comment_v5/${contentType}s/${contentId}/root_comment?order_by=${order}`;
}

/** 顶评游标必须精确匹配本内容源的 root_comment 前缀，拒绝跨来源/控制字符/片段/超长。 */
export function isRootCommentsCursorUrl(contentTypeValue: string, contentIdValue: string, cursor: string): boolean {
  const contentType = normalizeContentType(contentTypeValue);
  const contentId = normalizeContentId(contentIdValue);
  if (!isTrustedCommentCursor(cursor)) {
    return false;
  }
  const prefix = `https://www.zhihu.com/api/v4/comment_v5/${contentType}s/${contentId}/root_comment?`;
  return cursor.startsWith(prefix);
}

/** 构造子评论列表 URL；与上游 ChildCommentViewModel 一致使用 comment_v5/comment/{rootId}/child_comment。 */
export function buildChildCommentsUrl(rootCommentIdValue: string, cursor?: string): string {
  const rootCommentId = normalizeCommentId(rootCommentIdValue);
  if (cursor !== undefined) {
    if (!isChildCommentsCursorUrl(rootCommentId, cursor)) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_CURSOR);
    }
    return cursor;
  }
  return `https://www.zhihu.com/api/v4/comment_v5/comment/${rootCommentId}/child_comment`;
}

export function isChildCommentsCursorUrl(rootCommentIdValue: string, cursor: string): boolean {
  const rootCommentId = normalizeCommentId(rootCommentIdValue);
  if (!isTrustedCommentCursor(cursor)) {
    return false;
  }
  const prefix = `https://www.zhihu.com/api/v4/comment_v5/comment/${rootCommentId}/child_comment?`;
  return cursor.startsWith(prefix);
}

/** 发表评论/回复端点：与上游 RootCommentViewModel.submitCommentUrl 一致（comment_v5/{type}s/{id}/comment）。 */
export function buildSubmitCommentUrl(contentTypeValue: string, contentIdValue: string): string {
  const contentType = normalizeContentType(contentTypeValue);
  const contentId = normalizeContentId(contentIdValue);
  return `https://www.zhihu.com/api/v4/comment_v5/${contentType}s/${contentId}/comment`;
}

export function buildDeleteCommentUrl(commentIdValue: string): string {
  return `https://www.zhihu.com/api/v4/comments/${normalizeCommentId(commentIdValue)}`;
}

/** 评论点赞端点：与上游 ArticleViewModel 的 /voters 语义一致。 */
export function buildCommentLikeUrl(commentIdValue: string): string {
  return `https://www.zhihu.com/api/v4/comments/${normalizeCommentId(commentIdValue)}/voters`;
}

export function buildCommentLikeBody(): string {
  return JSON.stringify({ type: 'up' });
}

export function buildSubmitCommentBody(input: SubmitCommentInput): string {
  const content = input.content.trim();
  if (content.length === 0) {
    throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_CONTENT);
  }
  const body: SubmitCommentWire = {
    content: `<p>${escapeCommentHtml(content)}</p>`
  };
  if (input.replyToCommentId !== undefined && input.replyToCommentId.length > 0) {
    body.reply_comment_id = input.replyToCommentId;
  }
  return JSON.stringify(body);
}

/** 转义评论正文的 HTML 特殊字符，防止 HTML 注入；与上游 RootCommentViewModel.escapeCommentHtml 一致。 */
export function escapeCommentHtml(source: string): string {
  let result = '';
  for (const char of source) {
    if (char === '&') {
      result += '&amp;';
    } else if (char === '<') {
      result += '&lt;';
    } else if (char === '>') {
      result += '&gt;';
    } else if (char === '"') {
      result += '&quot;';
    } else if (char === '\'') {
      result += '&#39;';
    } else {
      result += char;
    }
  }
  return result;
}

function terminalCursor(cursor: PageCursor): PageCursor {
  return {
    isEnd: true,
    isStart: cursor.isStart,
    previous: cursor.previous,
    page: cursor.page,
    total: cursor.total
  };
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}

export class DefaultCommentRepository implements CommentRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredRootIdentities: Set<string> = new Set<string>();
  private deliveredChildIdentities: Set<string> = new Set<string>();

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getRootCommentsPage(contentType: string, contentId: string, orderBy?: CommentSortOrder,
    cursor?: string): Promise<CommentPage> {
    const requestGeneration = this.generation;
    const requestUrl = buildRootCommentsUrl(contentType, contentId, orderBy, cursor);
    if (cursor !== undefined && this.requestedCursors.has(requestUrl)) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response = await this.execute(requestUrl, ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.CANCELLED);
    }
    const page = decodeRootCommentPage(response.body);
    return this.deduplicate(page, cursor, requestUrl, this.deliveredRootIdentities);
  }

  async getChildCommentsPage(rootCommentId: string, cursor?: string): Promise<CommentPage> {
    const requestGeneration = this.generation;
    const requestUrl = buildChildCommentsUrl(rootCommentId, cursor);
    if (cursor !== undefined && this.requestedCursors.has(requestUrl)) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response = await this.execute(requestUrl, ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.CANCELLED);
    }
    const page = decodeChildCommentPage(response.body);
    return this.deduplicate(page, cursor, requestUrl, this.deliveredChildIdentities);
  }

  /** 去重并更新游标集合；fresh 加载（cursor 缺省）时重置已投递集合，分页时累积。 */
  private deduplicate(page: CommentPage, cursor: string | undefined, requestUrl: string,
    delivered: Set<string>): CommentPage {
    const requested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const retained = cursor === undefined ? new Set<string>() : delivered;
    requested.add(requestUrl);
    const items = page.items.filter((comment: CommentItem): boolean => {
      if (retained.has(comment.id)) {
        return false;
      }
      retained.add(comment.id);
      return true;
    });
    const next = page.cursor.next;
    const cursorLoops = (next === undefined && !page.cursor.isEnd) || next === requestUrl ||
      (next !== undefined && requested.has(next));
    this.requestedCursors = requested;
    if (cursor === undefined) {
      delivered.clear();
      retained.forEach((value: string): void => {
        delivered.add(value);
      });
    }
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(page.cursor) : page.cursor
    };
  }

  async submitComment(input: SubmitCommentInput): Promise<CommentItem> {
    const requestGeneration = this.generation;
    const contentType = normalizeContentType(input.contentType);
    const contentId = normalizeContentId(input.contentId);
    const body = buildSubmitCommentBody(input);
    const response = await this.execute(
      buildSubmitCommentUrl(contentType, contentId),
      ZhihuHttpMethod.POST,
      body
    );
    if (requestGeneration !== this.generation) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.CANCELLED);
    }
    return decodeCommentResponse(response.body);
  }

  async deleteComment(commentId: string): Promise<void> {
    const requestGeneration = this.generation;
    await this.execute(buildDeleteCommentUrl(commentId), ZhihuHttpMethod.DELETE);
    if (requestGeneration !== this.generation) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.CANCELLED);
    }
  }

  async likeComment(commentId: string, liked: boolean): Promise<void> {
    const requestGeneration = this.generation;
    await this.execute(
      buildCommentLikeUrl(commentId),
      liked ? ZhihuHttpMethod.POST : ZhihuHttpMethod.DELETE,
      buildCommentLikeBody()
    );
    if (requestGeneration !== this.generation) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.CANCELLED);
    }
  }

  private async execute(url: string, method: ZhihuHttpMethod, body?: string): Promise<ZhihuHttpResponse> {
    return this.httpClient.execute({
      url: url,
      method: method,
      body: body,
      accept: 'application/json',
      useSession: true,
      signWithZse: true,
      contentType: body === undefined ? undefined : 'application/json'
    });
  }
}
