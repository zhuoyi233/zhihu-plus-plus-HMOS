import { PageCursor } from './DomainModels';

/** 评论排序：与上游 BaseCommentViewModel 的 CommentSortOrder 一一对应（score=热度，ts=时间）。 */
export enum CommentSortOrder {
  SCORE = 'score',
  TIME = 'ts'
}

/** 评论所属内容类型：与上游 NavDestination 的 Article/Question/Pin 对应。 */
export enum CommentContentKind {
  ANSWER = 'answer',
  ARTICLE = 'article',
  QUESTION = 'question',
  PIN = 'pin'
}

export interface CommentAuthor {
  readonly id: string;
  readonly urlToken: string;
  readonly name: string;
  readonly avatarUrl: string;
  readonly headline: string;
}

export interface CommentTag {
  readonly type: string;
  readonly text: string;
}

/** 单条评论（根评论与子评论共用），与上游 DataHolder.Comment 字段对齐。 */
export interface CommentItem {
  readonly id: string;
  /** 评论正文 HTML（如 `<p>text</p>`），与上游 content 字段一致。 */
  readonly contentHtml: string;
  /** 创建时间（Unix 秒）。 */
  readonly createdAt: number;
  readonly liked: boolean;
  readonly likeCount: number;
  readonly collapsed: boolean;
  readonly reviewing: boolean;
  readonly isDelete: boolean;
  readonly isAuthor: boolean;
  readonly isAuthorTop: boolean;
  readonly replyCommentId?: string;
  readonly replyRootCommentId?: string;
  readonly author: CommentAuthor;
  readonly replyToAuthor?: CommentAuthor;
  /** 首个 author_tag 的文本（如「作者」），无则缺省。 */
  readonly authorTag?: string;
  /** comment_tag 列表（如 ip_info 属地）。 */
  readonly commentTags: Array<CommentTag>;
  /** 服务端返回的子评论总数；0 表示无子评论。 */
  readonly childCommentCount: number;
  /** root_comment 响应内联携带的可见子评论。 */
  readonly childComments: Array<CommentItem>;
}

export interface CommentPage {
  readonly items: Array<CommentItem>;
  readonly cursor: PageCursor;
}

export interface SubmitCommentInput {
  readonly contentType: CommentContentKind;
  readonly contentId: string;
  /** 原始评论文本（仓库负责转义 HTML 后包装为 `<p>`）。 */
  readonly content: string;
  /** 回复目标评论 ID；缺省表示发表新根评论。 */
  readonly replyToCommentId?: string;
}

export function commentIdentity(comment: CommentItem): string {
  return comment.id;
}

/** 返回带新点赞状态/计数的新评论对象，供乐观更新替换列表项（保持其余字段不变）。 */
export function copyCommentWithLike(comment: CommentItem, liked: boolean, likeCount: number): CommentItem {
  return {
    id: comment.id,
    contentHtml: comment.contentHtml,
    createdAt: comment.createdAt,
    liked: liked,
    likeCount: likeCount,
    collapsed: comment.collapsed,
    reviewing: comment.reviewing,
    isDelete: comment.isDelete,
    isAuthor: comment.isAuthor,
    isAuthorTop: comment.isAuthorTop,
    replyCommentId: comment.replyCommentId,
    replyRootCommentId: comment.replyRootCommentId,
    author: comment.author,
    replyToAuthor: comment.replyToAuthor,
    authorTag: comment.authorTag,
    commentTags: comment.commentTags,
    childCommentCount: comment.childCommentCount,
    childComments: comment.childComments
  };
}
