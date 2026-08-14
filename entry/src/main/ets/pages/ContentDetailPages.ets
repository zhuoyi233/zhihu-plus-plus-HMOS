import {
  P1Destination,
  P1DestinationName
} from 'core';
import {
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
          this.loadedContent(this.content)
        }
      }
      .id(`p2_${this.kind}_detail_page`)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.kind === ContentDetailKind.ANSWER || this.kind === ContentDetailKind.ARTICLE) {
        if (this.phase === ContentDetailPhase.READY && this.content !== undefined) {
          this.bottomActionBar()
        }
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

        if (contentAuthorName(content).length > 0) {
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
        emptyMessage: contentEmptyMessage(content)
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
          // 左组：投票胶囊（赞同图标+数字 / 反对），Neutral 浅蓝底、激活实蓝底（对齐上游主视觉）。
          Row({ space: 0 }) {
            this.voteUpAction()
            this.voteDownAction()
          }
          .borderRadius(22)
          .backgroundColor(this.voteState === ContentVoteState.NEUTRAL
            ? $r('app.color.brand_primary_container')
            : $r('app.color.brand_primary'))
          .clip(true)

          Blank()
            .layoutWeight(1)

          // 右组：收藏 + 评论 + 更多（对齐上游 bottomBar 右侧）。
          Button(this.favoriteDialogShown ? '收藏' : '收藏', { type: ButtonType.Normal })
            .id(`p3_${this.kind}_detail_favorite_bar`)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              if (this.collectionRepository !== undefined && this.session !== undefined) {
                this.favoriteDialogShown = true;
              } else {
                this.navigate({ name: P1DestinationName.LOGIN });
              }
            })

          Button(`评论 ${this.content?.value.commentCount ?? 0}`, { type: ButtonType.Normal })
            .id(`p3_${this.kind}_detail_comment_bar`)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              if (this.commentRepository !== undefined && this.session !== undefined) {
                this.showComments = true;
              } else {
                this.navigate({ name: P1DestinationName.LOGIN });
              }
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
  }

  @Builder
  private voteUpAction() {
    Button(this.voteState === ContentVoteState.UP ? `已赞同 ${this.voteupCount}` : `赞同 ${this.voteupCount}`,
      { type: ButtonType.Normal })
      .id(`p3_${this.kind}_vote_up`)
      .fontSize($r('app.float.p1_body_font_size'))
      .fontColor(this.voteState === ContentVoteState.UP
        ? $r('app.color.on_brand')
        : $r('app.color.brand_primary'))
      .backgroundColor(Color.Transparent)
      .enabled(!this.interactionPending)
      .onClick((): void => {
        this.voteController?.toggleVote(true);
      })
  }

  @Builder
  private voteDownAction() {
    Button(this.voteState === ContentVoteState.DOWN ? '已反对' : '反对', { type: ButtonType.Normal })
      .id(`p3_${this.kind}_vote_down`)
      .fontSize($r('app.float.p1_body_font_size'))
      .fontColor(this.voteState === ContentVoteState.DOWN
        ? $r('app.color.on_brand')
        : $r('app.color.brand_primary'))
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
