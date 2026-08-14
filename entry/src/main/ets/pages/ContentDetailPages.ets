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
  /** P3-9-D：阅读进度（0..1），驱动右侧阅读进度条。 */
  @State private readingPercent: number = 0;
  private controller?: ContentDetailController;
  private blockingAction?: BlockingActionController;
  private voteController?: ContentVoteController;
  private followController?: FollowController;

  aboutToAppear(): void {
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
        if (this.phase === ContentDetailPhase.LOADING || this.phase === ContentDetailPhase.IDLE) {
          this.statusPanel('正在加载内容…', false)
        } else if (this.phase === ContentDetailPhase.ERROR) {
          this.statusPanel(this.errorMessage, true)
        } else if (this.content !== undefined) {
          Column() {
            Column() {
              this.loadedContent(this.content)
            }
            .layoutWeight(1)
            .width('100%')
            if (this.kind === ContentDetailKind.ANSWER || this.kind === ContentDetailKind.ARTICLE) {
              this.bottomActionBar()
            }
          }
          .width('100%')
          .height('100%')
        }
      }
      .id(`p2_${this.kind}_detail_page`)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.phase === ContentDetailPhase.READY && this.content !== undefined) {
        this.detailTopBar(this.content)
      }
      // P3-9-D：右侧阅读进度条（正文加载完成且已滚动时显示）。
      if (this.phase === ContentDetailPhase.READY && this.readingPercent > 0 && this.readingPercent < 1) {
        Column() {
          Column()
            .width(3)
            .layoutWeight(this.readingPercent)
            .backgroundColor($r('app.color.brand_primary'))
          Column()
            .width(3)
            .layoutWeight(1 - this.readingPercent)
            .backgroundColor($r('app.color.control_background'))
        }
        .id('p3_detail_reading_progress')
        .width(3)
        .height('80%')
        .borderRadius(2)
        .align(Alignment.Center)
        .margin({ left: '96%' })
      }
      if (this.favoriteDialogShown && this.collectionRepository !== undefined && this.session !== undefined) {
        this.favoriteDialog()
      }
      if (this.pendingUserBlock !== undefined) {
        this.userBlockDialog()
      }
      if (this.keywordBlockVisible) {
        this.keywordBlockDialog()
      }
      if (this.actionMenuShown) {
        this.actionMenuSheet()
      }
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
    Column() {
      Blank()
        .onClick((): void => {
          this.favoriteDialogShown = false;
        })
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
        .height('70%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
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
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private loadedContent(content: LoadedContentDetail) {
    Column() {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Text(contentTitle(content))
          .id(`p2_${content.kind}_detail_title`)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')

        // 作者行仅问题页保留（回答/文章的顶栏折叠作者行已含头像+名字+签名，避免重复）。
        if (content.kind === ContentDetailKind.QUESTION && contentAuthorName(content).length > 0) {
          Text(contentAuthorLine(content))
            .id(`p2_${content.kind}_detail_author`)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .width('100%')
        }

        Text(contentStatistics(content))
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

        if (contentAuthorName(content).length > 0) {
          Button('屏蔽作者')
            .id(`p3_${content.kind}_block_author`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .enabled(!this.blockingBusy && this.blockingAction !== undefined)
            .onClick((): void => {
              const author = content.value.author;
              if (author !== undefined) {
                this.pendingUserBlock = { userId: author.id, userName: author.name };
              }
            })
        }

        Button('屏蔽关键词')
          .id(`p3_${content.kind}_block_keyword`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .enabled(!this.blockingBusy && this.blockingAction !== undefined)
          .onClick((): void => {
            this.keywordBlockInput = '';
            this.keywordBlockVisible = true;
          })

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
        top: $r('app.float.p1_spacing_medium'),
        bottom: $r('app.float.p1_spacing_medium')
      })
      .backgroundColor($r('app.color.surface_background'))

      NativeContentDocument({
        html: contentHtml(content),
        emptyMessage: contentEmptyMessage(content),
        onScrollOffset: (offset: number): void => {
          this.topBarScrolled = offset > 0;
        },
        onScrollPercent: (percent: number): void => {
          this.readingPercent = percent;
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
    Column() {
      if (this.interactionErrorMessage.length > 0) {
        this.interactionStatusRow()
      }
      Row({ space: 0 }) {
        if (this.kind === ContentDetailKind.QUESTION) {
          if (this.followController !== undefined) {
            this.followQuestionAction()
          }
          Blank()
            .layoutWeight(1)
        } else {
          // 左组：投票胶囊（赞同图标+数字 / 反对），对齐上游主视觉——
          // Neutral 显示赞+踩（浅蓝底蓝字）；点赞同后反对隐藏、踩后赞同隐藏（实蓝底白字）。
          Row({ space: 0 }) {
            if (this.voteState !== ContentVoteState.DOWN) {
              this.voteUpAction()
            }
            if (this.voteState !== ContentVoteState.UP) {
              this.voteDownAction()
            }
          }
          .borderRadius(24)
          .backgroundColor(this.voteState === ContentVoteState.NEUTRAL
            ? $r('app.color.brand_primary_container')
            : $r('app.color.brand_primary'))
          .clip(true)

          Blank()
            .layoutWeight(1)

          // 右组：收藏 + 评论 + 更多（对齐上游 bottomBar 右侧图标按钮）。
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.bookmark'))
              .fontSize(22)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id(`p3_${this.kind}_detail_favorite_bar`)
          .width(50)
          .height(50)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            if (this.collectionRepository !== undefined && this.session !== undefined) {
              this.favoriteDialogShown = true;
            } else {
              this.navigate({ name: P1DestinationName.LOGIN });
            }
          })

          Button({ type: ButtonType.Normal }) {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.message'))
                .fontSize(22)
                .fontColor([$r('app.color.secondary_text')])
              Text(`${this.content?.value.commentCount ?? 0}`)
                .fontSize($r('app.float.p1_body_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.secondary_text'))
            }
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          }
          .id(`p3_${this.kind}_detail_comment_bar`)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            if (this.commentRepository !== undefined && this.session !== undefined) {
              this.showComments = true;
            } else {
              this.navigate({ name: P1DestinationName.LOGIN });
            }
          })

          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(22)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id(`p3_${this.kind}_detail_more`)
          .width(50)
          .height(50)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.actionMenuShown = true;
          })
        }
      }
      .width('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: $r('app.float.p1_spacing_small'),
        bottom: $r('app.float.p1_spacing_small')
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_background'))
    .border({ width: { top: 0.5 }, color: $r('app.color.divider_color') })
    .zIndex(2)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private detailTopBar(content: LoadedContentDetail) {
    // P3-9-B：顶部折叠作者栏——未滚动展开显示作者行（头像/名字/简介），滚动后收起为标题行。
    // 返回键由 NavDestination 系统提供，此处不重复。
    Row() {
      if (!this.topBarScrolled) {
        if (contentAuthorName(content).length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(36)
                .height(36)
                .fill($r('app.color.control_background'))
              Text(contentAuthorName(content).substring(0, 1))
                .fontSize($r('app.float.p1_caption_font_size'))
                .fontColor($r('app.color.secondary_text'))
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
      } else {
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
    .width('100%')
    .backgroundColor($r('app.color.surface_background'))
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider_color') })
    .zIndex(2)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private actionMenuSheet() {
    // P3-9-C：底部菜单弹窗（对齐上游 MyModalBottomSheet）。分享/复制链接可用，
    // 朗读/总结/导出/沉浸式为占位入口（依赖系统能力或后续切片）。
    Column() {
      Blank()
        .onClick((): void => {
          this.actionMenuShown = false;
        })
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text('更多操作')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          Button('关闭')
            .id('p3_detail_menu_close')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.actionMenuShown = false;
            })
        }
        .width('100%')

        Button('复制链接')
          .id('p3_detail_menu_copy_link')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
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

        Button('分享')
          .id('p3_detail_menu_share')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick((): void => {
            this.actionMenuShown = false;
            this.copyContentLink();
          })

        Button('朗读（开发中）')
          .id('p3_detail_menu_tts')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .enabled(false)

        Button('导出文章（开发中）')
          .id('p3_detail_menu_export')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .enabled(false)
      }
      .width('100%')
      .padding($r('app.float.p1_spacing_medium'))
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius({
        topLeft: $r('app.float.p1_card_radius'),
        topRight: $r('app.float.p1_card_radius')
      })
    }
    .id('p3_detail_menu_sheet')
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
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
    Button({ type: ButtonType.Normal }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(22)
          .fontColor([this.voteState === ContentVoteState.UP
            ? $r('app.color.on_brand')
            : $r('app.color.brand_primary')])
        Text(`${this.voteupCount}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.voteState === ContentVoteState.UP
            ? $r('app.color.on_brand')
            : $r('app.color.brand_primary'))
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    }
    .id(`p3_${this.kind}_vote_up`)
    .backgroundColor(Color.Transparent)
    .enabled(!this.interactionPending)
    .onClick((): void => {
      this.voteController?.toggleVote(true);
    })
  }

  @Builder
  private voteDownAction() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_down'))
          .fontSize(22)
          .fontColor([this.voteState === ContentVoteState.DOWN
            ? $r('app.color.on_brand')
            : $r('app.color.brand_primary')])
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    }
    .id(`p3_${this.kind}_vote_down`)
    .backgroundColor(Color.Transparent)
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
      navigate: this.navigate
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
      navigate: this.navigate
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
      navigate: this.navigate
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

export function contentStatistics(content: LoadedContentDetail): string {
  switch (content.kind) {
    case ContentDetailKind.QUESTION:
      return `${content.value.answerCount} 个回答 · ${content.value.followerCount} 人关注 · ` +
        `${content.value.commentCount} 条评论`;
    case ContentDetailKind.ANSWER:
    case ContentDetailKind.ARTICLE:
      return `${content.value.voteupCount} 赞同 · ${content.value.commentCount} 条评论`;
  }
}
