import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  MobileNotificationCategory,
  MOBILE_NOTIFICATION_CATEGORIES,
  mobileNotificationCategoryInfo,
  MobileNotificationCategoryUnreadCounts,
  MobileNotificationColumnHead,
  MobileNotificationMessagePage,
  MobileNotificationRepository,
  MobileNotificationTimelineItem,
  mobileNotificationUnreadTotal,
  mobileTimelineStableId,
  SessionStatus
} from 'data';

export enum NotificationPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface NotificationViewState {
  readonly phase: NotificationPhase;
  readonly items: Array<MobileNotificationTimelineItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly busy: boolean;
  readonly unreadTotal: number;
  readonly categoryUnread: MobileNotificationCategoryUnreadCounts;
  readonly invitation?: MobileNotificationColumnHead;
  readonly errorMessage?: string;
}

export type NotificationStateObserver = (state: NotificationViewState) => void;

function cloneCategoryUnread(counts: MobileNotificationCategoryUnreadCounts):
  MobileNotificationCategoryUnreadCounts {
  return {
    comment: counts.comment,
    like: counts.like,
    favorite: counts.favorite,
    follow: counts.follow
  };
}

/**
 * 消息中心控制器（对齐上游 `NotificationViewModel`）：首屏 message/v3 提供
 * 四分类未读数、邀请回答列头与会话列表；全部已读按四分类串行 POST readall。
 */
export class NotificationController {
  private readonly repository: MobileNotificationRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: NotificationStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: NotificationPhase = NotificationPhase.IDLE;
  private items: Array<MobileNotificationTimelineItem> = [];
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private requiresLogin: boolean = false;
  private busy: boolean = false;
  private unreadTotal: number = 0;
  private categoryUnread: MobileNotificationCategoryUnreadCounts =
    { comment: 0, like: 0, favorite: 0, follow: 0 };
  private invitation?: MobileNotificationColumnHead;
  private errorMessage?: string;

  constructor(repository: MobileNotificationRepository, session: LoginSessionGateway,
    observer: NotificationStateObserver = (_state: NotificationViewState): void => {
    }) {
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
    this.loadingMore = false;
    this.repository.cancel();
  }

  snapshot(): NotificationViewState {
    return {
      phase: this.phase,
      items: this.items.slice(),
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && !this.reachedEnd && this.nextCursor !== undefined,
      requiresLogin: this.requiresLogin,
      busy: this.busy,
      unreadTotal: this.unreadTotal,
      categoryUnread: cloneCategoryUnread(this.categoryUnread),
      invitation: this.invitation,
      errorMessage: this.errorMessage
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = NotificationPhase.LOADING;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = NotificationPhase.ERROR;
      this.errorMessage = '消息需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
    return this.fetchPage(generation, undefined);
  }

  retry(): Promise<void> {
    return this.loadInitial();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === NotificationPhase.LOADING || this.loadingMore ||
      this.paginationBlocked || this.reachedEnd || this.nextCursor === undefined) {
      return;
    }
    const generation = this.generation;
    const cursor = this.nextCursor;
    this.loadingMore = true;
    this.errorMessage = undefined;
    this.emit();
    try {
      await this.fetchPage(generation, cursor);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      if (this.items.length === 0) {
        this.phase = NotificationPhase.ERROR;
      }
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  /**
   * 全部已读（对齐上游 `markAllAsRead`）：乐观清零四分类未读，串行 POST
   * readall；任一失败则回滚未读数并展示结构化错误。
   */
  async markAllRead(): Promise<boolean> {
    if (!this.active || this.busy) {
      return false;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = '标记已读需要登录，请登录后重试';
      this.emit();
      return false;
    }
    const generation = this.generation;
    const previousUnread = this.categoryUnread;
    this.busy = true;
    this.errorMessage = undefined;
    this.unreadTotal = 0;
    this.categoryUnread = { comment: 0, like: 0, favorite: 0, follow: 0 };
    this.emit();
    try {
      for (let index = 0; index < MOBILE_NOTIFICATION_CATEGORIES.length; index += 1) {
        await this.repository.markEntryAsRead(
          mobileNotificationCategoryInfo(MOBILE_NOTIFICATION_CATEGORIES[index]).entryName);
        if (!this.isCurrent(generation)) {
          return false;
        }
      }
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.categoryUnread = previousUnread;
        this.unreadTotal = mobileNotificationUnreadTotal(previousUnread);
        this.errorMessage = notificationMutationError(error);
        this.requiresLogin = notificationMutationRequiresLogin(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.busy = false;
        this.emit();
      }
    }
  }

  private async fetchPage(generation: number, cursor?: string): Promise<void> {
    try {
      const page: MobileNotificationMessagePage = await this.repository.getMessagePage(cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyPage(page, cursor === undefined);
      this.phase = this.items.length === 0 ? NotificationPhase.EMPTY : NotificationPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = NotificationPhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private applyPage(page: MobileNotificationMessagePage, isFirstPage: boolean): void {
    if (isFirstPage) {
      let comment = 0;
      let like = 0;
      let favorite = 0;
      let follow = 0;
      MOBILE_NOTIFICATION_CATEGORIES.forEach((category: MobileNotificationCategory): void => {
        const detailTitle = mobileNotificationCategoryInfo(category).detailTitle;
        const entry = page.overview.head.find((head): boolean => head.detailTitle === detailTitle);
        const count = entry === undefined ? 0 : entry.unreadCount;
        if (category === MobileNotificationCategory.LIKE) {
          like = count;
        } else if (category === MobileNotificationCategory.FAVORITE) {
          favorite = count;
        } else if (category === MobileNotificationCategory.FOLLOW) {
          follow = count;
        } else {
          comment = count;
        }
      });
      const unread: MobileNotificationCategoryUnreadCounts = {
        comment: comment,
        like: like,
        favorite: favorite,
        follow: follow
      };
      this.categoryUnread = unread;
      this.unreadTotal = mobileNotificationUnreadTotal(unread);
      this.invitation = page.overview.columnHead.length > 0 ? page.overview.columnHead[0] : undefined;
      this.items = [];
    }
    // 对齐上游：过滤 type=="empty" 占位并按 stableId 去重。
    const existing: Set<string> = new Set<string>();
    this.items.forEach((item: MobileNotificationTimelineItem): void => {
      existing.add(mobileTimelineStableId(item));
    });
    page.items.forEach((item: MobileNotificationTimelineItem): void => {
      if (item.type === 'empty') {
        return;
      }
      const id = mobileTimelineStableId(item);
      if (!existing.has(id)) {
        existing.add(id);
        this.items.push(item);
      }
    });
    this.nextCursor = page.cursor.next;
    this.reachedEnd = page.cursor.isEnd || page.cursor.next === undefined;
    this.paginationBlocked = false;
  }

  private setFailure(error: Object, more: boolean): void {
    const authentication = error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION;
    this.requiresLogin = authentication && (error.status === undefined || error.status === 401);
    this.errorMessage = authentication && error.status === 403
      ? '请求被拒绝，可能需要完成知乎风控验证'
      : this.requiresLogin
        ? '消息需要登录，请登录后重试'
        : more ? '加载更多失败，请重试' : '消息加载失败，请检查网络后重试';
    this.paginationBlocked = more;
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

function notificationMutationError(error: Object): string {
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
  return '标记已读失败，请重试';
}

function notificationMutationRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}
