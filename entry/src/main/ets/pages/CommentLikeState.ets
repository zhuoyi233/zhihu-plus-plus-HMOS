import { CommentItem } from 'data';

/** 每条评论共享一个可观察的点赞状态，更新时保留评论行和头像节点。 */
@Observed
export class CommentLikeState {
  readonly id: string;
  liked: boolean;
  count: number;

  constructor(comment: CommentItem) {
    this.id = comment.id;
    this.liked = comment.liked;
    this.count = comment.likeCount;
  }

  update(comment: CommentItem): void {
    if (this.liked !== comment.liked) {
      this.liked = comment.liked;
    }
    if (this.count !== comment.likeCount) {
      this.count = comment.likeCount;
    }
  }
}

export class CommentLikeStateStore {
  private readonly states: Map<string, CommentLikeState> = new Map<string, CommentLikeState>();

  get(comment: CommentItem): CommentLikeState {
    const existing = this.states.get(comment.id);
    if (existing !== undefined) {
      return existing;
    }
    const state = new CommentLikeState(comment);
    this.states.set(comment.id, state);
    return state;
  }

  sync(items: Array<CommentItem>): void {
    items.forEach((comment: CommentItem): void => {
      this.get(comment).update(comment);
      this.sync(comment.childComments);
    });
  }

  snapshot(): Record<string, CommentLikeState> {
    const result: Record<string, CommentLikeState> = {};
    this.states.forEach((state: CommentLikeState, id: string): void => {
      result[id] = state;
    });
    return result;
  }
}
