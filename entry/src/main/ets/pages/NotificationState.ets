import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  NotificationCategory,
  NotificationItem,
  NotificationPage,
  NotificationRepository,
  NotificationUnreadCounts,
  SessionStatus,
  notificationItemIdentity,
  notificationUnreadTotal
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
  readonly selectedCategory: NotificationCategory;
  readonly items: Array<NotificationItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly busy: boolean;
  readonly unreadTotal: number;
  readonly categoryUnread: NotificationUnreadCounts;
  readonly errorMessage?: string;
}

export type NotificationStateObserver = (state: NotificationViewState) => void;

interface CategoryPaging {
  nextCursor?: string;
  reachedEnd: boolean;
}

function emptyPaging(): CategoryPaging {
  return { nextCursor: undefined, reachedEnd: true };
}

function cloneCategoryUnread(counts: NotificationUnreadCounts): NotificationUnreadCounts {
  return {
    defaultCount: counts.defaultCount,
    followCount: counts.followCount,
    voteThankCount: counts.voteThankCount
  };
}

export class NotificationController {
  private readonly repository: NotificationRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: NotificationStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: NotificationPhase = NotificationPhase.IDLE;
  private selectedCategory: NotificationCategory = NotificationCategory.DEFAULT;
  private categoryData: Map<NotificationCategory, Array<NotificationItem>> = new Map();
  private categoryPaging: Map<NotificationCategory, CategoryPaging> = new Map();
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private retryLoadMore: boolean = false;
  private requiresLogin: boolean = false;
  private busy: boolean = false;
  private unreadTotal: number = 0;
  private categoryUnread: NotificationUnreadCounts = { defaultCount: 0, followCount: 0, voteThankCount: 0 };
  private errorMessage?: string;

  constructor(repository: NotificationRepository, session: LoginSessionGateway,
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
      selectedCategory: this.selectedCategory,
      items: this.currentItems().map((item: NotificationItem): NotificationItem => cloneNotification(item)),
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && this.hasNext(),
      requiresLogin: this.requiresLogin,
      busy: this.busy,
      unreadTotal: this.unreadTotal,
      categoryUnread: cloneCategoryUnread(this.categoryUnread),
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
    this.retryLoadMore = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = NotificationPhase.ERROR;
      this.errorMessage = '通知需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
    return this.loadInitialSerialized(generation);
  }

  selectCategory(category: NotificationCategory): Promise<void> {
    if (!this.active || category === this.selectedCategory) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.selectedCategory = category;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.retryLoadMore = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    const existing = this.categoryData.get(category);
    if (existing !== undefined && existing.length > 0) {
      this.phase = NotificationPhase.READY;
      this.emit();
      return Promise.resolve();
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = NotificationPhase.ERROR;
      this.errorMessage = '通知需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
    this.phase = NotificationPhase.LOADING;
    this.emit();
    return this.loadCategory(generation, category, true);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.paginationBlocked = false;
      return this.loadMore();
    }
    return this.loadInitial();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === NotificationPhase.LOADING || this.loadingMore ||
      this.paginationBlocked || !this.hasNext()) {
      return;
    }
    const generation = this.generation;
    const cursor = this.paging().nextCursor;
    if (cursor === undefined) {
      return;
    }
    this.loadingMore = true;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.retryLoadMore = false;
    this.emit();
    try {
      const page = await this.repository.getNotificationsPage(this.selectedCategory, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.mergePage(page);
      this.phase = this.currentItems().length === 0 ? NotificationPhase.EMPTY : NotificationPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = this.currentItems().length === 0 ? NotificationPhase.ERROR : NotificationPhase.READY;
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  /**
   * 单条已读：本地乐观更新。上游 NotificationViewModel 没有单条已读接口
   * （只有三个分类的 readall），点击通知项只做本地已读，不发网络请求。
   */
  markItemRead(itemId: string): void {
    const category = this.selectedCategory;
    const current = this.categoryData.get(category);
    if (current === undefined) {
      return;
    }
    const updated: Array<NotificationItem> = [];
    current.forEach((item: NotificationItem): void => {
      updated.push(item.id === itemId ? withReadFlag(item, true) : item);
    });
    this.categoryData.set(category, updated);
    this.emit();
  }

  /**
   * 全部已读：乐观更新所有已加载分类的未读项，随后按上游语义串行 POST
   * 三个分类的 readall；任一失败则回滚已读状态并展示结构化错误。
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
    const previousData = this.snapshotCategoryData();
    const previousUnread = this.unreadTotal;
    this.busy = true;
    this.errorMessage = undefined;
    this.markAllItemsReadLocally();
    this.unreadTotal = 0;
    this.categoryUnread = { defaultCount: 0, followCount: 0, voteThankCount: 0 };
    this.emit();
    try {
      await this.repository.markAllAsRead();
      if (!this.isCurrent(generation)) {
        return false;
      }
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.restoreCategoryData(previousData);
        this.unreadTotal = previousUnread;
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

  private async loadInitialSerialized(generation: number): Promise<void> {
    // ZhihuHttpClient 单飞：未读数与列表请求必须串行，先取未读数（失败不阻断），再取列表。
    await this.refreshUnreadCounts(generation);
    if (!this.isCurrent(generation)) {
      return;
    }
    await this.loadCategory(generation, this.selectedCategory, true);
  }

  private async loadCategory(generation: number, category: NotificationCategory, initial: boolean): Promise<void> {
    try {
      const page = await this.repository.getNotificationsPage(category);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.replaceCategoryData(category, page);
      this.phase = this.currentItems().length === 0 ? NotificationPhase.EMPTY : NotificationPhase.READY;
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

  private async refreshUnreadCounts(generation: number): Promise<void> {
    try {
      const counts = await this.repository.getUnreadCounts();
      if (!this.isCurrent(generation)) {
        return;
      }
      this.categoryUnread = cloneCategoryUnread(counts);
      this.unreadTotal = notificationUnreadTotal(counts);
      this.emit();
    } catch (_error) {
      // 未读数获取失败不阻断列表加载
    }
  }

  private mergePage(page: NotificationPage): void {
    const category = this.selectedCategory;
    const current = this.categoryData.get(category) ?? [];
    const merged = mergeNotifications(current, page.items);
    this.categoryData.set(category, merged);
    this.applyPaging(category, page);
  }

  private replaceCategoryData(category: NotificationCategory, page: NotificationPage): void {
    this.categoryData.set(category, mergeNotifications([], page.items));
    this.applyPaging(category, page);
  }

  private applyPaging(category: NotificationCategory, page: NotificationPage): void {
    this.categoryPaging.set(category, {
      nextCursor: page.cursor.next,
      reachedEnd: page.cursor.isEnd
    });
    this.paginationBlocked = false;
  }

  private currentItems(): Array<NotificationItem> {
    return this.categoryData.get(this.selectedCategory) ?? [];
  }

  private paging(): CategoryPaging {
    return this.categoryPaging.get(this.selectedCategory) ?? emptyPaging();
  }

  private hasNext(): boolean {
    const paging = this.paging();
    return !paging.reachedEnd && paging.nextCursor !== undefined && paging.nextCursor.length > 0;
  }

  private markAllItemsReadLocally(): void {
    NOTIFICATION_CATEGORY_ORDER.forEach((category: NotificationCategory): void => {
      const current = this.categoryData.get(category);
      if (current === undefined) {
        return;
      }
      const updated: Array<NotificationItem> = [];
      current.forEach((item: NotificationItem): void => {
        updated.push(item.isRead ? item : withReadFlag(item, true));
      });
      this.categoryData.set(category, updated);
    });
  }

  private snapshotCategoryData(): Map<NotificationCategory, Array<NotificationItem>> {
    const snapshot: Map<NotificationCategory, Array<NotificationItem>> = new Map();
    NOTIFICATION_CATEGORY_ORDER.forEach((category: NotificationCategory): void => {
      const current = this.categoryData.get(category);
      if (current !== undefined) {
        snapshot.set(category, current.map((item: NotificationItem): NotificationItem => cloneNotification(item)));
      }
    });
    return snapshot;
  }

  private restoreCategoryData(snapshot: Map<NotificationCategory, Array<NotificationItem>>): void {
    NOTIFICATION_CATEGORY_ORDER.forEach((category: NotificationCategory): void => {
      const restored = snapshot.get(category);
      if (restored !== undefined) {
        this.categoryData.set(category, restored);
      }
    });
  }

  private setFailure(error: Object, more: boolean): void {
    const authentication = error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION;
    this.requiresLogin = authentication && (error.status === undefined || error.status === 401);
    this.errorMessage = authentication && error.status === 403
      ? '请求被拒绝，可能需要完成知乎风控验证'
      : this.requiresLogin
        ? '通知需要登录，请登录后重试'
        : more ? '加载更多失败，请重试' : '通知加载失败，请检查网络后重试';
    this.paginationBlocked = more;
    this.retryLoadMore = more;
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

export const NOTIFICATION_CATEGORY_ORDER: Array<NotificationCategory> = [
  NotificationCategory.DEFAULT,
  NotificationCategory.FOLLOW,
  NotificationCategory.VOTE_THANK
];

export function mergeNotifications(current: Array<NotificationItem>, incoming: Array<NotificationItem>):
  Array<NotificationItem> {
  const result: Array<NotificationItem> = [];
  const seen: Set<string> = new Set<string>();
  current.concat(incoming).forEach((item: NotificationItem): void => {
    const identity = notificationItemIdentity(item);
    if (!seen.has(identity)) {
      seen.add(identity);
      result.push(item);
    }
  });
  return result;
}

function cloneNotification(item: NotificationItem): NotificationItem {
  return {
    id: item.id,
    category: item.category,
    isRead: item.isRead,
    createTime: item.createTime,
    mergeCount: item.mergeCount,
    verb: item.verb,
    actors: item.actors.slice(),
    contentText: item.contentText,
    contentLink: item.contentLink,
    extendText: item.extendText,
    target: item.target === undefined ? undefined : {
      kind: item.target.kind,
      id: item.target.id,
      title: item.target.title,
      url: item.target.url
    }
  };
}

function withReadFlag(item: NotificationItem, isRead: boolean): NotificationItem {
  return {
    id: item.id,
    category: item.category,
    isRead: isRead,
    createTime: item.createTime,
    mergeCount: item.mergeCount,
    verb: item.verb,
    actors: item.actors.slice(),
    contentText: item.contentText,
    contentLink: item.contentLink,
    extendText: item.extendText,
    target: item.target === undefined ? undefined : {
      kind: item.target.kind,
      id: item.target.id,
      title: item.target.title,
      url: item.target.url
    }
  };
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
