import { CommentContentKind, CommentItem, CommentPage, CommentRepository, CommentSortOrder } from 'data';
import { commentImageUrl, stripCommentHtml } from './CommentText';

/** 回答尾部「热门评论」展示条数上限。 */
export const HOT_COMMENT_PREVIEW_LIMIT: number = 3;

/**
 * 从热度排序的根评论页里挑出适合在回答尾部预览的条目：
 * 去掉已折叠、已删除、没有任何可见文字/图片、以及赞同数为 0 的评论，按服务端顺序取前 limit 条。
 */
export function hotCommentPreview(items: Array<CommentItem>, limit: number): Array<CommentItem> {
  const picked: Array<CommentItem> = [];
  if (limit <= 0) {
    return picked;
  }
  for (const item of items) {
    if (picked.length >= limit) {
      break;
    }
    if (item.isDelete || item.collapsed) {
      continue;
    }
    // 0 赞同的评论不算"热评"：热度排序兜底段会混入没人认可的条目，预览里直接跳过。
    if (item.likeCount <= 0) {
      continue;
    }
    if (stripCommentHtml(item.contentHtml).length === 0 && commentImageUrl(item.contentHtml).length === 0) {
      continue;
    }
    picked.push(item);
  }
  return picked;
}

export enum HotCommentPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  EMPTY = 'empty',
  ERROR = 'error',
  READY = 'ready'
}

/**
 * 正文尾部是否渲染热评区块：
 * 只有拿到可展示的热评时才占位；「没有热评」（含评论都在但都没赞）整块隐藏，
 * 不再留一张只有「暂无热评」的空卡片。加载中与失败仍保留反馈（在文档末尾，出现/消失不推移上方正文）。
 */
export function hotCommentSectionVisible(phase: HotCommentPhase): boolean {
  return phase === HotCommentPhase.LOADING || phase === HotCommentPhase.ERROR ||
    phase === HotCommentPhase.READY;
}

export interface HotCommentViewState {
  answerId: string;
  phase: HotCommentPhase;
  comments: Array<CommentItem>;
}

/** 每次请求独占仓库；取消只影响自己的 IO，不取消完整评论页或另一回答的请求。 */
export class HotCommentController {
  private generation: number = 0;
  private identity: string = '';
  private pending?: CommentRepository;
  private state: HotCommentViewState = { answerId: '', phase: HotCommentPhase.IDLE, comments: [] };
  private readonly repositoryFactory: () => CommentRepository | undefined;
  private readonly observe: (state: HotCommentViewState) => void;

  constructor(factory: () => CommentRepository | undefined, observe: (state: HotCommentViewState) => void) {
    this.repositoryFactory = factory;
    this.observe = observe;
  }

  snapshot(): HotCommentViewState { return this.state; }

  reset(): void {
    this.generation += 1;
    this.identity = '';
    const pending = this.pending;
    this.pending = undefined;
    pending?.cancel();
    this.publish('', HotCommentPhase.IDLE, []);
  }

  async load(answerId: string, documentKey: string, accountKey: string, force: boolean = false): Promise<void> {
    const identity = JSON.stringify([answerId, documentKey, accountKey]);
    if (!force && this.identity === identity) { return; }
    this.reset();
    this.identity = identity;
    const generation = this.generation;
    this.publish(answerId, HotCommentPhase.LOADING, []);
    try {
      const repository = this.repositoryFactory();
      if (repository === undefined) { throw new Error('热评数据源未配置'); }
      this.pending = repository;
      const page: CommentPage = await repository.getRootCommentsPage(
        CommentContentKind.ANSWER, answerId, CommentSortOrder.SCORE);
      if (generation !== this.generation || identity !== this.identity) { return; }
      const comments = hotCommentPreview(page.items, HOT_COMMENT_PREVIEW_LIMIT);
      this.publish(answerId, comments.length > 0 ? HotCommentPhase.READY : HotCommentPhase.EMPTY, comments);
    } catch (_error) {
      if (generation === this.generation && identity === this.identity) {
        this.publish(answerId, HotCommentPhase.ERROR, []);
      }
    } finally {
      if (generation === this.generation) { this.pending = undefined; }
    }
  }

  private publish(answerId: string, phase: HotCommentPhase, comments: Array<CommentItem>): void {
    this.state = { answerId: answerId, phase: phase, comments: comments };
    this.observe(this.state);
  }
}
