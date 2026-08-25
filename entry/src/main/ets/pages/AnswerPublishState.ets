import {
  AnswerPublishInput,
  AnswerPublishRepository,
  ContentDraftKind,
  ContentDraftLoadStatus,
  ContentDraftSaveInput,
  createAnswerDraftIdentity,
  DraftRepository,
  ExistingAnswerForEditing,
  isExistingAnswerConflict,
  LocalDraftImageReference,
  LoginSessionGateway,
  cloneLocalDraftImageReferences,
  parseLocalDraftImageReferences,
  parsePublishedContentId,
  PublishFailure,
  PublishFailureKind,
  SessionStatus,
  serializeLocalDraftImageReferences,
  toPublishFailure
} from 'data';

export enum AnswerPublishPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  SAVING_REMOTE_DRAFT = 'saving_remote_draft',
  PUBLISHING = 'publishing',
  PUBLISHED = 'published',
  CONFLICT = 'conflict',
  FAILED = 'failed',
  RELEASED = 'released'
}

export interface AnswerPublishViewState {
  readonly phase: AnswerPublishPhase;
  readonly generation: number;
  readonly questionId: string;
  readonly answerId?: string;
  readonly html: string;
  readonly tocEnabled: boolean;
  /** 仅用于本地草稿恢复；不属于知乎发布图片。 */
  readonly localImageReferences: Array<LocalDraftImageReference>;
  readonly localDraftSaved: boolean;
  readonly pending: boolean;
  readonly requiresLogin: boolean;
  readonly requiresVerification: boolean;
  readonly canRetry: boolean;
  readonly conflictAnswerId?: string;
  readonly publishedAnswerId?: string;
  readonly errorMessage?: string;
}

export type AnswerPublishObserver = (state: AnswerPublishViewState) => void;

export const ANSWER_PUBLISH_LOGIN_REQUIRED_MESSAGE: string = '发布回答需要登录，请先登录';
export const ANSWER_PUBLISH_VERIFICATION_MESSAGE: string = '发布被拒绝或需要完成安全验证';
export const ANSWER_PUBLISH_RATE_LIMITED_MESSAGE: string = '发布过于频繁，请稍后重试';
export const ANSWER_PUBLISH_FAILED_MESSAGE: string = '回答发布失败，草稿已保留';
export const ANSWER_PUBLISH_CONFLICT_MESSAGE: string = '该问题已有回答，可转入编辑';

/**
 * 回答发布的无 UI 编排层。它只依赖 P4-0 发布合同和 P4-1 加密草稿仓储，
 * 因而可以通过 fake 仓储验证完整顺序，而不会发起真实知乎写请求。
 */
export class AnswerPublishController {
  private readonly publishRepository: AnswerPublishRepository;
  private readonly draftRepository: DraftRepository;
  private readonly session: LoginSessionGateway;
  private readonly accountKey: string;
  private readonly questionId: string;
  private readonly observer: AnswerPublishObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: AnswerPublishPhase = AnswerPublishPhase.IDLE;
  private answerId?: string;
  private html: string = '';
  private tocEnabled: boolean = false;
  private localImageReferences: Array<LocalDraftImageReference> = [];
  private localDraftSaved: boolean = false;
  private pending: boolean = false;
  private requiresLogin: boolean = false;
  private requiresVerification: boolean = false;
  private canRetry: boolean = false;
  private conflictAnswerId?: string;
  private publishedAnswerId?: string;
  private errorMessage?: string;

  constructor(publishRepository: AnswerPublishRepository, draftRepository: DraftRepository,
    session: LoginSessionGateway, accountKey: string, questionId: string,
    observer: AnswerPublishObserver = (_state: AnswerPublishViewState): void => {}, initialAnswerId?: string) {
    this.publishRepository = publishRepository;
    this.draftRepository = draftRepository;
    this.session = session;
    this.accountKey = accountKey;
    this.questionId = questionId;
    this.observer = observer;
    this.answerId = initialAnswerId;
  }

  activate(): void {
    if (this.active || this.phase === AnswerPublishPhase.RELEASED) {
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
    this.publishRepository.cancel();
    this.pending = false;
    this.phase = AnswerPublishPhase.RELEASED;
  }

  snapshot(): AnswerPublishViewState {
    return {
      phase: this.phase,
      generation: this.generation,
      questionId: this.questionId,
      answerId: this.answerId,
      html: this.html,
      tocEnabled: this.tocEnabled,
      localImageReferences: cloneLocalDraftImageReferences(this.localImageReferences),
      localDraftSaved: this.localDraftSaved,
      pending: this.pending,
      requiresLogin: this.requiresLogin,
      requiresVerification: this.requiresVerification,
      canRetry: this.canRetry,
      conflictAnswerId: this.conflictAnswerId,
      publishedAnswerId: this.publishedAnswerId,
      errorMessage: this.errorMessage
    };
  }

  async open(): Promise<void> {
    if (!this.active || this.pending) {
      return;
    }
    if (!this.requireAuthenticatedSession()) {
      return;
    }
    const operation = this.begin(AnswerPublishPhase.LOADING);
    const identity = createAnswerDraftIdentity(this.accountKey, this.questionId);
    try {
      const local = await this.draftRepository.load(identity);
      if (!this.isCurrent(operation)) {
        return;
      }
      if (this.answerId === undefined) {
        const answerId = await this.publishRepository.findMyAnswerId(this.questionId);
        if (!this.isCurrent(operation)) {
          return;
        }
        this.answerId = answerId ?? local.draft?.metadata.remoteContentId;
      }
      const hasLocalDraft = local.status === ContentDraftLoadStatus.FOUND && local.draft !== undefined;
      if (hasLocalDraft && local.draft !== undefined) {
        this.html = local.draft.html;
        this.tocEnabled = local.draft.metadata.tocEnabled;
        this.localImageReferences = parseLocalDraftImageReferences(local.draft.metadata.imageRefsJson);
        this.localDraftSaved = true;
      } else if (this.answerId !== undefined) {
        const existing = await this.publishRepository.fetchAnswerForEditing(this.answerId);
        if (!this.isCurrent(operation)) {
          return;
        }
        this.applyExistingAnswer(existing);
      }
      this.finishReady();
    } catch (error) {
      this.fail(operation, error);
    }
  }

  updateContent(html: string, tocEnabled: boolean): void {
    if (!this.active || this.pending || this.phase === AnswerPublishPhase.RELEASED ||
      this.phase === AnswerPublishPhase.PUBLISHED) {
      return;
    }
    this.html = html;
    this.tocEnabled = tocEnabled;
    this.localDraftSaved = false;
    this.phase = AnswerPublishPhase.READY;
    this.clearFailure();
    this.emit();
  }

  /** 只接收已验证的受控缓存引用；这里不会上传或写远端草稿。 */
  updateLocalImageReferences(references: Array<LocalDraftImageReference>): void {
    if (!this.active || this.pending || this.phase === AnswerPublishPhase.RELEASED ||
      this.phase === AnswerPublishPhase.PUBLISHED) {
      return;
    }
    try {
      this.localImageReferences = parseLocalDraftImageReferences(serializeLocalDraftImageReferences(references));
      this.localDraftSaved = false;
      this.phase = AnswerPublishPhase.READY;
      this.clearFailure();
      this.emit();
    } catch (_error) {
      // 非受控路径和不完整元数据均不能进入草稿或远端发布链路。
    }
  }

  async saveLocalDraft(now: number = Date.now()): Promise<void> {
    if (!this.active || this.pending || this.phase === AnswerPublishPhase.RELEASED ||
      this.phase === AnswerPublishPhase.PUBLISHED) {
      return;
    }
    const operation = this.generation;
    try {
      await this.draftRepository.save(this.createLocalDraftInput(), now);
      if (!this.isCurrent(operation)) {
        return;
      }
      this.phase = AnswerPublishPhase.READY;
      this.localDraftSaved = true;
      this.clearFailure();
      this.emit();
    } catch (error) {
      this.fail(operation, error);
    }
  }

  async publish(traceId: string, now: number = Date.now()): Promise<void> {
    if (!this.active || this.pending || this.phase === AnswerPublishPhase.RELEASED ||
      this.phase === AnswerPublishPhase.PUBLISHED) {
      return;
    }
    if (!this.requireAuthenticatedSession()) {
      return;
    }
    const operation = this.begin(AnswerPublishPhase.SAVING_REMOTE_DRAFT);
    try {
      await this.draftRepository.save(this.createLocalDraftInput(), now);
      if (!this.isCurrent(operation)) {
        return;
      }
      const input = this.createPublishInput(traceId);
      await this.publishRepository.saveRemoteDraft(input);
      if (!this.isCurrent(operation)) {
        return;
      }
      this.phase = AnswerPublishPhase.PUBLISHING;
      this.emit();
      const response = await this.publishRepository.publish(input);
      if (!this.isCurrent(operation)) {
        return;
      }
      const publishedAnswerId = parsePublishedContentId(response);
      if (publishedAnswerId !== undefined) {
        await this.draftRepository.discard(createAnswerDraftIdentity(this.accountKey, this.questionId));
        if (!this.isCurrent(operation)) {
          return;
        }
        this.answerId = publishedAnswerId;
        this.publishedAnswerId = publishedAnswerId;
        this.pending = false;
        this.phase = AnswerPublishPhase.PUBLISHED;
        this.clearFailure();
        this.emit();
        return;
      }
      if (isExistingAnswerConflict(response)) {
        await this.handleConflict(operation);
        return;
      }
      this.fail(operation, new PublishFailure(PublishFailureKind.SERVER));
    } catch (error) {
      if (isConflictFailure(error)) {
        await this.handleConflict(operation);
        return;
      }
      this.fail(operation, error);
    }
  }

  /** 103003 后只转换目标，不覆盖已保留的本地草稿正文。 */
  continueEditingExistingAnswer(): void {
    if (!this.active || this.phase !== AnswerPublishPhase.CONFLICT || this.conflictAnswerId === undefined) {
      return;
    }
    this.answerId = this.conflictAnswerId;
    this.phase = AnswerPublishPhase.READY;
    this.pending = false;
    this.clearFailure();
    this.emit();
  }

  private async handleConflict(operation: number): Promise<void> {
    try {
      const answerId = await this.publishRepository.findMyAnswerId(this.questionId);
      if (!this.isCurrent(operation)) {
        return;
      }
      if (answerId === undefined) {
        this.fail(operation, new PublishFailure(PublishFailureKind.CONFLICT));
        return;
      }
      this.answerId = answerId;
      this.conflictAnswerId = answerId;
      this.pending = false;
      this.phase = AnswerPublishPhase.CONFLICT;
      this.requiresLogin = false;
      this.requiresVerification = false;
      this.canRetry = false;
      this.errorMessage = ANSWER_PUBLISH_CONFLICT_MESSAGE;
      this.emit();
    } catch (error) {
      this.fail(operation, error);
    }
  }

  private createLocalDraftInput(): ContentDraftSaveInput {
    const identity = createAnswerDraftIdentity(this.accountKey, this.questionId);
    return {
      draftKey: identity.draftKey,
      accountKey: identity.accountKey,
      kind: ContentDraftKind.ANSWER,
      targetId: identity.targetId,
      html: this.html,
      remoteContentId: this.answerId,
      title: '',
      plainTextLength: countPlainText(this.html),
      tocEnabled: this.tocEnabled,
      imageRefsJson: serializeLocalDraftImageReferences(this.localImageReferences),
      topicRefsJson: '[]',
      dirty: true
    };
  }

  private createPublishInput(traceId: string): AnswerPublishInput {
    return {
      questionId: this.questionId,
      answerId: this.answerId,
      html: this.html,
      tocEnabled: this.tocEnabled,
      traceId: traceId
    };
  }

  private begin(phase: AnswerPublishPhase): number {
    this.generation += 1;
    this.phase = phase;
    this.pending = true;
    this.clearFailure();
    this.emit();
    return this.generation;
  }

  private finishReady(): void {
    this.pending = false;
    this.phase = AnswerPublishPhase.READY;
    this.clearFailure();
    this.emit();
  }

  private applyExistingAnswer(existing: ExistingAnswerForEditing | undefined): void {
    if (existing === undefined) {
      return;
    }
    this.answerId = existing.answerId;
    this.html = existing.html;
    this.tocEnabled = existing.tocEnabled;
  }

  private requireAuthenticatedSession(): boolean {
    if (this.session.getState().status === SessionStatus.AUTHENTICATED) {
      return true;
    }
    this.pending = false;
    this.phase = AnswerPublishPhase.READY;
    this.requiresLogin = true;
    this.requiresVerification = false;
    this.canRetry = false;
    this.errorMessage = ANSWER_PUBLISH_LOGIN_REQUIRED_MESSAGE;
    this.emit();
    return false;
  }

  private fail(operation: number, error: Object): void {
    if (!this.isCurrent(operation)) {
      return;
    }
    const failure = toPublishFailure(error);
    this.pending = false;
    this.phase = AnswerPublishPhase.FAILED;
    this.requiresLogin = failure.kind === PublishFailureKind.AUTHENTICATION;
    this.requiresVerification = failure.kind === PublishFailureKind.FORBIDDEN;
    this.canRetry = failure.retryable;
    this.errorMessage = messageForFailure(failure.kind);
    this.emit();
  }

  private clearFailure(): void {
    this.requiresLogin = false;
    this.requiresVerification = false;
    this.canRetry = false;
    this.conflictAnswerId = undefined;
    this.errorMessage = undefined;
  }

  private isCurrent(operation: number): boolean {
    return this.active && operation === this.generation;
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

function isConflictFailure(error: Object): boolean {
  return error instanceof PublishFailure && error.kind === PublishFailureKind.CONFLICT;
}

function countPlainText(html: string): number {
  return html.replace(/<[^>]*>/g, '').length;
}

function messageForFailure(kind: PublishFailureKind): string {
  switch (kind) {
    case PublishFailureKind.AUTHENTICATION:
      return ANSWER_PUBLISH_LOGIN_REQUIRED_MESSAGE;
    case PublishFailureKind.FORBIDDEN:
      return ANSWER_PUBLISH_VERIFICATION_MESSAGE;
    case PublishFailureKind.RATE_LIMITED:
      return ANSWER_PUBLISH_RATE_LIMITED_MESSAGE;
    default:
      return ANSWER_PUBLISH_FAILED_MESSAGE;
  }
}
