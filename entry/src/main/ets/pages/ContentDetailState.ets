import {
  Answer,
  Article,
  ContentDetailKind,
  ContentRepository,
  ContentRepositoryFailure,
  ContentRepositoryFailureKind,
  DomainDecodeError,
  HttpFailure,
  HttpFailureKind,
  OpenedContentStore,
  Question,
  UserProfile
} from 'data';

export enum ContentDetailPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  ERROR = 'error'
}

export enum OpenedRecordPhase {
  NOT_CONFIGURED = 'not_configured',
  NOT_RECORDED = 'not_recorded',
  PENDING = 'pending',
  RECORDED = 'recorded',
  FAILED = 'failed'
}

export interface LoadedQuestionDetail {
  readonly kind: ContentDetailKind.QUESTION;
  readonly value: Question;
}

export interface LoadedAnswerDetail {
  readonly kind: ContentDetailKind.ANSWER;
  readonly value: Answer;
}

export interface LoadedArticleDetail {
  readonly kind: ContentDetailKind.ARTICLE;
  readonly value: Article;
}

export type LoadedContentDetail = LoadedQuestionDetail | LoadedAnswerDetail | LoadedArticleDetail;

export interface ContentDetailViewState {
  readonly phase: ContentDetailPhase;
  readonly kind?: ContentDetailKind;
  readonly content?: LoadedContentDetail;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
  readonly openedRecordPhase: OpenedRecordPhase;
}

export type ContentDetailStateObserver = (state: ContentDetailViewState) => void;

export class ContentDetailController {
  private readonly repository: ContentRepository;
  private readonly openedContentStore?: OpenedContentStore;
  private readonly observer: ContentDetailStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: ContentDetailPhase = ContentDetailPhase.IDLE;
  private kind?: ContentDetailKind;
  private content?: LoadedContentDetail;
  private errorMessage?: string;
  private requiresLogin: boolean = false;
  private openedRecordPhase: OpenedRecordPhase = OpenedRecordPhase.NOT_CONFIGURED;

  constructor(repository: ContentRepository, openedContentStore?: OpenedContentStore,
    observer: ContentDetailStateObserver = (_state: ContentDetailViewState): void => {
    }) {
    this.repository = repository;
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

  snapshot(): ContentDetailViewState {
    return {
      phase: this.phase,
      kind: this.kind,
      content: this.content === undefined ? undefined : cloneLoadedContent(this.content),
      errorMessage: this.errorMessage,
      requiresLogin: this.requiresLogin,
      openedRecordPhase: this.openedRecordPhase
    };
  }

  async load(kind: ContentDetailKind, id: string): Promise<void> {
    if (!this.active) {
      return;
    }
    if (this.phase === ContentDetailPhase.LOADING) {
      this.repository.cancel();
    }
    const generation = ++this.generation;
    this.kind = kind;
    this.content = undefined;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.openedRecordPhase = this.openedContentStore === undefined
      ? OpenedRecordPhase.NOT_CONFIGURED
      : OpenedRecordPhase.NOT_RECORDED;
    this.phase = ContentDetailPhase.LOADING;
    this.emit();
    try {
      const loaded = await this.fetch(kind, id);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.content = loaded;
      this.phase = ContentDetailPhase.READY;
      this.openedRecordPhase = this.openedContentStore === undefined
        ? OpenedRecordPhase.NOT_CONFIGURED
        : OpenedRecordPhase.PENDING;
      this.emit();
      await this.recordOpenIfConfigured(loaded, generation);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.content = undefined;
      this.phase = ContentDetailPhase.ERROR;
      this.errorMessage = contentDetailErrorMessage(error);
      this.requiresLogin = contentDetailRequiresLogin(error);
      this.openedRecordPhase = this.openedContentStore === undefined
        ? OpenedRecordPhase.NOT_CONFIGURED
        : OpenedRecordPhase.NOT_RECORDED;
      this.emit();
    }
  }

  private async fetch(kind: ContentDetailKind, id: string): Promise<LoadedContentDetail> {
    switch (kind) {
      case ContentDetailKind.QUESTION:
        return { kind: kind, value: await this.repository.getQuestion(id) };
      case ContentDetailKind.ANSWER:
        return { kind: kind, value: await this.repository.getAnswer(id) };
      case ContentDetailKind.ARTICLE:
        return { kind: kind, value: await this.repository.getArticle(id) };
    }
  }

  /** 历史记录展示标题：回答用问题标题，问题/文章用自身标题；缺失时为空串，由列表页回退显示。 */
  private recordTitle(content: LoadedContentDetail): string {
    switch (content.kind) {
      case ContentDetailKind.QUESTION:
        return content.value.title;
      case ContentDetailKind.ANSWER:
        return content.value.questionTitle ?? '';
      case ContentDetailKind.ARTICLE:
        return content.value.title;
    }
  }

  private async recordOpenIfConfigured(content: LoadedContentDetail, generation: number): Promise<void> {
    const store = this.openedContentStore;
    if (store === undefined) {
      return;
    }
    try {
      await store.upsert({
        contentKey: contentDetailIdentity(content.kind, content.value.id),
        openedAt: Date.now(),
        contentType: content.kind,
        title: this.recordTitle(content)
      });
      if (this.isCurrent(generation)) {
        this.openedRecordPhase = OpenedRecordPhase.RECORDED;
        this.emit();
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.openedRecordPhase = OpenedRecordPhase.FAILED;
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

export function contentDetailIdentity(kind: ContentDetailKind, id: string): string {
  return `${kind}:${id}`;
}

export function contentDetailErrorMessage(error: Object): string {
  if (error instanceof ContentRepositoryFailure &&
    error.kind === ContentRepositoryFailureKind.INVALID_ID) {
    return '内容 ID 无效，无法加载详情';
  }
  if (error instanceof HttpFailure) {
    switch (error.kind) {
      case HttpFailureKind.AUTHENTICATION:
        return contentDetailRequiresLogin(error)
          ? '登录状态不可用，请重新登录后重试'
          : '内容请求被拒绝，可能需要完成知乎风控验证';
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
        return '内容不存在或请求已被拒绝';
    }
  }
  if (error instanceof DomainDecodeError) {
    return '内容响应无法解析，请稍后重试';
  }
  return '内容加载失败，请稍后重试';
}

export function contentDetailRequiresLogin(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION &&
    (error.status === undefined || error.status === 401);
}

function cloneAuthor(author?: UserProfile): UserProfile | undefined {
  if (author === undefined) {
    return undefined;
  }
  return {
    id: author.id,
    name: author.name,
    urlToken: author.urlToken,
    headline: author.headline,
    avatarUrl: author.avatarUrl,
    followerCount: author.followerCount,
    isFollowing: author.isFollowing,
    isOrganization: author.isOrganization
  };
}

function cloneLoadedContent(content: LoadedContentDetail): LoadedContentDetail {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return {
        kind: content.kind,
        value: {
          id: content.value.id,
          title: content.value.title,
          detailHtml: content.value.detailHtml,
          url: content.value.url,
          answerCount: content.value.answerCount,
          commentCount: content.value.commentCount,
          followerCount: content.value.followerCount,
          createdAt: content.value.createdAt,
          updatedAt: content.value.updatedAt,
          author: cloneAuthor(content.value.author),
          isFollowing: content.value.isFollowing
        }
      };
    case ContentDetailKind.ANSWER:
      return {
        kind: content.kind,
        value: {
          id: content.value.id,
          questionId: content.value.questionId,
          questionTitle: content.value.questionTitle,
          contentHtml: content.value.contentHtml,
          excerpt: content.value.excerpt,
          url: content.value.url,
          voteupCount: content.value.voteupCount,
          commentCount: content.value.commentCount,
          createdAt: content.value.createdAt,
          updatedAt: content.value.updatedAt,
          author: cloneAuthor(content.value.author),
          voteState: content.value.voteState,
          thanksCount: content.value.thanksCount,
          isThanked: content.value.isThanked
        }
      };
    case ContentDetailKind.ARTICLE:
      return {
        kind: content.kind,
        value: {
          id: content.value.id,
          title: content.value.title,
          contentHtml: content.value.contentHtml,
          excerpt: content.value.excerpt,
          url: content.value.url,
          voteupCount: content.value.voteupCount,
          commentCount: content.value.commentCount,
          createdAt: content.value.createdAt,
          updatedAt: content.value.updatedAt,
          author: cloneAuthor(content.value.author),
          voteState: content.value.voteState,
          thanksCount: content.value.thanksCount,
          isThanked: content.value.isThanked
        }
      };
  }
}
