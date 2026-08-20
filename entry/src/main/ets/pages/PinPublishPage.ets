import {
  ContentDraftIdentity,
  DraftRepository,
  LoginSessionGateway,
  PinPublishRepository,
  PinTopicSuggestion,
  PublishPinTopic
} from 'data';
import { PinPublishOperation, PinPublishTraceIdFactory, PinTopicSearchScheduler } from './PinPublishState';
import {
  PinPublishPageController,
  PinPublishPagePhase,
  PinPublishPageViewState
} from './PinPublishPageState';

export type PinPublishPageBackCallback = () => void;
export type PinPublishPageLoginCallback = () => void;
export type PinPublishPagePublishedCallback = (contentId: string) => void;

/**
 * 可注入的想法创作页。它不注册目的地，也不创建网络仓储；组合根在准备好账号、草稿和发布依赖后
 * 才能嵌入本页。离开只取消，不暗中保存；正文只绑定编辑控件和加密草稿边界。
 */
@Component
export struct PinPublishPage {
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
  private controller: PinPublishPageController | undefined = undefined;

  aboutToAppear(): void {
    if (this.controller !== undefined) {
      return;
    }
    if (this.repository === undefined || this.drafts === undefined || this.session === undefined ||
      this.identity === undefined || this.traceIds === undefined || this.topicScheduler === undefined) {
      this.viewState = configurationFailureState();
      return;
    }
    this.controller = new PinPublishPageController(this.repository, this.drafts, this.session, this.identity,
      this.traceIds, this.topicScheduler, (state: PinPublishPageViewState): void => {
        this.viewState = state;
      }, this.onPublished);
    this.controller.activate();
  }

  aboutToDisappear(): void {
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
        .fontSize($r('app.float.p1_title_font_size'))
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
            this.controller?.publishPin().then((): void => {}, (): void => {});
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
