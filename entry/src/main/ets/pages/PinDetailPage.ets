/**
 * 想法详情页（#119 想法页设计重构）。
 *
 * 结构（自上而下）：HDS 顶栏（AppShell 唯一顶栏，标题固定"想法"）→ 作者身份 →
 * 正文与媒体 → 话题与统计 → 悬浮操作胶囊。页面只负责组合与流程，正文解析、图片
 * 预览、链接路由沿用 NativeContentDocument，屏蔽规则写入沿用 BlockingActionController。
 *
 * 关键口径：
 * - 内容视口延伸到顶栏之后，只有首屏起点让位（PinDetailLayout.pinTopContentInsetVp）；
 * - 正文启用共享阅读布局（限宽 + 用户字号/行高/段距偏好 + 信息头 24vp 分组间距）；
 * - 文末让位按底栏实测高度动态计算，安全区只在底栏里算一次；
 * - 分享、屏蔽、点赞的反馈都出现在底栏上方的状态行，不要求滚回顶部才能看到。
 */
import { CenteredOverlayDialog } from './CenteredOverlayDialog';
import { AppDestination, AppDestinationName } from 'core';
import {
  AnswerDoubleTapAction,
  AppPreferencesStore,
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  CommentRepository,
  DEFAULT_THEME_COLOR,
  FeedCardStyle,
  LinkCardMetaRepository,
  LoginSessionGateway,
  onThemeColor,
  OpenedContentStore,
  PinDetail,
  PinLikeRepository,
  PinRepository,
  PinTopic,
  ReadHistoryUploadRepository
} from 'data';
import { PinDetailController, PinDetailViewState, ReadOnlyDetailPhase } from './PeoplePinDetailState';
import { PinLikeController, PinLikeViewState } from './ContentInteractionState';
import { ReadOnlyDetailStatusPanel } from './PeoplePinDetailPages';
import { ContentImagePreview, NativeContentDocument } from './NativeContentDocument';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { createSystemShareService } from '../platform/SystemShareService';
import { SharePayloadKind, ShareTextPayload } from '../platform/ShareContracts';
import { Want } from '@kit.AbilityKit';
import { contentLinkDestination } from './NotificationLinkResolver';
import {
  BlockingActionContext,
  BlockingActionController,
  BlockingActionPhase,
  BlockingActionViewState,
  BlockingUserCandidate
} from './BlockingActionState';
import { GlassCapsule } from './components/MaterialCanvas';
import {
  adaptiveOverlayWidth,
  ADAPTIVE_OVERLAY_MENU_WIDTH_VP,
  isWideOverlayContainer
} from '../common/style/AdaptiveOverlayLayout';
import {
  pinBottomBarSideInsetVp,
  pinBottomContentInsetVp,
  pinCompactBottomActions,
  pinTopContentInsetVp
} from './PinDetailLayout';
import {
  emptyPinBlockDialogView,
  PinBlockDialogKind,
  PinBlockDialogState,
  PinBlockDialogViewState
} from './PinBlockDialogState';

@Component
export struct PinDetailPage {
  contentId: string = '';
  repository: PinRepository | undefined = undefined;
  likeRepository: PinLikeRepository | undefined = undefined;
  /** 推荐阅读卡片站内元数据仓库：赞同/评论计数与资源类型（正文 link-card 展示）。 */
  linkCardMetaRepository: LinkCardMetaRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  /** 阅读历史上云仓库（对齐上游 addReadHistory；未配置或游客态时不上报）。 */
  historyUploader: ReadHistoryUploadRepository | undefined = undefined;
  commentRepository: CommentRepository | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  onBack: () => void = (): void => {};
  @State private phase: ReadOnlyDetailPhase = ReadOnlyDetailPhase.IDLE;
  @State private pin: PinDetail | undefined = undefined;
  @State private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  @State private openedRecordFailed: boolean = false;
  @State private pendingUserBlock?: BlockingUserCandidate = undefined;
  @State private pinActionsSheetShown: boolean = false;
  @State private overlayWidthVp: number = 0;
  @State private shareStatus: string = '';
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  @State private blockingPhase: BlockingActionPhase = BlockingActionPhase.IDLE;
  @State private liked: boolean = false;
  @State private likeCount: number = 0;
  @State private likePending: boolean = false;
  @State private interactionErrorMessage: string = '';
  @State private interactionRequiresLogin: boolean = false;
  /** 底栏实测高度（含状态行与系统手势区）：驱动正文尾部让位，换行/大字后自动重测。 */
  @State private bottomActionBarHeightVp: number = 0;
  @State private blockDialog: PinBlockDialogViewState = emptyPinBlockDialogView();
  @State @Watch('userBlockDialogChanged') private userBlockDialogShown: boolean = false;
  @State @Watch('keywordBlockDialogChanged') private keywordBlockDialogShown: boolean = false;
  @StorageProp('bottomRectHeight') private bottomRectHeightVp: number = 0;
  @StorageProp('statusBarHeightVp') private statusBarHeightVp: number = 0;
  @StorageProp('systemFontSizeScale') private systemFontSizeScale: number = 1;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('answerDoubleTapAction') private doubleTapAction: AnswerDoubleTapAction = AnswerDoubleTapAction.ASK;
  /** 全屏图片查看器地址（正文图片点击后写入）：查看时页面根叠层渲染，顶栏由 AppShell 隐藏。 */
  @StorageProp('imagePreviewUrl') private imagePreviewUrl: string = '';
  private doubleTapMenuShown: boolean = false;
  private controller?: PinDetailController;
  private likeController?: PinLikeController;
  private blockingAction?: BlockingActionController;
  private blockFlow?: PinBlockDialogState;
  /** 页面失活后丢弃迟到回调（屏蔽提交、分享结果、点赞结果）。 */
  private pageActive: boolean = false;
  /** 从更多菜单进入屏蔽弹层：等菜单完全收起后再开弹层，保持单一活动浮层。 */
  private pendingDialogAfterSheet: boolean = false;
  private pendingDialogIsKeyword: boolean = false;
  private blockMessageTimerId: number = -1;

  private userBlockDialogController: CustomDialogController = new CustomDialogController({
    builder: CenteredOverlayDialog({ content: (): void => { this.userBlockDialog(); } }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    maskColor: '#99000000',
    backgroundColor: Color.Transparent,
    cancel: (): void => {
      this.userBlockDialogShown = false;
      this.blockFlow?.cancel();
    }
  });

  private keywordBlockDialogController: CustomDialogController = new CustomDialogController({
    builder: CenteredOverlayDialog({ content: (): void => { this.keywordBlockDialog(); } }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    maskColor: '#99000000',
    backgroundColor: Color.Transparent,
    cancel: (): void => {
      this.keywordBlockDialogShown = false;
      this.blockFlow?.cancel();
    }
  });

  private userBlockDialogChanged(): void {
    if (this.userBlockDialogShown) {
      this.userBlockDialogController.open();
    } else {
      this.userBlockDialogController.close();
    }
  }

  private keywordBlockDialogChanged(): void {
    if (this.keywordBlockDialogShown) {
      this.keywordBlockDialogController.open();
    } else {
      this.keywordBlockDialogController.close();
    }
  }

  aboutToAppear(): void {
    this.pageActive = true;
    if (this.blockFlow === undefined) {
      this.blockFlow = new PinBlockDialogState((state: PinBlockDialogViewState): void => {
        this.applyBlockDialog(state);
      });
    }
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载正文导致滚动位置、点赞状态丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      this.likeController?.activate();
      if (this.blockingAction === undefined) {
        this.createBlockingAction();
      }
      return;
    }
    if (this.repository === undefined || this.session === undefined) {
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = '想法详情数据源未配置';
      return;
    }
    this.controller = new PinDetailController(
      this.repository,
      this.session,
      this.openedContentStore,
      (state: PinDetailViewState): void => this.applyState(state),
      this.historyUploader
    );
    this.controller.activate();
    this.controller.load(this.contentId);
    this.createBlockingAction();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    if (this.blockMessageTimerId >= 0) {
      clearTimeout(this.blockMessageTimerId);
    }
    this.blockMessageTimerId = -1;
    // 只停用控制器、保留实例：从评论/作者页返回时复用同一份控制器与点赞状态，
    // 不重载正文、不回顶，也不会把已点赞的想法恢复成加载时的旧快照。
    this.controller?.deactivate();
    this.likeController?.deactivate();
    this.blockFlow?.cancel();
    this.blockFlow?.resetForReappear();
    // 屏蔽是短时反馈：离开页面即清掉进行中/成功提示，返回后不会留下禁用态。
    this.blockingAction?.reset();
    this.blockingBusy = false;
    this.blockingMessage = '';
    this.blockingPhase = BlockingActionPhase.IDLE;
    this.pendingUserBlock = undefined;
    this.pinActionsSheetShown = false;
    this.shareStatus = '';
    this.userBlockDialogShown = false;
    this.keywordBlockDialogShown = false;
    // 离开页面时收起共享的图片查看器，避免叠层留着上次打开的地址。
    if (this.imagePreviewUrl.length > 0) {
      AppStorage.setOrCreate('imagePreviewUrl', '');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.phase === ReadOnlyDetailPhase.IDLE || this.phase === ReadOnlyDetailPhase.LOADING) {
          this.statusPanel('正在加载想法…', true)
        } else if (this.phase === ReadOnlyDetailPhase.ERROR) {
          this.statusPanel(this.errorMessage, false)
        } else if (this.pin !== undefined) {
          this.loadedPin(this.pin)
        }
      }
      .width('100%')
      .height('100%')

      // 底栏作为页级悬浮层：两块 HDS 材质画布独立承载，正文滚动到屏幕底边；
      // 中间空白与整层都不拦截正文的滚动、点链接与选字。
      if (this.phase === ReadOnlyDetailPhase.READY && this.pin !== undefined) {
        this.bottomActionBar(this.pin)
      }

      // 全屏图片查看器：想法正文图片点击后由页面根叠层渲染，盖住正文与底栏。
      if (this.imagePreviewUrl.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          ContentImagePreview({
            url: this.imagePreviewUrl,
            onClose: (): void => {
              AppStorage.setOrCreate('imagePreviewUrl', '');
            }
          })
        }
        .id('pin_image_preview_overlay')
        .width('100%')
        .height('100%')
        // 高于底栏（zIndex 2）：查看图片时胶囊不压在全屏图上。
        .zIndex(3)
      }
    }
    .id('pin_detail_page')
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (width > 0) {
        this.overlayWidthVp = width;
      }
    })
    .backgroundColor($r('app.color.page_background'))
  }

  /** 加载/错误面板同样避开顶栏与系统手势区，不先闪一帧空态。 */
  @Builder
  private statusPanel(message: string, loading: boolean) {
    ReadOnlyDetailStatusPanel({
      kind: 'pin',
      message: message,
      loading: loading,
      requiresLogin: this.requiresLogin,
      topInsetVp: pinTopContentInsetVp(this.statusBarHeightVp),
      bottomInsetVp: Math.max(0, this.bottomRectHeightVp),
      onRetry: (): void => {
        this.controller?.load(this.contentId);
      },
      navigate: this.navigate
    })
  }

  @Builder
  private loadedPin(pin: PinDetail) {
    Column() {
      // 与回答/文章页共用正文列表：作者区随正文滚动，首屏为悬浮 HDS 顶栏让位。
      NativeContentDocument({
        html: pin.contentHtml,
        emptyMessage: '这条想法暂时没有正文',
        readingLayout: true,
        topInsetVp: pinTopContentInsetVp(this.statusBarHeightVp),
        bottomInsetVp: pinBottomContentInsetVp(this.bottomActionBarHeightVp),
        documentHeader: (): void => { this.pinAuthorHeader(pin) },
        documentFooter: (): void => { this.pinTrailer(pin) },
        onBodyDoubleTap: (): void => this.onBodyDoubleTap(),
        linkCardMetaRepository: this.linkCardMetaRepository,
        onLinkClick: (url: string): void => this.openContentLink(url)
      })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 作者区：40vp 头像 + 姓名（16fp Medium）+ 简介与时间（14fp 次级）。
   * 卡片模式用 surface_background + 16vp 圆角 + 18vp 内边距；分割线模式透明底 + 底部细线。
   * 外层左右边距由正文列表统一提供，这里不再叠加，避免两套内缩。
   */
  @Builder
  private pinAuthorHeader(pin: PinDetail) {
    Column({ space: $r('app.float.spacing_small') }) {
      Row({ space: $r('app.float.spacing_medium') }) {
        Stack({ alignContent: Alignment.Center }) {
          if (pin.author.avatarUrl === undefined) {
            Text(pin.author.name.substring(0, 1))
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('app.color.control_background'))
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
          } else {
            Image(pin.author.avatarUrl)
              .id('pin_detail_author_avatar')
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
          Text(pin.author.name)
            .id('pin_detail_author')
            .fontSize($r('app.float.body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (pin.author.headline.length > 0) {
            Text(pin.author.headline)
              .id('pin_detail_author_headline')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .id('pin_detail_author_row')
      .width('100%')
      .accessibilityText(`${pin.author.name}${pin.author.headline.length > 0 ? `，${pin.author.headline}` : ''}，查看主页`)
      .onClick((): void => {
        this.navigate({ name: AppDestinationName.PEOPLE, id: pin.author.urlToken ?? pin.author.id });
      })

      // 时间属于辅助信息，不扩大为作者跳转热区。
      if (pin.createdAt > 0) {
        Text(pinTimeText(pin))
          .id('pin_detail_time')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      if (!this.cardSurface()) {
        Divider()
          .color($r('app.color.divider_color'))
          .margin({ top: $r('app.float.spacing_xsmall') })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    // 卡片模式四周 18vp；分割线模式不加内边距，细线落在分组边界上。
    .padding(this.cardSurface() ? $r('app.float.card_padding') : 0)
    .backgroundColor(this.cardSurface() ? $r('app.color.surface_background') : Color.Transparent)
    .borderRadius(this.cardSurface() ? $r('app.float.card_radius') : 0)
  }

  private cardSurface(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  /**
   * 尾部：话题胶囊 → 统计行 → 非阻断提示。
   * 统计与底栏点赞共用同一状态源（likeCount），避免两处数字不一致。
   */
  @Builder
  private pinTrailer(pin: PinDetail) {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (pin.topics.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(pin.topics, (topic: PinTopic) => {
            // 想法话题暂无跳转端点：按说明性标签呈现，不做成看似可点的按钮。
            Text(`# ${topic.name}`)
              .id(`pin_detail_topic_${topic.id}`)
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .height(30)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.control_background'))
              .borderRadius(15)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '100%' })
              .margin({ right: 8, bottom: 8 })
          }, (topic: PinTopic): string => topic.id)
        }
        .id('pin_detail_topics')
        .width('100%')
      }
      Text(`${this.likeCount} 赞 · ${pin.commentCount} 条评论`)
        .id('pin_detail_statistics')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      if (this.openedRecordFailed) {
        Text('本次打开记录未能保存，阅读不受影响')
          .id('pin_detail_opened_record_failed')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: $r('app.float.spacing_medium') })
  }

  private applyState(state: PinDetailViewState): void {
    if (!this.pageActive) {
      return;
    }
    this.phase = state.phase;
    this.pin = state.pin;
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
    this.openedRecordFailed = state.openedRecordFailed;
    if (state.pin !== undefined && this.likeController === undefined) {
      this.liked = state.pin.isLiked ?? false;
      this.likeCount = state.pin.likeCount;
      if (this.likeRepository !== undefined && this.session !== undefined) {
        this.likeController = new PinLikeController(this.likeRepository, this.session, this.contentId,
          this.liked, this.likeCount, (likeState: PinLikeViewState): void => {
            if (!this.pageActive) {
              return;
            }
            this.liked = likeState.liked;
            this.likeCount = likeState.likeCount;
            this.likePending = likeState.pending;
            this.interactionErrorMessage = likeState.errorMessage ?? '';
            this.interactionRequiresLogin = likeState.requiresLogin;
          });
        this.likeController.activate();
      }
    }
  }

  private createBlockingAction(): void {
    const rules = this.rules;
    const history = this.history;
    if (rules === undefined || history === undefined) {
      return;
    }
    this.blockingAction = new BlockingActionController(rules, history, (state: BlockingActionViewState): void => {
      if (!this.pageActive) {
        return;
      }
      this.blockingPhase = state.phase;
      this.blockingBusy = state.busy;
      this.blockingMessage = state.message;
      if (this.blockMessageTimerId >= 0) {
        clearTimeout(this.blockMessageTimerId);
        this.blockMessageTimerId = -1;
      }
      // 成功提示是一次性反馈，停留 4 秒后消退；失败/进行中保持可见。
      if (state.phase === BlockingActionPhase.SUCCESS && state.message.length > 0) {
        this.blockMessageTimerId = setTimeout((): void => {
          this.blockMessageTimerId = -1;
          this.blockingMessage = '';
        }, 4000);
      }
    });
  }

  private onBodyDoubleTap(): void {
    if (this.phase !== ReadOnlyDetailPhase.READY || this.doubleTapMenuShown) {
      return;
    }
    if (this.doubleTapAction === AnswerDoubleTapAction.NONE) {
      return;
    }
    if (this.doubleTapAction === AnswerDoubleTapAction.OPEN_COMMENTS) {
      this.openPinComments();
      return;
    }
    if (this.doubleTapAction === AnswerDoubleTapAction.VOTE_UP) {
      void this.likeController?.likeFromDoubleTap();
      return;
    }
    if (this.doubleTapAction !== AnswerDoubleTapAction.ASK) {
      this.getUIContext().getPromptAction().showToast({ message: '想法详情暂不支持此动作，可在设置中选择打开评论' });
      return;
    }
    this.doubleTapMenuShown = true;
    this.getUIContext().getPromptAction().showActionMenu({
      title: '设置双击正文动作',
      buttons: [{ text: '设为无操作', color: this.resolvedThemeColor },
        { text: '打开评论', color: this.resolvedThemeColor },
        { text: '点赞', color: this.resolvedThemeColor }]
    }).then((result): void => {
      this.doubleTapMenuShown = false;
      const action = result.index === 2 ? AnswerDoubleTapAction.VOTE_UP :
        (result.index === 1 ? AnswerDoubleTapAction.OPEN_COMMENTS : AnswerDoubleTapAction.NONE);
      AppStorage.setOrCreate('answerDoubleTapAction', action);
      const context = getAbilityContext();
      if (context !== undefined) {
        void new AppPreferencesStore(context).saveAnswerDoubleTapAction(action).catch((_error: Object): void => {});
      }
      if (action === AnswerDoubleTapAction.OPEN_COMMENTS) {
        this.openPinComments();
      } else if (action === AnswerDoubleTapAction.VOTE_UP) {
        void this.likeController?.likeFromDoubleTap();
      }
    }).catch((_error: Object): void => {
      this.doubleTapMenuShown = false;
    });
  }

  private openPinComments(): void {
    if (this.commentRepository !== undefined && this.session !== undefined) {
      this.navigate({ name: AppDestinationName.COMMENT, contentType: 'pin', contentId: this.contentId });
    }
  }

  /** 想法正文内联链接：站内内容走应用内导航，其余 http(s) 交系统浏览器。 */
  private openContentLink(url: string): void {
    const destination = contentLinkDestination(url);
    if (destination !== undefined) {
      this.navigate(destination);
      return;
    }
    if (!/^https?:\/\//i.test(url)) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    context.startAbility(want).catch((_error: Error): void => {});
  }

  /** 想法分享只转交 HarmonyOS 系统面板，链接由共享服务执行白名单校验。 */
  private sharePinLink(): void {
    const pin = this.pin;
    const context = getAbilityContext();
    if (pin === undefined || context === undefined || pin.url.trim().length === 0) {
      this.shareStatus = '暂时无法打开分享面板';
      return;
    }
    const avatarUrl = pin.author.avatarUrl?.trim() ?? '';
    const payload: ShareTextPayload = {
      kind: SharePayloadKind.TEXT,
      title: '想法',
      summary: '来自知乎++的受信想法链接',
      contentUrl: pin.url,
      thumbnailUrl: /^https:\/\/(?:pic|pica|picx|pic[0-9]+)\.zhimg\.com\//.test(avatarUrl) ? avatarUrl : undefined
    };
    createSystemShareService(context).share(payload).then((): void => {
      // 取消与成功都保持安静：面板已打开不代表分享已完成，此时不再给"成功"提示。
      if (this.pageActive) {
        this.shareStatus = '';
      }
    }).catch((): void => {
      if (this.pageActive) {
        this.shareStatus = '暂时无法打开分享面板';
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 底部操作区
  // ---------------------------------------------------------------------------

  @Builder
  private bottomActionBar(pin: PinDetail) {
    Column({ space: $r('app.float.spacing_xsmall') }) {
      if (this.hasStatusMessage()) {
        this.pinStatusMessages()
      }
      Row({ space: $r('app.float.spacing_small') }) {
        Row() {
          // HDS ADAPTIVE 由共享画布按设备与全局挡位降级。
          GlassCapsule() {
            this.pinLikeAction()
          }
        }
        .id('pin_detail_like_capsule')
        Blank().layoutWeight(1)
        Row() {
          GlassCapsule() {
            this.pinRightActions(pin)
          }
        }
        .id('pin_detail_actions_capsule')
      }
      .id('pin_detail_bottom_actions')
      .width('100%')
      .padding({
        left: pinBottomBarSideInsetVp(this.overlayWidthVp),
        right: pinBottomBarSideInsetVp(this.overlayWidthVp),
        top: $r('app.float.spacing_xsmall'),
        // 与根底栏同口径：底栏离物理底边的高度取系统手势避让区。
        bottom: Math.max(this.bottomRectHeightVp, 0)
      })
    }
    .width('100%')
    .zIndex(2)
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const height = Number(newArea.height);
      if (height > 0 && Math.abs(height - this.bottomActionBarHeightVp) > 1) {
        this.bottomActionBarHeightVp = height;
      }
    })
  }

  private hasStatusMessage(): boolean {
    return this.interactionErrorMessage.length > 0 || this.blockingMessage.length > 0 ||
      this.shareStatus.length > 0;
  }

  /** 就近反馈：点赞、分享、屏蔽的结果都显示在底栏上方，不强制滚回顶部。 */
  @Builder
  private pinStatusMessages() {
    // 提示铺一层中性底色：正文正好滚到同一位置时不与正文文字叠字。
    Column() {
      Column({ space: $r('app.float.spacing_xsmall') }) {
        if (this.interactionErrorMessage.length > 0) {
          Row({ space: $r('app.float.spacing_small') }) {
            Text(this.interactionErrorMessage)
              .id('pin_interaction_status')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.error_text'))
              .layoutWeight(1)
            if (this.interactionRequiresLogin) {
              Button('去登录')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id('pin_interaction_login')
                .fontSize($r('app.float.secondary_font_size'))
                .constraintSize({ minHeight: 32 })
                .onClick((): void => { this.navigate({ name: AppDestinationName.LOGIN }); })
            }
          }
          .width('100%')
        }
        if (this.blockingMessage.length > 0) {
          Text(this.blockingMessage)
            .id('pin_detail_blocking_status')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        if (this.shareStatus.length > 0) {
          Text(this.shareStatus)
            .id('pin_detail_share_status')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.error_text'))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius(12)
    }
    .width('100%')
    .padding({
      left: pinBottomBarSideInsetVp(this.overlayWidthVp),
      right: pinBottomBarSideInsetVp(this.overlayWidthVp)
    })
  }

  private compactBottomActions(): boolean {
    return pinCompactBottomActions(this.overlayWidthVp, this.systemFontSizeScale);
  }

  @Builder
  private pinLikeAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 4 }) {
        SymbolGlyph(this.liked ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup'))
          .fontSize(20)
          .fontColor([this.liked ? this.resolvedThemeColor : $r('app.color.primary_text')])
        if (!this.compactBottomActions()) {
          Text(`${this.likeCount}`)
            .fontSize($r('app.float.secondary_font_size'))
            .fontWeight(this.liked ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.liked ? this.resolvedThemeColor : $r('app.color.secondary_text'))
        }
      }
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    }
    .id('pin_detail_like')
    // 36vp 是正常字号下的起点，大字时随内容增高，不固定高度裁切文本。
    .constraintSize({ minHeight: 36 })
    .backgroundColor(Color.Transparent)
    .lightUpEffect(1)
    .accessibilityText(`${this.liked ? '取消点赞' : '点赞'}，${this.likeCount} 赞`)
    .enabled(this.likeController !== undefined && !this.likePending)
    .onClick((): void => { void this.likeController?.toggleLike(); })
  }

  @Builder
  private pinRightActions(pin: PinDetail) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
        if (!this.compactBottomActions()) {
          Text(`${pin.commentCount}`)
            .fontSize($r('app.float.secondary_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .padding({ left: 6, right: 6, top: 8, bottom: 8 })
    }
    .id('pin_detail_comment_bar')
    .constraintSize({ minHeight: 36 })
    .backgroundColor(Color.Transparent)
    .accessibilityText(`查看 ${pin.commentCount} 条评论`)
    .enabled(this.commentRepository !== undefined && this.session !== undefined)
    .onClick((): void => this.openPinComments())

    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(20)
        .fontColor([$r('app.color.primary_text')])
    }
    .id('pin_detail_more')
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .accessibilityText('更多想法操作')
    .bindSheet(this.pinActionsSheetShown, this.pinActionsSheet(), {
      preferType: isWideOverlayContainer(this.overlayWidthVp) ? SheetType.POPUP : SheetType.BOTTOM,
      width: isWideOverlayContainer(this.overlayWidthVp)
        ? adaptiveOverlayWidth(this.overlayWidthVp, ADAPTIVE_OVERLAY_MENU_WIDTH_VP) : '100%',
      height: SheetSize.FIT_CONTENT,
      dragBar: !isWideOverlayContainer(this.overlayWidthVp),
      showClose: false,
      maskColor: '#99000000',
      backgroundColor: $r('app.color.surface_background'),
      onDisappear: (): void => {
        if (this.pinActionsSheetShown) {
          this.pinActionsSheetShown = false;
        }
        // 单一活动浮层：菜单收起后再开屏蔽弹层。
        if (this.pendingDialogAfterSheet) {
          this.pendingDialogAfterSheet = false;
          if (this.pendingDialogIsKeyword) {
            this.openKeywordBlockDialog();
          } else {
            this.openUserBlockDialog();
          }
        }
      }
    })
    .onClick((): void => { this.pinActionsSheetShown = true; })
  }

  // ---------------------------------------------------------------------------
  // 更多菜单
  // ---------------------------------------------------------------------------

  @Builder
  private pinActionsSheet() {
    Column({ space: $r('app.float.spacing_small') }) {
      // 关闭入口固定在滚动区之外，长菜单滚动时仍然可达。
      Row({ space: $r('app.float.spacing_small') }) {
        Text('更多操作')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('pin_detail_actions_close')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭更多想法操作')
        .onClick((): void => {
          this.pinActionsSheetShown = false;
        })
      }
      .width('100%')

      Scroll() {
        Column({ space: $r('app.float.spacing_small') }) {
          this.pinActionButton('分享', 'pin_detail_share', $r('app.color.control_background'),
            $r('app.color.primary_text'), (): void => {
              this.pinActionsSheetShown = false;
              this.sharePinLink();
            })
          // 屏蔽是次要破坏性动作：中性底色 + 明确文案，不与主保存按钮共用高强调外观。
          this.pinActionButton('屏蔽作者', 'pin_detail_block_user', $r('app.color.control_background'),
            $r('app.color.primary_text'), (): void => {
              this.pinActionsSheetShown = false;
              this.pendingDialogAfterSheet = this.blockingAction !== undefined && this.pin !== undefined;
              this.pendingDialogIsKeyword = false;
            })
          this.pinActionButton('屏蔽关键词', 'pin_detail_block_keyword', $r('app.color.control_background'),
            $r('app.color.primary_text'), (): void => {
              this.pinActionsSheetShown = false;
              this.pendingDialogAfterSheet = this.blockingAction !== undefined;
              this.pendingDialogIsKeyword = true;
            })
          if (this.pin !== undefined) {
            ForEach(this.pin.topics, (topic: PinTopic) => {
              this.pinTopicBlockButton(topic)
            }, (topic: PinTopic): string => topic.id)
          }
        }
        .width('100%')
      }
      // 菜单内容按可用高度滚动：话题很多时不把关闭入口和使用者推出屏幕。
      .constraintSize({ maxHeight: 420 })
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
  }

  @Builder
  private pinActionButton(label: string, elementId: string, background: Resource, foreground: Resource,
    action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontColor(foreground)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .id(elementId)
    .width('100%')
    .constraintSize({ minHeight: 40 })
    .backgroundColor(background)
    .borderRadius(12)
    .enabled(!this.blockingBusy)
    .onClick(action)
  }

  /** 屏蔽话题：长话题名允许换行，仍是一次点击即执行。 */
  @Builder
  private pinTopicBlockButton(topic: PinTopic) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Text(`屏蔽话题：${topic.name}`)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(`pin_detail_block_topic_${topic.id}`)
    .width('100%')
    .constraintSize({ minHeight: 40 })
    .backgroundColor($r('app.color.control_background'))
    .borderRadius(12)
    .enabled(!this.blockingBusy && this.blockingAction !== undefined)
    .onClick((): void => {
      const pin = this.pin;
      if (pin === undefined) {
        return;
      }
      this.pinActionsSheetShown = false;
      const context: BlockingActionContext = {
        contentTitle: `${pin.author.name}的想法`,
        contentKind: 'pin',
        contentId: pin.id
      };
      this.blockingAction?.blockTopic(topic.id, topic.name, context);
    })
  }

  // ---------------------------------------------------------------------------
  // 屏蔽弹层
  // ---------------------------------------------------------------------------

  private applyBlockDialog(state: PinBlockDialogViewState): void {
    if (!this.pageActive) {
      return;
    }
    this.blockDialog = state;
    if (state.kind === PinBlockDialogKind.NONE) {
      this.userBlockDialogShown = false;
      this.keywordBlockDialogShown = false;
    }
  }

  private openUserBlockDialog(): void {
    const pin = this.pin;
    if (pin === undefined || this.blockingAction === undefined) {
      return;
    }
    const candidate: BlockingUserCandidate = { userId: pin.author.id, userName: pin.author.name };
    this.pendingUserBlock = candidate;
    // 清掉上一次的屏蔽结论，避免旧的成功状态被当成这次提交的结果。
    this.blockingAction.reset();
    this.blockFlow?.openUser();
    this.userBlockDialogShown = true;
  }

  private openKeywordBlockDialog(): void {
    if (this.blockingAction === undefined) {
      return;
    }
    this.blockingAction.reset();
    this.blockFlow?.openKeyword();
    this.keywordBlockDialogShown = true;
  }

  private cancelBlockDialog(): void {
    this.userBlockDialogShown = false;
    this.keywordBlockDialogShown = false;
    this.blockFlow?.cancel();
  }

  /**
   * 提交屏蔽：返回 true 表示规则已写入。BlockingActionController 内部吞掉异常并发布
   * ERROR 状态，这里以状态相位判断结果；页面已离开时直接按失败处理。
   */
  private async submitPinBlock(kind: PinBlockDialogKind, value: string): Promise<boolean> {
    const action = this.blockingAction;
    const pin = this.pin;
    if (!this.pageActive || action === undefined || pin === undefined) {
      return false;
    }
    const context: BlockingActionContext = {
      contentTitle: `${pin.author.name}的想法`,
      contentKind: 'pin',
      contentId: pin.id
    };
    if (kind === PinBlockDialogKind.USER) {
      const candidate = this.pendingUserBlock;
      if (candidate === undefined) {
        return false;
      }
      await action.blockUser(candidate.userId, candidate.userName, context);
    } else if (kind === PinBlockDialogKind.KEYWORD) {
      await action.blockKeyword(value, context);
    } else {
      return false;
    }
    return this.blockingPhase === BlockingActionPhase.SUCCESS;
  }

  @Builder
  private userBlockDialog() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text(`确定要屏蔽用户「${this.pendingUserBlock?.userName ?? ''}」吗？`)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('屏蔽后，该作者的内容将不再显示。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      if (this.blockDialog.errorMessage.length > 0) {
        Text(this.blockDialog.errorMessage)
          .id('pin_detail_block_user_error')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.error_text'))
          .width('100%')
      }
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .enabled(!this.blockDialog.submitting)
          .onClick((): void => this.cancelBlockDialog())
        Button(this.blockDialog.submitting ? '正在屏蔽…' : '确定屏蔽')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('pin_detail_confirm_block_user')
          .layoutWeight(1)
          .enabled(!this.blockDialog.submitting)
          .onClick((): void => { void this.blockFlow?.submit(
            (kind: PinBlockDialogKind, value: string): Promise<boolean> => this.submitPinBlock(kind, value),
            '屏蔽'); })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private keywordBlockDialog() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('屏蔽关键词')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('输入要屏蔽的关键词（普通文本，不区分大小写）')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      TextInput({ text: this.blockDialog.input, placeholder: '输入关键词' })
        .id('pin_detail_keyword_block_input')
        .maxLength(200)
        .enabled(!this.blockDialog.submitting)
        .onChange((value: string): void => {
          this.blockFlow?.updateInput(value);
        })
      if (this.blockDialog.errorMessage.length > 0) {
        Text(this.blockDialog.errorMessage)
          .id('pin_detail_block_keyword_error')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.error_text'))
          .width('100%')
      }
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .enabled(!this.blockDialog.submitting)
          .onClick((): void => this.cancelBlockDialog())
        Button(this.blockDialog.submitting ? '正在屏蔽…' : '确认屏蔽')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('pin_detail_confirm_block_keyword')
          .layoutWeight(1)
          .enabled(!this.blockDialog.submitting && this.blockDialog.input.trim().length > 0)
          .onClick((): void => { void this.blockFlow?.submit(
            (kind: PinBlockDialogKind, value: string): Promise<boolean> => this.submitPinBlock(kind, value),
            '屏蔽'); })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }
}

function pinTimeText(pin: PinDetail): string {
  const usesUpdatedTime = pin.updatedAt > pin.createdAt;
  const value = usesUpdatedTime ? pin.updatedAt : pin.createdAt;
  const date = new Date(value * 1000);
  return `${usesUpdatedTime ? '更新于' : '发布于'} ${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}
