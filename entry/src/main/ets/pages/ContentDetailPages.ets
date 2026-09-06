import { QuestionAnswerDataSource } from './QuestionAnswerDataSource';
import { AnswerNavigationPreview, QuestionAnswerNavigator, stageQuestionAnswerNavigator, takeQuestionAnswerNavigator } from './QuestionAnswerNavigator';
import { ContentImagePreview } from './NativeContentDocument';
import { publishQuestionTitle } from './QuestionTitleBar';
import { publishAnswerTitle } from './AnswerTitleBar';
import { publishArticleTitle } from './ArticleTitleBar';
import { FeedContentSummary } from './components/FeedContentSummary';
import { AppPageStatusKind, AppPageStatusPanel, FeedPullDownIndicatorOptions, feedPullDownIndicator } from './AppPageChrome';
import { pasteboard } from '@kit.BasicServicesKit';
import { ComponentContent, SegmentButton, SegmentButtonOptions, curves } from '@kit.ArkUI';
import {
  P1Destination,
  P1DestinationName
} from 'core';
import {
  AnswerDoubleTapAction,
  answerDoubleTapActionLabel,
  AnswerEndorsementDisplay,
  AppPreferencesStore,
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  ChannelContentItem,
  CollectionRepository,
  CommentRepository,
  ContentDetailKind,
  ContentRepository,
  ContentVoteState,
  feedItemIdentity,
  FollowMutationResult,
  FollowRepository,
  LoginSessionGateway,
  OpenedContentStore,
  QuestionAnswerFeedRepository,
  QuestionAnswerSortOrder,
  QuestionTopicSummary,
  SessionStatus,
  VoteRepository
} from 'data';
import {
  BlockingActionContext,
  BlockingActionController,
  BlockingActionViewState,
  BlockingUserCandidate
} from './BlockingActionState';
import {
  QuestionAnswersController,
  QuestionAnswersPhase,
  QuestionAnswersViewState
} from './QuestionAnswersState';
import {
  ContentDetailController,
  ContentDetailPhase,
  ContentDetailViewState,
  LoadedContentDetail,
  OpenedRecordPhase
} from './ContentDetailState';
import {
  ContentVoteController,
  ContentVoteViewState,
  FollowController,
  FollowViewState
} from './ContentInteractionState';
import { CollectionDialogComponent } from './CollectionDialogComponent';
import { CommentLayer } from './CommentLayer';
import { NativeContentDocument } from './NativeContentDocument';
import { stageAnswerEditSeed } from './AnswerEditSeedStore';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { createSystemShareService } from '../platform/SystemShareService';
import { setStatusBarHidden } from '../platform/SystemBars';
import { performConfirmHaptic } from '../platform/HapticFeedback';
import { ShareOutcome, SharePayloadKind, ShareTextPayload } from '../platform/ShareContracts';
import { hdsMaterial } from '@kit.UIDesignKit';
import { GlassCapsule } from './components/MaterialCanvas';

@Component
struct ContentDetailPage {
  kind: ContentDetailKind = ContentDetailKind.QUESTION;
  contentId: string = '';
  @State private activeContentId: string = '';
  @State private refreshingAnswers: boolean = false;
  @State private navigatorBusy: boolean = false;
  @State private navigatorRevision: number = 0;
  /** 回答页过滑切换：主内容 overscroll 偏移（<0 上移露底部"下一答"预览卡，>0 下移露顶部"上一答"预览卡）。 */
  @State private answerOverscrollOffset: number = 0;
  /** 正文是否贴在列表底边（NativeContentDocument 回推）。 */
  @State private contentAtBottom: boolean = false;
  /** 正文是否贴在列表顶边（NativeContentDocument 回推）。 */
  @State private contentAtTop: boolean = true;
  /** overscroll 原始拖动累计量（阻尼换算前）。 */
  private overscrollRawDrag: number = 0;
  /** 上一次 pan 手势 offsetY（换算单帧 delta）。 */
  private overscrollPanPrevY: number = 0;
  /** 悬浮"下一个回答"按钮拖动偏移（相对右下角默认位，负值向左/向上），松手后保留。 */
  @State private answerFabOffsetX: number = 0;
  @State private answerFabOffsetY: number = 0;
  /** 上一次按钮拖动 pan 手势 offset（换算单帧 delta）。 */
  private answerFabPanPrevX: number = 0;
  private answerFabPanPrevY: number = 0;
  /** 悬浮按钮拖动进行中：冻结正文过滑手势（同指不得同时驱动按钮与预览卡）。 */
  private answerFabDragging: boolean = false;
  /** 悬浮按钮实测宽度（vp）与所在悬浮层尺寸（vp）：拖动越界钳制用。 */
  private answerFabWidthVp: number = 0;
  private answerFabOverlayWidthVp: number = 0;
  private answerFabOverlayHeightVp: number = 0;
  @StorageProp('loginFeedReloadTick') @Watch('onLoginChanged') private loginTick: number = 0;
  /** 全屏图片查看器：正文/评论图点击后经 AppStorage 广播，在页面根 Stack 叠层渲染
   *（正文列表惰性树与模态覆盖层树内均无法可靠驱动状态更新，见 NativeContentDocument 注释）。 */
  @StorageProp('p2ImagePreviewUrl') @Watch('onImagePreviewChanged') private imagePreviewUrl: string = '';
  @State private authenticated: boolean = false;
  private answerNavigator?: QuestionAnswerNavigator;
  private readonly answerDataSource: QuestionAnswerDataSource = new QuestionAnswerDataSource();
  private refreshContent?: ComponentContent<FeedPullDownIndicatorOptions>;
  private questionScrolled: boolean = false;
  /** 回答页顶栏折叠：问题标题已滚出视口（经 AppStorage 驱动 HDS 标题栏折叠态）。 */
  private answerQuestionScrolled: boolean = false;
  /** 文章页顶栏折叠：文章标题已滚出视口（经 AppStorage 驱动 HDS 标题栏折叠态）。 */
  private articleTitleScrolled: boolean = false;
  /** 详情页滚动信息头中主标题实测高度（vp）：折叠阈值的动态基准；未测得前按单行估算。 */
  private contentTitleHeightVp: number = 0;
  private pageActive: boolean = false;
  repository: ContentRepository | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  voteRepository: VoteRepository | undefined = undefined;
  followRepository: FollowRepository | undefined = undefined;
  collectionRepository: CollectionRepository | undefined = undefined;
  commentRepository: CommentRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  questionAnswerFeedFactory: () => QuestionAnswerFeedRepository | undefined = () => undefined;
  onBack: () => void = (): void => {
  };
  @State private phase: ContentDetailPhase = ContentDetailPhase.IDLE;
  @State private content: LoadedContentDetail | undefined = undefined;
  @State private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  @State private openedRecordPhase: OpenedRecordPhase = OpenedRecordPhase.NOT_CONFIGURED;
  @State private pendingUserBlock?: BlockingUserCandidate = undefined;
  @State private keywordBlockVisible: boolean = false;
  @State private keywordBlockInput: string = '';
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  @State private voteState: ContentVoteState = ContentVoteState.NEUTRAL;
  @State private voteupCount: number = 0;
  @State private thanked: boolean = false;
  @State private thanksCount: number = 0;
  @State private following: boolean = false;
  @State private followerCount: number = 0;
  @State private interactionPending: boolean = false;
  @State private interactionErrorMessage: string = '';
  @State private interactionRequiresLogin: boolean = false;
  @State private favoriteDialogShown: boolean = false;
  /** 回答页双击正文动作（对齐上游 answerDoubleTapAction）：AppStorage 广播跨页同步
   * （详情页 Ask 面板与设置页改动互见），默认询问并记住。 */
  @StorageProp('answerDoubleTapAction') private answerDoubleTapAction: AnswerDoubleTapAction =
    AnswerDoubleTapAction.ASK;
  /** 双击动作询问面板（Ask 动作）可见性。 */
  @State private doubleTapAskSheetShown: boolean = false;
  @State private showComments: boolean = false;
  @State private commentRootDraft: string = '';
  @State private commentReplyDraft: string = '';
  /** 问题页回答信息流（P1）：状态由 QuestionAnswersController 推送。 */
  @State private answersState: QuestionAnswersViewState = {
    phase: QuestionAnswersPhase.IDLE,
    items: [],
    loadingMore: false,
    canLoadMore: false,
    sortOrder: QuestionAnswerSortOrder.DEFAULT,
    errorMessage: '',
    requiresLogin: false
  };
  @State private answersSortIndexes: number[] = [0];
  private answersController?: QuestionAnswersController;
  /** P3-9-C：底部菜单弹窗可见性。 */
  @State private actionMenuShown: boolean = false;
  /** P3-9-C：菜单操作反馈（复制链接结果等）。 */
  @State private menuStatus: string = '';
  /** 沉浸式阅读仅收起页面 Chrome，不改变正文、互动或滚动状态。
   * 变化经 AppStorage 广播给 P1Shell 隐藏/恢复 NavDestination 顶栏（对齐上游 topBar={}）。 */
  @State @Watch('onImmersiveReadingChanged') private immersiveReading: boolean = false;
  /** P1Shell Back 拦截发出的"先退沉浸式"信号（跨页面信号必须走 AppStorage 广播）。 */
  @StorageProp('detailImmersiveExitTick') @Watch('onImmersiveExitSignal') private immersiveExitTick: number = 0;
  /** 状态栏高度（vp，EntryAbility 广播）：沉浸式隐藏顶栏后正文的顶部留空。 */
  @StorageProp('statusBarHeight') private statusBarHeightVp: number = 0;
  /** 设备支持沉浸材质：玻璃胶囊走 HDS 画布，否则回落组件模糊。 */
  private immersiveMaterialSupported: boolean = false;
  private controller?: ContentDetailController;
  private blockingAction?: BlockingActionController;
  private voteController?: ContentVoteController;
  private followController?: FollowController;

  aboutToAppear(): void {
    this.pageActive = true;
    if (this.activeContentId.length === 0) { this.activeContentId = this.contentId; }
    this.authenticated = this.session?.getState().status === SessionStatus.AUTHENTICATED;
    // 双击动作偏好全局生效，返回栈重显时也刷新（可能刚在设置页改过）。
    void this.restoreAnswerDoubleTapAction();
    // 同步沉浸式初始/保留态给 P1Shell（返回栈重显时实例与状态均保留）。
    AppStorage.setOrCreate('detailImmersiveActive', this.immersiveReading);
    this.refreshContent = new ComponentContent(this.getUIContext(), wrapBuilder(feedPullDownIndicator),
      new FeedPullDownIndicatorOptions());
    if (this.kind === ContentDetailKind.ANSWER && this.answerNavigator === undefined) {
      this.answerNavigator = takeQuestionAnswerNavigator(this.activeContentId);
    }
    this.answerNavigator?.resume();
    try {
      this.immersiveMaterialSupported =
        hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_error) {
      this.immersiveMaterialSupported = false;
    }
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载正文导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      this.answersController?.activate();
      this.ensureAnswers();
      if (this.phase === ContentDetailPhase.LOADING) {
        void this.controller.load(this.kind, this.activeContentId);
      }
      return;
    }
    const repository = this.repository;
    if (repository === undefined) {
      this.phase = ContentDetailPhase.ERROR;
      this.errorMessage = '内容数据源未配置';
      return;
    }
    this.controller = new ContentDetailController(
      repository,
      this.openedContentStore,
      (state: ContentDetailViewState): void => this.applyState(state)
    );
    this.controller.activate();
    this.controller.load(this.kind, this.activeContentId);
    this.createBlockingAction();
    this.ensureAnswers();
  }

  private ensureAnswers(): void {
    if (!this.pageActive || this.kind !== ContentDetailKind.QUESTION || !this.authenticated) { return; }
    if (this.answersController === undefined) {
      const repository = this.questionAnswerFeedFactory();
      if (repository === undefined) { return; }
      this.answersSortIndexes = [0];
      this.answersController = new QuestionAnswersController(repository, this.activeContentId,
        (state: QuestionAnswersViewState): void => {
          this.answersState = state;
          this.answerDataSource.replace(state.items);
        });
    }
    this.answersController.activate();
  }

  private onLoginChanged(): void {
    this.authenticated = this.session?.getState().status === SessionStatus.AUTHENTICATED;
    if (!this.pageActive) { return; }
    this.answersController?.deactivate();
    this.answersController = undefined;
    this.answerDataSource.replace([]);
    this.ensureAnswers();
    this.followController?.deactivate();
    this.followController = undefined;
    void this.controller?.load(this.kind, this.activeContentId);
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.refreshContent?.dispose();
    this.refreshContent = undefined;
    this.answersController?.deactivate();
    this.controller?.deactivate();
    this.voteController?.deactivate();
    this.followController?.deactivate();
    this.voteController = undefined;
    this.followController = undefined;
    this.answerNavigator?.pause();
    this.resetAnswerOverscroll(false);
    this.contentAtBottom = false;
    this.pendingUserBlock = undefined;
    this.keywordBlockVisible = false;
    this.keywordBlockInput = '';
    this.showComments = false;
    this.commentRootDraft = '';
    this.commentReplyDraft = '';
    this.immersiveReading = false;
    AppStorage.setOrCreate('detailImmersiveActive', false);
    AppStorage.setOrCreate('p2ImagePreviewUrl', '');
    // 对齐上游 LeaveImmersiveModeCleanup：页面销毁时确保状态栏恢复。
    setStatusBarHidden(false);
  }

  private onImmersiveReadingChanged(): void {
    AppStorage.setOrCreate('detailImmersiveActive', this.immersiveReading);
    // 真全屏：沉浸中隐藏状态栏（对齐上游 WindowInsetsController.hide(statusBars)）。
    setStatusBarHidden(this.immersiveReading);
  }

  /** 全屏图片查看器打开时同步隐藏状态栏（对齐沉浸阅读的真全屏处理），关闭时恢复。 */
  private onImagePreviewChanged(): void {
    setStatusBarHidden(this.immersiveReading || this.imagePreviewUrl.length > 0);
  }

  private onImmersiveExitSignal(): void {
    if (this.immersiveReading) {
      this.immersiveReading = false;
    }
  }

  private async refreshQuestion(): Promise<void> {
    this.refreshingAnswers = true;
    this.followController?.deactivate();
    this.followController = undefined;
    try {
      await Promise.all([this.controller?.load(this.kind, this.activeContentId) ?? Promise.resolve(),
        this.answersController?.refresh() ?? Promise.resolve()]);
    } finally { this.refreshingAnswers = false; }
  }

  private createBlockingAction(): void {
    const rules = this.rules;
    const history = this.history;
    if (rules === undefined || history === undefined) {
      return;
    }
    this.blockingAction = new BlockingActionController(rules, history, (state: BlockingActionViewState): void => {
      this.blockingMessage = state.message;
      this.blockingBusy = state.busy;
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 页面页头（返回 + 标题）由 P1Shell 的 HDS 标题栏 stackBuilder 承载。
        if (this.phase === ContentDetailPhase.LOADING || this.phase === ContentDetailPhase.IDLE) {
          this.statusPanel('正在加载内容…', false)
        } else if (this.phase === ContentDetailPhase.ERROR) {
          this.statusPanel(this.errorMessage, true)
        } else if (this.content !== undefined) {
          Column() {
            // P3-9-B：顶栏作为占位（非覆盖），正文在其下方。
            // 回答/文章页信息头（标题/作者/时间）随正文滚动（对齐上游折叠顶栏），无固定信息条。
            Column() {
              if (this.kind === ContentDetailKind.QUESTION) {
                this.questionDocument(this.content)
              } else {
                this.loadedContent(this.content)
              }
            }
            .layoutWeight(1)
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .id(`p2_${this.kind}_detail_page`)
      .width('100%')
      .height('100%')
      // 94vp 为顶栏叠加预留；沉浸式隐藏顶栏后仅保留状态栏高度（对齐上游 topBar={}）。
      .padding({ top: this.immersiveReading ? Math.max(this.statusBarHeightVp, 0) : 94 })
      .backgroundColor($r('app.color.page_background'))

      // 底部操作栏：全屏悬浮层单实例承载（正文从下方穿透直至物理底边）。
      // 切勿在布局流内再渲染第二份——两份会完全重叠绘制（06a2ab90 修复的错乱根源）。
      if (!this.immersiveReading && this.content !== undefined &&
        this.phase === ContentDetailPhase.READY) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.bottomActionBar()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 悬浮"下一个回答"按钮（对齐上游 SkipNext FAB）：右下角、底部操作栏上方，可拖动避让正文；
      // 底部"下一答"预览卡展开时隐藏，避免盖住预览卡。
      if (this.kind === ContentDetailKind.ANSWER && !this.immersiveReading &&
        this.content !== undefined && this.phase === ContentDetailPhase.READY &&
        this.answerOverscrollOffset >= 0 && this.navigatorHasNext()) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.answerNextFloatingButton()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const width = Number(newArea.width);
          const height = Number(newArea.height);
          if (width > 0 && Math.abs(width - this.answerFabOverlayWidthVp) > 1) {
            this.answerFabOverlayWidthVp = width;
          }
          if (height > 0 && Math.abs(height - this.answerFabOverlayHeightVp) > 1) {
            this.answerFabOverlayHeightVp = height;
          }
        })
      }

      if (this.phase === ContentDetailPhase.READY &&
        this.collectionRepository !== undefined && this.session !== undefined) {
        Column()
          .bindSheet(this.favoriteDialogShown, this.favoriteDialog(), {
            height: SheetSize.LARGE,
            dragBar: true,
            showClose: false,
            maskColor: '#66000000',
            backgroundColor: $r('app.color.surface_background'),
            onDisappear: (): void => {
              if (this.favoriteDialogShown) {
                this.favoriteDialogShown = false;
              }
            }
          })
      }
      if (this.pendingUserBlock !== undefined) {
        this.userBlockDialog()
      }
      if (this.keywordBlockVisible) {
        this.keywordBlockDialog()
      }
      Column()
        .bindSheet(this.actionMenuShown, this.actionMenuSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.actionMenuShown) {
              this.actionMenuShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.doubleTapAskSheetShown, this.doubleTapAskSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.doubleTapAskSheetShown) {
              this.doubleTapAskSheetShown = false;
            }
          }
        })
      // 切换回答期间卸载旧内容的弹层，避免普通入参 contentId 留在前一答。
      if (this.phase === ContentDetailPhase.READY && (this.kind === ContentDetailKind.ANSWER ||
        this.kind === ContentDetailKind.ARTICLE || this.kind === ContentDetailKind.QUESTION)) {
        CommentLayer({
          contentType: this.kind === ContentDetailKind.ARTICLE ? 'article'
            : this.kind === ContentDetailKind.QUESTION ? 'question' : 'answer',
          contentId: this.activeContentId,
          repository: this.commentRepository,
          session: this.session,
          navigate: this.navigate,
          showComments: this.showComments,
          rootDraft: this.commentRootDraft,
          replyDraft: this.commentReplyDraft,
          onRootDraftChange: (value: string): void => {
            this.commentRootDraft = value;
          },
          onReplyDraftChange: (value: string): void => {
            this.commentReplyDraft = value;
          },
          onDismiss: (): void => {
            this.showComments = false;
          }
        })
      }

      // 全屏图片查看器叠层：置于根 Stack 最后一个子节点，盖住正文/底部操作栏；
      // 标题栏由 P1Shell 监听同一 AppStorage 键隐藏（hideTitleBar）。
      if (this.imagePreviewUrl.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          ContentImagePreview({
            url: this.imagePreviewUrl,
            onClose: (): void => {
              AppStorage.setOrCreate('p2ImagePreviewUrl', '');
            }
          })
        }
        .id('p2_image_preview_overlay')
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private favoriteDialog() {
    CollectionDialogComponent({
      contentType: this.kind === ContentDetailKind.ARTICLE ? 'article' : 'answer',
      contentId: this.activeContentId,
      repository: this.collectionRepository,
      session: this.session,
      navigate: this.navigate,
      onDismiss: (): void => {
        this.favoriteDialogShown = false;
      }
    })
  }

  @Builder
  private statusPanel(message: string, retry: boolean) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (!retry) {
        LoadingProgress()
          .id(`p2_${this.kind}_detail_loading_progress`)
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      }
      Text(message)
        .id(`p2_${this.kind}_detail_status`)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        if (this.requiresLogin) {
          Button('去登录')
            .id(`p2_${this.kind}_detail_login`)
            .onClick((): void => {
              this.navigate({ name: P1DestinationName.LOGIN });
            })
        } else {
          Button('重新加载')
            .id(`p2_${this.kind}_detail_retry`)
            .onClick((): void => {
              this.controller?.load(this.kind, this.activeContentId);
            })
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private loadedContent(content: LoadedContentDetail) {
    Stack({ alignContent: Alignment.Bottom }) {
      // 底层：顶部"上一个回答"预览卡（对齐上游 AnswerVerticalOverscroll 顶部卡，
      // 标签行在上、作者行在下）；主内容随 overscroll 下移露出；只在有上一答时渲染。
      if (this.kind === ContentDetailKind.ANSWER && this.answerOverscrollOffset > 0 &&
        this.answerNavigator !== undefined && this.navigatorHasPrevious()) {
        Stack({ alignContent: Alignment.Top }) {
          this.answerPreviewCard(true)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }

      // 底层：底部"下一个回答"预览卡（对齐上游 AnswerVerticalOverscroll 底部卡，
      // 作者行在上、标签行在下）；主内容随 overscroll 上移露出；只在有下一答时渲染。
      if (this.kind === ContentDetailKind.ANSWER && this.answerOverscrollOffset < 0 &&
        this.answerNavigator !== undefined && this.navigatorHasNext()) {
        this.answerPreviewCard(false)
      }

      // 上层：主内容，跟随 overscroll 偏移平移。
      Column() {
        // 回答/文章页：信息头（标题/作者/时间）入列随正文滚动（对齐上游折叠顶栏），
        // 滚过主标题后经 AppStorage 通知 HDS 标题栏折叠为内容标题。
        NativeContentDocument({
          html: contentHtml(content),
          emptyMessage: contentEmptyMessage(content),
          disableEdgeSpring: this.kind === ContentDetailKind.ANSWER,
          documentHeader: (): void => { this.contentHeader(content) },
          onScrollOffset: (offset: number): void => {
            if (this.kind === ContentDetailKind.ANSWER) {
              this.updateAnswerTitleScrolled(content, offset);
            } else {
              this.updateArticleTitleScrolled(content, offset);
            }
          },
          onBottomEdgeChange: (atBottom: boolean): void => {
            this.contentAtBottom = atBottom;
          },
          onTopEdgeChange: (atTop: boolean): void => {
            this.contentAtTop = atTop;
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .translate({ y: this.answerOverscrollOffset })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    // 并行手势：与正文 List 滚动同时识别，贴边后的继续滑动量由本容器转为 overscroll
    // （List 的 edgeEffect 已在回答页关闭，不会自身回弹）。
    .parallelGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical })
        .onActionStart((event: GestureEvent): void => {
          this.overscrollPanPrevY = event.offsetY;
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.onAnswerOverscrollPanUpdate(event);
        })
        .onActionEnd((): void => {
          this.onAnswerOverscrollPanEnd();
        })
    )
    // 双击正文赞同一键：互斥手势默认子组件优先，图片/链接等可点区域不触发；
    // 与上方 parallelGesture 过滑 PanGesture 并存（tap 与 pan 不互斥）。
    .gesture(
      TapGesture({ count: 2 })
        .onAction((): void => {
          this.onAnswerDoubleTap();
        })
    )
  }

  /** 过滑预览卡（对齐上游 AnswerPreviewCard）：上一答卡标签行在上、作者行在下；
   * 下一答卡 reverseLayout：作者行在上、标签行在下。 */
  @Builder
  private answerPreviewCard(previous: boolean) {
    Column({ space: 8 }) {
      if (previous) {
        this.answerPreviewLabelRow(previous)
        this.answerPreviewAuthorRow(previous)
      } else {
        this.answerPreviewAuthorRow(previous)
        this.answerPreviewLabelRow(previous)
      }
    }
    .id(previous ? 'p2_answer_prev_preview_card' : 'p2_answer_next_preview_card')
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.p1_card_radius'))
    .margin({
      left: $r('app.float.p1_page_padding'),
      right: $r('app.float.p1_page_padding'),
      // 上一答卡贴顶部（页顶栏下方留 8vp）；下一答卡预留在底部悬浮操作栏（约 44vp 高 + 12vp 底距）上方。
      top: previous ? 8 : 0,
      bottom: previous ? 0 : 72
    })
    .backgroundColor(this.answerOverscrollTriggered()
      ? $r('app.color.brand_primary_container') : $r('app.color.surface_background'))
    .opacity(this.answerOverscrollProgress())
  }

  /** 预览卡标签行：方向图标 + 文案（触发后高亮为"松手切换"）。 */
  @Builder
  private answerPreviewLabelRow(previous: boolean) {
    Row({ space: 6 }) {
      SymbolGlyph(previous ? $r('sys.symbol.arrow_up') : $r('sys.symbol.arrow_down'))
        .fontSize(16)
        .fontColor([this.answerOverscrollTriggered()
          ? $r('app.color.brand_primary') : $r('app.color.secondary_text')])
      Text(this.answerOverscrollTriggered() ? '松手切换' : (previous ? '上一个回答' : '下一个回答'))
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontWeight(this.answerOverscrollTriggered() ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.answerOverscrollTriggered()
          ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
    }
    .width('100%')
  }

  /** 预览卡作者行：头像 + 姓名/摘要。 */
  @Builder
  private answerPreviewAuthorRow(previous: boolean) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(28)
          .height(28)
          .fill($r('app.color.control_background'))
        if (this.answerPreviewAvatarUrl(previous).length > 0) {
          Image(this.answerPreviewAvatarUrl(previous))
            .id(previous ? 'p2_answer_prev_preview_avatar' : 'p2_answer_next_preview_avatar')
            .width(28)
            .height(28)
            .borderRadius(14)
            .objectFit(ImageFit.Cover)
        } else if (this.answerPreviewAuthorName(previous).length > 0) {
          Text(this.answerPreviewAuthorName(previous).substring(0, 1))
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .width(28)
      .height(28)
      .clip(true)

      Column({ space: 2 }) {
        if (this.answerPreviewAuthorName(previous).length > 0) {
          Text(this.answerPreviewAuthorName(previous))
            .id(previous ? 'p2_answer_prev_preview_author' : 'p2_answer_next_preview_author')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.answerPreviewExcerpt(previous).length > 0) {
          Text(this.answerPreviewExcerpt(previous))
            .id(previous ? 'p2_answer_prev_preview_excerpt' : 'p2_answer_next_preview_excerpt')
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  /** 悬浮"下一个回答"按钮：品牌色胶囊 + 官方符号图标，点击切换下一答；可拖动避让正文。 */
  @Builder
  private answerNextFloatingButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_down'))
          .fontSize(20)
          .fontColor([$r('app.color.on_brand')])
        Text('下一个回答')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_brand'))
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    }
    .id('p2_answer_next_floating')
    .height(44)
    .borderRadius(22)
    .backgroundColor($r('app.color.brand_primary'))
    .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
    .margin({
      right: $r('app.float.p1_page_padding'),
      // 底部操作栏高约 44vp + 12vp 底距，再加少量间隔。
      bottom: 76
    })
    .offset({ x: this.answerFabOffsetX, y: this.answerFabOffsetY })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (width > 0 && Math.abs(width - this.answerFabWidthVp) > 1) {
        this.answerFabWidthVp = width;
      }
    })
    .enabled(!this.navigatorBusy)
    .accessibilityText('下一个回答')
    .gesture(
      PanGesture({ fingers: 1 })
        .onActionStart((event: GestureEvent): void => {
          this.answerFabPanPrevX = event.offsetX;
          this.answerFabPanPrevY = event.offsetY;
          this.answerFabDragging = true;
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.onAnswerFabPanUpdate(event);
        })
        .onActionEnd((): void => {
          this.answerFabPanPrevX = 0;
          this.answerFabPanPrevY = 0;
          this.answerFabDragging = false;
        })
        .onActionCancel((): void => {
          this.answerFabPanPrevX = 0;
          this.answerFabPanPrevY = 0;
          this.answerFabDragging = false;
        })
    )
    .onClick((): void => {
      void this.moveAnswer(1);
    })
  }

  /** 悬浮"下一个回答"按钮拖动：累计偏移并钳制在页面可视域内
   * （左/上不越过页边距与页头区，右/下不越过默认位——再低会压住底部操作栏）。 */
  private onAnswerFabPanUpdate(event: GestureEvent): void {
    const deltaX = event.offsetX - this.answerFabPanPrevX;
    const deltaY = event.offsetY - this.answerFabPanPrevY;
    this.answerFabPanPrevX = event.offsetX;
    this.answerFabPanPrevY = event.offsetY;
    if (deltaX === 0 && deltaY === 0) {
      return;
    }
    // 与 p1_page_padding（12vp）保持一致；悬浮层尺寸未就绪（=0）时钳制退化为仅禁越右侧/下侧。
    const pagePadding = 12;
    const fabHeight = 44;
    const minX = this.answerFabWidthVp + pagePadding * 2 - this.answerFabOverlayWidthVp;
    // 页头（返回 + 标题）区高约 94vp，按钮顶边不得低于其下沿。
    const minY = 94 + pagePadding + fabHeight + 76 - this.answerFabOverlayHeightVp;
    this.answerFabOffsetX = Math.min(0, Math.max(minX, this.answerFabOffsetX + deltaX));
    this.answerFabOffsetY = Math.min(0, Math.max(minY, this.answerFabOffsetY + deltaY));
  }

  @Builder
  private contentHeader(content: LoadedContentDetail) {
    if ((content.kind === ContentDetailKind.ANSWER || content.kind === ContentDetailKind.ARTICLE) &&
      this.immersiveReading) {
      // 沉浸式：收起问题标题/时间/统计等完整信息头，仅留窄作者行（对齐上游 isImmersiveMode 分支）。
      this.immersiveAuthorRow(content)
    } else {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        // 主标题保留在正文信息头：回答显示所属问题，文章显示文章标题，避免仅依赖通用路由标题。
        if (contentContextTitle(content).length > 0) {
          Text(contentContextTitle(content))
            .id(`p2_${content.kind}_detail_context_title`)
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              const height = Number(newArea.height);
              if (height > 0 && Math.abs(height - this.contentTitleHeightVp) > 1) {
                this.contentTitleHeightVp = height;
              }
            })
            .accessibilityDescription(content.kind === ContentDetailKind.ANSWER ? '点击查看问题详情' : '')
            .onClick((): void => {
              if (content.kind === ContentDetailKind.ANSWER) {
                this.navigate({ name: P1DestinationName.QUESTION, id: content.value.questionId });
              }
            })
        }

        // 回答/文章页作者信息随信息头滚动（对齐上游展开顶栏）：头像 + 名称 + 一句话简介。
        if (content.kind === ContentDetailKind.ANSWER || content.kind === ContentDetailKind.ARTICLE) {
          this.contentHeaderAuthorRow(content)
        }

        // 回答/文章页发布/编辑时间（对齐上游 DateTexts：编辑时间与发布不同才显示）。
        if (contentCreatedAtText(content).length > 0) {
          Text(contentCreatedAtText(content))
            .id(`p2_${content.kind}_detail_created_at`)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        if (contentUpdatedAtText(content).length > 0) {
          Text(contentUpdatedAtText(content))
            .id(`p2_${content.kind}_detail_updated_at`)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        if (content.kind === ContentDetailKind.QUESTION) {
          Row({ space: $r('app.float.p1_spacing_medium') }) {
            this.questionStatItem($r('sys.symbol.eye'), `${content.value.visitCount ?? 0} 浏览`)
            this.questionStatItem($r('sys.symbol.heart'), `${this.followController === undefined ? content.value.followerCount : this.followerCount} 关注`)
            this.questionStatItem($r('sys.symbol.message'), `${content.value.commentCount} 评论`)
          }
          .id(`p2_${content.kind}_detail_statistics`)
          .width('100%')
        } else {
          Text(this.displayedContentStatistics(content))
            .id(`p2_${content.kind}_detail_statistics`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        if (contentEndorsements(content).length > 0) {
          this.endorsementFlow(contentEndorsements(content))
        }

        if (contentIpInfo(content).length > 0) {
          Text(`IP 属地：${contentIpInfo(content)}`)
            .id(`p2_${content.kind}_detail_ip`)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        if (this.blockingMessage.length > 0) {
          Text(this.blockingMessage)
            .id(`p3_${content.kind}_blocking_status`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        if (this.openedRecordPhase === OpenedRecordPhase.FAILED) {
          Text('本次打开记录未能保存，阅读不受影响')
            .id(`p2_${content.kind}_opened_record_failed`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({
        // 回答/文章页信息头在列表内滚动：左右与顶部留白由 List 统一提供，避免双重内边距。
        left: content.kind === ContentDetailKind.ANSWER || content.kind === ContentDetailKind.ARTICLE
          ? 0 : $r('app.float.p1_page_padding'),
        right: content.kind === ContentDetailKind.ANSWER || content.kind === ContentDetailKind.ARTICLE
          ? 0 : $r('app.float.p1_page_padding'),
        top: content.kind === ContentDetailKind.ANSWER || content.kind === ContentDetailKind.ARTICLE
          ? 0 : $r('app.float.p1_spacing_medium'),
        bottom: $r('app.float.p1_spacing_medium')
      })
      .backgroundColor($r('app.color.surface_background'))
    }
  }

  /** 沉浸式窄作者行（对齐上游 isImmersiveMode 分支）：24vp 头像 + 名称，点击进作者主页。 */
  @Builder
  private immersiveAuthorRow(content: LoadedContentDetail) {
    if (contentAuthorName(content).length > 0) {
      Row({ space: 6 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(24)
            .height(24)
            .fill($r('app.color.control_background'))
          Text(contentAuthorName(content).substring(0, 1))
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
          if (contentAuthorAvatarUrl(content).length > 0) {
            Image(contentAuthorAvatarUrl(content))
              .id(`p3_${content.kind}_immersive_author_avatar`)
              .width(24)
              .height(24)
              .borderRadius(12)
              .objectFit(ImageFit.Cover)
          }
        }
          .width(24)
          .height(24)
          .clip(true)

        Text(contentAuthorName(content))
          .id(`p3_${content.kind}_immersive_author_name`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .id(`p3_${content.kind}_immersive_author_row`)
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .onClick((): void => {
        const author = content.value.author;
        if (author !== undefined && author.id.trim().length > 0) {
          const urlToken = author.urlToken ?? author.id;
          this.navigate({ name: P1DestinationName.PEOPLE, id: urlToken });
        }
      })
    }
  }

  /** 回答/文章页滚动信息头作者行（对齐上游展开顶栏 subtitle）：头像 + 名称 + 简介，点击进入用户主页。 */
  @Builder
  private contentHeaderAuthorRow(content: LoadedContentDetail) {
    if (contentAuthorName(content).length > 0) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(40)
            .height(40)
            .fill($r('app.color.control_background'))
          Text(contentAuthorName(content).substring(0, 1))
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
          if (contentAuthorAvatarUrl(content).length > 0) {
            Image(contentAuthorAvatarUrl(content))
              .id(`p3_${content.kind}_detail_header_avatar`)
              .width(40)
              .height(40)
              .borderRadius(20)
              .objectFit(ImageFit.Cover)
          }
        }
          .width(40)
          .height(40)
          .clip(true)

        Column({ space: 2 }) {
          Text(contentAuthorName(content))
            .id(`p3_${content.kind}_detail_header_author`)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (contentAuthorHeadline(content).length > 0) {
            Text(contentAuthorHeadline(content))
              .fontSize($r('app.float.p1_caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
      }
      .id(`p3_${content.kind}_detail_header_author_row`)
      .width('100%')
      .onClick((): void => {
        const author = content.value.author;
        if (author !== undefined && author.id.trim().length > 0) {
          const urlToken = author.urlToken ?? author.id;
          this.navigate({ name: P1DestinationName.PEOPLE, id: urlToken });
        }
      })
    }
  }

  /** 回答页顶栏折叠联动：正文滚过问题标题（高度经 onAreaChange 实测，未测得前用 64vp 兜底）
   * 即折叠，滚回复原；经 AppStorage 广播给 HDS 标题栏（同问题页 160px 阈值模式）。
   * 通道键固定用路由 contentId（标题栏按 destination.id 查找，过滑切换回答不改路由，
   * activeContentId 会随切换漂移导致顶栏读到陈旧条目）；闭包捕获的 content 是构造时
   * 的克隆（@Builder 传值不更新已挂载子组件属性，且控制器每次 emit 都换新克隆），
   * 陈旧判定只能按内容 id 比较——id 不同才说明是切换期间的陈旧回调，直接丢弃。 */
  private updateAnswerTitleScrolled(content: LoadedContentDetail, offset: number): void {
    if (content.kind !== ContentDetailKind.ANSWER || content.value.id !== this.content?.value.id) {
      return;
    }
    const threshold = this.contentTitleHeightVp > 0 ? this.contentTitleHeightVp + 8 : 64;
    const scrolled = offset > threshold;
    if (scrolled !== this.answerQuestionScrolled) {
      this.answerQuestionScrolled = scrolled;
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
        publishAnswerTitle({
          id: this.contentId,
          questionTitle: contentContextTitle(content),
          authorName: contentAuthorName(content),
          authorAvatarUrl: contentAuthorAvatarUrl(content),
          scrolled: scrolled
        });
      });
    }
  }

  /** 文章页顶栏折叠联动：信息头入列随正文滚动，滚过文章主标题（高度经 onAreaChange 实测，
   * 未测得前用 64vp 兜底）即折叠为顶栏"标题 + 作者"两行，滚回复原；经 AppStorage 广播给
   * HDS 标题栏（对齐回答页模式，通道键固定用路由 contentId，陈旧回调按内容 id 丢弃）。 */
  private updateArticleTitleScrolled(content: LoadedContentDetail, offset: number): void {
    if (content.kind !== ContentDetailKind.ARTICLE || content.value.id !== this.content?.value.id) {
      return;
    }
    const threshold = this.contentTitleHeightVp > 0 ? this.contentTitleHeightVp + 8 : 64;
    const scrolled = offset > threshold;
    if (scrolled !== this.articleTitleScrolled) {
      this.articleTitleScrolled = scrolled;
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
        publishArticleTitle({
          id: this.contentId,
          title: contentContextTitle(content),
          authorName: contentAuthorName(content),
          authorAvatarUrl: contentAuthorAvatarUrl(content),
          scrolled: scrolled
        });
      });
    }
  }

  @Builder
  private questionDocument(content: LoadedContentDetail) {
    Refresh({ refreshing: $$this.refreshingAnswers, refreshingContent: this.refreshContent }) {
      NativeContentDocument({
        html: contentHtml(content), emptyMessage: contentEmptyMessage(content), collapsible: true,
        documentHeader: (): void => { this.contentHeader(content) },
        documentBodyFooter: (): void => { this.questionBodyFooter(content) },
        documentItems: (): void => { this.questionAnswerItems() },
        documentFooter: (): void => { this.questionAnswersFooter() },
        onListReachEnd: (): void => { this.answersController?.loadMore(); },
        onScrollOffset: (offset: number): void => {
          const scrolled = offset > 160;
          if (scrolled !== this.questionScrolled) {
            this.questionScrolled = scrolled;
            this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
              publishQuestionTitle({ id: this.activeContentId, title: contentTitle(content), scrolled: scrolled });
            });
          }
        }
      })
    }.height('100%').width('100%').onRefreshing((): void => { void this.refreshQuestion(); })
  }

  @Builder
  private questionBodyFooter(content: LoadedContentDetail) {
    Column({ space: 12 }) {
        if (content.kind === ContentDetailKind.QUESTION &&
          (content.value.topics?.length ?? 0) > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(content.value.topics, (topic: QuestionTopicSummary): void => {
              Button(`# ${topic.name}`, { type: ButtonType.Normal, stateEffect: true })
                .id(`p3_question_topic_${topic.id}`)
                .height(30)
                .fontSize($r('app.float.p1_caption_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .backgroundColor($r('app.color.surface_background'))
                .borderRadius(15)
                .margin({ right: 8, bottom: 8 })
                .onClick((): void => this.navigate({ name: P1DestinationName.SEARCH, query: topic.name }))
            }, (topic: QuestionTopicSummary): string => topic.id)
          }
          .width('100%')
        }


      Button('写回答')
        .id('question_write_answer').width('100%')
        .onClick((): void => this.navigate(this.authenticated
          ? { name: P1DestinationName.WRITE_ANSWER, questionId: this.activeContentId }
          : { name: P1DestinationName.LOGIN }))
      Row() {
        Text(this.questionAnswerCount().toString() + ' 回答').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text')).layoutWeight(1)
        SegmentButton({ options: this.answersSortOptions, selectedIndexes: $answersSortIndexes,
          onItemClicked: (index: number): void => this.selectAnswerSort(index) })
          .id('question_sort').width(168).height(36)
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private questionAnswerItems() {
    LazyForEach(this.answerDataSource, (item: ChannelContentItem) => {
      ListItem() { this.answerFeedCard(item) }
    }, (item: ChannelContentItem): string => feedItemIdentity(item.feedItem))
  }

  @Builder
  private userBlockDialog() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text(`确定要屏蔽用户「${this.pendingUserBlock?.userName ?? ''}」吗？`)
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Text('屏蔽后，该作者的内容将不再显示。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => {
            this.pendingUserBlock = undefined;
          })
        Button('确定屏蔽')
          .id(`p3_${this.kind}_confirm_block_user`)
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => this.confirmUserBlock())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private keywordBlockDialog() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('输入要屏蔽的关键词（普通文本，不区分大小写）')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      TextInput({ text: this.keywordBlockInput, placeholder: '输入关键词' })
        .id(`p3_${this.kind}_keyword_block_input`)
        .maxLength(200)
        .onChange((value: string): void => {
          this.keywordBlockInput = value;
        })
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => {
            this.keywordBlockVisible = false;
            this.keywordBlockInput = '';
          })
        Button('确认屏蔽')
          .id(`p3_${this.kind}_confirm_block_keyword`)
          .layoutWeight(1)
          .enabled(!this.blockingBusy && this.keywordBlockInput.trim().length > 0)
          .onClick((): void => this.confirmKeywordBlock())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  private confirmUserBlock(): void {
    const pending = this.pendingUserBlock;
    const action = this.blockingAction;
    const content = this.content;
    if (pending === undefined || action === undefined || content === undefined) {
      return;
    }
    this.pendingUserBlock = undefined;
    action.blockUser(pending.userId, pending.userName, this.blockContext(content));
  }

  private confirmKeywordBlock(): void {
    const action = this.blockingAction;
    const input = this.keywordBlockInput;
    const content = this.content;
    this.keywordBlockVisible = false;
    this.keywordBlockInput = '';
    if (action === undefined || input.trim().length === 0 || content === undefined) {
      return;
    }
    action.blockKeyword(input, this.blockContext(content));
  }

  private blockContext(content: LoadedContentDetail): BlockingActionContext {
    return {
      contentTitle: contentBlockingTitle(content),
      contentKind: content.kind,
      contentId: content.value.id
    };
  }

        @Builder
  private bottomActionBar() {
    // 沉浸光感玻璃胶囊：左右两块独立悬浮胶囊（PR 的空 HdsTabs 材质画布方案），
    // 由全屏悬浮层单实例承载，正文从下方穿透直至物理底边（窗口为全屏布局，无避让空带）。
    Column({ space: $r('app.float.p1_spacing_xsmall') }) {
      if (this.interactionErrorMessage.length > 0) {
        this.interactionStatusRow()
      }
      Row({ space: $r('app.float.p1_spacing_small') }) {
        if (this.kind === ContentDetailKind.QUESTION) {
          GlassCapsule({ useMaterial: this.immersiveMaterialSupported }) {
            if (this.followController !== undefined) {
              this.followQuestionAction()
            }
          }

          Blank()
            .layoutWeight(1)

          GlassCapsule({ useMaterial: this.immersiveMaterialSupported }) {
            this.questionRightActions()
          }
        } else {
          GlassCapsule({ useMaterial: this.immersiveMaterialSupported }) {
            Row({ space: 0 }) {
              if (this.voteState !== ContentVoteState.DOWN) {
                this.voteUpAction()
              }
              if (this.voteState !== ContentVoteState.UP) {
                this.voteDownAction()
              }
            }
          }

          Blank()
            .layoutWeight(1)

          GlassCapsule({ useMaterial: this.immersiveMaterialSupported }) {
            this.answerRightActions()
          }
        }
      }
      .width('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        bottom: 12
      })
    }
    .width('100%')
    .zIndex(2)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private answerRightActions() {
    if (this.canEditExistingAnswer()) {
      Button('编辑')
        .id('p4_answer_edit_existing')
        .height(44)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .onClick((): void => this.openExistingAnswerEditor())
    }

    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.bookmark'))
        .fontSize(22)
        .fontColor([$r('app.color.secondary_text')])
    }
    .id(`p3_${this.kind}_detail_favorite_bar`)
    .width(40)
    .height(44)
    .backgroundColor(Color.Transparent)
    .onClick((): void => {
      if (this.collectionRepository !== undefined && this.session !== undefined) {
        this.favoriteDialogShown = true;
      } else {
        this.navigate({ name: P1DestinationName.LOGIN });
      }
    })

    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(22)
          .fontColor([$r('app.color.secondary_text')])
        Text(`${this.content?.value.commentCount ?? 0}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.secondary_text'))
      }
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    }
    .id(`p3_${this.kind}_detail_comment_bar`)
    .height(44)
    .backgroundColor(Color.Transparent)
    .onClick((): void => {
      if (this.commentRepository !== undefined && this.session !== undefined) {
        this.showComments = true;
      } else {
        this.navigate({ name: P1DestinationName.LOGIN });
      }
    })

    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(22)
        .fontColor([$r('app.color.secondary_text')])
    }
    .id(`p3_${this.kind}_detail_more`)
    .width(40)
    .height(44)
    .backgroundColor(Color.Transparent)
    .onClick((): void => {
      this.actionMenuShown = true;
    })
  }

  @Builder
  private questionRightActions() {
    // 对齐回答详情页右下角动作组：评论 + 更多（问题暂无投票/收藏端点，见 ContentDetailPages 注释）。
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(22)
          .fontColor([$r('app.color.secondary_text')])
        Text(`${this.content?.value.commentCount ?? 0}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.secondary_text'))
      }
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    }
    .id('p3_question_detail_comment_bar')
    .height(44)
    .backgroundColor(Color.Transparent)
    .accessibilityText('问题评论')
    .onClick((): void => {
      if (this.commentRepository !== undefined && this.session !== undefined) {
        this.showComments = true;
      } else {
        this.navigate({ name: P1DestinationName.LOGIN });
      }
    })

    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(22)
        .fontColor([$r('app.color.secondary_text')])
    }
    .id('p3_question_detail_more')
    .width(40)
    .height(44)
    .backgroundColor(Color.Transparent)
    .accessibilityText('更多问题操作')
    .onClick((): void => {
      this.actionMenuShown = true;
    })
  }

  /** 问题页统计项：小图标 + 辅助文字（对齐上游 StatItem）。 */
  @Builder
  private questionStatItem(icon: Resource, text: string) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(14)
        .fontColor([$r('app.color.secondary_text')])
      Text(text)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 问题页回答信息流 footer：挂载在正文文档列表末尾，随同一滚动贯通（对齐上游单列表）。
   * 注意：@BuilderParam 传入的箭头闭包体内只允许直接调用本 builder（不得再包 if 等非 UI
   * 语句，否则编译器不转换 builder 调用，运行时静默不渲染）；kind 守卫放在 builder 内部。
   */
  @Builder
  private questionAnswersFooter() {
    if (this.kind === ContentDetailKind.QUESTION) {
      Column({ space: 12 }) {
        if (!this.authenticated) {
          AppPageStatusPanel({ kind: AppPageStatusKind.EMPTY, message: '登录后即可查看全部回答',
            testId: 'question_answers_login', actionLabel: '去登录', actionId: 'question_answers_login_button',
            onAction: (): void => this.navigate({ name: P1DestinationName.LOGIN }) })
        } else if (this.answersState.phase === QuestionAnswersPhase.INITIAL_LOADING) {
          AppPageStatusPanel({ message: '正在加载回答…', testId: 'question_answers_loading' })
        } else if (this.answersState.errorMessage.length > 0) {
          AppPageStatusPanel({ kind: AppPageStatusKind.ERROR, message: this.answersState.errorMessage,
            testId: 'question_answers_error', actionLabel: this.answersState.requiresLogin ? '去登录' : '重试',
            actionId: 'question_answers_retry', onAction: (): void => {
              if (this.answersState.requiresLogin) { this.navigate({ name: P1DestinationName.LOGIN }); }
              else if (this.answersState.phase === QuestionAnswersPhase.ERROR) { this.answersController?.refresh(); }
              else { this.answersController?.loadMore(); }
            } })
        } else if (this.answersState.phase === QuestionAnswersPhase.EMPTY) {
          AppPageStatusPanel({ kind: AppPageStatusKind.EMPTY, message: '暂无可显示的回答', testId: 'question_answers_empty' })
        } else if (this.answersState.loadingMore) {
          LoadingProgress().id('p3_question_answers_loading_more').width(40).height(40)
            .color($r('app.color.brand_primary'))
        } else if (this.answersState.canLoadMore) {
          Button('加载更多回答').id('question_answers_more')
            .onClick((): void => { this.answersController?.loadMore(); })
        } else {
          Text('已显示全部回答').fontColor($r('app.color.secondary_text'))
        }
      }.width('100%').padding({ top: 12, bottom: 12 })
    }
  }

  @Builder
  private answerFeedCard(item: ChannelContentItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      FeedContentSummary({ target: item.feedItem.target, showTitle: false })
    }.id('p3_question_answers_card_' + item.feedItem.target.id)
      .width('100%').padding($r('app.float.p1_card_padding'))
      .borderRadius($r('app.float.p1_card_radius')).backgroundColor($r('app.color.surface_background'))
      .accessibilityText('打开回答').onClick((): void => {
        const repository = this.questionAnswerFeedFactory();
        const seed = this.answersController?.snapshot();
        if (repository !== undefined && seed !== undefined) {
          stageQuestionAnswerNavigator(new QuestionAnswerNavigator(this.activeContentId,
            item.feedItem.target.id, seed, repository));
        }
        this.navigate({ name: P1DestinationName.ANSWER, id: item.feedItem.target.id });
      })
  }

  // SegmentButton 的 options 是 @ObjectLink，须放观察状态（内联对象在真机上会丢点击回调）。
  @State private answersSortOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '默认' }, { text: '最新' }]
  });

  private questionAnswerCount(): number {
    const content = this.content;
    if (content === undefined || content.kind !== ContentDetailKind.QUESTION) {
      return 0;
    }
    return content.value.answerCount;
  }

  private selectAnswerSort(index: number): void {
    if (index !== 0 && index !== 1) {
      return;
    }
    if (this.answersSortIndexes[0] !== index) {
      this.answersSortIndexes = [index];
    }
    const order = index === 0 ? QuestionAnswerSortOrder.DEFAULT : QuestionAnswerSortOrder.UPDATED;
    this.answersController?.setSortOrder(order);
  }

  private navigatorHasPrevious(): boolean {
    return this.navigatorRevision >= 0 && (this.answerNavigator?.hasPrevious() ?? false);
  }
  private navigatorHasNext(): boolean {
    return this.navigatorRevision >= 0 && (this.answerNavigator?.hasNext() ?? false);
  }
  /** 双击正文动作分发（对齐上游 performAnswerDoubleTapAction）：仅回答页生效；
   * 震感仅点赞与打开评论区有；Ask 弹询问面板，选择后记住。 */
  private onAnswerDoubleTap(): void {
    if (this.kind !== ContentDetailKind.ANSWER) {
      return;
    }
    const action = this.answerDoubleTapAction;
    if (action === AnswerDoubleTapAction.NONE) {
      return;
    }
    if (action === AnswerDoubleTapAction.OPEN_COMMENTS) {
      performConfirmHaptic();
      this.showComments = true;
      return;
    }
    if (action === AnswerDoubleTapAction.TOGGLE_IMMERSIVE) {
      this.immersiveReading = !this.immersiveReading;
      return;
    }
    if (action === AnswerDoubleTapAction.VOTE_UP) {
      performConfirmHaptic();
      void this.voteController?.voteUpFromDoubleTap();
      return;
    }
    this.doubleTapAskSheetShown = true;
  }

  /** 读取双击动作偏好；失败保持默认 Ask，不影响双击可用性。 */
  private async restoreAnswerDoubleTapAction(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    try {
      const action = await new AppPreferencesStore(context).loadAnswerDoubleTapAction();
      if (this.pageActive) {
        AppStorage.setOrCreate('answerDoubleTapAction', action);
      }
    } catch (_error) {
    }
  }

  /** 保存双击动作（询问面板与设置页共用）：先广播 AppStorage 再落盘，提示文案对齐上游。 */
  private saveAnswerDoubleTapAction(action: AnswerDoubleTapAction): void {
    AppStorage.setOrCreate('answerDoubleTapAction', action);
    const context = getAbilityContext();
    if (context !== undefined) {
      void new AppPreferencesStore(context).saveAnswerDoubleTapAction(action).catch((_error: Object): void => {
      });
    }
    this.getUIContext().getPromptAction()
      .showToast({ message: `已将双击回答动作设为：${answerDoubleTapActionLabel(action)}` });
  }

  private async moveAnswer(direction: number): Promise<void> {
    if (this.navigatorBusy) { return; }
    this.navigatorBusy = true;
    this.resetAnswerOverscroll(false);
    // 新内容从顶部渲染：边界状态归位，避免沿用上一答的贴底状态误触发底部过滑。
    this.contentAtBottom = false;
    this.contentAtTop = true;
    // 顶栏折叠态随新答复位：新内容从顶部渲染，问题标题回到视口内。
    this.answerQuestionScrolled = false;
    try {
      const id = await this.answerNavigator?.move(direction);
      this.navigatorRevision += 1;
      if (!this.pageActive) { return; }
      if (id === undefined) {
        const message = this.answerNavigator?.errorMessage() ?? '';
        this.getUIContext().getPromptAction()
          .showToast({ message: message.length > 0 ? message : '暂时无法切换回答' });
        return;
      }
      this.voteController?.deactivate();
      this.voteController = undefined;
      this.showComments = false;
      this.favoriteDialogShown = false;
      this.commentRootDraft = '';
      this.commentReplyDraft = '';
      this.activeContentId = id;
      await this.controller?.load(ContentDetailKind.ANSWER, id);
    } finally { this.navigatorBusy = false; }
  }

  /** 贴边后的继续滑动量按 tanh 阻尼转为 overscroll 偏移：贴顶下拉为正（上一答卡），
   * 贴底上滑为负（下一答卡）；反向回拉等量削减。 */
  private onAnswerOverscrollPanUpdate(event: GestureEvent): void {
    if (this.kind !== ContentDetailKind.ANSWER || this.answerFabDragging) { return; }
    const delta = event.offsetY - this.overscrollPanPrevY;
    this.overscrollPanPrevY = event.offsetY;
    if (delta < 0) {
      // 手指上移：贴底加深"下一答"过滑，或回拉已展开的"上一答"过滑。
      if (this.contentAtBottom && this.navigatorHasNext() && !this.navigatorBusy) {
        this.overscrollRawDrag += delta;
      } else if (this.answerOverscrollOffset > 0) {
        this.overscrollRawDrag = Math.max(0, this.overscrollRawDrag + delta);
      } else {
        return;
      }
    } else if (delta > 0) {
      // 手指下移：贴顶加深"上一答"过滑，或回拉已展开的"下一答"过滑。
      if (this.contentAtTop && this.navigatorHasPrevious() && !this.navigatorBusy) {
        this.overscrollRawDrag += delta;
      } else if (this.answerOverscrollOffset < 0) {
        this.overscrollRawDrag = Math.min(0, this.overscrollRawDrag + delta);
      } else {
        return;
      }
    } else {
      return;
    }
    this.answerOverscrollOffset = dampedOverscrollOffset(this.overscrollRawDrag,
      ANSWER_OVERSCROLL_MAX_OFFSET, ANSWER_OVERSCROLL_DAMPING_FACTOR);
  }

  /** 松手：达到阈值切换回答（顶部过滑切上一答、底部过滑切下一答，无回弹）；否则弹簧回位。 */
  private onAnswerOverscrollPanEnd(): void {
    if (this.kind !== ContentDetailKind.ANSWER || this.answerOverscrollOffset === 0) {
      this.overscrollRawDrag = 0;
      return;
    }
    const previous = this.answerOverscrollOffset > 0;
    const triggered = this.answerOverscrollTriggered() && !this.navigatorBusy &&
      (previous ? this.navigatorHasPrevious() : this.navigatorHasNext());
    this.overscrollRawDrag = 0;
    if (triggered) {
      this.resetAnswerOverscroll(false);
      void this.moveAnswer(previous ? -1 : 1);
      return;
    }
    this.getUIContext().animateTo({ curve: curves.springMotion(0.32, 0.78) }, (): void => {
      this.answerOverscrollOffset = 0;
    });
  }

  /** 切换回答/页面离开时归零 overscroll（animated=false 跳过回弹动画）。 */
  private resetAnswerOverscroll(animated: boolean): void {
    if (this.answerOverscrollOffset === 0 && this.overscrollRawDrag === 0) { return; }
    this.overscrollRawDrag = 0;
    if (animated) {
      this.getUIContext().animateTo({ curve: curves.springMotion(0.32, 0.78) }, (): void => {
        this.answerOverscrollOffset = 0;
      });
    } else {
      this.answerOverscrollOffset = 0;
    }
  }

  private answerOverscrollTriggered(): boolean {
    return Math.abs(this.answerOverscrollOffset) >= ANSWER_OVERSCROLL_TRIGGER_THRESHOLD;
  }

  private answerOverscrollProgress(): number {
    return Math.min(1, Math.abs(this.answerOverscrollOffset) / ANSWER_OVERSCROLL_TRIGGER_THRESHOLD);
  }

  /** 过滑方向对应的预览数据：previous=true 取上一答，否则取下一答。 */
  private answerPreviewData(previous: boolean): AnswerNavigationPreview | undefined {
    return previous ? this.answerNavigator?.previousAnswerPreview() : this.answerNavigator?.nextAnswerPreview();
  }

  private answerPreviewAuthorName(previous: boolean): string {
    return this.answerPreviewData(previous)?.authorName ?? '';
  }

  private answerPreviewAvatarUrl(previous: boolean): string {
    return this.answerPreviewData(previous)?.authorAvatarUrl ?? '';
  }

  private answerPreviewExcerpt(previous: boolean): string {
    const preview = this.answerPreviewData(previous);
    if (preview === undefined || !preview.detailLoaded) { return ''; }
    return preview.excerpt;
  }

  private canEditExistingAnswer(): boolean {
    const content = this.content;
    const session = this.session;
    const profile = session?.getState().profile;
    return content !== undefined && content.kind === ContentDetailKind.ANSWER &&
      session?.getState().status === SessionStatus.AUTHENTICATED && profile !== undefined &&
      content.value.author?.id === profile.id;
  }

  /** 只从当前已加载、且作者与登录身份精确一致的回答建立一次性编辑种子。 */
  private openExistingAnswerEditor(): void {
    const content = this.content;
    if (!this.canEditExistingAnswer() || content === undefined || content.kind !== ContentDetailKind.ANSWER) {
      return;
    }
    if (!stageAnswerEditSeed(content.value.id, content.value.contentHtml)) {
      return;
    }
    this.navigate({
      name: P1DestinationName.WRITE_ANSWER,
      questionId: content.value.questionId,
      answerId: content.value.id
    });
  }

  @Builder
  private actionMenuSheet() {
    // 分享、复制链接与屏蔽操作放入 API 26 系统半模态；尚未接线的能力不显示占位项。
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('更多操作')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_detail_menu_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭更多操作')
          .onClick((): void => {
            this.actionMenuShown = false;
          })
      }
      .width('100%')

      Button('分享', { type: ButtonType.Normal, stateEffect: true })
        .id('p3_detail_menu_share')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .onClick((): void => {
          this.actionMenuShown = false;
          this.shareContentLink();
        })

      Button('复制链接', { type: ButtonType.Normal, stateEffect: true })
        .id('p3_detail_menu_copy_link')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .onClick((): void => {
          this.actionMenuShown = false;
          this.copyContentLink();
        })

      if (this.menuStatus.length > 0) {
        Text(this.menuStatus)
          .id('p3_detail_menu_status')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }

      if (this.kind === ContentDetailKind.ANSWER || this.kind === ContentDetailKind.ARTICLE) {
        Button('沉浸式阅读', { type: ButtonType.Normal, stateEffect: true })
          .id(`p3_${this.kind}_detail_immersive`)
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.control_background'))
          .borderRadius($r('app.float.p1_card_radius'))
          .onClick((): void => {
            this.actionMenuShown = false;
            this.immersiveReading = true;
            // 对齐上游菜单提示：沉浸式下返回键优先退出沉浸式而非退出回答。
            this.getUIContext().getPromptAction()
              .showToast({ message: '已进入沉浸式，按返回键即可退出' });
          })
      }

      if (this.content !== undefined && contentAuthorName(this.content).length > 0) {
        Button('屏蔽作者', { type: ButtonType.Normal, stateEffect: true })
          .id(`p3_${this.kind}_block_author`)
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.control_background'))
          .borderRadius($r('app.float.p1_card_radius'))
          .enabled(!this.blockingBusy && this.blockingAction !== undefined)
          .onClick((): void => {
            const content = this.content;
            const author = content?.value.author;
            if (author !== undefined) {
              this.actionMenuShown = false;
              this.pendingUserBlock = { userId: author.id, userName: author.name };
            }
          })
      }

      Button('屏蔽关键词', { type: ButtonType.Normal, stateEffect: true })
        .id(`p3_${this.kind}_block_keyword`)
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .enabled(!this.blockingBusy && this.blockingAction !== undefined)
        .onClick((): void => {
          this.actionMenuShown = false;
          this.keywordBlockInput = '';
          this.keywordBlockVisible = true;
        })

    }
    .id('p3_detail_menu_sheet')
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
  }

  /** 双击动作询问面板（对齐上游 showDoubleTapActionDialog）：每项保存偏好并立即执行该动作。 */
  @Builder
  private doubleTapAskSheet() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('设置双击回答动作')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('选择以后双击回答时默认执行的动作。选择后会立即保存到设置，你也可以稍后在设置中修改。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Button('设为无操作', { type: ButtonType.Normal, stateEffect: true })
        .id('p3_answer_double_tap_none')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveAnswerDoubleTapAction(AnswerDoubleTapAction.NONE);
        })
      Button('设为点赞', { type: ButtonType.Normal, stateEffect: true })
        .id('p3_answer_double_tap_vote_up')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveAnswerDoubleTapAction(AnswerDoubleTapAction.VOTE_UP);
          performConfirmHaptic();
          void this.voteController?.voteUpFromDoubleTap();
        })
      Button('设为打开评论区', { type: ButtonType.Normal, stateEffect: true })
        .id('p3_answer_double_tap_open_comments')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveAnswerDoubleTapAction(AnswerDoubleTapAction.OPEN_COMMENTS);
          performConfirmHaptic();
          this.showComments = true;
        })
      Button('设为开关沉浸式', { type: ButtonType.Normal, stateEffect: true })
        .id('p3_answer_double_tap_toggle_immersive')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveAnswerDoubleTapAction(AnswerDoubleTapAction.TOGGLE_IMMERSIVE);
          this.immersiveReading = !this.immersiveReading;
        })
    }
    .id('p3_answer_double_tap_sheet')
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
  }

  private copyContentLink(): void {
    const content = this.content;
    if (content === undefined) {
      return;
    }
    const url = content.value.url;
    if (url.trim().length === 0) {
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(pasteData).then((): void => {
        this.menuStatus = '已复制链接';
      }).catch((_error: Error): void => {
        this.menuStatus = '复制失败，请重试';
      });
    } catch (_error) {
      this.menuStatus = '复制失败，请重试';
    }
  }

  /** 详情分享只交给 HarmonyOS 系统面板，且仅传通过平台白名单校验的内容 URL。 */
  private shareContentLink(): void {
    const content = this.content;
    const context = getAbilityContext();
    if (content === undefined || context === undefined || content.value.url.trim().length === 0) {
      this.menuStatus = '暂时无法打开分享面板';
      return;
    }
    const payload: ShareTextPayload = {
      kind: SharePayloadKind.TEXT,
      title: contentDetailPageTitle(content.kind),
      summary: '来自知乎++的受信内容链接',
      contentUrl: content.value.url
    };
    createSystemShareService(context).share(payload).then((outcome: ShareOutcome): void => {
      this.menuStatus = outcome === ShareOutcome.CANCELLED ? '' : '已打开系统分享面板';
    }).catch((): void => {
      this.menuStatus = '暂时无法打开分享面板';
    });
  }

  @Builder
  private endorsementFlow(endorsements: Array<AnswerEndorsementDisplay>) {
    // P3-9-D1：认可徽章流（对齐上游 FlowRow 胶囊）；用 Flex 换行近似流式布局。
    Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
      ForEach(endorsements, (endorsement: AnswerEndorsementDisplay) => {
        Row({ space: 4 }) {
          Text(endorsement.text)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor(endorsementTextColor(endorsement))
            .maxLines(1)
        }
        .padding({
          left: 10,
          right: 10,
          top: 5,
          bottom: 5
        })
        .borderRadius(16)
        .backgroundColor(endorsementBackgroundColor(endorsement))
        .margin({ right: $r('app.float.p1_spacing_small'), bottom: $r('app.float.p1_spacing_small') })
      }, (endorsement: AnswerEndorsementDisplay): string => endorsement.text)
    }
    .id(`p3_${this.kind}_detail_endorsements`)
    .width('100%')
  }

  @Builder
  private voteUpAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {

      Row({ space: 6 }) {
        SymbolGlyph(this.voteState === ContentVoteState.UP
            ? $r('sys.symbol.arrowtriangle_left_fill')
            : $r('sys.symbol.arrowtriangle_left'))
          .fontSize(22)
          .fontColor([$r('app.color.brand_primary')])
          .rotate({ x: 0, y: 0, z: 1, angle: 90 })
        Text(`${this.voteupCount}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(this.voteState === ContentVoteState.UP ? FontWeight.Bold : FontWeight.Medium)
          .fontColor($r('app.color.brand_primary'))
      }
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    }
    .id(`p3_${this.kind}_vote_up`)
    .backgroundColor(Color.Transparent)
    .lightUpEffect(1)
    .enabled(!this.interactionPending)
    .onClick((): void => {
      this.voteController?.toggleVote(true);
    })
  }

  @Builder
  private voteDownAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {

      Row({ space: 6 }) {
        // 左三角旋转 -90°（逆时针）得到向下方向；选中实心、未选中描边。
        SymbolGlyph(this.voteState === ContentVoteState.DOWN
            ? $r('sys.symbol.arrowtriangle_left_fill')
            : $r('sys.symbol.arrowtriangle_left'))
          .fontSize(22)
          .fontColor([$r('app.color.brand_primary')])
          .rotate({ x: 0, y: 0, z: 1, angle: -90 })
      }
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    }
    .id(`p3_${this.kind}_vote_down`)
    .backgroundColor(Color.Transparent)
    .lightUpEffect(1)
    .enabled(!this.interactionPending)
    .onClick((): void => {
      this.voteController?.toggleVote(false);
    })
  }

  @Builder
  private followQuestionAction() {
    // 对齐回答详情页底部动作语言：透明背景 + 符号 + 次要色文字，玻璃胶囊由外层承载。
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 5 }) {
        SymbolGlyph(this.following ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'))
          .fontSize(22)
          .fontColor([this.following ? $r('app.color.brand_primary') : $r('app.color.secondary_text')])
        Text(this.following ? `已关注 ${this.followerCount}` : `关注问题 ${this.followerCount}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.following ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
      }
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    }
      .id('p3_question_follow')
      .height(44)
      .backgroundColor(Color.Transparent)
      .enabled(!this.interactionPending)
      .onClick((): void => {
        this.followController?.toggleFollow();
      })
  }

  @Builder
  private interactionStatusRow() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Text(this.interactionErrorMessage)
        .id(`p3_${this.kind}_interaction_status`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.error_text'))
        .layoutWeight(1)
      if (this.interactionRequiresLogin) {
        Button('去登录')
          .id(`p3_${this.kind}_interaction_login`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .onClick((): void => {
            this.navigate({ name: P1DestinationName.LOGIN });
          })
      }
    }
    .width('100%')
  }

  private applyState(state: ContentDetailViewState): void {
    this.phase = state.phase;
    this.content = state.content;
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
    this.openedRecordPhase = state.openedRecordPhase;
    if (state.phase === ContentDetailPhase.READY && state.content !== undefined) {
      this.activateInteraction(state.content);
      if (state.content.kind === ContentDetailKind.QUESTION) {
        publishQuestionTitle({ id: this.activeContentId, title: state.content.value.title, scrolled: this.questionScrolled });
      }
      if (state.content.kind === ContentDetailKind.ANSWER) {
        publishAnswerTitle({
          id: this.contentId,
          questionTitle: contentContextTitle(state.content),
          authorName: contentAuthorName(state.content),
          authorAvatarUrl: contentAuthorAvatarUrl(state.content),
          scrolled: this.answerQuestionScrolled
        });
      }
      if (state.content.kind === ContentDetailKind.ARTICLE) {
        publishArticleTitle({
          id: this.contentId,
          title: contentContextTitle(state.content),
          authorName: contentAuthorName(state.content),
          authorAvatarUrl: contentAuthorAvatarUrl(state.content),
          scrolled: this.articleTitleScrolled
        });
      }
      if (state.content.kind === ContentDetailKind.ANSWER && this.answerNavigator === undefined) {
        this.ensureAnswerNavigator(state.content.value.questionId);
      }
    }
  }

  /** 信息流直达的回答页没有暂存导航器：按回答归属问题自建（对齐上游 ArticleViewModel）。 */
  private ensureAnswerNavigator(questionId: string): void {
    const repository = this.questionAnswerFeedFactory();
    if (repository === undefined) { return; }
    this.answerNavigator = new QuestionAnswerNavigator(questionId, this.activeContentId, undefined, repository,
      (): void => { this.navigatorRevision += 1; });
  }

  private activateInteraction(content: LoadedContentDetail): void {
    if (content.kind === ContentDetailKind.QUESTION) {
      if (this.followController !== undefined || this.followRepository === undefined || this.session === undefined) {
        return;
      }
      const repository = this.followRepository;
      const session = this.session;
      const contentId = this.activeContentId;
      this.followController = new FollowController(
        repository,
        session,
        (follow: boolean): Promise<FollowMutationResult> => repository.followQuestion(contentId, follow),
        (state: FollowViewState): void => this.applyFollowState(state)
      );
      this.followController.activate();
      this.followController.applyInitial(content.value.isFollowing ?? false, content.value.followerCount);
    } else {
      if (this.voteController !== undefined || this.voteRepository === undefined || this.session === undefined) {
        return;
      }
      this.voteController = new ContentVoteController(
        this.voteRepository,
        this.session,
        this.kind,
        this.activeContentId,
        (state: ContentVoteViewState): void => this.applyVoteState(state)
      );
      this.voteController.activate();
      this.voteController.applyInitial(content);
    }
  }

  private applyVoteState(state: ContentVoteViewState): void {
    this.voteState = state.voteState;
    this.voteupCount = state.voteupCount;
    this.thanked = state.thanked;
    this.thanksCount = state.thanksCount;
    this.interactionPending = state.pending;
    this.interactionErrorMessage = state.errorMessage ?? '';
    this.interactionRequiresLogin = state.requiresLogin;
  }

  private applyFollowState(state: FollowViewState): void {
    this.following = state.following;
    this.followerCount = state.followerCount;
    this.interactionPending = state.pending;
    this.interactionErrorMessage = state.errorMessage ?? '';
    this.interactionRequiresLogin = state.requiresLogin;
  }

  /** 互动状态机激活后，信息头与底栏使用同一份实时计数；初次加载前保留接口原始值。 */
  private displayedContentStatistics(content: LoadedContentDetail): string {
    return contentStatistics(content,
      this.voteController === undefined ? undefined : this.voteupCount,
      this.followController === undefined ? undefined : this.followerCount);
  }
}

@Component
export struct QuestionDetailPage {
  questionAnswerFeedFactory: () => QuestionAnswerFeedRepository | undefined = () => undefined;
  contentId: string = '';
  repository: ContentRepository | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  voteRepository: VoteRepository | undefined = undefined;
  followRepository: FollowRepository | undefined = undefined;
  collectionRepository: CollectionRepository | undefined = undefined;
  commentRepository: CommentRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onBack: () => void = (): void => {
  };

  build() {
    ContentDetailPage({
      kind: ContentDetailKind.QUESTION,
      questionAnswerFeedFactory: this.questionAnswerFeedFactory,
      contentId: this.contentId,
      repository: this.repository,
      openedContentStore: this.openedContentStore,
      rules: this.rules,
      history: this.history,
      voteRepository: this.voteRepository,
      followRepository: this.followRepository,
      collectionRepository: this.collectionRepository,
      commentRepository: this.commentRepository,
      session: this.session,
      navigate: this.navigate,
      onBack: this.onBack
    })
  }
}

@Component
export struct AnswerDetailPage {
  questionAnswerFeedFactory: () => QuestionAnswerFeedRepository | undefined = () => undefined;
  contentId: string = '';
  repository: ContentRepository | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  voteRepository: VoteRepository | undefined = undefined;
  followRepository: FollowRepository | undefined = undefined;
  collectionRepository: CollectionRepository | undefined = undefined;
  commentRepository: CommentRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onBack: () => void = (): void => {
  };

  build() {
    ContentDetailPage({
      kind: ContentDetailKind.ANSWER,
      questionAnswerFeedFactory: this.questionAnswerFeedFactory,
      contentId: this.contentId,
      repository: this.repository,
      openedContentStore: this.openedContentStore,
      rules: this.rules,
      history: this.history,
      voteRepository: this.voteRepository,
      followRepository: this.followRepository,
      collectionRepository: this.collectionRepository,
      commentRepository: this.commentRepository,
      session: this.session,
      navigate: this.navigate,
      onBack: this.onBack
    })
  }
}

@Component
export struct ArticleDetailPage {
  contentId: string = '';
  repository: ContentRepository | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  voteRepository: VoteRepository | undefined = undefined;
  followRepository: FollowRepository | undefined = undefined;
  collectionRepository: CollectionRepository | undefined = undefined;
  commentRepository: CommentRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onBack: () => void = (): void => {
  };

  build() {
    ContentDetailPage({
      kind: ContentDetailKind.ARTICLE,
      contentId: this.contentId,
      repository: this.repository,
      openedContentStore: this.openedContentStore,
      rules: this.rules,
      history: this.history,
      voteRepository: this.voteRepository,
      followRepository: this.followRepository,
      collectionRepository: this.collectionRepository,
      commentRepository: this.commentRepository,
      session: this.session,
      navigate: this.navigate,
      onBack: this.onBack
    })
  }
}

export function contentTitle(content: LoadedContentDetail): string {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return content.value.title;
    case ContentDetailKind.ANSWER:
      return '回答';
    case ContentDetailKind.ARTICLE:
      return content.value.title;
  }
}

export function contentDetailPageTitle(kind: ContentDetailKind): string {
  switch (kind) {
    case ContentDetailKind.QUESTION:
      return '问题';
    case ContentDetailKind.ANSWER:
      return '回答';
    case ContentDetailKind.ARTICLE:
      return '文章';
  }
}

/** 详情正文信息头的主标题：回答使用所属问题，问题/文章使用自身标题。 */
export function contentContextTitle(content: LoadedContentDetail): string {
  if (content.kind === ContentDetailKind.ANSWER) {
    return content.value.questionTitle?.trim() ?? '';
  }
  return contentTitle(content).trim();
}

export function contentHtml(content: LoadedContentDetail): string {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return content.value.detailHtml;
    case ContentDetailKind.ANSWER:
    case ContentDetailKind.ARTICLE:
      return content.value.contentHtml;
  }
}

export function contentEmptyMessage(content: LoadedContentDetail): string {
  if (content.kind === ContentDetailKind.QUESTION) {
    return '问题暂时没有补充说明';
  }
  const excerpt = content.value.excerpt.trim();
  return excerpt.length > 0 ? excerpt : '正文为空';
}

export function contentAuthorName(content: LoadedContentDetail): string {
  return content.value.author?.name ?? '';
}

export function contentAuthorHeadline(content: LoadedContentDetail): string {
  return content.value.author?.headline?.trim() ?? '';
}

/** 答主头像 URL：http 归一化为 https，缺失或不受信返回空串（走首字占位）。 */
export function contentAuthorAvatarUrl(content: LoadedContentDetail): string {
  const raw = content.value.author?.avatarUrl?.trim() ?? '';
  const url = raw.startsWith('http://') ? `https://${raw.substring(7)}` : raw;
  if (!/^https:\/\/[A-Za-z0-9.-]+/.test(url)) {
    return '';
  }
  return url;
}

/** 详情时间戳（unix 秒）转本地 yyyy-MM-dd HH:mm；对齐上游 formatArticleDateTime，非法值返回空串。 */
export function formatContentDateTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '';
  }
  const date = new Date(seconds * 1000);
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** 回答/文章发布时间文案：发布于 yyyy-MM-dd HH:mm（对齐上游 DateTexts）。 */
export function contentCreatedAtText(content: LoadedContentDetail): string {
  if (content.kind !== ContentDetailKind.ANSWER && content.kind !== ContentDetailKind.ARTICLE) {
    return '';
  }
  const formatted = formatContentDateTime(content.value.createdAt);
  return formatted.length > 0 ? `发布于 ${formatted}` : '';
}

/** 回答/文章编辑时间文案：编辑于 yyyy-MM-dd HH:mm；与发布时间相同则不显示（对齐上游）。 */
export function contentUpdatedAtText(content: LoadedContentDetail): string {
  if (content.kind !== ContentDetailKind.ANSWER && content.kind !== ContentDetailKind.ARTICLE) {
    return '';
  }
  if (content.value.updatedAt <= 0 || content.value.updatedAt === content.value.createdAt) {
    return '';
  }
  const formatted = formatContentDateTime(content.value.updatedAt);
  return formatted.length > 0 ? `编辑于 ${formatted}` : '';
}

/** P3-9-D1：回答/文章的认可徽章流（仅 ANSWER/ARTICLE 有）。 */
export function contentEndorsements(content: LoadedContentDetail): Array<AnswerEndorsementDisplay> {
  if (content.kind === ContentDetailKind.QUESTION) {
    return [];
  }
  return content.value.endorsements ?? [];
}

/** P3-9-D2：IP 属地（仅 ANSWER/ARTICLE 有）。 */
export function contentIpInfo(content: LoadedContentDetail): string {
  if (content.kind === ContentDetailKind.QUESTION) {
    return '';
  }
  return (content.value.ipInfo ?? '').trim();
}

/** 认可徽章背景色：按知乎 token 组映射，未知回退主题浅色。 */
function endorsementBackgroundColor(endorsement: AnswerEndorsementDisplay): ResourceColor {
  const group = endorsement.backgroundColorGroup ?? '';
  const alpha = endorsement.backgroundColorAlpha;
  if (group.startsWith('GBK') || group.startsWith('GBL') || group.startsWith('GRD') || group.startsWith('GYL')) {
    const base = endorsementGroupColor(group);
    return applyAlpha(base, alpha);
  }
  return $r('app.color.control_background');
}

/** 认可徽章文字色：按知乎 token 组映射，未知回退主题主色。 */
function endorsementTextColor(endorsement: AnswerEndorsementDisplay): ResourceColor {
  const group = endorsement.textColorGroup ?? '';
  if (group.startsWith('GBK') || group.startsWith('GBL') || group.startsWith('GRD') || group.startsWith('GYL')) {
    return endorsementGroupColor(group);
  }
  return $r('app.color.brand_primary');
}

/** 知乎认可徽章 token → 具体色值（精简自上游 ZhihuEndorsementColorTokens 的常见组）。 */
function endorsementGroupColor(group: string): string {
  switch (group) {
    case 'GBK02A':
      return '#191B1F';
    case 'GBK03A':
      return '#373A40';
    case 'GBK06A':
    case 'GBK06B':
    case 'GBK07A':
      return '#9196A1';
    case 'GBK10A':
    case 'GBK10B':
    case 'GBK12A':
      return '#F8F8FA';
    case 'GBL01A':
      return '#1772F6';
    case 'GRD01A':
    case 'GRD03A':
      return '#F05159';
    case 'GRD10A':
      return '#FF501A';
    case 'GYL01A':
      return '#F77A31';
    default:
      return '#0066FF';
  }
}

function applyAlpha(hex: string, alpha: number): string {
  const clamped = Math.min(1, Math.max(0, alpha));
  if (clamped >= 1) {
    return hex;
  }
  const byte = Math.round(clamped * 255).toString(16).padStart(2, '0');
  return `${hex}${byte}`;
}

export function contentBlockingTitle(content: LoadedContentDetail): string {
  if (content.kind === ContentDetailKind.QUESTION || content.kind === ContentDetailKind.ARTICLE) {
    return content.value.title;
  }
  const excerpt = content.value.excerpt.trim();
  return excerpt.length > 0 ? excerpt : '回答';
}

export function contentStatistics(content: LoadedContentDetail, voteupCount?: number, followerCount?: number): string {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return `${content.value.answerCount} 个回答 · ${followerCount ?? content.value.followerCount} 人关注 · ` +
        `${content.value.commentCount} 条评论`;
    case ContentDetailKind.ANSWER:
    case ContentDetailKind.ARTICLE:
      return `${voteupCount ?? content.value.voteupCount} 赞同 · ${content.value.commentCount} 条评论`;
  }
}

/** 回答下滑切换：overscroll 最大偏移（vp），对齐上游 MAX_OVERSCROLL_DP。 */
const ANSWER_OVERSCROLL_MAX_OFFSET: number = 200;
/** 回答下滑切换：松手触发阈值（vp），对齐上游 TRIGGER_THRESHOLD_DP。 */
const ANSWER_OVERSCROLL_TRIGGER_THRESHOLD: number = 80;
/** 回答下滑切换：阻尼系数，对齐上游 DAMPING_FACTOR。 */
const ANSWER_OVERSCROLL_DAMPING_FACTOR: number = 1.2;

/** tanh 阻尼（对齐上游 dampedOverscrollOffset）：位移趋近上限时增益渐减。 */
function dampedOverscrollOffset(rawDelta: number, maxOverscroll: number, dampingFactor: number): number {
  const sign = rawDelta >= 0 ? 1 : -1;
  return sign * maxOverscroll * Math.tanh(Math.abs(rawDelta) / (maxOverscroll * dampingFactor));
}
