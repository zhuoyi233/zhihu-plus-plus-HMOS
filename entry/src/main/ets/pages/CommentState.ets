import {
  CommentContentKind,
  CommentItem,
  CommentPage,
  CommentRepository,
  CommentRepositoryFailure,
  CommentRepositoryFailureKind,
  CommentSortOrder,
  copyCommentWithLike,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionStatus
} from 'data';

export enum CommentPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface CommentViewState {
  readonly phase: CommentPhase;
  /** 当前模式（根评论列表或子评论列表）的条目。 */
  readonly items: Array<CommentItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  /** 列表/分页加载错误文案。 */
  readonly errorMessage?: string;
  readonly sortOrder: CommentSortOrder;
  /** 非空表示正在浏览该根评论的子评论列表。 */
  readonly activeRoot?: CommentItem;
  /** 回复目标；非空时输入框提交为回复。 */
  readonly replyTarget?: CommentItem;
  /** 发表/回复进行中。 */
  readonly submitting: boolean;
  /** 点赞请求进行中（全局门禁，同一时间只允许一个点赞请求）。 */
  readonly likeBusy: boolean;
  /** 删除进行中。 */
  readonly deleting: boolean;
  /** 交互（发表/删除/点赞）失败文案。 */
  readonly actionMessage?: string;
  readonly actionRequiresLogin: boolean;
}

export type CommentStateObserver = (state: CommentViewState) => void;

export const COMMENT_LOGIN_REQUIRED_MESSAGE = '评论需要登录，请先登录';

/** 将字符串内容类型转换为评论内容类型枚举；非法输入返回 undefined。 */
export function commentContentKind(value: string): CommentContentKind | undefined {
  switch (value) {
    case CommentContentKind.ANSWER:
      return CommentContentKind.ANSWER;
    case CommentContentKind.ARTICLE:
      return CommentContentKind.ARTICLE;
    case CommentContentKind.QUESTION:
      return CommentContentKind.QUESTION;
    case CommentContentKind.PIN:
      return CommentContentKind.PIN;
    default:
      return undefined;
  }
}

/**
 * 评论控制器：根评论/子评论列表状态机、分页去重、发表/回复/删除/点赞交互。
 * 登录门禁由 SessionRepository 状态直接判定，未认证时不发出任何网络请求。
 * 草稿由弹层外的页面持有（跨关闭保留），本控制器不保存草稿。
 */
export class CommentController {
  private readonly contentType: CommentContentKind;
  private readonly contentId: string;
  private readonly repository: CommentRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: CommentStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: CommentPhase = CommentPhase.IDLE;
  private sortOrder: CommentSortOrder = CommentSortOrder.SCORE;
  private requiresLogin: boolean = false;
  private errorMessage?: string;
  private submitting: boolean = false;
  private likeBusy: boolean = false;
  private deleting: boolean = false;
  private actionMessage?: string;
  private actionRequiresLogin: boolean = false;
  private activeRoot?: CommentItem;
  private replyTarget?: CommentItem;
  private rootItems: Array<CommentItem> = [];
  private rootNextCursor?: string;
  private rootReachedEnd: boolean = true;
  private rootLoadingMore: boolean = false;
  private rootPaginationBlocked: boolean = false;
  private childItems: Array<CommentItem> = [];
  private childNextCursor?: string;
  private childReachedEnd: boolean = true;
  private childLoadingMore: boolean = false;
  private childPaginationBlocked: boolean = false;
  private retryLoadMore: boolean = false;

  constructor(contentType: CommentContentKind, contentId: string, repository: CommentRepository,
    session: LoginSessionGateway, observer: CommentStateObserver = (_state: CommentViewState): void => {
    }) {
    this.contentType = contentType;
    this.contentId = contentId;
    this.repository = repository;
    this.session = session;
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.rootLoadingMore = false;
    this.childLoadingMore = false;
    this.repository.cancel();
  }

  snapshot(): CommentViewState {
    const isChild = this.activeRoot !== undefined;
    const loadingMore = isChild ? this.childLoadingMore : this.rootLoadingMore;
    const paginationBlocked = isChild ? this.childPaginationBlocked : this.rootPaginationBlocked;
    return {
      phase: this.phase,
      items: isChild ? this.childItems.slice() : this.rootItems.slice(),
      loadingMore: loadingMore,
      canLoadMore: !paginationBlocked && this.hasNext(isChild),
      requiresLogin: this.requiresLogin,
      errorMessage: this.errorMessage,
      sortOrder: this.sortOrder,
      activeRoot: this.activeRoot,
      replyTarget: this.replyTarget,
      submitting: this.submitting,
      likeBusy: this.likeBusy,
      deleting: this.deleting,
      actionMessage: this.actionMessage,
      actionRequiresLogin: this.actionRequiresLogin
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = CommentPhase.LOADING;
    this.rootItems = [];
    this.rootNextCursor = undefined;
    this.rootReachedEnd = true;
    this.rootLoadingMore = false;
    this.rootPaginationBlocked = false;
    this.childItems = [];
    this.childNextCursor = undefined;
    this.childReachedEnd = true;
    this.childLoadingMore = false;
    this.childPaginationBlocked = false;
    this.activeRoot = undefined;
    this.replyTarget = undefined;
    this.submitting = false;
    this.likeBusy = false;
    this.deleting = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.actionMessage = undefined;
    this.actionRequiresLogin = false;
    this.retryLoadMore = false;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = CommentPhase.ERROR;
      this.errorMessage = COMMENT_LOGIN_REQUIRED_MESSAGE;
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
    return this.loadRootFirst(generation);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.clearPaginationBlocked();
      return this.loadMore();
    }
    return this.loadInitial();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === CommentPhase.LOADING || this.submitting || this.deleting) {
      return;
    }
    const activeRoot = this.activeRoot;
    const isChild = activeRoot !== undefined;
    const loadingMore = isChild ? this.childLoadingMore : this.rootLoadingMore;
    const paginationBlocked = isChild ? this.childPaginationBlocked : this.rootPaginationBlocked;
    if (loadingMore || paginationBlocked || !this.hasNext(isChild)) {
      return;
    }
    const cursor = isChild ? this.childNextCursor : this.rootNextCursor;
    if (cursor === undefined) {
      return;
    }
    const rootCommentId = activeRoot === undefined ? undefined : activeRoot.id;
    const generation = this.generation;
    if (isChild) {
      this.childLoadingMore = true;
    } else {
      this.rootLoadingMore = true;
    }
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.retryLoadMore = false;
    this.emit();
    try {
      const page = rootCommentId !== undefined
        ? await this.repository.getChildCommentsPage(rootCommentId, cursor)
        : await this.repository.getRootCommentsPage(this.contentType, this.contentId, this.sortOrder, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      if (isChild) {
        this.childItems = mergeComments(this.childItems, page.items);
        this.applyChildPage(page);
      } else {
        this.rootItems = mergeComments(this.rootItems, page.items);
        this.applyRootPage(page);
      }
      const items = isChild ? this.childItems : this.rootItems;
      this.phase = items.length === 0 ? CommentPhase.EMPTY : CommentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      const items = isChild ? this.childItems : this.rootItems;
      this.phase = items.length === 0 ? CommentPhase.ERROR : CommentPhase.READY;
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        if (isChild) {
          this.childLoadingMore = false;
        } else {
          this.rootLoadingMore = false;
        }
        this.emit();
      }
    }
  }

  async changeSortOrder(order: CommentSortOrder): Promise<void> {
    if (!this.active || order === this.sortOrder) {
      return Promise.resolve();
    }
    this.sortOrder = order;
    return this.loadInitial();
  }

  async openChildComments(root: CommentItem): Promise<void> {
    if (!this.active || this.activeRoot !== undefined || this.submitting || this.deleting) {
      return;
    }
    const generation = this.generation;
    this.activeRoot = root;
    this.replyTarget = undefined;
    this.childItems = [];
    this.childNextCursor = undefined;
    this.childReachedEnd = true;
    this.childLoadingMore = false;
    this.childPaginationBlocked = false;
    this.retryLoadMore = false;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.phase = CommentPhase.LOADING;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = CommentPhase.ERROR;
      this.errorMessage = COMMENT_LOGIN_REQUIRED_MESSAGE;
      this.requiresLogin = true;
      this.emit();
      return;
    }
    try {
      const page = await this.repository.getChildCommentsPage(root.id);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.childItems = mergeComments([], page.items);
      this.applyChildPage(page);
      this.phase = this.childItems.length === 0 ? CommentPhase.EMPTY : CommentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = CommentPhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  closeChildComments(): void {
    if (!this.active || this.activeRoot === undefined) {
      return;
    }
    this.activeRoot = undefined;
    this.replyTarget = undefined;
    this.childItems = [];
    this.childNextCursor = undefined;
    this.childReachedEnd = true;
    this.childLoadingMore = false;
    this.childPaginationBlocked = false;
    this.retryLoadMore = false;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.phase = this.rootItems.length === 0 ? CommentPhase.EMPTY : CommentPhase.READY;
    this.emit();
  }

  setReplyTarget(target: CommentItem | undefined): void {
    if (!this.active || this.submitting) {
      return;
    }
    this.replyTarget = target;
    this.actionMessage = undefined;
    this.actionRequiresLogin = false;
    this.emit();
  }

  /** 发表新根评论（replyTarget 与 activeRoot 均缺省时）或回复；成功返回 true。 */
  async submitComment(text: string): Promise<boolean> {
    if (!this.active || this.submitting || this.deleting) {
      return false;
    }
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      this.actionMessage = '评论内容不能为空';
      this.emit();
      return false;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.actionRequiresLogin = true;
      this.actionMessage = COMMENT_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return false;
    }
    const generation = this.generation;
    const replyTarget = this.replyTarget;
    const activeRoot = this.activeRoot;
    const replyToId = replyTarget !== undefined
      ? replyTarget.id
      : (activeRoot !== undefined ? activeRoot.id : undefined);
    this.submitting = true;
    this.actionMessage = undefined;
    this.actionRequiresLogin = false;
    this.emit();
    try {
      const created = await this.repository.submitComment({
        contentType: this.contentType,
        contentId: this.contentId,
        content: trimmed,
        replyToCommentId: replyToId
      });
      if (!this.isCurrent(generation)) {
        return false;
      }
      if (activeRoot !== undefined) {
        this.childItems = [created].concat(this.childItems);
      } else {
        this.rootItems = [created].concat(this.rootItems);
      }
      this.replyTarget = undefined;
      this.phase = CommentPhase.READY;
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.actionMessage = commentActionError(error, '评论发送失败，请重试');
        this.actionRequiresLogin = commentActionRequiresLogin(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.submitting = false;
        this.emit();
      }
    }
  }

  /** 删除自己的评论：乐观移除，失败时按原位置回滚。 */
  async deleteComment(commentId: string): Promise<boolean> {
    if (!this.active || this.deleting || this.submitting) {
      return false;
    }
    const isChild = this.activeRoot !== undefined;
    const targetList = isChild ? this.childItems : this.rootItems;
    const index = targetList.findIndex((comment: CommentItem): boolean => comment.id === commentId);
    if (index < 0) {
      return false;
    }
    const target = targetList[index];
    if (!target.isAuthor) {
      return false;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.actionRequiresLogin = true;
      this.actionMessage = COMMENT_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return false;
    }
    const generation = this.generation;
    this.deleting = true;
    this.actionMessage = undefined;
    this.actionRequiresLogin = false;
    this.emit();
    const updated = targetList.slice();
    updated.splice(index, 1);
    this.replaceModeItems(isChild, updated);
    if (updated.length === 0 && this.phase === CommentPhase.READY) {
      this.phase = CommentPhase.EMPTY;
    }
    this.emit();
    try {
      await this.repository.deleteComment(commentId);
      if (!this.isCurrent(generation)) {
        return false;
      }
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        const restored = (isChild ? this.childItems : this.rootItems).slice();
        restored.splice(Math.min(index, restored.length), 0, target);
        this.replaceModeItems(isChild, restored);
        if (this.phase === CommentPhase.EMPTY) {
          this.phase = CommentPhase.READY;
        }
        this.actionMessage = commentActionError(error, '删除评论失败，请重试');
        this.actionRequiresLogin = commentActionRequiresLogin(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.deleting = false;
        this.emit();
      }
    }
  }

  /** 点赞/取消点赞：乐观更新 + 失败回滚；全局 busy 门禁阻止并发点赞。 */
  async toggleLike(comment: CommentItem): Promise<void> {
    if (!this.active || this.likeBusy || this.deleting || this.submitting) {
      return;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.actionRequiresLogin = true;
      this.actionMessage = COMMENT_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return;
    }
    const isChild = this.activeRoot !== undefined;
    const targetList = isChild ? this.childItems : this.rootItems;
    const index = targetList.findIndex((candidate: CommentItem): boolean => candidate.id === comment.id);
    if (index < 0) {
      return;
    }
    const generation = this.generation;
    const previous = targetList[index];
    const nextLiked = !previous.liked;
    const nextCount = Math.max(0, previous.likeCount + (nextLiked ? 1 : -1));
    this.likeBusy = true;
    this.actionMessage = undefined;
    this.actionRequiresLogin = false;
    const updated = targetList.slice();
    updated[index] = copyCommentWithLike(previous, nextLiked, nextCount);
    this.replaceModeItems(isChild, updated);
    this.emit();
    try {
      await this.repository.likeComment(comment.id, nextLiked);
      if (!this.isCurrent(generation)) {
        return;
      }
    } catch (error) {
      if (this.isCurrent(generation)) {
        const reverted = (isChild ? this.childItems : this.rootItems).slice();
        const revertIndex = reverted.findIndex((candidate: CommentItem): boolean => candidate.id === comment.id);
        if (revertIndex >= 0) {
          reverted[revertIndex] = previous;
        }
        this.replaceModeItems(isChild, reverted);
        this.actionMessage = commentActionError(error, '点赞操作失败，请重试');
        this.actionRequiresLogin = commentActionRequiresLogin(error);
      }
    } finally {
      if (this.isCurrent(generation)) {
        this.likeBusy = false;
        this.emit();
      }
    }
  }

  private async loadRootFirst(generation: number): Promise<void> {
    try {
      const page = await this.repository.getRootCommentsPage(
        this.contentType, this.contentId, this.sortOrder
      );
      if (!this.isCurrent(generation)) {
        return;
      }
      this.rootItems = mergeComments([], page.items);
      this.applyRootPage(page);
      this.phase = this.rootItems.length === 0 ? CommentPhase.EMPTY : CommentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = CommentPhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private applyRootPage(page: CommentPage): void {
    this.rootNextCursor = page.cursor.next;
    this.rootReachedEnd = page.cursor.isEnd;
    this.rootPaginationBlocked = false;
  }

  private applyChildPage(page: CommentPage): void {
    this.childNextCursor = page.cursor.next;
    this.childReachedEnd = page.cursor.isEnd;
    this.childPaginationBlocked = false;
  }

  private replaceModeItems(isChild: boolean, items: Array<CommentItem>): void {
    if (isChild) {
      this.childItems = items;
    } else {
      this.rootItems = items;
    }
  }

  private clearPaginationBlocked(): void {
    if (this.activeRoot !== undefined) {
      this.childPaginationBlocked = false;
    } else {
      this.rootPaginationBlocked = false;
    }
  }

  private setFailure(error: Object, more: boolean): void {
    const authentication = error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION;
    this.requiresLogin = authentication && (error.status === undefined || error.status === 401);
    this.errorMessage = authentication && error.status === 403
      ? '请求被拒绝，可能需要完成知乎风控验证'
      : this.requiresLogin
        ? COMMENT_LOGIN_REQUIRED_MESSAGE
        : more ? '加载更多失败，请重试' : '评论加载失败，请检查网络后重试';
    if (more) {
      if (this.activeRoot !== undefined) {
        this.childPaginationBlocked = true;
      } else {
        this.rootPaginationBlocked = true;
      }
      this.retryLoadMore = true;
    }
  }

  private hasNext(isChild: boolean): boolean {
    if (isChild) {
      return !this.childReachedEnd && this.childNextCursor !== undefined && this.childNextCursor.length > 0;
    }
    return !this.rootReachedEnd && this.rootNextCursor !== undefined && this.rootNextCursor.length > 0;
  }

  private isCurrent(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

/** 按评论 ID 去重合并（保持现有顺序在前，新条目在后）。 */
export function mergeComments(current: Array<CommentItem>, incoming: Array<CommentItem>): Array<CommentItem> {
  const result: Array<CommentItem> = [];
  const seen: Set<string> = new Set<string>();
  current.concat(incoming).forEach((comment: CommentItem): void => {
    if (!seen.has(comment.id)) {
      seen.add(comment.id);
      result.push(comment);
    }
  });
  return result;
}

function commentActionError(error: Object, fallback: string): string {
  if (error instanceof CommentRepositoryFailure &&
    error.kind === CommentRepositoryFailureKind.INVALID_CONTENT) {
    return '评论内容不能为空';
  }
  if (error instanceof CommentRepositoryFailure &&
    error.kind === CommentRepositoryFailureKind.INVALID_IDENTIFIER) {
    return '评论标识无效，操作未能完成';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
    return error.status === 403
      ? '操作被拒绝，可能需要完成知乎风控验证'
      : '登录状态不可用，请登录后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.RATE_LIMITED) {
    return '操作过于频繁，请稍后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.TIMEOUT) {
    return '操作超时，请重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.SERVER) {
    return '知乎服务暂时不可用，请稍后重试';
  }
  return fallback;
}

function commentActionRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}
