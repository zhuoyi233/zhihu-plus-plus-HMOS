import {
  CollectionContentItem,
  CollectionContentPage,
  CollectionRepository,
  CollectionSummary,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionStatus
} from 'data';

export enum CollectionContentPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface CollectionContentViewState {
  readonly phase: CollectionContentPhase;
  readonly collection?: CollectionSummary;
  readonly items: Array<CollectionContentItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly errorMessage?: string;
}

export type CollectionContentStateObserver = (state: CollectionContentViewState) => void;

export class CollectionContentController {
  private readonly collectionId: string;
  private readonly repository: CollectionRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: CollectionContentStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: CollectionContentPhase = CollectionContentPhase.IDLE;
  private collection?: CollectionSummary;
  private items: Array<CollectionContentItem> = [];
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private retryLoadMore: boolean = false;
  private requiresLogin: boolean = false;
  private errorMessage?: string;

  constructor(collectionId: string, repository: CollectionRepository, session: LoginSessionGateway,
    observer: CollectionContentStateObserver = (_state: CollectionContentViewState): void => {
    }) {
    this.collectionId = collectionId;
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

  snapshot(): CollectionContentViewState {
    return {
      phase: this.phase,
      collection: this.collection === undefined ? undefined : cloneCollection(this.collection),
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
    this.phase = CollectionContentPhase.LOADING;
    this.collection = undefined;
    this.items = [];
    this.nextCursor = undefined;
    this.reachedEnd = true;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.retryLoadMore = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = CollectionContentPhase.ERROR;
      this.errorMessage = '收藏夹需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
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
    if (!this.active || this.phase === CollectionContentPhase.LOADING || this.loadingMore ||
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
      const page = await this.repository.getCollectionItemsPage(this.collectionId, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeCollectionItems(this.items, page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? CollectionContentPhase.EMPTY : CollectionContentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = this.items.length === 0 ? CollectionContentPhase.ERROR : CollectionContentPhase.READY;
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
      const detail = await this.repository.getCollection(this.collectionId);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.collection = detail;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = CollectionContentPhase.ERROR;
      this.setFailure(error, false);
      this.emit();
      return;
    }
    try {
      const page = await this.repository.getCollectionItemsPage(this.collectionId);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeCollectionItems([], page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? CollectionContentPhase.EMPTY : CollectionContentPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = this.items.length === 0 ? CollectionContentPhase.ERROR : CollectionContentPhase.READY;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private applyPage(page: CollectionContentPage): void {
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
        ? '收藏夹需要登录，请登录后重试'
        : more ? '加载更多失败，请重试' : '收藏夹内容加载失败，请检查网络后重试';
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

export function mergeCollectionItems(current: Array<CollectionContentItem>, incoming: Array<CollectionContentItem>):
  Array<CollectionContentItem> {
  const result: Array<CollectionContentItem> = [];
  const seen: Set<string> = new Set<string>();
  current.concat(incoming).forEach((item: CollectionContentItem): void => {
    const identity = `${item.kind}:${item.id}`;
    if (!seen.has(identity)) {
      seen.add(identity);
      result.push(item);
    }
  });
  return result;
}

function cloneCollection(collection: CollectionSummary): CollectionSummary {
  return {
    id: collection.id,
    title: collection.title,
    description: collection.description,
    isPublic: collection.isPublic,
    answerCount: collection.answerCount,
    followerCount: collection.followerCount,
    itemCount: collection.itemCount,
    likeCount: collection.likeCount,
    commentCount: collection.commentCount,
    isFavorited: collection.isFavorited,
    updatedAt: collection.updatedAt,
    creatorName: collection.creatorName
  };
}
