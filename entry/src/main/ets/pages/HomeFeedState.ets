import { feedItemIdentity, FeedItem, FeedPage, FeedRepository } from 'data';

export enum HomeFeedPhase {
  IDLE = 'idle',
  INITIAL_LOADING = 'initial_loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface HomeFeedViewState {
  readonly phase: HomeFeedPhase;
  readonly items: Array<FeedItem>;
  readonly refreshing: boolean;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly errorMessage?: string;
}

export type HomeFeedStateObserver = (state: HomeFeedViewState) => void;

export class HomeFeedController {
  private readonly repository: FeedRepository;
  private readonly observer: HomeFeedStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: HomeFeedPhase = HomeFeedPhase.IDLE;
  private items: Array<FeedItem> = [];
  private refreshing: boolean = false;
  private loadingMore: boolean = false;
  private nextCursor: string | undefined = undefined;
  private reachedEnd: boolean = false;
  private errorMessage: string | undefined = undefined;
  private retryLoadMore: boolean = false;
  private paginationRetryRequired: boolean = false;

  constructor(repository: FeedRepository, observer: HomeFeedStateObserver = (_state: HomeFeedViewState): void => {
  }) {
    this.repository = repository;
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.refreshing = false;
    this.loadingMore = false;
    this.phase = this.items.length > 0 ? HomeFeedPhase.READY : HomeFeedPhase.IDLE;
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.refreshing = false;
    this.loadingMore = false;
    this.repository.cancel();
  }

  snapshot(): HomeFeedViewState {
    return {
      phase: this.phase,
      items: this.items.slice(),
      refreshing: this.refreshing,
      loadingMore: this.loadingMore,
      canLoadMore: this.canLoadMore(),
      errorMessage: this.errorMessage
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active || this.phase !== HomeFeedPhase.IDLE) {
      return Promise.resolve();
    }
    return this.loadFirstPage(false);
  }

  refresh(): Promise<void> {
    if (!this.active || this.refreshing || this.loadingMore || this.phase === HomeFeedPhase.INITIAL_LOADING) {
      return Promise.resolve();
    }
    return this.loadFirstPage(this.items.length > 0);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.paginationRetryRequired = false;
      return this.loadMore();
    }
    return this.refresh();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.refreshing || this.loadingMore || !this.canLoadMore()) {
      return;
    }
    const generation = this.generation;
    const cursor = this.nextCursor;
    if (cursor === undefined) {
      return;
    }
    this.loadingMore = true;
    this.errorMessage = undefined;
    this.retryLoadMore = false;
    this.paginationRetryRequired = false;
    this.emit();
    try {
      const page = await this.repository.loadHomePage(cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeUniqueFeedItems(this.items, page.items);
      this.applyCursor(page);
      this.phase = this.items.length > 0 ? HomeFeedPhase.READY : HomeFeedPhase.EMPTY;
      this.retryLoadMore = this.items.length === 0 && this.hasNextPage();
      this.paginationRetryRequired = false;
    } catch (_error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.errorMessage = '加载更多失败，请重试';
      this.phase = this.items.length > 0 ? HomeFeedPhase.READY : HomeFeedPhase.ERROR;
      this.retryLoadMore = true;
      this.paginationRetryRequired = true;
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
    this.errorMessage = undefined;
    this.retryLoadMore = false;
    this.paginationRetryRequired = false;
    if (!keepVisibleItems) {
      this.phase = HomeFeedPhase.INITIAL_LOADING;
    }
    this.emit();
    try {
      const page = await this.repository.loadHomePage();
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeUniqueFeedItems([], page.items);
      this.applyCursor(page);
      this.phase = this.items.length > 0 ? HomeFeedPhase.READY : HomeFeedPhase.EMPTY;
      this.retryLoadMore = this.items.length === 0 && this.hasNextPage();
      this.paginationRetryRequired = false;
    } catch (_error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.errorMessage = '首页加载失败，请检查网络后重试';
      this.phase = this.items.length > 0 ? HomeFeedPhase.READY : HomeFeedPhase.ERROR;
      this.retryLoadMore = false;
    } finally {
      if (this.isCurrent(generation)) {
        this.refreshing = false;
        this.emit();
      }
    }
  }

  private applyCursor(page: FeedPage): void {
    this.nextCursor = page.cursor.next;
    this.reachedEnd = page.cursor.isEnd;
  }

  private canLoadMore(): boolean {
    return !this.paginationRetryRequired && this.hasNextPage();
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

export function mergeUniqueFeedItems(current: Array<FeedItem>, incoming: Array<FeedItem>): Array<FeedItem> {
  const merged: Array<FeedItem> = [];
  const identities: Set<string> = new Set();
  current.concat(incoming).forEach((item: FeedItem): void => {
    const identity = feedItemIdentity(item);
    if (!identities.has(identity)) {
      identities.add(identity);
      merged.push(item);
    }
  });
  return merged;
}
