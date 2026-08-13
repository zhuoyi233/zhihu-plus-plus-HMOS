import {
  HttpFailure,
  HttpFailureKind,
  peopleContentIdentity,
  PeopleContentItem,
  PeopleContentPage,
  PeopleContentRepository,
  PeopleContentSection
} from 'data';

export enum PeopleContentPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface PeopleContentViewState {
  readonly phase: PeopleContentPhase;
  readonly section: PeopleContentSection;
  readonly items: Array<PeopleContentItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly errorMessage?: string;
}

export type PeopleContentObserver = (state: PeopleContentViewState) => void;

export class PeopleContentController {
  private readonly identifier: string;
  private readonly section: PeopleContentSection;
  private readonly repository: PeopleContentRepository;
  private readonly observer: PeopleContentObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: PeopleContentPhase = PeopleContentPhase.IDLE;
  private items: Array<PeopleContentItem> = [];
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private retryLoadMore: boolean = false;
  private requiresLogin: boolean = false;
  private errorMessage?: string;

  constructor(identifier: string, section: PeopleContentSection, repository: PeopleContentRepository,
    observer: PeopleContentObserver = (_state: PeopleContentViewState): void => {
    }) {
    this.identifier = identifier;
    this.section = section;
    this.repository = repository;
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

  snapshot(): PeopleContentViewState {
    return {
      phase: this.phase,
      section: this.section,
      items: this.items.slice(),
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && this.hasNext(),
      requiresLogin: this.requiresLogin,
      errorMessage: this.errorMessage
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = PeopleContentPhase.LOADING;
    this.items = [];
    this.nextCursor = undefined;
    this.reachedEnd = true;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.retryLoadMore = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    return this.loadFirst(generation);
  }

  retry(): Promise<void> {
    if (this.retryLoadMore) {
      this.paginationBlocked = false;
      return this.loadMore();
    }
    return this.loadInitial();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === PeopleContentPhase.LOADING || this.loadingMore ||
      this.paginationBlocked || !this.hasNext()) {
      return;
    }
    const cursor = this.nextCursor;
    if (cursor === undefined) {
      return;
    }
    const generation = this.generation;
    this.loadingMore = true;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.retryLoadMore = false;
    this.emit();
    try {
      const page = await this.repository.getContentPage(this.identifier, this.section, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergePeopleContent(this.items, page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? PeopleContentPhase.EMPTY : PeopleContentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = this.items.length === 0 ? PeopleContentPhase.ERROR : PeopleContentPhase.READY;
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  private async loadFirst(generation: number): Promise<void> {
    try {
      const page = await this.repository.getContentPage(this.identifier, this.section);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergePeopleContent([], page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? PeopleContentPhase.EMPTY : PeopleContentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = PeopleContentPhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private applyPage(page: PeopleContentPage): void {
    this.nextCursor = page.cursor.next;
    this.reachedEnd = page.cursor.isEnd;
    this.paginationBlocked = false;
  }

  private setFailure(error: Object, more: boolean): void {
    const authentication = error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION;
    this.requiresLogin = authentication && (error.status === undefined || error.status === 401);
    this.errorMessage = authentication && error.status === 403
      ? '请求被拒绝，可能需要完成知乎风控验证'
      : this.requiresLogin
        ? '用户内容需要登录，请登录后重试'
        : more ? '加载更多失败，请重试' : '用户内容加载失败，请检查网络后重试';
    this.paginationBlocked = more;
    this.retryLoadMore = more;
  }

  private hasNext(): boolean {
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

export function mergePeopleContent(current: Array<PeopleContentItem>, incoming: Array<PeopleContentItem>):
  Array<PeopleContentItem> {
  const result: Array<PeopleContentItem> = [];
  const seen: Set<string> = new Set<string>();
  current.concat(incoming).forEach((item: PeopleContentItem): void => {
    const identity = peopleContentIdentity(item);
    if (!seen.has(identity)) {
      seen.add(identity);
      result.push(item);
    }
  });
  return result;
}
