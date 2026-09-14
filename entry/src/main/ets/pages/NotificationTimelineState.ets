import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  MobileNotificationRepository,
  MobileNotificationTimelineItem,
  MobileNotificationTimelinePage,
  NotificationPreferences,
  SessionStatus,
  shouldShowMobileNotification
} from 'data';

export enum NotificationTimelinePhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface NotificationTimelineViewState {
  readonly phase: NotificationTimelinePhase;
  readonly items: Array<MobileNotificationTimelineItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly errorMessage?: string;
}

export type NotificationTimelineStateObserver = (state: NotificationTimelineViewState) => void;

/**
 * 分类/邀请回答时间线控制器（对齐上游 `NotificationTimelineViewModel`）：
 * 首次加载成功后按设置自动 POST readall；按显示开关过滤通知动词。
 */
export class NotificationTimelineController {
  private readonly repository: MobileNotificationRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: NotificationTimelineStateObserver;
  private readonly entryName: string;
  private active: boolean = false;
  private generation: number = 0;
  private phase: NotificationTimelinePhase = NotificationTimelinePhase.IDLE;
  private items: Array<MobileNotificationTimelineItem> = [];
  private allItems: Array<MobileNotificationTimelineItem> = [];
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private requiresLogin: boolean = false;
  private markedAsRead: boolean = false;
  private preferences?: NotificationPreferences;
  private errorMessage?: string;

  constructor(entryName: string, repository: MobileNotificationRepository,
    session: LoginSessionGateway, observer: NotificationTimelineStateObserver = (_state:
      NotificationTimelineViewState): void => {
    }) {
    this.entryName = entryName;
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

  snapshot(): NotificationTimelineViewState {
    return {
      phase: this.phase,
      items: this.items.slice(),
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && !this.reachedEnd && this.nextCursor !== undefined,
      requiresLogin: this.requiresLogin,
      errorMessage: this.errorMessage
    };
  }

  setPreferences(preferences: NotificationPreferences): void {
    this.preferences = preferences;
    this.applyFilter();
    this.emit();
  }

  loadInitial(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = NotificationTimelinePhase.LOADING;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = NotificationTimelinePhase.ERROR;
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
    if (!this.active || this.phase === NotificationTimelinePhase.LOADING || this.loadingMore ||
      this.paginationBlocked || this.reachedEnd || this.nextCursor === undefined) {
      return;
    }
    const generation = this.generation;
    const cursor = this.nextCursor;
    this.loadingMore = true;
    this.emit();
    try {
      await this.fetchPage(generation, cursor);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      if (this.allItems.length === 0) {
        this.phase = NotificationTimelinePhase.ERROR;
      }
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  private async fetchPage(generation: number, cursor?: string): Promise<void> {
    try {
      const page: MobileNotificationTimelinePage = await this.repository.getTimelinePage(this.entryName, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      const existing: Set<string> = new Set<string>();
      this.allItems.forEach((item: MobileNotificationTimelineItem): void => {
        existing.add(item.uniqueId.length > 0 ? item.uniqueId : item.id);
      });
      page.items.forEach((item: MobileNotificationTimelineItem): void => {
        const id = item.uniqueId.length > 0 ? item.uniqueId : item.id;
        if (!existing.has(id)) {
          existing.add(id);
          this.allItems.push(item);
        }
      });
      this.nextCursor = page.cursor.next;
      this.reachedEnd = page.cursor.isEnd || page.cursor.next === undefined;
      this.paginationBlocked = false;
      this.applyFilter();
      this.phase = this.items.length === 0 && this.allItems.length === 0
        ? NotificationTimelinePhase.EMPTY
        : NotificationTimelinePhase.READY;
      if (!this.markedAsRead && this.preferences !== undefined && this.preferences.autoMarkAsRead) {
        this.markedAsRead = true;
        try {
          await this.repository.markEntryAsRead(this.entryName);
        } catch (_error) {
          // 自动已读失败不阻断列表展示
        }
      }
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = NotificationTimelinePhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  /** 应用内显示过滤（对齐上游 `shouldShowNotification`）。 */
  private applyFilter(): void {
    const preferences = this.preferences;
    if (preferences === undefined) {
      this.items = this.allItems.slice();
      return;
    }
    this.items = this.allItems.filter((item: MobileNotificationTimelineItem): boolean =>
      shouldShowMobileNotification(item, preferences));
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
