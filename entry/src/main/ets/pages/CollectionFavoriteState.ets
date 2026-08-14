import {
  CollectionRepository,
  CollectionRepositoryFailure,
  CollectionRepositoryFailureKind,
  CollectionSummary,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionStatus
} from 'data';

export enum CollectionFavoritePhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  ERROR = 'error'
}

export interface CollectionFavoriteViewState {
  readonly phase: CollectionFavoritePhase;
  readonly collections: Array<CollectionSummary>;
  readonly busyCollectionId?: string;
  readonly requiresLogin: boolean;
  readonly message?: string;
}

export type CollectionFavoriteObserver = (state: CollectionFavoriteViewState) => void;

export class CollectionFavoriteController {
  private readonly repository: CollectionRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: CollectionFavoriteObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: CollectionFavoritePhase = CollectionFavoritePhase.IDLE;
  private collections: Array<CollectionSummary> = [];
  private busyCollectionId?: string;
  private requiresLogin: boolean = false;
  private message?: string;

  constructor(repository: CollectionRepository, session: LoginSessionGateway,
    observer: CollectionFavoriteObserver = (_state: CollectionFavoriteViewState): void => {
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
    this.repository.cancel();
  }

  snapshot(): CollectionFavoriteViewState {
    return {
      phase: this.phase,
      collections: this.collections.slice(),
      busyCollectionId: this.busyCollectionId,
      requiresLogin: this.requiresLogin,
      message: this.message
    };
  }

  load(contentType: string, contentId: string): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = CollectionFavoritePhase.LOADING;
    this.collections = [];
    this.busyCollectionId = undefined;
    this.requiresLogin = false;
    this.message = undefined;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = CollectionFavoritePhase.ERROR;
      this.message = '收藏需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
    return this.repository.getContentCollections(contentType, contentId).then((collections: Array<CollectionSummary>): void => {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.collections = collections.slice();
      this.phase = CollectionFavoritePhase.READY;
    }).catch((error: Object): void => {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = CollectionFavoritePhase.ERROR;
      this.message = favoriteLoadError(error);
      this.requiresLogin = favoriteRequiresLogin(error);
    }).then((): void => {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    });
  }

  async toggle(collection: CollectionSummary, contentType: string, contentId: string): Promise<boolean> {
    if (!this.active || this.busyCollectionId !== undefined ||
      this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      return false;
    }
    const generation = this.generation;
    const optimistic = !collection.isFavorited;
    this.busyCollectionId = collection.id;
    this.message = undefined;
    this.collections = this.collections.map((candidate: CollectionSummary): CollectionSummary => {
      if (candidate.id !== collection.id) {
        return candidate;
      }
      return cloneCollectionWithFavorite(candidate, optimistic);
    });
    this.emit();
    try {
      if (optimistic) {
        await this.repository.addContentToCollection(collection.id, contentType, contentId);
      } else {
        await this.repository.removeContentFromCollection(collection.id, contentType, contentId);
      }
      if (!this.isCurrent(generation)) {
        return false;
      }
      this.message = optimistic ? '已收藏到「' + collection.title + '」' : '已取消收藏';
      return true;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return false;
      }
      this.collections = this.collections.map((candidate: CollectionSummary): CollectionSummary => {
        if (candidate.id !== collection.id) {
          return candidate;
        }
        return cloneCollectionWithFavorite(candidate, collection.isFavorited);
      });
      this.message = favoriteToggleError(error);
      this.requiresLogin = favoriteRequiresLogin(error);
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.busyCollectionId = undefined;
        this.emit();
      }
    }
  }

  async createAndAdd(title: string, description: string, isPublic: boolean, contentType: string,
    contentId: string): Promise<boolean> {
    if (!this.active || this.busyCollectionId !== undefined ||
      this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      return false;
    }
    const trimmedTitle = title.trim();
    if (trimmedTitle.length === 0) {
      this.message = '收藏夹名称不能为空';
      this.emit();
      return false;
    }
    const generation = this.generation;
    this.busyCollectionId = 'creating';
    this.message = undefined;
    this.emit();
    try {
      await this.repository.createCollection(trimmedTitle, description, isPublic);
      if (!this.isCurrent(generation)) {
        return false;
      }
      await this.load(contentType, contentId);
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.message = favoriteCreateError(error);
        this.requiresLogin = favoriteRequiresLogin(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.busyCollectionId = undefined;
        this.emit();
      }
    }
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

function favoriteLoadError(error: Object): string {
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
    return error.status === 403 ? '请求被拒绝，可能需要完成知乎风控验证' : '收藏需要登录，请登录后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.RATE_LIMITED) {
    return '请求过于频繁，请稍后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.SERVER) {
    return '知乎服务暂时不可用，请稍后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.TIMEOUT) {
    return '请求超时，请重试';
  }
  return '收藏夹加载失败，请重试';
}

function favoriteToggleError(error: Object): string {
  if (error instanceof CollectionRepositoryFailure &&
    error.kind === CollectionRepositoryFailureKind.INVALID_IDENTIFIER) {
    return '收藏夹标识无效，操作未能完成';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
    return error.status === 403 ? '操作被拒绝，可能需要完成知乎风控验证' : '登录状态不可用，请登录后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.RATE_LIMITED) {
    return '操作过于频繁，请稍后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.SERVER) {
    return '知乎服务暂时不可用，请稍后重试';
  }
  return '收藏操作失败，请重试';
}

function favoriteCreateError(error: Object): string {
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
    return error.status === 403 ? '创建被拒绝，可能需要完成知乎风控验证' : '登录状态不可用，请登录后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.RATE_LIMITED) {
    return '操作过于频繁，请稍后重试';
  }
  if (error instanceof HttpFailure && error.kind === HttpFailureKind.SERVER) {
    return '知乎服务暂时不可用，请稍后重试';
  }
  return '创建收藏夹失败，请重试';
}

function favoriteRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}

function cloneCollectionWithFavorite(collection: CollectionSummary, isFavorited: boolean): CollectionSummary {
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
    isFavorited: isFavorited,
    updatedAt: collection.updatedAt,
    creatorName: collection.creatorName
  };
}
