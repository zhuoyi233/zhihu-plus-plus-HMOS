import {
  AnswerPublishInput,
  AnswerPublishRepository,
  DraftRepository,
  ExistingAnswerForEditing,
  hashDraftAccountId,
  LoginSessionGateway,
  PublishFailure,
  PublishFailureKind,
  SessionStatus
} from 'data';
import {
  AnswerPublishController,
  AnswerPublishObserver,
  AnswerPublishPhase,
  AnswerPublishViewState
} from './AnswerPublishState';
import { takeAnswerEditSeed } from './AnswerEditSeedStore';

export enum AnswerPublishPagePhase {
  PREPARING = 'preparing',
  READY = 'ready',
  LOGIN_REQUIRED = 'login_required',
  UNAVAILABLE = 'unavailable',
  RELEASED = 'released'
}

export interface AnswerPublishPageViewState {
  readonly phase: AnswerPublishPagePhase;
  readonly questionId: string;
  readonly answerId?: string;
  readonly html: string;
  readonly tocEnabled: boolean;
  readonly pending: boolean;
  readonly canPublish: boolean;
  readonly canSaveDraft: boolean;
  readonly canContinueEditing: boolean;
  readonly statusMessage: string;
}

/** 页面只依赖这组窄接口；Hypium 可注入 fake，页面不会直接持有发布仓储。 */
export interface AnswerPublishPageController {
  activate(): void;
  deactivate(): void;
  open(): Promise<void>;
  updateContent(html: string, tocEnabled: boolean): void;
  saveLocalDraft(now?: number): Promise<void>;
  publish(traceId: string, now?: number): Promise<void>;
  continueEditingExistingAnswer(): void;
  snapshot(): AnswerPublishViewState;
}

export interface AnswerPublishPageControllerFactory {
  create(questionId: string, answerId: string | undefined,
    observer: AnswerPublishObserver): Promise<AnswerPublishPageController | undefined>;
}

export interface AnswerPublishTraceIdFactory {
  createTraceId(): string;
}

export type AnswerPublishPageObserver = (state: AnswerPublishPageViewState) => void;

const LOGIN_REQUIRED_STATUS: string = '登录后即可撰写和发布回答';
const UNAVAILABLE_STATUS: string = '回答发布服务暂未配置；不会发送任何发布请求';

/**
 * 页面级编排先检查登录态，再延迟创建控制器。因此游客态既不会创建草稿，也不会触发任何写网络。
 * AnswerPublishController 是唯一的草稿/发布执行者，避免与 EditorDraftController 对同一草稿键双写。
 */
export class AnswerPublishPageCoordinator {
  private readonly session: LoginSessionGateway | undefined;
  private readonly factory: AnswerPublishPageControllerFactory | undefined;
  private readonly traceIds: AnswerPublishTraceIdFactory;
  private readonly observer: AnswerPublishPageObserver;
  private controller: AnswerPublishPageController | undefined;
  private active: boolean = false;
  private generation: number = 0;
  private questionId: string = '';
  private requestedAnswerId?: string;
  private state: AnswerPublishPageViewState = emptyViewState();

  constructor(session: LoginSessionGateway | undefined, factory: AnswerPublishPageControllerFactory | undefined,
    traceIds: AnswerPublishTraceIdFactory = new SystemAnswerPublishTraceIdFactory(),
    observer: AnswerPublishPageObserver = (_state: AnswerPublishPageViewState): void => {}) {
    this.session = session;
    this.factory = factory;
    this.traceIds = traceIds;
    this.observer = observer;
  }

  activate(questionId: string, answerId?: string): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.questionId = questionId;
    this.requestedAnswerId = answerId;
    this.prepare();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.controller?.deactivate();
    this.controller = undefined;
    this.state = {
      phase: AnswerPublishPagePhase.RELEASED,
      questionId: this.questionId,
      answerId: this.requestedAnswerId,
      html: '',
      tocEnabled: false,
      pending: false,
      canPublish: false,
      canSaveDraft: false,
      canContinueEditing: false,
      statusMessage: ''
    };
  }

  snapshot(): AnswerPublishPageViewState {
    return this.state;
  }

  updateContent(html: string, tocEnabled: boolean): void {
    this.controller?.updateContent(html, tocEnabled);
  }

  saveLocalDraft(): void {
    const controller = this.controller;
    if (controller === undefined || this.state.pending) {
      return;
    }
    void controller.saveLocalDraft();
  }

  publish(): void {
    const controller = this.controller;
    if (controller === undefined || this.state.pending || this.state.html.trim().length === 0) {
      return;
    }
    // 发布能力只能经已注入的 AnswerPublishController 触发；本页不认识发布 URL、Cookie 或请求体。
    void controller.publish(this.traceIds.createTraceId());
  }

  continueEditingExistingAnswer(): void {
    this.controller?.continueEditingExistingAnswer();
  }

  private prepare(): void {
    const session = this.session;
    if (session === undefined || session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.applyLoginRequired();
      return;
    }
    const factory = this.factory;
    if (factory === undefined) {
      this.applyUnavailable();
      return;
    }
    const operation = this.nextGeneration();
    this.apply({
      phase: AnswerPublishPagePhase.PREPARING,
      questionId: this.questionId,
      answerId: this.requestedAnswerId,
      html: '',
      tocEnabled: false,
      pending: true,
      canPublish: false,
      canSaveDraft: false,
      canContinueEditing: false,
      statusMessage: '正在准备回答编辑器…'
    });
    const observer: AnswerPublishObserver = (state: AnswerPublishViewState): void => {
      if (this.isCurrent(operation)) {
        this.applyPublisherState(state);
      }
    };
    factory.create(this.questionId, this.requestedAnswerId, observer).then(
      (controller: AnswerPublishPageController | undefined): void => {
        if (!this.isCurrent(operation)) {
          controller?.deactivate();
          return;
        }
        if (controller === undefined) {
          this.applyUnavailable();
          return;
        }
        this.controller = controller;
        controller.activate();
        void controller.open();
      },
      (_error: Error): void => {
        if (this.isCurrent(operation)) {
          this.applyUnavailable();
        }
      }
    );
  }

  private applyPublisherState(state: AnswerPublishViewState): void {
    this.apply({
      phase: AnswerPublishPagePhase.READY,
      questionId: state.questionId,
      answerId: state.answerId ?? this.requestedAnswerId,
      html: state.html,
      tocEnabled: state.tocEnabled,
      pending: state.pending,
      canPublish: !state.pending && state.phase !== AnswerPublishPhase.PUBLISHED && state.html.trim().length > 0,
      canSaveDraft: !state.pending && state.phase !== AnswerPublishPhase.PUBLISHED,
      canContinueEditing: state.phase === AnswerPublishPhase.CONFLICT && state.conflictAnswerId !== undefined,
      statusMessage: pageStatusMessage(state)
    });
  }

  private applyLoginRequired(): void {
    this.apply({
      phase: AnswerPublishPagePhase.LOGIN_REQUIRED,
      questionId: this.questionId,
      answerId: this.requestedAnswerId,
      html: '',
      tocEnabled: false,
      pending: false,
      canPublish: false,
      canSaveDraft: false,
      canContinueEditing: false,
      statusMessage: LOGIN_REQUIRED_STATUS
    });
  }

  private applyUnavailable(): void {
    this.apply({
      phase: AnswerPublishPagePhase.UNAVAILABLE,
      questionId: this.questionId,
      answerId: this.requestedAnswerId,
      html: '',
      tocEnabled: false,
      pending: false,
      canPublish: false,
      canSaveDraft: false,
      canContinueEditing: false,
      statusMessage: UNAVAILABLE_STATUS
    });
  }

  private nextGeneration(): number {
    this.generation += 1;
    return this.generation;
  }

  private isCurrent(operation: number): boolean {
    return this.active && operation === this.generation;
  }

  private apply(state: AnswerPublishPageViewState): void {
    this.state = state;
    if (this.active) {
      this.observer(this.state);
    }
  }
}

/**
 * 组合根默认使用此工厂：草稿仍通过加密 DraftRepository，但发布仓储刻意为本地安全占位，
 * 因此当前页面可编辑、可保留草稿，却不会向知乎发出任何写请求。
 */
export class LocalDraftAnswerPublishControllerFactory implements AnswerPublishPageControllerFactory {
  private readonly session: LoginSessionGateway;
  private readonly drafts: DraftRepository;

  constructor(session: LoginSessionGateway, drafts: DraftRepository) {
    this.session = session;
    this.drafts = drafts;
  }

  async create(questionId: string, answerId: string | undefined,
    observer: AnswerPublishObserver): Promise<AnswerPublishPageController | undefined> {
    const profile = this.session.getState().profile;
    if (profile === undefined) {
      return undefined;
    }
    const accountKey = await hashDraftAccountId(profile.id);
    const editSeed = answerId === undefined ? undefined : takeAnswerEditSeed(answerId);
    return new AnswerPublishController(new LocalDraftOnlyAnswerPublishRepository(editSeed), this.drafts,
      this.session, accountKey, questionId, observer, answerId);
  }
}

/** 不含 HTTP 客户端的默认仓储，确保接线完成前发布不会意外落到外部服务。 */
class LocalDraftOnlyAnswerPublishRepository implements AnswerPublishRepository {
  private editSeed: ExistingAnswerForEditing | undefined;

  constructor(editSeed: ExistingAnswerForEditing | undefined = undefined) {
    this.editSeed = editSeed;
  }

  findMyAnswerId(_questionId: string): Promise<string | undefined> {
    return Promise.resolve(undefined);
  }

  fetchAnswerForEditing(_answerId: string): Promise<ExistingAnswerForEditing | undefined> {
    const seed = this.editSeed;
    this.editSeed = undefined;
    if (seed === undefined || seed.answerId !== _answerId) {
      return Promise.resolve(undefined);
    }
    return Promise.resolve(seed);
  }

  saveRemoteDraft(_input: AnswerPublishInput): Promise<void> {
    return Promise.reject(new PublishFailure(PublishFailureKind.SERVER));
  }

  publish(_input: AnswerPublishInput): Promise<string> {
    return Promise.reject(new PublishFailure(PublishFailureKind.SERVER));
  }

  cancel(): void {
  }
}

export class SystemAnswerPublishTraceIdFactory implements AnswerPublishTraceIdFactory {
  createTraceId(): string {
    const timestamp = Math.max(1, Math.floor(Date.now()));
    return `${timestamp},${randomHex(8)}-${randomHex(4)}-4${randomHex(3)}-8${randomHex(3)}-${randomHex(12)}`;
  }
}

@Component
export struct AnswerPublishPage {
  questionId: string = '';
  answerId?: string = undefined;
  session: LoginSessionGateway | undefined = undefined;
  controllerFactory: AnswerPublishPageControllerFactory | undefined = undefined;
  traceIds: AnswerPublishTraceIdFactory | undefined = undefined;
  onGoLogin: () => void = (): void => {};
  onBack: () => void = (): void => {};
  @State private viewState: AnswerPublishPageViewState = emptyViewState();
  @State private publishConfirmationVisible: boolean = false;
  private coordinator: AnswerPublishPageCoordinator | undefined = undefined;

  aboutToAppear(): void {
    if (this.coordinator !== undefined) {
      return;
    }
    this.coordinator = new AnswerPublishPageCoordinator(this.session, this.controllerFactory, this.traceIds,
      (state: AnswerPublishPageViewState): void => {
        this.viewState = state;
      });
    this.coordinator.activate(this.questionId, this.answerId);
  }

  aboutToDisappear(): void {
    this.publishConfirmationVisible = false;
    this.coordinator?.deactivate();
    this.coordinator = undefined;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text(this.viewState.answerId === undefined ? '撰写回答' : '编辑回答')
          .id('p4_answer_page_title')
          .layoutWeight(1)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        Button('退出')
          .id('p4_answer_page_exit')
          .onClick((): void => this.exitEditor())
      }
      .width('100%')

      Text(this.viewState.statusMessage)
        .id('p4_answer_page_status')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))

      if (this.viewState.phase === AnswerPublishPagePhase.LOGIN_REQUIRED) {
        Button('去登录')
          .id('p4_answer_page_go_login')
          .width('100%')
          .onClick((): void => this.onGoLogin())
      } else if (this.viewState.phase === AnswerPublishPagePhase.READY) {
        TextArea({ text: this.viewState.html, placeholder: '写下你的回答…' })
          .id('p4_answer_page_editor')
          .width('100%')
          .layoutWeight(1)
          .maxLength(1048576)
          .onChange((value: string): void => {
            this.coordinator?.updateContent(value, this.viewState.tocEnabled);
          })

        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text('显示目录')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
          Toggle({ type: ToggleType.Switch, isOn: this.viewState.tocEnabled })
            .id('p4_answer_page_toc')
            .onChange((value: boolean): void => {
              this.coordinator?.updateContent(this.viewState.html, value);
            })
        }
        .width('100%')

        Row({ space: $r('app.float.p1_spacing_small') }) {
          Button('保存草稿')
            .id('p4_answer_page_save_draft')
            .layoutWeight(1)
            .enabled(this.viewState.canSaveDraft)
            .onClick((): void => this.coordinator?.saveLocalDraft())
        Button('发布回答')
            .id('p4_answer_page_publish')
            .layoutWeight(1)
            .enabled(this.viewState.canPublish)
            .onClick((): void => this.requestPublishConfirmation())
        }
        .width('100%')

        if (this.viewState.canContinueEditing) {
          Button('编辑已有回答')
            .id('p4_answer_page_continue_existing')
            .width('100%')
            .onClick((): void => this.coordinator?.continueEditingExistingAnswer())
        }
      }
      if (this.publishConfirmationVisible) {
        this.publishConfirmation()
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_card_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  private exitEditor(): void {
    this.publishConfirmationVisible = false;
    this.coordinator?.deactivate();
    this.onBack();
  }

  private requestPublishConfirmation(): void {
    if (!this.viewState.canPublish || this.viewState.pending) {
      return;
    }
    this.publishConfirmationVisible = true;
  }

  @Builder
  private publishConfirmation() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('确认发布回答')
        .id('p4_answer_page_publish_confirm_title')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
      Text('确认后将先保存本地草稿并同步知乎草稿，再提交回答。')
        .id('p4_answer_page_publish_confirm_message')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('继续编辑')
          .id('p4_answer_page_publish_confirm_cancel')
          .layoutWeight(1)
          .onClick((): void => {
            this.publishConfirmationVisible = false;
          })
        Button('确认发布')
          .id('p4_answer_page_publish_confirm_submit')
          .layoutWeight(1)
          .onClick((): void => {
            this.publishConfirmationVisible = false;
            this.coordinator?.publish();
          })
      }
      .width('100%')
    }
    .id('p4_answer_page_publish_confirmation')
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }
}

function emptyViewState(): AnswerPublishPageViewState {
  return {
    phase: AnswerPublishPagePhase.PREPARING,
    questionId: '',
    html: '',
    tocEnabled: false,
    pending: false,
    canPublish: false,
    canSaveDraft: false,
    canContinueEditing: false,
    statusMessage: '正在准备回答编辑器…'
  };
}

function pageStatusMessage(state: AnswerPublishViewState): string {
  if (state.errorMessage !== undefined) {
    return state.errorMessage;
  }
  switch (state.phase) {
    case AnswerPublishPhase.LOADING:
      return '正在恢复回答草稿…';
    case AnswerPublishPhase.SAVING_REMOTE_DRAFT:
      return '正在保存草稿…';
    case AnswerPublishPhase.PUBLISHING:
      return '正在发布回答…';
    case AnswerPublishPhase.PUBLISHED:
      return '回答已发布';
    case AnswerPublishPhase.CONFLICT:
      return '该问题已有回答，可继续编辑';
    default:
      return '回答草稿仅保存在本机加密存储中';
  }
}

function randomHex(length: number): string {
  let value = '';
  for (let index = 0; index < length; index += 1) {
    value += Math.floor(Math.random() * 16).toString(16);
  }
  return value;
}
