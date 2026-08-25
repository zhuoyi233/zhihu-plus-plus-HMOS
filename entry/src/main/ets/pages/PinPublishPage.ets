import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftMetadata,
  createPinDraftIdentity,
  DraftRepository,
  hashDraftAccountId,
  LoginSessionGateway,
  PinPublishInput,
  PinPublishRepository,
  PinTopicSuggestion,
  PublishFailure,
  PublishFailureKind,
  PublishPinTopic,
  SessionStatus
} from 'data';
import {
  PinPublishOperation,
  PinPublishTraceIdFactory,
  PinTopicSearchScheduler
} from './PinPublishState';
import {
  PinPublishPageController,
  PinPublishPagePhase,
  PinPublishPageViewState
} from './PinPublishPageState';
import { isSafeLocalDraftId } from 'core';

export type PinPublishPageBackCallback = () => void;
export type PinPublishPageLoginCallback = () => void;
export type PinPublishPagePublishedCallback = (contentId: string) => void;

/** 已解析的发布页依赖；组合根在认证完成后才创建，避免游客态接触草稿或发布仓储。 */
export interface PinPublishPageConfiguration {
  readonly repository: PinPublishRepository;
  readonly drafts: DraftRepository;
  readonly session: LoginSessionGateway;
  readonly identity: ContentDraftIdentity;
  readonly traceIds: PinPublishTraceIdFactory;
  readonly topicScheduler: PinTopicSearchScheduler;
}

/** 用 draftId 延迟构造依赖，保证路由参数不会承载账号信息、Cookie 或正文。 */
export interface PinPublishPageConfigurationFactory {
  create(draftId: string): Promise<PinPublishPageConfiguration | undefined>;
}

/** 每个想法编辑页创建独立仓储，避免跨页面取消请求。 */
export type PinPublishRepositoryFactory = () => PinPublishRepository;

export const MAX_PIN_DRAFT_RESUME_COUNT: number = 100;

/** 草稿箱只展示加密正文之外的最少恢复元数据。 */
export interface PinDraftResumeItem {
  readonly draftId: string;
  readonly title: string;
  readonly updatedAt: number;
}

export interface PinDraftResumeListGateway {
  listResumeItems(): Promise<Array<PinDraftResumeItem>>;
}

/** API 26 组合根可注入生产仓储；默认值保持本地草稿模式，供单测与受限场景使用。 */
export class LocalDraftPinPublishPageConfigurationFactory implements PinPublishPageConfigurationFactory,
  PinDraftResumeListGateway {
  private readonly session: LoginSessionGateway;
  private readonly drafts: DraftRepository;
  private readonly repositories: PinPublishRepositoryFactory;

  constructor(session: LoginSessionGateway, drafts: DraftRepository,
    repositories: PinPublishRepositoryFactory = (): PinPublishRepository => new LocalDraftOnlyPinPublishRepository()) {
    this.session = session;
    this.drafts = drafts;
    this.repositories = repositories;
  }

  async create(draftId: string): Promise<PinPublishPageConfiguration | undefined> {
    const accountKey = await this.resolveAccountKey();
    if (accountKey === undefined) {
      return undefined;
    }
    try {
      return {
        repository: this.repositories(),
        drafts: this.drafts,
        session: this.session,
        identity: createPinDraftIdentity(accountKey, draftId),
        traceIds: new SystemPinPublishTraceIdFactory(),
        topicScheduler: new SystemPinTopicSearchScheduler()
      };
    } catch (_error) {
      return undefined;
    }
  }

  async listResumeItems(): Promise<Array<PinDraftResumeItem>> {
    const accountKey = await this.resolveAccountKey();
    if (accountKey === undefined) {
      return [];
    }
    try {
      const metadata = await this.drafts.listMetadataForAccount(accountKey);
      const result: Array<PinDraftResumeItem> = [];
      metadata.forEach((item: ContentDraftMetadata): void => {
        if (item.kind !== ContentDraftKind.PIN || !item.dirty || !isSafeLocalDraftId(item.targetId)) {
          return;
        }
        result.push({
          draftId: item.targetId,
          title: item.title.trim().length === 0 ? '未命名想法' : item.title,
          updatedAt: item.updatedAt
        });
      });
      result.sort((first: PinDraftResumeItem, second: PinDraftResumeItem): number => second.updatedAt - first.updatedAt);
      return result.slice(0, MAX_PIN_DRAFT_RESUME_COUNT);
    } catch (_error) {
      return [];
    }
  }

  private async resolveAccountKey(): Promise<string | undefined> {
    const state = this.session.getState();
    const profile = state.profile;
    if (state.status !== SessionStatus.AUTHENTICATED || profile === undefined) {
      return undefined;
    }
    try {
      return await hashDraftAccountId(profile.id);
    } catch (_error) {
      return undefined;
    }
  }
}

/** 不含 HTTP 客户端的默认实现，绝不读取 Cookie，也不向知乎发送任何请求。 */
export class LocalDraftOnlyPinPublishRepository implements PinPublishRepository {
  recommendTopics(_query: string, _title: string, _contentHtml: string): Promise<Array<PinTopicSuggestion>> {
    return Promise.resolve([]);
  }

  saveRemoteDraft(_input: PinPublishInput): Promise<void> {
    return Promise.reject(new PublishFailure(PublishFailureKind.SERVER));
  }

  publish(_input: PinPublishInput): Promise<string> {
    return Promise.reject(new PublishFailure(PublishFailureKind.SERVER));
  }

  cancel(): void {
  }
}

export class SystemPinPublishTraceIdFactory implements PinPublishTraceIdFactory {
  createTraceId(): string {
    const timestamp = Math.max(1, Math.floor(Date.now()));
    return `${timestamp},${randomHex(8)}-${randomHex(4)}-4${randomHex(3)}-8${randomHex(3)}-${randomHex(12)}`;
  }
}

export class SystemPinTopicSearchScheduler implements PinTopicSearchScheduler {
  schedule(delayMs: number, callback: () => void): number {
    return setTimeout(callback, delayMs) as number;
  }

  cancel(handle: number): void {
    clearTimeout(handle);
  }
}

/**
 * 可注入的想法创作页。它不注册目的地，也不创建网络仓储；组合根在准备好账号、草稿和发布依赖后
 * 才能嵌入本页。离开只取消，不暗中保存；正文只绑定编辑控件和加密草稿边界。
 */
@Component
export struct PinPublishPage {
  /** 仅用于 factory 模式；必须是经 P1Destination 校验的本地 UUID。 */
  draftId: string = '';
  configurationFactory: PinPublishPageConfigurationFactory | undefined = undefined;
  repository: PinPublishRepository | undefined = undefined;
  drafts: DraftRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  identity: ContentDraftIdentity | undefined = undefined;
  traceIds: PinPublishTraceIdFactory | undefined = undefined;
  topicScheduler: PinTopicSearchScheduler | undefined = undefined;
  onBack: PinPublishPageBackCallback = (): void => {};
  onLoginRequired: PinPublishPageLoginCallback = (): void => {};
  onPublished: PinPublishPagePublishedCallback = (_contentId: string): void => {};
  @State private viewState: PinPublishPageViewState = initialViewState();
  @State private topicQuery: string = '';
  @State private publishConfirmationVisible: boolean = false;
  private controller: PinPublishPageController | undefined = undefined;
  private configurationGeneration: number = 0;

  aboutToAppear(): void {
    if (this.controller !== undefined) {
      return;
    }
    const factory = this.configurationFactory;
    if (factory !== undefined) {
      this.prepareFromFactory(factory);
      return;
    }
    this.prepareDirectConfiguration();
  }

  private prepareDirectConfiguration(): void {
    if (this.repository === undefined || this.drafts === undefined || this.session === undefined ||
      this.identity === undefined || this.traceIds === undefined || this.topicScheduler === undefined) {
      this.viewState = configurationFailureState();
      return;
    }
    this.installConfiguration({
      repository: this.repository,
      drafts: this.drafts,
      session: this.session,
      identity: this.identity,
      traceIds: this.traceIds,
      topicScheduler: this.topicScheduler
    });
  }

  private prepareFromFactory(factory: PinPublishPageConfigurationFactory): void {
    const generation = this.configurationGeneration + 1;
    this.configurationGeneration = generation;
    factory.create(this.draftId).then((configuration: PinPublishPageConfiguration | undefined): void => {
      if (generation !== this.configurationGeneration) {
        return;
      }
      if (configuration === undefined) {
        const session = this.session;
        if (session !== undefined && session.getState().status !== SessionStatus.AUTHENTICATED) {
          this.viewState = loginRequiredState();
        } else {
          this.viewState = configurationFailureState();
        }
        return;
      }
      this.installConfiguration(configuration);
    }, (_error: Error): void => {
      if (generation === this.configurationGeneration) {
        this.viewState = configurationFailureState();
      }
    });
  }

  private installConfiguration(configuration: PinPublishPageConfiguration): void {
    this.controller = new PinPublishPageController(configuration.repository, configuration.drafts, configuration.session,
      configuration.identity, configuration.traceIds, configuration.topicScheduler,
      (state: PinPublishPageViewState): void => {
        this.viewState = state;
      }, this.onPublished);
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.configurationGeneration += 1;
    this.publishConfirmationVisible = false;
    this.controller?.deactivate();
    this.controller = undefined;
    this.topicQuery = '';
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      this.header()
      if (this.viewState.requiresLogin) {
        this.loginRequired()
      } else {
        this.editor()
      }
      Text(this.viewState.message)
        .id('p4_pin_publish_status')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor(this.viewState.requiresSecurityVerification ? $r('app.color.error_text') :
          $r('app.color.secondary_text'))
        .width('100%')
      if (this.publishConfirmationVisible) {
        this.publishConfirmation()
      }
    }
    .id('p4_pin_publish_page')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private header() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Text('发布想法')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
      Button('取消')
        .id('p4_pin_publish_cancel')
        .enabled(this.viewState.phase !== PinPublishPagePhase.RELEASED)
        .onClick((): void => {
          this.controller?.cancel();
          this.onBack();
        })
    }
    .width('100%')
  }

  @Builder
  private loginRequired() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text(PIN_PAGE_LOGIN_REQUIRED_TEXT)
        .id('p4_pin_publish_login_required')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Button('去登录')
        .id('p4_pin_publish_login')
        .width('100%')
        .onClick(this.onLoginRequired)
    }
    .width('100%')
  }

  @Builder
  private editor() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      TextInput({ text: this.viewState.content.title, placeholder: '标题（可选）' })
        .id('p4_pin_publish_title')
        .maxLength(100)
        .enabled(this.viewState.canEdit)
        .onChange((value: string): void => this.controller?.updateTitle(value))
      TextArea({ text: this.viewState.content.html, placeholder: '分享你的想法' })
        .id('p4_pin_publish_body')
        .maxLength(10000)
        .height(180)
        .enabled(this.viewState.canEdit)
        .onChange((value: string): void => this.controller?.updateHtml(value))
      this.topicEditor()
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('保存草稿')
          .id('p4_pin_publish_save_draft')
          .layoutWeight(1)
          .enabled(this.viewState.canSaveDraft)
          .onClick((): void => {
            this.controller?.saveLocalDraft().then((): void => {}, (): void => {});
          })
        Button(this.publishLabel())
          .id('p4_pin_publish_submit')
          .layoutWeight(1)
          .enabled(this.viewState.canPublish)
          .onClick((): void => {
            this.requestPublishConfirmation();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private topicEditor() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      TextInput({ text: this.topicQuery, placeholder: '搜索话题（可选）' })
        .id('p4_pin_publish_topic_query')
        .enabled(this.viewState.canEdit)
        .onChange((value: string): void => {
          this.topicQuery = value;
          this.controller?.requestTopicSuggestions(value);
        })
      if (this.viewState.content.topics.length > 0) {
        ForEach(this.viewState.content.topics, (topic: PublishPinTopic) => {
          Row() {
            Text(`#${topic.displayName}`).layoutWeight(1)
            Button('移除')
              .onClick((): void => this.controller?.removeTopic(topic.topicId))
          }
          .id(`p4_pin_publish_topic_${topic.topicId}`)
          .width('100%')
        }, (topic: PublishPinTopic): string => topic.topicId)
      }
      if (this.viewState.phase === PinPublishPagePhase.EDITING) {
        ForEach(this.viewState.topicSuggestions, (topic: PinTopicSuggestion) => {
          Button(`#${topic.displayName}`)
            .id(`p4_pin_publish_topic_suggestion_${topic.topicId}`)
            .width('100%')
            .enabled(this.viewState.canEdit)
            .onClick((): void => {
              this.controller?.selectTopic({ topicId: topic.topicId, displayName: topic.displayName });
              this.topicQuery = '';
              this.controller?.requestTopicSuggestions('');
            })
        }, (topic: PinTopicSuggestion): string => topic.topicId)
      }
    }
    .width('100%')
  }

  private publishLabel(): string {
    return this.viewState.operation === PinPublishOperation.PUBLISHED ? '已发布' : '发布';
  }

  private requestPublishConfirmation(): void {
    if (!this.viewState.canPublish || !this.viewState.canEdit) {
      return;
    }
    this.publishConfirmationVisible = true;
  }

  @Builder
  private publishConfirmation() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('确认发布想法')
        .id('p4_pin_publish_confirm_title')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
      Text('确认后将先保存本地草稿并同步知乎草稿，再发布想法。')
        .id('p4_pin_publish_confirm_message')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('继续编辑')
          .id('p4_pin_publish_confirm_cancel')
          .layoutWeight(1)
          .onClick((): void => {
            this.publishConfirmationVisible = false;
          })
        Button('确认发布')
          .id('p4_pin_publish_confirm_submit')
          .layoutWeight(1)
          .onClick((): void => {
            this.publishConfirmationVisible = false;
            this.controller?.publishPin().then((): void => {}, (): void => {});
          })
      }
      .width('100%')
    }
    .id('p4_pin_publish_confirmation')
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }
}

const PIN_PAGE_LOGIN_REQUIRED_TEXT: string = '登录后才可保存或发布想法';

function initialViewState(): PinPublishPageViewState {
  return {
    phase: PinPublishPagePhase.SETUP,
    content: { title: '', html: '', images: [], topics: [] },
    operation: PinPublishOperation.IDLE,
    canEdit: false,
    canSaveDraft: false,
    canPublish: false,
    requiresLogin: false,
    requiresSecurityVerification: false,
    retryable: false,
    topicSuggestions: [],
    message: '正在准备创作页'
  };
}

function configurationFailureState(): PinPublishPageViewState {
  return {
    phase: PinPublishPagePhase.SETUP,
    content: { title: '', html: '', images: [], topics: [] },
    operation: PinPublishOperation.IDLE,
    canEdit: false,
    canSaveDraft: false,
    canPublish: false,
    requiresLogin: false,
    requiresSecurityVerification: false,
    retryable: false,
    topicSuggestions: [],
    message: '创作功能暂不可用'
  };
}

function loginRequiredState(): PinPublishPageViewState {
  return {
    phase: PinPublishPagePhase.LOGIN_REQUIRED,
    content: { title: '', html: '', images: [], topics: [] },
    operation: PinPublishOperation.IDLE,
    canEdit: false,
    canSaveDraft: false,
    canPublish: false,
    requiresLogin: true,
    requiresSecurityVerification: false,
    retryable: false,
    topicSuggestions: [],
    message: PIN_PAGE_LOGIN_REQUIRED_TEXT
  };
}

function randomHex(length: number): string {
  let value = '';
  for (let index = 0; index < length; index += 1) {
    value += Math.floor(Math.random() * 16).toString(16);
  }
  return value;
}
