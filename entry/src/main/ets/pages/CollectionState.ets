import {
  collectionIdentity,
  CollectionPage,
  CollectionRepository,
  CollectionRepositoryFailure,
  CollectionRepositoryFailureKind,
  CollectionSummary,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionStatus
} from 'data';

export enum CollectionPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface CollectionViewState {
  readonly phase: CollectionPhase;
  readonly items: Array<CollectionSummary>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly busy: boolean;
  readonly errorMessage?: string;
}

export type CollectionStateObserver = (state: CollectionViewState) => void;

export class CollectionController {
  private readonly identifier: string;
  private readonly repository: CollectionRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: CollectionStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: CollectionPhase = CollectionPhase.IDLE;
  private items: Array<CollectionSummary> = [];
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private retryLoadMore: boolean = false;
  private requiresLogin: boolean = false;
  private busy: boolean = false;
  private errorMessage?: string;

  constructor(identifier: string, repository: CollectionRepository, session: LoginSessionGateway,
    observer: CollectionStateObserver = (_state: CollectionViewState): void => {
    }) {
    this.identifier = identifier;
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

  snapshot(): CollectionViewState {
    return {
      phase: this.phase,
      items: this.items.slice(),
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && this.hasNext(),
      requiresLogin: this.requiresLogin,
      busy: this.busy,
      errorMessage: this.errorMessage
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = CollectionPhase.LOADING;
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
      this.phase = CollectionPhase.ERROR;
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
    if (!this.active || this.phase === CollectionPhase.LOADING || this.loadingMore ||
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
      const page = await this.repository.getCollectionsPage(this.identifier, cursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeCollections(this.items, page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? CollectionPhase.EMPTY : CollectionPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = this.items.length === 0 ? CollectionPhase.ERROR : CollectionPhase.READY;
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  async createCollection(title: string, description: string, isPublic: boolean): Promise<boolean> {
    if (!this.active || this.busy) {
      return false;
    }
    const trimmedTitle = title.trim();
    if (trimmedTitle.length === 0) {
      this.errorMessage = '收藏夹名称不能为空';
      this.emit();
      return false;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = '创建收藏夹需要登录，请登录后重试';
      this.emit();
      return false;
    }
    const generation = this.generation;
    this.busy = true;
    this.errorMessage = undefined;
    this.emit();
    try {
      await this.repository.createCollection(trimmedTitle, description, isPublic);
      if (!this.isCurrent(generation)) {
        return false;
      }
      await this.reloadAfterMutation(generation);
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.errorMessage = collectionMutationError(error, '创建收藏夹失败，请重试');
        this.requiresLogin = collectionMutationRequiresLogin(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.busy = false;
        this.emit();
      }
    }
  }

  async deleteCollection(collectionId: string): Promise<boolean> {
    if (!this.active || this.busy) {
      return false;
    }
    const target = this.items.find((collection: CollectionSummary): boolean =>
      collection.id === collectionId);
    if (target === undefined) {
      return false;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = '删除收藏夹需要登录，请登录后重试';
      this.emit();
      return false;
    }
    const generation = this.generation;
    this.busy = true;
    this.errorMessage = undefined;
    this.emit();
    const index = this.items.findIndex((collection: CollectionSummary): boolean =>
      collection.id === collectionId);
    this.items = this.items.filter((collection: CollectionSummary): boolean =>
      collection.id !== collectionId);
    if (this.items.length === 0 && this.phase === CollectionPhase.READY) {
      this.phase = CollectionPhase.EMPTY;
    }
    this.emit();
    try {
      await this.repository.deleteCollection(collectionId);
      if (!this.isCurrent(generation)) {
        return false;
      }
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.items = insertCollectionAt(this.items, target, index);
        if (this.phase === CollectionPhase.EMPTY) {
          this.phase = CollectionPhase.READY;
        }
        this.errorMessage = collectionMutationError(error, '删除收藏夹失败，请重试');
        this.requiresLogin = collectionMutationRequiresLogin(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.busy = false;
        this.emit();
      }
    }
  }

  private async loadFirst(generation: number): Promise<void> {
    try {
      const page = await this.repository.getCollectionsPage(this.identifier);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeCollections([], page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? CollectionPhase.EMPTY : CollectionPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = CollectionPhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private async reloadAfterMutation(generation: number): Promise<void> {
    this.phase = CollectionPhase.LOADING;
    this.items = [];
    this.nextCursor = undefined;
    this.reachedEnd = true;
    this.paginationBlocked = false;
    this.retryLoadMore = false;
    this.emit();
    try {
      const page = await this.repository.getCollectionsPage(this.identifier);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.items = mergeCollections([], page.items);
      this.applyPage(page);
      this.phase = this.items.length === 0 ? CollectionPhase.EMPTY : CollectionPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = CollectionPhase.ERROR;
      this.setFailure(error, false);
    }
  }

  private applyPage(page: CollectionPage): void {
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
        : more ? '加载更多失败，请重试' : '收藏夹加载失败，请检查网络后重试';
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

export function mergeCollections(current: Array<CollectionSummary>, incoming: Array<CollectionSummary>):
  Array<CollectionSummary> {
  const result: Array<CollectionSummary> = [];
  const seen: Set<string> = new Set<string>();
  current.concat(incoming).forEach((collection: CollectionSummary): void => {
    const identity = collectionIdentity(collection);
    if (!seen.has(identity)) {
      seen.add(identity);
      result.push(collection);
    }
  });
  return result;
}

function insertCollectionAt(items: Array<CollectionSummary>, collection: CollectionSummary, index: number):
  Array<CollectionSummary> {
  const result = items.slice();
  const bounded = Math.max(0, Math.min(index, result.length));
  result.splice(bounded, 0, collection);
  return result;
}

function collectionMutationError(error: Object, fallback: string): string {
  if (error instanceof CollectionRepositoryFailure &&
    error.kind === CollectionRepositoryFailureKind.INVALID_IDENTIFIER) {
    return '收藏夹标识无效，操作未能完成';
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

function collectionMutationRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}
