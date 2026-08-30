import { pasteboard } from '@kit.BasicServicesKit';
import {
  P1Destination,
  P1DestinationName
} from 'core';
import {
  AnswerEndorsementDisplay,
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  CollectionRepository,
  CommentRepository,
  ContentDetailKind,
  ContentRepository,
  ContentVoteState,
  FollowMutationResult,
  FollowRepository,
  LoginSessionGateway,
  OpenedContentStore,
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
import { ShareOutcome, SharePayloadKind, ShareTextPayload } from '../platform/ShareContracts';
import { hdsMaterial } from '@kit.UIDesignKit';
import { GlassCapsule } from './components/MaterialCanvas';

@Component
struct ContentDetailPage {
  kind: ContentDetailKind = ContentDetailKind.QUESTION;
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
  @State private showComments: boolean = false;
  @State private commentRootDraft: string = '';
  @State private commentReplyDraft: string = '';
  /** P3-9-B：顶栏折叠状态——false 收起（标题行）、true 展开（作者行），滚动后收为标题行。 */
  @State private topBarScrolled: boolean = false;
  /** P3-9-C：底部菜单弹窗可见性。 */
  @State private actionMenuShown: boolean = false;
  /** P3-9-C：菜单操作反馈（复制链接结果等）。 */
  @State private menuStatus: string = '';
  /** 沉浸式阅读仅收起页面 Chrome，不改变正文、互动或滚动状态。 */
  @State private immersiveReading: boolean = false;
  /** 设备支持沉浸材质：玻璃胶囊走 HDS 画布，否则回落组件模糊。 */
  private immersiveMaterialSupported: boolean = false;
  private controller?: ContentDetailController;
  private blockingAction?: BlockingActionController;
  private voteController?: ContentVoteController;
  private followController?: FollowController;

  aboutToAppear(): void {
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
    this.controller.load(this.kind, this.contentId);
    this.createBlockingAction();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.voteController?.deactivate();
    this.followController?.deactivate();
    this.controller = undefined;
    this.blockingAction = undefined;
    this.pendingUserBlock = undefined;
    this.keywordBlockVisible = false;
    this.keywordBlockInput = '';
    this.voteController = undefined;
    this.followController = undefined;
    this.showComments = false;
    this.commentRootDraft = '';
    this.commentReplyDraft = '';
    this.topBarScrolled = false;
    this.immersiveReading = false;
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
          // 沉浸光感风格：正文铺满并从操作栏下方穿透，操作栏为两块交互材质胶囊悬浮于文字上方。
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              // P3-9-B：顶栏作为占位（非覆盖），正文在其下方，避免作者行与标题/统计重叠。
              if (!this.immersiveReading) {
                this.detailTopBar(this.content)
              }
              Column() {
                this.loadedContent(this.content)
              }
              .layoutWeight(1)
              .width('100%')
            }
            .width('100%')
            .height('100%')

            if (!this.immersiveReading) {
              this.bottomActionBar()
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .id(`p2_${this.kind}_detail_page`)
      .width('100%')
      .height('100%')
      .padding({ top: 94 })
      .backgroundColor($r('app.color.page_background'))

      if (!this.immersiveReading && this.content !== undefined &&
        this.phase === ContentDetailPhase.READY) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.bottomActionBar()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.immersiveReading) {
        this.immersiveExitControl()
      }

      if (this.collectionRepository !== undefined && this.session !== undefined) {
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
      if (this.kind === ContentDetailKind.ANSWER || this.kind === ContentDetailKind.ARTICLE) {
        CommentLayer({
          contentType: this.kind === ContentDetailKind.ARTICLE ? 'article' : 'answer',
          contentId: this.contentId,
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
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private favoriteDialog() {
    CollectionDialogComponent({
      contentType: this.kind === ContentDetailKind.ARTICLE ? 'article' : 'answer',
      contentId: this.contentId,
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
              this.controller?.load(this.kind, this.contentId);
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
  private immersiveExitControl() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([$r('app.color.primary_text')])
    }
      .id(`p3_${this.kind}_detail_exit_immersive`)
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius(20)
      .accessibilityText('退出沉浸式阅读')
      .align(Alignment.TopStart)
      .margin({
        left: $r('app.float.p1_page_padding'),
        top: $r('app.float.p1_spacing_medium')
      })
      .onClick((): void => {
        this.immersiveReading = false;
      })
  }

  @Builder
  private loadedContent(content: LoadedContentDetail) {
    Column() {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        // 作者行仅问题页保留（回答/文章的顶栏折叠作者行已含头像+名字+签名，避免重复）。
        if (content.kind === ContentDetailKind.QUESTION && contentAuthorName(content).length > 0) {
          Text(contentAuthorLine(content))
            .id(`p2_${content.kind}_detail_author`)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .width('100%')
        }

        // 主标题保留在正文信息头：回答显示所属问题，文章显示文章标题，避免仅依赖通用路由标题。
        if (contentContextTitle(content).length > 0) {
          Text(contentContextTitle(content))
            .id(`p2_${content.kind}_detail_context_title`)
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        Text(this.displayedContentStatistics(content))
          .id(`p2_${content.kind}_detail_statistics`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')

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
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: this.immersiveReading ? 56 : $r('app.float.p1_spacing_medium'),
        bottom: $r('app.float.p1_spacing_medium')
      })
      .backgroundColor($r('app.color.surface_background'))

      NativeContentDocument({
        html: contentHtml(content),
        emptyMessage: contentEmptyMessage(content),
        onScrollOffset: (offset: number): void => {
          // 像素阈值滞回：视口因顶栏收起而变高时偏移量不变，状态不会振荡。
          this.topBarScrolled = offset > 20;
        }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
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
    // 沉浸光感玻璃胶囊：左右两块独立悬浮（PR 的空 HdsTabs 材质画布方案），正文从下方穿透。
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

    Button({ type: ButtonType.Circle, stateEffect: true }) {
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

    Button({ type: ButtonType.Circle, stateEffect: true }) {
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

    Button({ type: ButtonType.Circle, stateEffect: true }) {
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
    Button({ type: ButtonType.Circle, stateEffect: true }) {
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
    Button('写回答')
      .id('p4_question_write_answer')
      .height(44)
      .fontSize($r('app.float.p1_secondary_font_size'))
      .onClick((): void => this.openAnswerComposer())
  }

private openAnswerComposer(): void {
    const session = this.session;
    if (session === undefined || session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.navigate({ name: P1DestinationName.LOGIN });
      return;
    }
    this.navigate({ name: P1DestinationName.WRITE_ANSWER, questionId: this.contentId });
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
  private detailTopBar(content: LoadedContentDetail) {
    // P3-9-B：顶部折叠作者栏——未滚动展开显示作者行（头像/名字/简介），滚动后收起为标题行。
    // 页面返回与类型标题由固定单行标题栏提供，此处只承载内容上下文。
    Row() {
      if (!this.topBarScrolled) {
        if (contentAuthorName(content).length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Stack({ alignContent: Alignment.Center }) {
              // 底层占位：首字圆，头像缺失或加载失败时可见。
              Circle()
                .width(36)
                .height(36)
                .fill($r('app.color.control_background'))
              Text(contentAuthorName(content).substring(0, 1))
                .fontSize($r('app.float.p1_caption_font_size'))
                .fontColor($r('app.color.secondary_text'))
              // 顶层真实头像：加载成功覆盖占位（加载失败保持透明，露出首字圆）。
              if (contentAuthorAvatarUrl(content).length > 0) {
                Image(contentAuthorAvatarUrl(content))
                  .id(`p3_${content.kind}_detail_top_avatar`)
                  .width(36)
                  .height(36)
                  .borderRadius(18)
                  .objectFit(ImageFit.Cover)
              }
            }
            .width(36)
            .height(36)
            .clip(true)

            Column({ space: 2 }) {
              Text(contentAuthorName(content))
                .id(`p3_${content.kind}_detail_top_author`)
                .fontSize($r('app.float.p1_body_font_size'))
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
          .id(`p3_${content.kind}_detail_top_author_row`)
          .layoutWeight(1)
          .padding({
            left: $r('app.float.p1_page_padding'),
            right: $r('app.float.p1_page_padding'),
            top: $r('app.float.p1_spacing_small'),
            bottom: $r('app.float.p1_spacing_small')
          })
          .onClick((): void => {
            const author = content.value.author;
            if (author !== undefined && author.id.trim().length > 0) {
              const urlToken = author.urlToken ?? author.id;
              this.navigate({ name: P1DestinationName.PEOPLE, id: urlToken });
            }
          })
        } else {
          // 无作者时：回答/文章不显示「回答」文字（系统栏已有），问题页显示标题。
          if (content.kind === ContentDetailKind.QUESTION) {
            Text(contentTitle(content))
              .id(`p3_${content.kind}_detail_top_title`)
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .padding({
                left: $r('app.float.p1_page_padding'),
                right: $r('app.float.p1_page_padding'),
                top: $r('app.float.p1_spacing_small'),
                bottom: $r('app.float.p1_spacing_small')
              })
            }
          }
      } else {
        // 收起态：回答/文章完全不渲染（节省空间，标题由 NavDestination 系统栏提供）；
        // 问题页保留标题（系统栏无对应完整标题）。
        if (content.kind === ContentDetailKind.QUESTION) {
          Text(contentTitle(content))
            .id(`p3_${content.kind}_detail_top_title`)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .padding({
              left: $r('app.float.p1_page_padding'),
              right: $r('app.float.p1_page_padding'),
              top: $r('app.float.p1_spacing_small'),
              bottom: $r('app.float.p1_spacing_small')
            })
        }
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_background'))
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider_color') })
    .zIndex(2)
    .hitTestBehavior(HitTestMode.Default)
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
    Button({ type: ButtonType.Circle, stateEffect: true }) {

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
    Button({ type: ButtonType.Circle, stateEffect: true }) {

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
    Button(this.following ? `已关注 ${this.followerCount}` : `关注问题 ${this.followerCount}`,
      { type: ButtonType.Normal })
      .id('p3_question_follow')
      .fontSize($r('app.float.p1_body_font_size'))
      .fontColor(this.following ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
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
    }
  }

  private activateInteraction(content: LoadedContentDetail): void {
    if (content.kind === ContentDetailKind.QUESTION) {
      if (this.followController !== undefined || this.followRepository === undefined || this.session === undefined) {
        return;
      }
      const repository = this.followRepository;
      const session = this.session;
      const contentId = this.contentId;
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
        this.contentId,
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

export function contentAuthorLine(content: LoadedContentDetail): string {
  const author = content.value.author;
  if (author === undefined) {
    return '';
  }
  return author.headline.trim().length > 0 ? `${author.name} · ${author.headline}` : author.name;
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
