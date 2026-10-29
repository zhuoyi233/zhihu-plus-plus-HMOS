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
  QuestionTopicSummary,
  ReadHistoryUploadRepository,
  SegmentInfoMark,
  SegmentInfoMeta,
  SegmentInfoParagraph,
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
  /** 本次加载代次：跨 ArkUI 状态代理仍保持稳定。 */
  readonly loadGeneration?: number;
  readonly kind: ContentDetailKind.QUESTION;
  readonly value: Question;
}

export interface LoadedAnswerDetail {
  /** 本次加载代次：跨 ArkUI 状态代理仍保持稳定。 */
  readonly loadGeneration?: number;
  readonly kind: ContentDetailKind.ANSWER;
  readonly value: Answer;
}

export interface LoadedArticleDetail {
  /** 本次加载代次：跨 ArkUI 状态代理仍保持稳定。 */
  readonly loadGeneration?: number;
  readonly kind: ContentDetailKind.ARTICLE;
  readonly value: Article;
}

export type LoadedContentDetail = LoadedQuestionDetail | LoadedAnswerDetail | LoadedArticleDetail;

/** 只接受当前已显示正文的事件，阅读记录仍在写入不影响正文边界同步。 */
export function acceptsContentDocumentEvent(phase: ContentDetailPhase, current: LoadedContentDetail | undefined,
  source: LoadedContentDetail): boolean {
  return phase === ContentDetailPhase.READY && current !== undefined &&
    current.loadGeneration !== undefined && current.loadGeneration === source.loadGeneration &&
    current.kind === source.kind && current.value.id === source.value.id;
}

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
  private readonly historyUploader?: ReadHistoryUploadRepository;
  private readonly observer: ContentDetailStateObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: ContentDetailPhase = ContentDetailPhase.IDLE;
  private kind?: ContentDetailKind;
  private content?: LoadedContentDetail;
  private errorMessage?: string;
  private requiresLogin: boolean = false;
  private openedRecordPhase: OpenedRecordPhase = OpenedRecordPhase.NOT_CONFIGURED;
  /** 已准备但尚未提交的候选回答 id：防止过期候选借新代次提交。 */
  private preparedAnswerId: string = '';
  private pendingRequestGeneration: number = -1;

  constructor(repository: ContentRepository, openedContentStore?: OpenedContentStore,
    observer: ContentDetailStateObserver = (_state: ContentDetailViewState): void => {
    }, historyUploader?: ReadHistoryUploadRepository) {
    this.repository = repository;
    this.openedContentStore = openedContentStore;
    this.historyUploader = historyUploader;
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
    this.cancelPendingRequest();
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
    this.cancelPendingRequest();
    const generation = ++this.generation;
    this.pendingRequestGeneration = generation;
    this.kind = kind;
    this.preparedAnswerId = '';
    this.content = undefined;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.openedRecordPhase = this.openedContentStore === undefined
      ? OpenedRecordPhase.NOT_CONFIGURED
      : OpenedRecordPhase.NOT_RECORDED;
    this.phase = ContentDetailPhase.LOADING;
    this.emit();
    try {
      const loaded = await this.fetch(kind, id, generation);
      this.finishPendingRequest(generation);
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
      this.finishPendingRequest(generation);
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

  /** 准备回答时保留已显示内容；调用方确认导航后再提交。 */
  async prepareAnswer(id: string): Promise<LoadedContentDetail | undefined> {
    if (!this.active || this.phase !== ContentDetailPhase.READY) { return undefined; }
    this.cancelPendingRequest();
    const generation = ++this.generation;
    this.pendingRequestGeneration = generation;
    this.errorMessage = undefined;
    this.preparedAnswerId = id;
    try {
      const loaded = await this.fetch(ContentDetailKind.ANSWER, id, generation);
      this.finishPendingRequest(generation);
      return this.isCurrent(generation) ? loaded : undefined;
    } catch (error) {
      this.finishPendingRequest(generation);
      if (this.isCurrent(generation)) {
        this.errorMessage = contentDetailErrorMessage(error);
      }
      return undefined;
    }
  }

  /**
   * 登记预取/手势期间已取得的候选详情：分配本次加载代次并标记为准备态。
   * 不替换当前显示内容、不写阅读记录；返回的对象必须同时用于挂载候选正文实例与提交，
   * 否则正文实例键会变化导致重建。
   */
  admitAnswer(answer: Answer): LoadedContentDetail | undefined {
    if (!this.active || this.phase !== ContentDetailPhase.READY || answer.id.length === 0) {
      return undefined;
    }
    this.cancelPendingRequest();
    this.errorMessage = undefined;
    this.preparedAnswerId = answer.id;
    return { kind: ContentDetailKind.ANSWER, loadGeneration: ++this.generation, value: answer };
  }

  /** 取消候选不会清空当前正文，也不产生阅读记录。 */
  cancelPreparedAnswer(): void {
    this.preparedAnswerId = '';
    this.generation += 1;
    this.cancelPendingRequest();
  }

  private finishPendingRequest(generation: number): void {
    if (this.pendingRequestGeneration === generation) { this.pendingRequestGeneration = -1; }
  }

  private cancelPendingRequest(): void {
    if (this.pendingRequestGeneration < 0) { return; }
    this.pendingRequestGeneration = -1;
    // 仓库可能被其他详情页复用；接纳缓存候选或 READY 页退出时没有自己的网络请求。
    this.repository.cancel();
  }

  canCommitPreparedAnswer(content: LoadedContentDetail): boolean {
    return content.kind === ContentDetailKind.ANSWER && content.loadGeneration !== undefined &&
      this.preparedAnswerId === content.value.id && this.isCurrent(content.loadGeneration) &&
      this.content?.loadGeneration !== content.loadGeneration;
  }

  preparedAnswerError(): string { return this.errorMessage ?? ''; }

  commitPreparedAnswer(content: LoadedContentDetail): boolean {
    if (!this.canCommitPreparedAnswer(content) || content.loadGeneration === undefined) {
      return false;
    }
    this.preparedAnswerId = '';
    this.kind = ContentDetailKind.ANSWER;
    this.content = content;
    this.errorMessage = undefined;
    this.requiresLogin = false;
    this.phase = ContentDetailPhase.READY;
    this.openedRecordPhase = this.openedContentStore === undefined
      ? OpenedRecordPhase.NOT_CONFIGURED : OpenedRecordPhase.PENDING;
    this.emit();
    void this.recordOpenIfConfigured(content, content.loadGeneration);
    return true;
  }

  private async fetch(kind: ContentDetailKind, id: string, generation: number): Promise<LoadedContentDetail> {
    switch (kind) {
      case ContentDetailKind.QUESTION:
        return { kind: kind, loadGeneration: generation, value: await this.repository.getQuestion(id) };
      case ContentDetailKind.ANSWER:
        return { kind: kind, loadGeneration: generation, value: await this.repository.getAnswer(id) };
      case ContentDetailKind.ARTICLE:
        return { kind: kind, loadGeneration: generation, value: await this.repository.getArticle(id) };
    }
  }

  /** 历史记录展示标题：回答用问题标题，问题/文章用自身标题；缺失时为空串，由列表页回退显示。 */
  private recordTitle(content: LoadedContentDetail): string {
    return contentRecordTitle(content);
  }

  private async recordOpenIfConfigured(content: LoadedContentDetail, generation: number): Promise<void> {
    const store = this.openedContentStore;
    if (store === undefined) {
      return;
    }
    const recorded = await recordContentOpen(store, this.historyUploader, content);
    // 候选准备会推进请求代次，但当前正文的历史写入仍属于这个实例。
    if (this.active && this.content?.loadGeneration === generation) {
      this.openedRecordPhase = recorded ? OpenedRecordPhase.RECORDED : OpenedRecordPhase.FAILED;
      this.emit();
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

/** 历史记录展示标题：回答用问题标题，问题/文章用自身标题；缺失时为空串，由列表页回退显示。 */
export function contentRecordTitle(content: LoadedContentDetail): string {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return content.value.title;
    case ContentDetailKind.ANSWER:
      return content.value.questionTitle ?? '';
    case ContentDetailKind.ARTICLE:
      return content.value.title;
  }
}

/**
 * 取得正文后的阅读记录入口（连续阅读计划 P1 抽离）：本地 upsert + 按现有规则云端上报
 * （对齐上游 addReadHistory，失败静默不阻塞阅读）。返回本地记录是否成功，供调用方区分状态。
 */
export async function recordContentOpen(store: OpenedContentStore,
  uploader: ReadHistoryUploadRepository | undefined, content: LoadedContentDetail): Promise<boolean> {
  try {
    await store.upsert({
      contentKey: contentDetailIdentity(content.kind, content.value.id),
      openedAt: Date.now(),
      contentType: content.kind,
      title: contentRecordTitle(content)
    });
  } catch (_error) {
    return false;
  }
  if (uploader !== undefined) {
    uploader.add(contentDetailIdentity(content.kind, content.value.id)).catch((_error: Error): void => {
    });
  }
  return true;
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
    isOrganization: author.isOrganization,
    badge: author.badge
  };
}

function cloneQuestionTopics(topics?: QuestionTopicSummary[]): QuestionTopicSummary[] | undefined {
  if (topics === undefined) {
    return undefined;
  }
  return topics.map((topic: QuestionTopicSummary): QuestionTopicSummary => {
    return { id: topic.id, name: topic.name };
  });
}

function cloneLoadedContent(content: LoadedContentDetail): LoadedContentDetail {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return {
        kind: content.kind,
        loadGeneration: content.loadGeneration,
        value: {
          id: content.value.id,
          title: content.value.title,
          detailHtml: content.value.detailHtml,
          url: content.value.url,
          answerCount: content.value.answerCount,
          commentCount: content.value.commentCount,
          followerCount: content.value.followerCount,
          visitCount: content.value.visitCount,
          createdAt: content.value.createdAt,
          updatedAt: content.value.updatedAt,
          author: cloneAuthor(content.value.author),
          isFollowing: content.value.isFollowing,
          topics: cloneQuestionTopics(content.value.topics)
        }
      };
    case ContentDetailKind.ANSWER:
      return {
        kind: content.kind,
        loadGeneration: content.loadGeneration,
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
          isThanked: content.value.isThanked,
          endorsements: content.value.endorsements,
          ipInfo: content.value.ipInfo,
          segmentInfos: cloneSegmentInfos(content.value.segmentInfos),
          allowSegmentInteraction: content.value.allowSegmentInteraction
        }
      };
    case ContentDetailKind.ARTICLE:
      return {
        kind: content.kind,
        loadGeneration: content.loadGeneration,
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
          isThanked: content.value.isThanked,
          endorsements: content.value.endorsements,
          topics: cloneQuestionTopics(content.value.topics),
          ipInfo: content.value.ipInfo,
          segmentInfos: cloneSegmentInfos(content.value.segmentInfos),
          allowSegmentInteraction: content.value.allowSegmentInteraction
        }
      };
  }
}

/** 深克隆他人划线（segment_infos），与既有防御性克隆口径一致。 */
function cloneSegmentInfos(value: SegmentInfoParagraph[] | undefined): SegmentInfoParagraph[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  return value.map((paragraph: SegmentInfoParagraph): SegmentInfoParagraph => {
    return {
      pid: paragraph.pid,
      text: paragraph.text,
      marks: paragraph.marks.map((mark: SegmentInfoMark): SegmentInfoMark => {
        return {
          startIndex: mark.startIndex,
          endIndex: mark.endIndex,
          segInfo: cloneSegmentMeta(mark.segInfo),
          masterSegInfo: cloneSegmentMeta(mark.masterSegInfo)
        };
      })
    };
  });
}

function cloneSegmentMeta(value: SegmentInfoMeta | undefined): SegmentInfoMeta | undefined {
  if (value === undefined) {
    return undefined;
  }
  return {
    segIds: value.segIds.slice(),
    isLike: value.isLike,
    likeCount: value.likeCount,
    commentCount: value.commentCount,
    myCommentCount: value.myCommentCount,
    isSpan: value.isSpan
  };
}
