import {
  CommentContentKind,
  CommentItem,
  CommentPage,
  CommentSortOrder,
  SubmitCommentInput
} from '../domain/CommentModels';
import { decodeCommentResponse, decodeRootCommentPage } from '../domain/CommentDecoder';
import { ZhihuHttpClient, ZhihuHttpMethod } from '../network/ZhihuHttpClient';
import {
  CommentRepositoryFailure,
  CommentRepositoryFailureKind,
  DefaultCommentRepository,
  escapeCommentHtml
} from './DefaultCommentRepository';

/** 划线句评论目标（对齐上游 SegmentCommentHolder）：seg_id 维度的评论流。 */
export interface SegmentCommentTarget {
  /** 'answer' | 'article'：划线评论仅对支持 segment_infos 的内容类型开放。 */
  readonly contentType: string;
  readonly contentId: string;
  /** 划线标识（可逗号分隔多个，对齐上游 segIds.joinToString(",")）。 */
  readonly segmentId: string;
  /** 划线句原文（发布段评时作为 segment.content 回传）。 */
  readonly segmentContent: string;
  readonly paragraphId: string;
  readonly startOffset: number;
  readonly endOffset: number;
}

export function isSegmentCommentTargetContentType(value: string): boolean {
  return value === CommentContentKind.ANSWER || value === CommentContentKind.ARTICLE;
}

/** 划线评论列表地址：comment_v5/{type}s/{id}/segment/root_comment?segment_id=...（对齐上游 RootCommentViewModel）。 */
export function buildSegmentRootCommentsUrl(target: SegmentCommentTarget, orderBy?: CommentSortOrder,
  cursor?: string): string {
  if (!isSegmentCommentTargetContentType(target.contentType)) {
    throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  if (cursor !== undefined) {
    if (!isSegmentRootCommentsCursorUrl(target, cursor)) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_CURSOR);
    }
    return cursor;
  }
  const order = orderBy ?? CommentSortOrder.SCORE;
  return `https://www.zhihu.com/api/v4/comment_v5/${target.contentType}s/${target.contentId}/` +
    `segment/root_comment?segment_id=${encodeURIComponent(target.segmentId)}&order_by=${order}`;
}

export function isSegmentRootCommentsCursorUrl(target: SegmentCommentTarget, cursor: string): boolean {
  if (!isSegmentCommentTargetContentType(target.contentType)) {
    return false;
  }
  const prefix = `https://www.zhihu.com/api/v4/comment_v5/${target.contentType}s/${target.contentId}/segment/root_comment?`;
  return cursor.startsWith(prefix);
}

/** 发布段评端点：comment_v5/{type}s/{id}/segment/comment（对齐上游 submitCommentUrl）。 */
export function buildSubmitSegmentCommentUrl(target: SegmentCommentTarget): string {
  if (!isSegmentCommentTargetContentType(target.contentType)) {
    throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  return `https://www.zhihu.com/api/v4/comment_v5/${target.contentType}s/${target.contentId}/segment/comment`;
}

/**
 * 发布段评请求体：在普通根评论 body 之上追加 segment 块（划线原文 + 段内区间），
 * 对齐上游 RootCommentViewModel.buildSubmitCommentBody 的 SegmentCommentHolder 分支。
 */
export function buildSubmitSegmentCommentBody(target: SegmentCommentTarget, content: string,
  replyToCommentId?: string): string {
  const text = content.trim();
  if (text.length === 0) {
    throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_CONTENT);
  }
  const startOffsetWire: SegmentSubmitOffset = { offset: target.startOffset, paragraph_id: target.paragraphId };
  const endOffsetWire: SegmentSubmitOffset = { offset: target.endOffset, paragraph_id: target.paragraphId };
  const positionWire: SegmentSubmitPosition = { start: startOffsetWire, end: endOffsetWire };
  const segmentWire: SegmentSubmitBlock = { content: target.segmentContent, position: positionWire };
  const body: SegmentSubmitWire = {
    content: `<p>${escapeCommentHtml(text)}</p>`,
    segment: segmentWire
  };
  if (replyToCommentId !== undefined && replyToCommentId.length > 0) {
    body.reply_comment_id = replyToCommentId;
  }
  return JSON.stringify(body);
}

interface SegmentSubmitOffset {
  offset: number;
  paragraph_id: string;
}

interface SegmentSubmitPosition {
  start: SegmentSubmitOffset;
  end: SegmentSubmitOffset;
}

interface SegmentSubmitBlock {
  content: string;
  position: SegmentSubmitPosition;
}

interface SegmentSubmitWire {
  content: string;
  reply_comment_id?: string;
  segment: SegmentSubmitBlock;
}

/**
 * 划线句评论仓库：实现通用 CommentRepository 接口，使评论页 UI 零改动切换数据源。
 * 根评论列表与发布走 segment 专用端点；子评论/点赞/删除与通用评论完全一致，直接继承。
 */
export class DefaultSegmentCommentRepository extends DefaultCommentRepository {
  private readonly target: SegmentCommentTarget;
  private deliveredSegmentIdentities: Set<string> = new Set<string>();

  constructor(target: SegmentCommentTarget, httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    super(httpClient);
    this.target = target;
  }

  async getRootCommentsPage(contentType: string, contentId: string, orderBy?: CommentSortOrder,
    cursor?: string): Promise<CommentPage> {
    if (contentType !== this.target.contentType || contentId !== this.target.contentId) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
    }
    const requestUrl = buildSegmentRootCommentsUrl(this.target, orderBy, cursor);
    const response = await this.execute(requestUrl, ZhihuHttpMethod.GET);
    const page = decodeRootCommentPage(response.body);
    return this.deduplicate(page, cursor, requestUrl, this.deliveredSegmentIdentities);
  }

  async submitComment(input: SubmitCommentInput): Promise<CommentItem> {
    if (input.contentType !== this.target.contentType || input.contentId !== this.target.contentId) {
      throw new CommentRepositoryFailure(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
    }
    const body = buildSubmitSegmentCommentBody(this.target, input.content, input.replyToCommentId);
    const response = await this.execute(
      buildSubmitSegmentCommentUrl(this.target),
      ZhihuHttpMethod.POST,
      body
    );
    return decodeCommentResponse(response.body);
  }
}
