import {
  channelFeedItemIdentity,
  ChannelFeedItem,
  ChannelFeedPage,
  ChannelFeedRepository,
  ChannelFeedSource,
  HttpFailure,
  HttpFailureKind
} from 'data';

export enum ChannelFeedPhase {
  IDLE = 'idle',
  INITIAL_LOADING = 'initial_loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface ChannelFeedViewState {
  readonly phase: ChannelFeedPhase;
  readonly items: Array<ChannelFeedItem>;
  readonly refreshing: boolean;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly errorMessage?: string;
}

export type ChannelFeedStateObserver = (state: ChannelFeedViewState) => void;

export class ChannelFeedController {
  private readonly source: ChannelFeedSource;
  private readonly repository: ChannelFeedRepository;
  private readonly observer: ChannelFeedStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: ChannelFeedPhase = ChannelFeedPhase.IDLE;
  private items: Array<ChannelFeedItem> = [];
  private refreshing: boolean = false;
  private loadingMore: boolean = false;
  private nextCursor?: string;
  private reachedEnd: boolean = false;
  private paginationBlocked: boolean = false;
  private retryLoadMore: boolean = false;
  private requiresLogin: boolean = false;
  private restartFirstPageOnActivate: boolean = false;
  private errorMessage?: string;

  constructor(source: ChannelFeedSource, repository: ChannelFeedRepository,
    observer: ChannelFeedStateObserver = (_state: ChannelFeedViewState): void => {
    }) {
    this.source = source;
    this.repository = repository;
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    if (this.restartFirstPageOnActivate) {
      this.restartFirstPageOnActivate = false;
      this.phase = this.items.length > 0 ? ChannelFeedPhase.READY : ChannelFeedPhase.IDLE;
      this.refresh();
      return;
    }
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.restartFirstPageOnActivate = this.phase === ChannelFeedPhase.INITIAL_LOADING || this.refreshing;
    this.active = false;
    this.generation += 1;
    this.refreshing = false;
    this.loadingMore = false;
    this.repository.cancel();
  }

  snapshot(): ChannelFeedViewState {
    return {
      phase: this.phase,
      items: this.items.slice(),
      refreshing: this.refreshing,
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && this.hasNextPage(),
      requiresLogin: this.requiresLogin,
      errorMessage: this.errorMessage
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active || this.phase !== ChannelFeedPhase.IDLE) {
      return Promise.resolve();
    }
    return this.loadFirstPage(false);
  }

  refresh(): Promise<void> {
    if (!this.active || this.refreshing || this.loadingMore ||
      this.phase === ChannelFeedPhase.INITIAL_LOADING) {
      return Promise.resolve();
    }
    return this.loadFirstPage(this.items.length > 0);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.paginationBlocked = false;
      return this.loadMore();
    }
    return this.refresh();
  }

  removeItem(identity: string): void {
    if (!this.active) {
      return;
    }
    this.items = this.items.filter((item: ChannelFeedItem): boolean =>
      channelFeedItemIdentity(item) !== identity);
    this.phase = this.items.length > 0 ? ChannelFeedPhase.READY : ChannelFeedPhase.EMPTY;
    this.emit();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.refreshing || this.loadingMore || this.paginationBlocked || !this.hasNextPage()) {
      return;
    }
    const cursor = this.nextCursor;
    if (cursor === undefined) {
      return;
    }
    const generation = this.generation;
    this.loadingMore = true;
    this.retryLoadMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    try {
      const page = await this.repository.loadPage(this.source, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeChannelFeedItems(this.items, page.items);
      this.applyCursor(page);
      this.phase = this.items.length > 0 ? ChannelFeedPhase.READY : ChannelFeedPhase.EMPTY;
      this.retryLoadMore = this.items.length === 0 && this.hasNextPage();
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyFailure(error, true);
      this.phase = this.items.length > 0 ? ChannelFeedPhase.READY : ChannelFeedPhase.ERROR;
      this.retryLoadMore = true;
      this.paginationBlocked = true;
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  private async loadFirstPage(keepVisibleItems: boolean): Promise<void> {
    const generation = ++this.generation;
    this.refreshing = keepVisibleItems;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.retryLoadMore = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    if (!keepVisibleItems) {
      this.phase = ChannelFeedPhase.INITIAL_LOADING;
    }
    this.emit();
    try {
      const page = await this.repository.loadPage(this.source);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeChannelFeedItems([], page.items);
      this.applyCursor(page);
      this.phase = this.items.length > 0 ? ChannelFeedPhase.READY : ChannelFeedPhase.EMPTY;
      this.retryLoadMore = this.items.length === 0 && this.hasNextPage();
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyFailure(error, false);
      this.phase = this.items.length > 0 ? ChannelFeedPhase.READY : ChannelFeedPhase.ERROR;
    } finally {
      if (this.isCurrent(generation)) {
        this.refreshing = false;
        this.emit();
      }
    }
  }

  private applyCursor(page: ChannelFeedPage): void {
    this.nextCursor = page.cursor.next;
    this.reachedEnd = page.cursor.isEnd;
    this.paginationBlocked = false;
  }

  private applyFailure(error: Object, loadingMore: boolean): void {
    let authenticationStatus: number | undefined = undefined;
    let authenticationFailure: boolean = false;
    if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
      authenticationFailure = true;
      authenticationStatus = error.status;
    }
    const sessionRequired = this.source === ChannelFeedSource.FOLLOWING || this.source === ChannelFeedSource.HOT;
    this.requiresLogin = sessionRequired && authenticationFailure &&
      (authenticationStatus === undefined || authenticationStatus === 401);
    if (authenticationFailure && authenticationStatus === 403) {
      this.errorMessage = '请求被拒绝，可能需要稍后重试或完成风控';
    } else if (this.requiresLogin) {
      this.errorMessage = `${channelFeedTitle(this.source)}需要登录，请登录后重试`;
    } else {
      this.errorMessage = loadingMore ? '加载更多失败，请重试' : `${channelFeedTitle(this.source)}加载失败，请检查网络后重试`;
    }
  }

  private hasNextPage(): boolean {
    return !this.reachedEnd && this.nextCursor !== undefined && this.nextCursor.length > 0;
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

export function mergeChannelFeedItems(current: Array<ChannelFeedItem>, incoming: Array<ChannelFeedItem>):
  Array<ChannelFeedItem> {
  const merged: Array<ChannelFeedItem> = [];
  const identities: Set<string> = new Set<string>();
  current.concat(incoming).forEach((item: ChannelFeedItem): void => {
    const identity = channelFeedItemIdentity(item);
    if (!identities.has(identity)) {
      identities.add(identity);
      merged.push(item);
    }
  });
  return merged;
}

export function channelFeedTitle(source: ChannelFeedSource): string {
  switch (source) {
    case ChannelFeedSource.FOLLOWING:
      return '关注';
    case ChannelFeedSource.HOT:
      return '热榜';
    case ChannelFeedSource.DAILY:
      return '日报';
  }
}
