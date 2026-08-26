import {
  ContentDraftIdentity,
  DraftRepository,
  LoginSessionGateway,
  LocalDraftImageReference,
  PinPublishRepository,
  PinTopicSuggestion,
  PublishPinTopic,
  SessionStatus,
  UploadedZhihuImage
} from 'data';
import {
  PinDraftContent,
  PinPublishController,
  PinPublishImageUploader,
  PinPublishOperation,
  PinPublishTraceIdFactory,
  PinPublishViewState,
  PinTopicSearchScheduler
} from './PinPublishState';

export const PIN_PAGE_LOGIN_REQUIRED_MESSAGE: string = '发布想法需要登录，请先登录';
export const PIN_PAGE_READY_MESSAGE: string = '内容仅会在你保存草稿或发布时写入';
export const PIN_PAGE_SAVING_MESSAGE: string = '正在安全保存草稿';
export const PIN_PAGE_UPLOADING_IMAGES_MESSAGE: string = '正在上传图片，草稿已保留';
export const PIN_PAGE_PUBLISHING_MESSAGE: string = '正在发布想法';
export const PIN_PAGE_PUBLISHED_MESSAGE: string = '想法已发布';
export const PIN_PAGE_CANCELLED_MESSAGE: string = '已取消编辑，未保存本次内容';

export enum PinPublishPagePhase {
  SETUP = 'setup',
  LOGIN_REQUIRED = 'login_required',
  EDITING = 'editing',
  PUBLISHED = 'published',
  RELEASED = 'released'
}

/** 页面状态中的提示固定生成，绝不透传正文或上游错误细节。 */
export interface PinPublishPageViewState {
  readonly phase: PinPublishPagePhase;
  readonly content: PinDraftContent;
  readonly operation: PinPublishOperation;
  readonly localDraftSaved: boolean;
  readonly canEdit: boolean;
  readonly canSaveDraft: boolean;
  readonly canPublish: boolean;
  readonly requiresLogin: boolean;
  readonly requiresSecurityVerification: boolean;
  readonly retryable: boolean;
  readonly topicSuggestions: Array<PinTopicSuggestion>;
  readonly publishedContentId?: string;
  readonly message: string;
}

export type PinPublishPageObserver = (state: PinPublishPageViewState) => void;
export type PinPublishPagePublishedCallback = (contentId: string) => void;

/**
 * 想法创作页的注入式协调器。它借鉴 EditorDraftController 的 activate/deactivate 门禁，
 * 但不再叠加一个 autosave 写入者：唯一草稿写入边界仍是 PinPublishController。
 * 因此访客、空内容及取消路径均不会进入 DraftRepository 或远端发布仓储。
 */
export class PinPublishPageController {
  private readonly session: LoginSessionGateway;
  private readonly publish: PinPublishController;
  private readonly observer: PinPublishPageObserver;
  private readonly onPublished: PinPublishPagePublishedCallback;
  private readonly imageUploaders: (() => PinPublishImageUploader) | undefined;
  private active: boolean = false;
  private phase: PinPublishPagePhase = PinPublishPagePhase.SETUP;
  private publishedNotified: boolean = false;

  constructor(repository: PinPublishRepository, drafts: DraftRepository, session: LoginSessionGateway,
    identity: ContentDraftIdentity, traceIds: PinPublishTraceIdFactory, scheduler: PinTopicSearchScheduler,
    observer: PinPublishPageObserver = (_state: PinPublishPageViewState): void => {},
    onPublished: PinPublishPagePublishedCallback = (_contentId: string): void => {},
    imageUploaders: (() => PinPublishImageUploader) | undefined = undefined) {
    this.session = session;
    this.observer = observer;
    this.onPublished = onPublished;
    this.imageUploaders = imageUploaders;
    this.publish = new PinPublishController(repository, drafts, identity, traceIds, scheduler,
      (state: PinPublishViewState): void => this.handlePublishState(state));
  }

  activate(): void {
    if (this.active || this.phase === PinPublishPagePhase.RELEASED) {
      return;
    }
    this.active = true;
    if (!this.requireAuthenticatedSession()) {
      return;
    }
    this.phase = PinPublishPagePhase.EDITING;
    this.publish.activate();
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.publish.deactivate();
    this.active = false;
    this.phase = PinPublishPagePhase.RELEASED;
    this.emit();
  }

  cancel(): void {
    this.deactivate();
  }

  updateTitle(title: string): void {
    if (!this.canWrite()) {
      return;
    }
    const content = this.publish.snapshot().content;
    this.publish.replaceContent({ title: title, html: content.html, images: content.images,
      localImageReferences: content.localImageReferences, topics: content.topics });
  }

  updateHtml(html: string): void {
    if (!this.canWrite()) {
      return;
    }
    const content = this.publish.snapshot().content;
    this.publish.replaceContent({ title: content.title, html: html, images: content.images,
      localImageReferences: content.localImageReferences, topics: content.topics });
  }

  replaceImages(images: Array<UploadedZhihuImage>): void {
    if (!this.canWrite()) {
      return;
    }
    const content = this.publish.snapshot().content;
    this.publish.replaceContent({ title: content.title, html: content.html, images: images,
      localImageReferences: content.localImageReferences, topics: content.topics });
  }

  replaceLocalImageReferences(references: Array<LocalDraftImageReference>): void {
    if (!this.canWrite()) {
      return;
    }
    this.publish.replaceLocalImageReferences(references);
  }

  requestTopicSuggestions(query: string): void {
    if (!this.canWrite()) {
      return;
    }
    this.publish.requestTopicSuggestions(query);
  }

  selectTopic(topic: PublishPinTopic): void {
    if (!this.canWrite()) {
      return;
    }
    this.publish.selectTopic(topic);
  }

  removeTopic(topicId: string): void {
    if (!this.canWrite()) {
      return;
    }
    this.publish.removeTopic(topicId);
  }

  async saveLocalDraft(): Promise<void> {
    if (!this.canWrite()) {
      return;
    }
    await this.publish.saveLocalDraft();
  }

  async publishPin(): Promise<void> {
    if (!this.canWrite()) {
      return;
    }
    const references = this.publish.snapshot().content.localImageReferences;
    if (references.length > 0) {
      const factory = this.imageUploaders;
      if (factory === undefined) {
        await this.publish.saveLocalDraft();
        return;
      }
      let uploader: PinPublishImageUploader;
      try {
        uploader = factory();
      } catch (_error) {
        return;
      }
      if (!await this.publish.uploadLocalImages(uploader)) {
        return;
      }
    }
    await this.publish.publish();
  }

  snapshot(): PinPublishPageViewState {
    const publish = this.publish.snapshot();
    const released = this.phase === PinPublishPagePhase.RELEASED;
    const requiresLogin = this.phase === PinPublishPagePhase.LOGIN_REQUIRED;
    const canEdit = this.active && this.phase === PinPublishPagePhase.EDITING && !isBusy(publish.operation);
    return {
      phase: this.phase,
      content: released ? emptyContent() : cloneContent(publish.content),
      operation: publish.operation,
      localDraftSaved: publish.localDraftSaved,
      canEdit: canEdit,
      canSaveDraft: canEdit && hasContent(publish.content),
      canPublish: canEdit && hasContent(publish.content),
      requiresLogin: requiresLogin || publish.requiresLogin,
      requiresSecurityVerification: publish.requiresSecurityVerification,
      retryable: publish.retryable,
      topicSuggestions: cloneSuggestions(publish.topicSearch.suggestions),
      publishedContentId: publish.publishedContentId,
      message: this.messageFor(publish, requiresLogin)
    };
  }

  private canWrite(): boolean {
    if (!this.active || this.phase !== PinPublishPagePhase.EDITING) {
      return false;
    }
    return this.requireAuthenticatedSession();
  }

  private requireAuthenticatedSession(): boolean {
    if (this.session.getState().status === SessionStatus.AUTHENTICATED) {
      return true;
    }
    this.phase = PinPublishPagePhase.LOGIN_REQUIRED;
    this.emit();
    return false;
  }

  private handlePublishState(state: PinPublishViewState): void {
    if (!this.active) {
      return;
    }
    if (state.operation === PinPublishOperation.PUBLISHED) {
      this.phase = PinPublishPagePhase.PUBLISHED;
      if (!this.publishedNotified && state.publishedContentId !== undefined) {
        this.publishedNotified = true;
        this.onPublished(state.publishedContentId);
      }
    } else if (this.phase !== PinPublishPagePhase.LOGIN_REQUIRED) {
      this.phase = PinPublishPagePhase.EDITING;
    }
    this.emit();
  }

  private messageFor(publish: PinPublishViewState, requiresLogin: boolean): string {
    if (this.phase === PinPublishPagePhase.RELEASED) {
      return PIN_PAGE_CANCELLED_MESSAGE;
    }
    if (requiresLogin || publish.requiresLogin) {
      return PIN_PAGE_LOGIN_REQUIRED_MESSAGE;
    }
    if (publish.operation === PinPublishOperation.SAVING_LOCAL ||
      publish.operation === PinPublishOperation.SAVING_REMOTE_DRAFT) {
      return PIN_PAGE_SAVING_MESSAGE;
    }
    if (publish.operation === PinPublishOperation.UPLOADING_IMAGES) {
      return PIN_PAGE_UPLOADING_IMAGES_MESSAGE;
    }
    if (publish.operation === PinPublishOperation.PUBLISHING) {
      return PIN_PAGE_PUBLISHING_MESSAGE;
    }
    if (publish.operation === PinPublishOperation.PUBLISHED) {
      return PIN_PAGE_PUBLISHED_MESSAGE;
    }
    if (publish.errorMessage !== undefined) {
      return publish.requiresSecurityVerification ? '发布需要完成安全验证，草稿已保留' :
        publish.retryable ? '发布失败，草稿已保留，可稍后重试' : '请检查内容后重试，草稿已保留';
    }
    return PIN_PAGE_READY_MESSAGE;
  }

  private emit(): void {
    this.observer(this.snapshot());
  }
}

function isBusy(operation: PinPublishOperation): boolean {
  return operation === PinPublishOperation.SAVING_LOCAL ||
    operation === PinPublishOperation.UPLOADING_IMAGES ||
    operation === PinPublishOperation.SAVING_REMOTE_DRAFT || operation === PinPublishOperation.PUBLISHING;
}

function hasContent(content: PinDraftContent): boolean {
  return content.title.trim().length > 0 || content.html.trim().length > 0 || content.images.length > 0 ||
    content.localImageReferences.length > 0;
}

function emptyContent(): PinDraftContent {
  return { title: '', html: '', images: [], localImageReferences: [], topics: [] };
}

function cloneContent(content: PinDraftContent): PinDraftContent {
  return {
    title: content.title,
    html: content.html,
    images: content.images.map((image: UploadedZhihuImage): UploadedZhihuImage => ({
      imageId: image.imageId,
      url: image.url,
      originalUrl: image.originalUrl,
      width: image.width,
      height: image.height,
      watermark: image.watermark,
      watermarkUrl: image.watermarkUrl
    })),
    localImageReferences: content.localImageReferences.map((reference: LocalDraftImageReference): LocalDraftImageReference => ({
      fileName: reference.fileName,
      mimeType: reference.mimeType,
      byteLength: reference.byteLength,
      width: reference.width,
      height: reference.height,
      animated: reference.animated,
      createdAtMillis: reference.createdAtMillis
    })),
    topics: content.topics.map((topic: PublishPinTopic): PublishPinTopic => ({
      topicId: topic.topicId,
      displayName: topic.displayName
    }))
  };
}

function cloneSuggestions(suggestions: Array<PinTopicSuggestion>): Array<PinTopicSuggestion> {
  return suggestions.map((topic: PinTopicSuggestion): PinTopicSuggestion => ({
    topicId: topic.topicId,
    displayName: topic.displayName,
    discussCount: topic.discussCount
  }));
}
