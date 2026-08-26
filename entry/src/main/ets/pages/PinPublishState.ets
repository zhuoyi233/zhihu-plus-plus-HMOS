import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftSaveInput,
  buildPinPublishRequest,
  DraftRepository,
  ImageUploadFailure,
  ImageUploadFailureKind,
  isSafeUploadedZhihuImage,
  MAX_PIN_IMAGE_COUNT,
  MAX_PIN_TOPIC_COUNT,
  LocalDraftImageReference,
  PinPublishInput,
  PinPublishRepository,
  PinTopicSuggestion,
  PublishFailure,
  PublishFailureKind,
  PublishPinTopic,
  parseLocalDraftImageReferences,
  serializeLocalDraftImageReferences,
  toPublishFailure,
  UploadedZhihuImage
} from 'data';
import { isSafeDecimalContentId } from 'core';

export const PIN_TOPIC_SEARCH_DEBOUNCE_MS: number = 350;
export const MAX_PIN_TOPIC_SUGGESTION_COUNT: number = 20;
export const PIN_EMPTY_CONTENT_MESSAGE: string = '请先填写标题、正文或添加图片';
export const PIN_TOPIC_LOOKUP_FAILED_MESSAGE: string = '话题建议暂不可用，可继续编辑并稍后重试';

export enum PinPublishOperation {
  IDLE = 'idle',
  SAVING_LOCAL = 'saving_local',
  UPLOADING_IMAGES = 'uploading_images',
  SAVING_REMOTE_DRAFT = 'saving_remote_draft',
  PUBLISHING = 'publishing',
  PUBLISHED = 'published',
  ERROR = 'error'
}

export interface PinDraftContent {
  readonly title: string;
  readonly html: string;
  readonly images: Array<UploadedZhihuImage>;
  /** 尚未上传的应用受控缓存引用；不传给远端发布合同。 */
  readonly localImageReferences: Array<LocalDraftImageReference>;
  readonly topics: Array<PublishPinTopic>;
}

export interface PinTopicSearchViewState {
  readonly query: string;
  readonly pending: boolean;
  readonly suggestions: Array<PinTopicSuggestion>;
  readonly errorMessage?: string;
}

export interface PinPublishViewState {
  readonly content: PinDraftContent;
  readonly operation: PinPublishOperation;
  readonly localDraftSaved: boolean;
  readonly remoteDraftSaved: boolean;
  readonly publishedContentId?: string;
  readonly failureKind?: PublishFailureKind;
  readonly errorMessage?: string;
  readonly requiresLogin: boolean;
  readonly requiresSecurityVerification: boolean;
  readonly retryable: boolean;
  readonly topicSearch: PinTopicSearchViewState;
}

export interface PinPublishTraceIdFactory {
  createTraceId(): string;
}

/** 最终确认后才由页面注入；发布状态机不读取路径、文件或会话。 */
export interface PinPublishImageUploader {
  upload(references: Array<LocalDraftImageReference>): Promise<Array<UploadedZhihuImage>>;
  cancel(): void;
}

/**
 * 平台层可以用 setTimeout/clearTimeout 实现；测试通过 fake scheduler 精确推进防抖。
 * 返回值只在当前 scheduler 内使用，避免把定时器句柄泄漏给页面。
 */
export interface PinTopicSearchScheduler {
  schedule(delayMs: number, callback: () => void): number;
  cancel(handle: number): void;
}

export type PinPublishObserver = (state: PinPublishViewState) => void;

/**
 * 新想法发布编排。它不拼接发布 URL 或 Cookie，并且绝不把 HTML、图片 URL 或上游错误文本写入状态。
 * 发布前总是先安全落本地草稿；远端草稿和正式发布的失败都只更新可恢复的视图状态。
 */
export class PinPublishController {
  private readonly repository: PinPublishRepository;
  private readonly drafts: DraftRepository;
  private readonly identity: ContentDraftIdentity;
  private readonly traceIds: PinPublishTraceIdFactory;
  private readonly scheduler: PinTopicSearchScheduler;
  private readonly observer: PinPublishObserver;
  private active: boolean = false;
  private content: PinDraftContent = emptyPinDraftContent();
  private operation: PinPublishOperation = PinPublishOperation.IDLE;
  private localDraftSaved: boolean = false;
  private remoteDraftSaved: boolean = false;
  private publishedContentId?: string;
  private failure?: PublishFailure;
  private topicQuery: string = '';
  private topicPending: boolean = false;
  private topicSuggestions: Array<PinTopicSuggestion> = [];
  private topicErrorMessage?: string;
  private topicSearchGeneration: number = 0;
  private scheduledTopicSearch?: number;
  private activeImageUploader?: PinPublishImageUploader;

  constructor(repository: PinPublishRepository, drafts: DraftRepository, identity: ContentDraftIdentity,
    traceIds: PinPublishTraceIdFactory, scheduler: PinTopicSearchScheduler,
    observer: PinPublishObserver = (_state: PinPublishViewState): void => {
    }) {
    if (identity.kind !== ContentDraftKind.PIN) {
      throw new Error('Pin publishing requires a pin draft identity');
    }
    this.repository = repository;
    this.drafts = drafts;
    this.identity = identity;
    this.traceIds = traceIds;
    this.scheduler = scheduler;
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
    this.cancelScheduledTopicSearch();
    this.topicSearchGeneration += 1;
    this.topicPending = false;
    this.activeImageUploader?.cancel();
    this.activeImageUploader = undefined;
    this.repository.cancel();
  }

  snapshot(): PinPublishViewState {
    const failure = this.failure;
    return {
      content: clonePinDraftContent(this.content),
      operation: this.operation,
      localDraftSaved: this.localDraftSaved,
      remoteDraftSaved: this.remoteDraftSaved,
      publishedContentId: this.publishedContentId,
      failureKind: failure?.kind,
      errorMessage: failure?.message,
      requiresLogin: failure?.kind === PublishFailureKind.AUTHENTICATION,
      requiresSecurityVerification: failure?.kind === PublishFailureKind.FORBIDDEN,
      retryable: failure?.retryable ?? false,
      topicSearch: {
        query: this.topicQuery,
        pending: this.topicPending,
        suggestions: cloneTopicSuggestions(this.topicSuggestions),
        errorMessage: this.topicErrorMessage
      }
    };
  }

  replaceContent(content: PinDraftContent): void {
    if (!this.active || this.isBusy()) {
      return;
    }
    this.content = normalizePinDraftContent(content);
    this.localDraftSaved = false;
    this.remoteDraftSaved = false;
    this.publishedContentId = undefined;
    this.operation = PinPublishOperation.IDLE;
    this.failure = undefined;
    this.emit();
  }

  /** 本地引用只进入 DraftRepository；上传必须由最终发布确认后的专用网关接管。 */
  replaceLocalImageReferences(references: Array<LocalDraftImageReference>): void {
    if (!this.active || this.isBusy()) {
      return;
    }
    this.replaceContent({
      title: this.content.title,
      html: this.content.html,
      images: this.content.images,
      localImageReferences: normalizeLocalImageReferences(references),
      topics: this.content.topics
    });
  }

  selectTopic(topic: PublishPinTopic): void {
    if (!this.active || this.isBusy() || this.content.topics.some((item: PublishPinTopic): boolean => item.topicId === topic.topicId)) {
      return;
    }
    const topics = this.content.topics.concat([cloneTopic(topic)]);
    this.replaceContent({
      title: this.content.title,
      html: this.content.html,
      images: this.content.images,
      localImageReferences: this.content.localImageReferences,
      topics: topics
    });
  }

  removeTopic(topicId: string): void {
    if (!this.active || this.isBusy()) {
      return;
    }
    const topics = this.content.topics.filter((item: PublishPinTopic): boolean => item.topicId !== topicId);
    if (topics.length === this.content.topics.length) {
      return;
    }
    this.replaceContent({
      title: this.content.title,
      html: this.content.html,
      images: this.content.images,
      localImageReferences: this.content.localImageReferences,
      topics: topics
    });
  }

  async saveLocalDraft(): Promise<void> {
    if (!this.active || this.isBusy()) {
      return;
    }
    if (!hasDraftContent(this.content)) {
      this.fail(new PublishFailure(PublishFailureKind.INVALID_INPUT), PIN_EMPTY_CONTENT_MESSAGE);
      return;
    }
    this.operation = PinPublishOperation.SAVING_LOCAL;
    this.failure = undefined;
    this.emit();
    try {
      await this.drafts.save(this.toDraftSaveInput());
      if (!this.active) {
        return;
      }
      this.localDraftSaved = true;
      this.operation = PinPublishOperation.IDLE;
      this.emit();
    } catch (error) {
      if (!this.active) {
        return;
      }
      this.fail(toPublishFailure(error));
    }
  }

  async saveRemoteDraft(): Promise<void> {
    if (!this.active || this.isBusy()) {
      return;
    }
    const input = this.createPublishInput();
    if (input === undefined) {
      this.fail(new PublishFailure(PublishFailureKind.INVALID_INPUT), PIN_EMPTY_CONTENT_MESSAGE);
      return;
    }
    if (!await this.ensureLocalDraftSaved(input)) {
      return;
    }
    this.operation = PinPublishOperation.SAVING_REMOTE_DRAFT;
    this.failure = undefined;
    this.emit();
    try {
      await this.repository.saveRemoteDraft(input);
      if (!this.active) {
        return;
      }
      this.remoteDraftSaved = true;
      this.operation = PinPublishOperation.IDLE;
      this.emit();
    } catch (error) {
      if (!this.active) {
        return;
      }
      this.fail(toPublishFailure(error));
    }
  }

  /**
   * 发布前先把未上传图片引用写入本地加密草稿，再上传并以受验证的知乎图片替换引用。
   * 任一上传失败均不触发远端草稿/发布，用户可在原草稿上重试。
   */
  async uploadLocalImages(uploader: PinPublishImageUploader): Promise<boolean> {
    if (!this.active || this.isBusy()) {
      return false;
    }
    const references = this.content.localImageReferences;
    if (references.length === 0) {
      return true;
    }
    if (!hasDraftContent(this.content) || this.content.images.length + references.length > MAX_PIN_IMAGE_COUNT) {
      this.fail(new PublishFailure(PublishFailureKind.INVALID_INPUT), PIN_EMPTY_CONTENT_MESSAGE);
      return false;
    }
    this.operation = PinPublishOperation.SAVING_LOCAL;
    this.failure = undefined;
    this.emit();
    try {
      await this.drafts.save(this.toDraftSaveInput());
      if (!this.active) {
        return false;
      }
      this.localDraftSaved = true;
      this.operation = PinPublishOperation.UPLOADING_IMAGES;
      this.activeImageUploader = uploader;
      this.emit();
      const uploaded = await uploader.upload(references);
      if (!this.active) {
        return false;
      }
      if (uploaded.length !== references.length || !uploaded.every((image: UploadedZhihuImage): boolean =>
        isSafeUploadedZhihuImage(image))) {
        throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
      }
      this.content = normalizePinDraftContent({
        title: this.content.title,
        html: this.content.html,
        images: this.content.images.concat(uploaded),
        localImageReferences: [],
        topics: this.content.topics
      });
      this.localDraftSaved = false;
      this.remoteDraftSaved = false;
      this.operation = PinPublishOperation.IDLE;
      this.failure = undefined;
      this.emit();
      return true;
    } catch (error) {
      if (this.active) {
        this.fail(toAttachmentPublishFailure(error));
      }
      return false;
    } finally {
      if (this.activeImageUploader === uploader) {
        this.activeImageUploader = undefined;
      }
    }
  }

  async publish(): Promise<void> {
    if (!this.active || this.isBusy()) {
      return;
    }
    const input = this.createPublishInput();
    if (input === undefined) {
      this.fail(new PublishFailure(PublishFailureKind.INVALID_INPUT), PIN_EMPTY_CONTENT_MESSAGE);
      return;
    }
    if (!await this.ensureLocalDraftSaved(input)) {
      return;
    }
    this.operation = PinPublishOperation.SAVING_REMOTE_DRAFT;
    this.failure = undefined;
    this.emit();
    try {
      await this.repository.saveRemoteDraft(input);
      if (!this.active) {
        return;
      }
      this.remoteDraftSaved = true;
      this.operation = PinPublishOperation.PUBLISHING;
      this.emit();
      const publishedId = await this.repository.publish(input);
      if (!this.active) {
        return;
      }
      if (!isSafeDecimalContentId(publishedId)) {
        this.fail(new PublishFailure(PublishFailureKind.SERVER));
        return;
      }
      await this.drafts.save(this.toDraftSaveInput(input, publishedId, false));
      if (!this.active) {
        return;
      }
      this.localDraftSaved = true;
      this.publishedContentId = publishedId;
      this.failure = undefined;
      this.operation = PinPublishOperation.PUBLISHED;
      this.emit();
    } catch (error) {
      if (!this.active) {
        return;
      }
      this.fail(toPublishFailure(error));
    }
  }

  requestTopicSuggestions(query: string): void {
    if (!this.active || this.isBusy()) {
      return;
    }
    this.cancelScheduledTopicSearch();
    this.topicSearchGeneration += 1;
    const generation = this.topicSearchGeneration;
    this.topicQuery = query;
    this.topicErrorMessage = undefined;
    if (query.trim().length === 0) {
      this.topicPending = false;
      this.topicSuggestions = [];
      this.repository.cancel();
      this.emit();
      return;
    }
    this.topicPending = true;
    this.scheduledTopicSearch = this.scheduler.schedule(PIN_TOPIC_SEARCH_DEBOUNCE_MS, (): void => {
      this.scheduledTopicSearch = undefined;
      void this.fetchTopicSuggestions(query, generation);
    });
    this.emit();
  }

  cancelTopicSuggestions(): void {
    if (!this.active) {
      return;
    }
    this.cancelScheduledTopicSearch();
    this.topicSearchGeneration += 1;
    this.topicPending = false;
    this.topicQuery = '';
    this.topicSuggestions = [];
    this.topicErrorMessage = undefined;
    this.repository.cancel();
    this.emit();
  }

  private async ensureLocalDraftSaved(input: PinPublishInput): Promise<boolean> {
    this.operation = PinPublishOperation.SAVING_LOCAL;
    this.failure = undefined;
    this.emit();
    try {
      await this.drafts.save(this.toDraftSaveInput(input));
      if (!this.active) {
        return false;
      }
      this.localDraftSaved = true;
      return true;
    } catch (error) {
      if (this.active) {
        this.fail(toPublishFailure(error));
      }
      return false;
    }
  }

  private async fetchTopicSuggestions(query: string, generation: number): Promise<void> {
    try {
      const suggestions = await this.repository.recommendTopics(query, this.content.title, this.content.html);
      if (!this.active || generation !== this.topicSearchGeneration) {
        return;
      }
      this.topicPending = false;
      this.topicSuggestions = boundAndDedupeSuggestions(suggestions);
      this.topicErrorMessage = undefined;
      this.emit();
    } catch (_error) {
      if (!this.active || generation !== this.topicSearchGeneration) {
        return;
      }
      this.topicPending = false;
      this.topicErrorMessage = PIN_TOPIC_LOOKUP_FAILED_MESSAGE;
      this.emit();
    }
  }

  private createPublishInput(): PinPublishInput | undefined {
    const input: PinPublishInput = {
      title: this.content.title,
      html: this.content.html,
      textLength: plainTextLength(this.content.html),
      images: cloneImages(this.content.images),
      topics: cloneTopics(this.content.topics),
      traceId: this.traceIds.createTraceId()
    };
    try {
      // 复用 data 合同校验空内容、话题、图片与 traceId；页面不拥有发布 body。
      if (input.title.trim().length === 0 && input.html.trim().length === 0 && input.images.length === 0) {
        return undefined;
      }
      buildPinPublishRequest(input);
      return input;
    } catch (_error) {
      return undefined;
    }
  }

  private toDraftSaveInput(input?: PinPublishInput, remoteContentId?: string,
    dirty: boolean = true): ContentDraftSaveInput {
    return {
      draftKey: this.identity.draftKey,
      accountKey: this.identity.accountKey,
      kind: this.identity.kind,
      targetId: this.identity.targetId,
      html: input?.html ?? this.content.html,
      remoteContentId: remoteContentId,
      title: input?.title ?? this.content.title,
      plainTextLength: input?.textLength ?? plainTextLength(this.content.html),
      tocEnabled: false,
      imageRefsJson: serializeDraftImageReferences(input?.images ?? this.content.images,
        this.content.localImageReferences),
      topicRefsJson: JSON.stringify(input?.topics ?? this.content.topics),
      dirty: dirty
    };
  }

  private isBusy(): boolean {
    return this.operation === PinPublishOperation.SAVING_LOCAL ||
      this.operation === PinPublishOperation.UPLOADING_IMAGES ||
      this.operation === PinPublishOperation.SAVING_REMOTE_DRAFT ||
      this.operation === PinPublishOperation.PUBLISHING;
  }

  private fail(failure: PublishFailure, message?: string): void {
    this.failure = message === undefined ? failure : new PinPublishMessageFailure(failure.kind, message);
    this.operation = PinPublishOperation.ERROR;
    this.emit();
  }

  private cancelScheduledTopicSearch(): void {
    if (this.scheduledTopicSearch !== undefined) {
      this.scheduler.cancel(this.scheduledTopicSearch);
      this.scheduledTopicSearch = undefined;
    }
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

class PinPublishMessageFailure extends PublishFailure {
  constructor(kind: PublishFailureKind, message: string) {
    super(kind);
    this.message = message;
  }
}

function emptyPinDraftContent(): PinDraftContent {
  return { title: '', html: '', images: [], localImageReferences: [], topics: [] };
}

function normalizePinDraftContent(content: PinDraftContent): PinDraftContent {
  return {
    title: content.title,
    html: content.html,
    images: cloneImages(content.images),
    localImageReferences: normalizeLocalImageReferences(content.localImageReferences),
    topics: dedupeTopics(content.topics)
  };
}

function clonePinDraftContent(content: PinDraftContent): PinDraftContent {
  return normalizePinDraftContent(content);
}

function cloneImages(images: Array<UploadedZhihuImage>): Array<UploadedZhihuImage> {
  return images.map((image: UploadedZhihuImage): UploadedZhihuImage => ({
    imageId: image.imageId,
    url: image.url,
    originalUrl: image.originalUrl,
    width: image.width,
    height: image.height,
    watermark: image.watermark,
    watermarkUrl: image.watermarkUrl
  }));
}

function normalizeLocalImageReferences(references: Array<LocalDraftImageReference>): Array<LocalDraftImageReference> {
  try {
    return parseLocalDraftImageReferences(serializeLocalDraftImageReferences(references));
  } catch (_error) {
    return [];
  }
}

function serializeDraftImageReferences(images: Array<UploadedZhihuImage>,
  localReferences: Array<LocalDraftImageReference>): string {
  const uploaded = JSON.stringify(cloneImages(images));
  const local = serializeLocalDraftImageReferences(localReferences);
  if (images.length === 0) {
    return local;
  }
  if (localReferences.length === 0) {
    return uploaded;
  }
  return uploaded.substring(0, uploaded.length - 1) + ',' + local.substring(1);
}

function hasDraftContent(content: PinDraftContent): boolean {
  return content.title.trim().length > 0 || content.html.trim().length > 0 || content.images.length > 0 ||
    content.localImageReferences.length > 0;
}

function cloneTopic(topic: PublishPinTopic): PublishPinTopic {
  return { topicId: topic.topicId, displayName: topic.displayName };
}

function cloneTopics(topics: Array<PublishPinTopic>): Array<PublishPinTopic> {
  return topics.map((topic: PublishPinTopic): PublishPinTopic => cloneTopic(topic));
}

function dedupeTopics(topics: Array<PublishPinTopic>): Array<PublishPinTopic> {
  const result: Array<PublishPinTopic> = [];
  topics.forEach((topic: PublishPinTopic): void => {
    if (result.length < MAX_PIN_TOPIC_COUNT && !result.some((item: PublishPinTopic): boolean => item.topicId === topic.topicId)) {
      result.push(cloneTopic(topic));
    }
  });
  return result;
}

function cloneTopicSuggestions(suggestions: Array<PinTopicSuggestion>): Array<PinTopicSuggestion> {
  return suggestions.map((suggestion: PinTopicSuggestion): PinTopicSuggestion => ({
    topicId: suggestion.topicId,
    displayName: suggestion.displayName,
    discussCount: suggestion.discussCount
  }));
}

function boundAndDedupeSuggestions(suggestions: Array<PinTopicSuggestion>): Array<PinTopicSuggestion> {
  const result: Array<PinTopicSuggestion> = [];
  suggestions.forEach((suggestion: PinTopicSuggestion): void => {
    if (result.length < MAX_PIN_TOPIC_SUGGESTION_COUNT && isSafeDecimalContentId(suggestion.topicId) &&
      !result.some((item: PinTopicSuggestion): boolean => item.topicId === suggestion.topicId)) {
      result.push({
        topicId: suggestion.topicId,
        displayName: suggestion.displayName,
        discussCount: suggestion.discussCount
      });
    }
  });
  return result;
}

function plainTextLength(html: string): number {
  const withoutTags = html.replace(/<[^>]*>/g, '').replace(/&(?:#(?:x[0-9a-fA-F]+|[0-9]+)|[a-zA-Z][a-zA-Z0-9]+);/g, ' ');
  return Array.from(withoutTags).length;
}

function toAttachmentPublishFailure(error: Object): PublishFailure {
  if (!(error instanceof ImageUploadFailure)) {
    return toPublishFailure(error);
  }
  if (error.kind === ImageUploadFailureKind.AUTHENTICATION) return new PublishFailure(PublishFailureKind.AUTHENTICATION);
  if (error.kind === ImageUploadFailureKind.FORBIDDEN) return new PublishFailure(PublishFailureKind.FORBIDDEN);
  if (error.kind === ImageUploadFailureKind.RATE_LIMITED) return new PublishFailure(PublishFailureKind.RATE_LIMITED);
  if (error.kind === ImageUploadFailureKind.TIMEOUT || error.kind === ImageUploadFailureKind.POLL_TIMEOUT) {
    return new PublishFailure(PublishFailureKind.TIMEOUT);
  }
  if (error.kind === ImageUploadFailureKind.CANCELLED) return new PublishFailure(PublishFailureKind.CANCELLED);
  if (error.kind === ImageUploadFailureKind.SERVER) return new PublishFailure(PublishFailureKind.SERVER);
  if (error.kind === ImageUploadFailureKind.NETWORK) return new PublishFailure(PublishFailureKind.NETWORK);
  return new PublishFailure(PublishFailureKind.INVALID_INPUT);
}
