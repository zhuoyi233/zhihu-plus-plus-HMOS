import {
  CommentContentKind,
  CommentItem,
  CommentPage,
  CommentSortOrder,
  SubmitCommentInput
} from '../domain/CommentModels';

export interface CommentRepository {
  /** 顶评列表：orderBy 缺省为热度（score）；cursor 提供分页续传。 */
  getRootCommentsPage(contentType: string, contentId: string, orderBy?: CommentSortOrder,
    cursor?: string): Promise<CommentPage>;
  /** 某条根评论的子评论列表分页。 */
  getChildCommentsPage(rootCommentId: string, cursor?: string): Promise<CommentPage>;
  /** 发表评论（replyToCommentId 缺省为新根评论）或回复；返回服务端创建的评论。 */
  submitComment(input: SubmitCommentInput): Promise<CommentItem>;
  /** 删除自己的评论。 */
  deleteComment(commentId: string): Promise<void>;
  /** 点赞/取消点赞评论：与上游 ArticleViewModel 的 /voters 语义一致（POST 点赞，DELETE 取消）。 */
  likeComment(commentId: string, liked: boolean): Promise<void>;
  cancel(): void;
}

export function isSupportedCommentContentType(value: string): boolean {
  return value === CommentContentKind.ANSWER || value === CommentContentKind.ARTICLE ||
    value === CommentContentKind.QUESTION || value === CommentContentKind.PIN;
}
