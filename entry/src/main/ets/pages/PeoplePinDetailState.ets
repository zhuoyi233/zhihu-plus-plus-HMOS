import {
  DomainDecodeError,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  OpenedContentStore,
  PeopleDetailRepository,
  PeopleProfile,
  PeopleRepositoryFailure,
  PeopleRepositoryFailureKind,
  PinDetail,
  PinTopic,
  PinRepository,
  PinRepositoryFailure,
  PinRepositoryFailureKind,
  SessionStatus,
  UserProfile
} from 'data';

export enum ReadOnlyDetailPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  ERROR = 'error'
}

export interface PeopleDetailViewState {
  readonly phase: ReadOnlyDetailPhase;
  readonly profile?: PeopleProfile;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
}

export interface PinDetailViewState {
  readonly phase: ReadOnlyDetailPhase;
  readonly pin?: PinDetail;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
  readonly openedRecordFailed: boolean;
}

export type PeopleDetailObserver = (state: PeopleDetailViewState) => void;
export type PinDetailObserver = (state: PinDetailViewState) => void;

export class PeopleDetailController {
  private readonly repository: PeopleDetailRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: PeopleDetailObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: ReadOnlyDetailPhase = ReadOnlyDetailPhase.IDLE;
  private profile?: PeopleProfile;
  private errorMessage?: string;
  private requiresLogin: boolean = false;

  constructor(repository: PeopleDetailRepository, session: LoginSessionGateway,
    observer: PeopleDetailObserver = (_state: PeopleDetailViewState): void => {
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

  snapshot(): PeopleDetailViewState {
    return {
      phase: this.phase,
      profile: this.profile === undefined ? undefined : clonePeopleProfile(this.profile),
      errorMessage: this.errorMessage,
      requiresLogin: this.requiresLogin
    };
  }

  async load(identifier: string): Promise<void> {
    if (!this.active) {
      return;
    }
    if (this.phase === ReadOnlyDetailPhase.LOADING) {
      this.repository.cancel();
    }
    const generation = ++this.generation;
    this.profile = undefined;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = '用户主页需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return;
    }
    this.phase = ReadOnlyDetailPhase.LOADING;
    this.emit();
    try {
      const profile = await this.repository.getUser(identifier);
      if (!this.isCurrent(generation)) {
        return;
      }
      if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
        this.phase = ReadOnlyDetailPhase.ERROR;
        this.errorMessage = '用户主页需要登录，请登录后重试';
        this.requiresLogin = true;
        this.emit();
        return;
      }
      this.profile = profile;
      this.phase = ReadOnlyDetailPhase.READY;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = peoplePinErrorMessage(error, '用户');
      this.requiresLogin = readOnlyDetailRequiresLogin(error);
    }
    this.emit();
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

export class PinDetailController {
  private readonly repository: PinRepository;
  private readonly session: LoginSessionGateway;
  private readonly openedContentStore?: OpenedContentStore;
  private readonly observer: PinDetailObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: ReadOnlyDetailPhase = ReadOnlyDetailPhase.IDLE;
  private pin?: PinDetail;
  private errorMessage?: string;
  private requiresLogin: boolean = false;
  private openedRecordFailed: boolean = false;

  constructor(repository: PinRepository, session: LoginSessionGateway, openedContentStore?: OpenedContentStore,
    observer: PinDetailObserver = (_state: PinDetailViewState): void => {
    }) {
    this.repository = repository;
    this.session = session;
    this.openedContentStore = openedContentStore;
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

  snapshot(): PinDetailViewState {
    return {
      phase: this.phase,
      pin: this.pin === undefined ? undefined : clonePinDetail(this.pin),
      errorMessage: this.errorMessage,
      requiresLogin: this.requiresLogin,
      openedRecordFailed: this.openedRecordFailed
    };
  }

  async load(id: string): Promise<void> {
    if (!this.active) {
      return;
    }
    if (this.phase === ReadOnlyDetailPhase.LOADING) {
      this.repository.cancel();
    }
    const generation = ++this.generation;
    this.pin = undefined;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.openedRecordFailed = false;
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = '想法详情需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return;
    }
    this.phase = ReadOnlyDetailPhase.LOADING;
    this.emit();
    try {
      const pin = await this.repository.getPin(id);
      if (!this.isCurrent(generation)) {
        return;
      }
      if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
        this.phase = ReadOnlyDetailPhase.ERROR;
        this.errorMessage = '想法详情需要登录，请登录后重试';
        this.requiresLogin = true;
        this.emit();
        return;
      }
      this.pin = pin;
      this.phase = ReadOnlyDetailPhase.READY;
      this.emit();
      await this.recordOpen(pin, generation);
      return;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = peoplePinErrorMessage(error, '想法');
      this.requiresLogin = readOnlyDetailRequiresLogin(error);
    }
    this.emit();
  }

  private async recordOpen(pin: PinDetail, generation: number): Promise<void> {
    if (this.openedContentStore === undefined) {
      return;
    }
    try {
      await this.openedContentStore.upsert({
        contentKey: `pin:${pin.id}`,
        openedAt: Date.now(),
        contentType: 'pin',
        title: pinHistoryExcerpt(pin.contentHtml)
      });
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.openedRecordFailed = true;
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

export function readOnlyDetailRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}

const PIN_HISTORY_EXCERPT_MAX_LENGTH = 50;

/** 历史页展示用想法摘要：去掉标签与多余空白，超长截断。想法没有标题字段，以正文开头代替。 */
export function pinHistoryExcerpt(html: string): string {
  const plain = html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
  if (plain.length <= PIN_HISTORY_EXCERPT_MAX_LENGTH) {
    return plain;
  }
  return plain.substring(0, PIN_HISTORY_EXCERPT_MAX_LENGTH) + '…';
}

export function peoplePinErrorMessage(error: Object, label: string): string {
  if (error instanceof PeopleRepositoryFailure &&
    error.kind === PeopleRepositoryFailureKind.INVALID_IDENTIFIER) {
    return '用户标识无效，无法加载主页';
  }
  if (error instanceof PinRepositoryFailure && error.kind === PinRepositoryFailureKind.INVALID_ID) {
    return '想法 ID 无效，无法加载详情';
  }
  if (error instanceof HttpFailure) {
    switch (error.kind) {
      case HttpFailureKind.AUTHENTICATION:
        return readOnlyDetailRequiresLogin(error)
          ? `${label}详情需要登录，请登录后重试`
          : `${label}请求被拒绝，可能需要完成知乎风控验证`;
      case HttpFailureKind.RATE_LIMITED:
        return '请求过于频繁，请稍后重试';
      case HttpFailureKind.TIMEOUT:
      case HttpFailureKind.NETWORK:
        return '网络连接失败，请检查网络后重试';
      case HttpFailureKind.SERVER:
        return '知乎服务暂时不可用，请稍后重试';
      case HttpFailureKind.BUSY:
        return '详情请求仍在处理中，请稍后重试';
      default:
        return `${label}不存在或请求已被拒绝`;
    }
  }
  if (error instanceof DomainDecodeError) {
    return `${label}响应无法解析，请稍后重试`;
  }
  return `${label}加载失败，请稍后重试`;
}

function cloneUserProfile(profile: UserProfile): UserProfile {
  return {
    id: profile.id,
    name: profile.name,
    urlToken: profile.urlToken,
    headline: profile.headline,
    avatarUrl: profile.avatarUrl,
    followerCount: profile.followerCount,
    isFollowing: profile.isFollowing,
    isOrganization: profile.isOrganization
  };
}

function clonePeopleProfile(profile: PeopleProfile): PeopleProfile {
  return {
    id: profile.id,
    name: profile.name,
    urlToken: profile.urlToken,
    headline: profile.headline,
    avatarUrl: profile.avatarUrl,
    followerCount: profile.followerCount,
    followingCount: profile.followingCount,
    answerCount: profile.answerCount,
    articleCount: profile.articleCount,
    isFollowing: profile.isFollowing,
    isOrganization: profile.isOrganization,
    canonicalUrl: profile.canonicalUrl
  };
}

function clonePinDetail(pin: PinDetail): PinDetail {
  return {
    id: pin.id,
    contentHtml: pin.contentHtml,
    url: pin.url,
    likeCount: pin.likeCount,
    commentCount: pin.commentCount,
    createdAt: pin.createdAt,
    updatedAt: pin.updatedAt,
    author: cloneUserProfile(pin.author),
    topics: pin.topics.map((topic: PinTopic): PinTopic => ({ id: topic.id, name: topic.name }))
  };
}
