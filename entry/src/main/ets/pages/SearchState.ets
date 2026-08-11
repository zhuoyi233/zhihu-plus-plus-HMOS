import {
  HttpFailure,
  HttpFailureKind,
  SearchRepository,
  SearchResultItem,
  SearchResultPage,
  searchResultIdentity
} from 'data';

export enum SearchPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface SearchViewState {
  readonly phase: SearchPhase;
  readonly query: string;
  readonly items: Array<SearchResultItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly errorMessage?: string;
}

export type SearchStateObserver = (state: SearchViewState) => void;

export class SearchController {
  private readonly repository: SearchRepository;
  private readonly observer: SearchStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: SearchPhase = SearchPhase.IDLE;
  private query: string = '';
  private items: Array<SearchResultItem> = [];
  private loadingMore: boolean = false;
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private retryLoadMore: boolean = false;
  private paginationBlocked: boolean = false;
  private requiresLogin: boolean = false;
  private restartFirstPageOnActivate: boolean = false;
  private errorMessage?: string;

  constructor(repository: SearchRepository, observer: SearchStateObserver = (_state: SearchViewState): void => {
  }) {
    this.repository = repository;
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    if (this.restartFirstPageOnActivate && this.query.length > 0) {
      this.restartFirstPageOnActivate = false;
      this.submit(this.query);
      return;
    }
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.restartFirstPageOnActivate = this.phase === SearchPhase.LOADING && this.query.length > 0;
    this.active = false;
    this.generation += 1;
    this.loadingMore = false;
    this.repository.cancel();
  }

  snapshot(): SearchViewState {
    return {
      phase: this.phase,
      query: this.query,
      items: this.items.slice(),
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && this.hasNextPage(),
      requiresLogin: this.requiresLogin,
      errorMessage: this.errorMessage
    };
  }

  submit(rawQuery: string): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    const query = rawQuery.trim();
    this.repository.cancel();
    const generation = ++this.generation;
    this.query = query;
    this.items = [];
    this.loadingMore = false;
    this.nextCursor = undefined;
    this.reachedEnd = true;
    this.retryLoadMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    if (query.length === 0) {
      this.phase = SearchPhase.IDLE;
      this.emit();
      return Promise.resolve();
    }
    this.phase = SearchPhase.LOADING;
    this.emit();
    return this.loadFirstPage(query, generation);
  }

  refresh(): Promise<void> {
    if (!this.active || this.phase === SearchPhase.LOADING || this.loadingMore || this.query.length === 0) {
      return Promise.resolve();
    }
    return this.submit(this.query);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.paginationBlocked = false;
      return this.loadMore();
    }
    return this.refresh();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === SearchPhase.LOADING || this.loadingMore ||
      this.paginationBlocked || !this.hasNextPage()) {
      return;
    }
    const generation = this.generation;
    const cursor = this.nextCursor as string;
    this.loadingMore = true;
    this.retryLoadMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    try {
      const page = await this.repository.search(this.query, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeSearchResults(this.items, page.items);
      this.applyCursor(page);
      this.phase = this.items.length > 0 ? SearchPhase.READY : SearchPhase.EMPTY;
      this.retryLoadMore = this.items.length === 0 && this.hasNextPage();
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      let authenticationStatus: number | undefined = undefined;
      let authenticationFailure: boolean = false;
      if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
        authenticationFailure = true;
        authenticationStatus = error.status;
      }
      this.requiresLogin = authenticationFailure &&
        (authenticationStatus === undefined || authenticationStatus === 401);
      this.errorMessage = authenticationFailure && authenticationStatus === 403
        ? '请求被拒绝，可能需要稍后重试或完成风控'
        : this.requiresLogin
          ? '登录状态已失效，请重新登录后重试'
          : '加载更多搜索结果失败，请重试';
      this.phase = this.items.length > 0 ? SearchPhase.READY : SearchPhase.ERROR;
      this.retryLoadMore = true;
      this.paginationBlocked = true;
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  private async loadFirstPage(query: string, generation: number): Promise<void> {
    try {
      const page = await this.repository.search(query);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeSearchResults([], page.items);
      this.applyCursor(page);
      this.phase = this.items.length > 0 ? SearchPhase.READY : SearchPhase.EMPTY;
      this.retryLoadMore = this.items.length === 0 && this.hasNextPage();
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = SearchPhase.ERROR;
      let authenticationStatus: number | undefined = undefined;
      let authenticationFailure: boolean = false;
      if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
        authenticationFailure = true;
        authenticationStatus = error.status;
      }
      this.requiresLogin = authenticationFailure &&
        (authenticationStatus === undefined || authenticationStatus === 401);
      this.errorMessage = authenticationFailure && authenticationStatus === 403
        ? '请求被拒绝，可能需要稍后重试或完成风控'
        : this.requiresLogin
          ? '搜索需要登录，请登录后重试'
          : '搜索失败，请检查网络后重试';
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private applyCursor(page: SearchResultPage): void {
    this.nextCursor = page.cursor.next;
    this.reachedEnd = page.cursor.isEnd;
    this.paginationBlocked = false;
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

export function mergeSearchResults(current: Array<SearchResultItem>, incoming: Array<SearchResultItem>):
  Array<SearchResultItem> {
  const merged: Array<SearchResultItem> = [];
  const identities: Set<string> = new Set<string>();
  current.concat(incoming).forEach((item: SearchResultItem): void => {
    const identity = searchResultIdentity(item);
    if (!identities.has(identity)) {
      identities.add(identity);
      merged.push(item);
    }
  });
  return merged;
}
