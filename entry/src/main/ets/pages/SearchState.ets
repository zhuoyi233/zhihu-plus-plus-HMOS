import {
  HttpFailure,
  HttpFailureKind,
  SearchDecodeError,
  SearchDecodeFailureKind,
  SearchEntity,
  SearchFilters,
  searchEntityIdentity,
  SearchRepository,
  SearchResultPage,
  SearchSortOption,
  SearchTab,
  SearchTimeRange
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
  readonly entities: Array<SearchEntity>;
  readonly activeTab: SearchTab;
  readonly sort: SearchSortOption;
  readonly timeRange: SearchTimeRange;
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
  private entities: Array<SearchEntity> = [];
  private tab: SearchTab = SearchTab.GENERAL;
  private filters: SearchFilters = { sort: SearchSortOption.DEFAULT, timeRange: SearchTimeRange.ALL };
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
      // 绕过 reload 的 LOADING 守卫：失活时被中断的首页请求在复活时原样重启（对齐上游）。
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
      entities: this.entities.slice(),
      activeTab: this.tab,
      sort: this.filters.sort,
      timeRange: this.filters.timeRange,
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
    this.generation += 1;
    this.query = query;
    // 新搜索回到综合 tab（对齐上游每次搜索新建 ViewModel 的行为），筛选保留本页会话选择。
    this.tab = SearchTab.GENERAL;
    return this.resetForReload(query.length > 0);
  }

  selectTab(tab: SearchTab): Promise<void> {
    if (!this.active || tab === this.tab || this.query.length === 0) {
      return Promise.resolve();
    }
    this.repository.cancel();
    this.generation += 1;
    this.tab = tab;
    return this.resetForReload(true);
  }

  updateFilters(sort: SearchSortOption, timeRange: SearchTimeRange): Promise<void> {
    if (!this.active || this.query.length === 0 ||
      (sort === this.filters.sort && timeRange === this.filters.timeRange)) {
      return Promise.resolve();
    }
    this.repository.cancel();
    this.generation += 1;
    this.filters = { sort: sort, timeRange: timeRange };
    return this.resetForReload(true);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.paginationBlocked = false;
      return this.loadMore();
    }
    return this.reload();
  }

  private resetForReload(loading: boolean): Promise<void> {
    this.entities = [];
    this.loadingMore = false;
    this.nextCursor = undefined;
    this.reachedEnd = true;
    this.retryLoadMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    if (!loading) {
      this.phase = SearchPhase.IDLE;
      this.emit();
      return Promise.resolve();
    }
    this.phase = SearchPhase.LOADING;
    this.emit();
    return this.loadFirstPage(this.query, this.generation);
  }

  private reload(): Promise<void> {
    if (!this.active || this.phase === SearchPhase.LOADING || this.loadingMore ||
      this.query.length === 0) {
      return Promise.resolve();
    }
    this.repository.cancel();
    this.generation += 1;
    return this.resetForReload(true);
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === SearchPhase.LOADING || this.loadingMore ||
      this.paginationBlocked || !this.hasNextPage()) {
      return;
    }
    const generation = this.generation;
    const cursor = this.nextCursor;
    if (cursor === undefined) {
      return;
    }
    this.loadingMore = true;
    this.retryLoadMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    try {
      const page = await this.repository.search(this.query, this.filters, this.tab, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.entities = mergeSearchEntities(this.entities, page.entities);
      this.applyCursor(page);
      this.phase = this.entities.length > 0 ? SearchPhase.READY : SearchPhase.EMPTY;
      this.retryLoadMore = this.entities.length === 0 && this.hasNextPage();
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyLoadFailure(error as Object, true);
      this.phase = this.entities.length > 0 ? SearchPhase.READY : SearchPhase.ERROR;
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
      const page = await this.repository.search(query, this.filters, this.tab);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.entities = mergeSearchEntities([], page.entities);
      this.applyCursor(page);
      this.phase = this.entities.length > 0 ? SearchPhase.READY : SearchPhase.EMPTY;
      this.retryLoadMore = this.entities.length === 0 && this.hasNextPage();
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = SearchPhase.ERROR;
      this.applyLoadFailure(error as Object, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private applyLoadFailure(error: Object, loadingMore: boolean): void {
    let authenticationStatus: number | undefined = undefined;
    let authenticationFailure: boolean = false;
    if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
      authenticationFailure = true;
      authenticationStatus = error.status;
    }
    this.requiresLogin = authenticationFailure &&
      (authenticationStatus === undefined || authenticationStatus === 401);
    this.errorMessage = searchErrorMessage(error, this.requiresLogin, authenticationStatus, loadingMore);
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

function searchErrorMessage(error: Object, requiresLogin: boolean, authenticationStatus: number | undefined,
  loadingMore: boolean): string {
  const action = loadingMore ? '加载更多搜索结果' : '搜索';
  if (authenticationStatus === 403) {
    return '请求被拒绝，可能需要稍后重试或完成风控';
  }
  if (requiresLogin) {
    return loadingMore ? '登录状态已失效，请重新登录后重试' : '搜索需要登录，请登录后重试';
  }
  if (error instanceof SearchDecodeError) {
    return error.kind === SearchDecodeFailureKind.UPSTREAM_ERROR
      ? '知乎搜索服务返回了错误，请稍后重试'
      : '知乎搜索服务返回了无法解析的响应，请稍后重试';
  }
  if (error instanceof HttpFailure) {
    if (error.kind === HttpFailureKind.RATE_LIMITED) {
      return '搜索请求过于频繁，请稍后重试';
    }
    if (error.kind === HttpFailureKind.SERVER) {
      return '知乎搜索服务暂时不可用，请稍后重试';
    }
    if (error.kind === HttpFailureKind.TIMEOUT) {
      return '搜索请求超时，请稍后重试';
    }
    if (error.kind === HttpFailureKind.CLIENT) {
      return '知乎拒绝了搜索请求，请稍后重试或完成风控';
    }
  }
  return `${action}失败，请检查网络后重试`;
}

export function mergeSearchEntities(current: Array<SearchEntity>, incoming: Array<SearchEntity>):
  Array<SearchEntity> {
  const merged: Array<SearchEntity> = [];
  const identities: Set<string> = new Set<string>();
  current.concat(incoming).forEach((entity: SearchEntity): void => {
    const identity = searchEntityIdentity(entity);
    if (!identities.has(identity)) {
      identities.add(identity);
      merged.push(entity);
    }
  });
  return merged;
}
