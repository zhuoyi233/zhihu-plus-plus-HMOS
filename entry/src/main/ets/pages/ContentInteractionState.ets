import {
  ContentDetailKind,
  ContentVoteState,
  FollowMutationResult,
  FollowRepository,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  PinLikeRepository,
  SessionStatus,
  VoteRepository
} from 'data';
import { LoadedContentDetail } from './ContentDetailState';

export const INTERACTION_LOGIN_REQUIRED_MESSAGE = '互动操作需要登录，请先登录';
export const INTERACTION_FAILED_MESSAGE = '操作失败，请稍后重试';

export interface ContentVoteViewState {
  readonly voteState: ContentVoteState;
  readonly voteupCount: number;
  readonly thanked: boolean;
  readonly thanksCount: number;
  readonly pending: boolean;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
}

export interface FollowViewState {
  readonly following: boolean;
  readonly followerCount: number;
  readonly pending: boolean;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
}

export type ContentVoteObserver = (state: ContentVoteViewState) => void;
export type FollowObserver = (state: FollowViewState) => void;

export interface PinLikeViewState {
  readonly liked: boolean;
  readonly likeCount: number;
  readonly pending: boolean;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
}

/** 想法点赞：乐观计数、失败回滚、登录门禁及失活后的迟到响应隔离。 */
export class PinLikeController {
  private readonly repository: PinLikeRepository;
  private readonly session: LoginSessionGateway;
  private readonly contentId: string;
  private readonly observer: (state: PinLikeViewState) => void;
  private liked: boolean;
  private likeCount: number;
  private active: boolean = false;
  private pending: boolean = false;
  private errorMessage?: string;
  private requiresLogin: boolean = false;
  private generation: number = 0;

  constructor(repository: PinLikeRepository, session: LoginSessionGateway, contentId: string,
    liked: boolean, likeCount: number,
    observer: (state: PinLikeViewState) => void = (_state: PinLikeViewState): void => {}) {
    this.repository = repository;
    this.session = session;
    this.contentId = contentId;
    this.liked = liked;
    this.likeCount = likeCount;
    this.observer = observer;
  }

  activate(): void {
    this.active = true;
    this.emit();
  }

  deactivate(): void {
    this.active = false;
    this.generation += 1;
    this.repository.cancel();
  }

  snapshot(): PinLikeViewState {
    return { liked: this.liked, likeCount: this.likeCount, pending: this.pending,
      errorMessage: this.errorMessage, requiresLogin: this.requiresLogin };
  }

  async likeFromDoubleTap(): Promise<void> {
    if (!this.liked) {
      await this.toggleLike();
    }
  }

  async toggleLike(): Promise<void> {
    if (!this.active || this.pending) { return; }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = INTERACTION_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return;
    }
    const generation = this.generation;
    const previousLiked = this.liked;
    const previousCount = this.likeCount;
    this.liked = !this.liked;
    this.likeCount = Math.max(0, this.likeCount + (this.liked ? 1 : -1));
    this.pending = true;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.emit();
    try {
      const result = await this.repository.setLiked(this.contentId, this.liked);
      if (!this.active || generation !== this.generation) { return; }
      this.likeCount = result.likeCount ?? this.likeCount;
      this.pending = false;
      this.emit();
    } catch (error) {
      if (!this.active || generation !== this.generation) { return; }
      this.liked = previousLiked;
      this.likeCount = previousCount;
      this.pending = false;
      this.requiresLogin = interactionRequiresLogin(error);
      this.errorMessage = this.requiresLogin ? INTERACTION_LOGIN_REQUIRED_MESSAGE : INTERACTION_FAILED_MESSAGE;
      this.emit();
    }
  }

  private emit(): void {
    if (this.active) { this.observer(this.snapshot()); }
  }
}

/**
 * 回答/文章互动控制器：点赞、反对、感谢，乐观更新 + 失败回滚 + 登录门禁。
 * 未登录时仅发布 requiresLogin 状态（不发请求），页面据此提示并可跳转登录。
 */
export class ContentVoteController {
  private readonly repository: VoteRepository;
  private readonly session: LoginSessionGateway;
  private readonly kind: ContentDetailKind;
  private readonly contentId: string;
  private readonly observer: ContentVoteObserver;
  private active: boolean = false;
  private voteState: ContentVoteState = ContentVoteState.NEUTRAL;
  private voteupCount: number = 0;
  private thanked: boolean = false;
  private thanksCount: number = 0;
  private pending: boolean = false;
  private errorMessage?: string;
  private requiresLogin: boolean = false;

  constructor(repository: VoteRepository, session: LoginSessionGateway, kind: ContentDetailKind,
    contentId: string, observer: ContentVoteObserver = (_state: ContentVoteViewState): void => {
    }) {
    this.repository = repository;
    this.session = session;
    this.kind = kind;
    this.contentId = contentId;
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
    this.repository.cancel();
  }

  snapshot(): ContentVoteViewState {
    return {
      voteState: this.voteState,
      voteupCount: this.voteupCount,
      thanked: this.thanked,
      thanksCount: this.thanksCount,
      pending: this.pending,
      errorMessage: this.errorMessage,
      requiresLogin: this.requiresLogin
    };
  }

  applyInitial(content: LoadedContentDetail): void {
    if (!this.active) {
      return;
    }
    if (content.kind === ContentDetailKind.ANSWER || content.kind === ContentDetailKind.ARTICLE) {
      this.voteState = content.value.voteState ?? ContentVoteState.NEUTRAL;
      this.voteupCount = content.value.voteupCount;
      this.thanksCount = content.value.thanksCount ?? 0;
      this.thanked = content.value.isThanked ?? false;
    }
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.pending = false;
    this.emit();
  }

  /** 双击正文赞同一键（对齐上游 upVoteFromDoubleTap）：已赞时静默幂等，不取消赞。 */
  async voteUpFromDoubleTap(): Promise<void> {
    if (this.voteState === ContentVoteState.UP) {
      return;
    }
    await this.toggleVote(true);
  }

  async toggleVote(up: boolean): Promise<void> {
    if (!this.active || this.pending) {
      return;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = INTERACTION_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return;
    }
    const previousState = this.voteState;
    const previousCount = this.voteupCount;
    const next = up
      ? (this.voteState === ContentVoteState.UP ? ContentVoteState.NEUTRAL : ContentVoteState.UP)
      : (this.voteState === ContentVoteState.DOWN ? ContentVoteState.NEUTRAL : ContentVoteState.DOWN);
    this.voteState = next;
    this.voteupCount = optimisticVoteupCount(previousState, next, this.voteupCount);
    this.pending = true;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.emit();
    try {
      const result = this.kind === ContentDetailKind.ARTICLE
        ? await this.repository.voteArticle(this.contentId, next)
        : await this.repository.voteAnswer(this.contentId, next);
      if (!this.active) {
        return;
      }
      if (result.voteupCount !== undefined) {
        this.voteupCount = result.voteupCount;
      }
      this.pending = false;
      this.emit();
    } catch (error) {
      if (!this.active) {
        return;
      }
      this.voteState = previousState;
      this.voteupCount = previousCount;
      this.pending = false;
      this.requiresLogin = interactionRequiresLogin(error);
      this.errorMessage = this.requiresLogin ? INTERACTION_LOGIN_REQUIRED_MESSAGE : INTERACTION_FAILED_MESSAGE;
      this.emit();
    }
  }

  async toggleThanks(): Promise<void> {
    if (!this.active || this.pending || this.kind !== ContentDetailKind.ANSWER) {
      return;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = INTERACTION_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return;
    }
    const previousThanked = this.thanked;
    const previousCount = this.thanksCount;
    this.thanked = !this.thanked;
    this.thanksCount = Math.max(0, this.thanksCount + (this.thanked ? 1 : -1));
    this.pending = true;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.emit();
    try {
      const result = await this.repository.thankAnswer(this.contentId, this.thanked);
      if (!this.active) {
        return;
      }
      if (result.thanksCount !== undefined) {
        this.thanksCount = result.thanksCount;
      }
      if (result.thanked !== undefined) {
        this.thanked = result.thanked;
      }
      this.pending = false;
      this.emit();
    } catch (error) {
      if (!this.active) {
        return;
      }
      this.thanked = previousThanked;
      this.thanksCount = previousCount;
      this.pending = false;
      this.requiresLogin = interactionRequiresLogin(error);
      this.errorMessage = this.requiresLogin ? INTERACTION_LOGIN_REQUIRED_MESSAGE : INTERACTION_FAILED_MESSAGE;
      this.emit();
    }
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

/**
 * 关注/取消关注控制器（问题关注与用户关注共用，提交动作由调用方注入）。
 * 乐观更新 + 失败回滚 + 登录门禁。
 */
export class FollowController {
  private readonly repository: FollowRepository;
  private readonly session: LoginSessionGateway;
  private readonly submit: (follow: boolean) => Promise<FollowMutationResult>;
  private readonly observer: FollowObserver;
  private active: boolean = false;
  private following: boolean = false;
  private followerCount: number = 0;
  private pending: boolean = false;
  private errorMessage?: string;
  private requiresLogin: boolean = false;

  constructor(repository: FollowRepository, session: LoginSessionGateway,
    submit: (follow: boolean) => Promise<FollowMutationResult>,
    observer: FollowObserver = (_state: FollowViewState): void => {
    }) {
    this.repository = repository;
    this.session = session;
    this.submit = submit;
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
    this.repository.cancel();
  }

  snapshot(): FollowViewState {
    return {
      following: this.following,
      followerCount: this.followerCount,
      pending: this.pending,
      errorMessage: this.errorMessage,
      requiresLogin: this.requiresLogin
    };
  }

  applyInitial(following: boolean, followerCount: number): void {
    if (!this.active) {
      return;
    }
    this.following = following;
    this.followerCount = Math.max(0, followerCount);
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.pending = false;
    this.emit();
  }

  async toggleFollow(): Promise<void> {
    if (!this.active || this.pending) {
      return;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.errorMessage = INTERACTION_LOGIN_REQUIRED_MESSAGE;
      this.emit();
      return;
    }
    const previousFollowing = this.following;
    const previousCount = this.followerCount;
    this.following = !this.following;
    this.followerCount = Math.max(0, this.followerCount + (this.following ? 1 : -1));
    this.pending = true;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.emit();
    try {
      const result = await this.submit(this.following);
      if (!this.active) {
        return;
      }
      if (result.followerCount !== undefined) {
        this.followerCount = result.followerCount;
      }
      this.pending = false;
      this.emit();
    } catch (error) {
      if (!this.active) {
        return;
      }
      this.following = previousFollowing;
      this.followerCount = previousCount;
      this.pending = false;
      this.requiresLogin = interactionRequiresLogin(error);
      this.errorMessage = this.requiresLogin ? INTERACTION_LOGIN_REQUIRED_MESSAGE : INTERACTION_FAILED_MESSAGE;
      this.emit();
    }
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

function optimisticVoteupCount(previous: ContentVoteState, next: ContentVoteState, current: number): number {
  if (previous === ContentVoteState.UP) {
    return Math.max(0, current - 1);
  }
  if (next === ContentVoteState.UP) {
    return current + 1;
  }
  return current;
}

function interactionRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}
