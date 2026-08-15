import { P1Destination, P1DestinationName } from 'core';
import {
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  DefaultFeedRepository,
  feedItemIdentity,
  FeedItem,
  FeedRepository,
  FeedTargetKind
} from 'data';
import {
  BlockingActionContext,
  BlockingActionController,
  BlockingActionPhase,
  BlockingActionViewState,
  BlockingUserCandidate
} from './BlockingActionState';
import { HomeFeedController, HomeFeedPhase, HomeFeedViewState } from './HomeFeedState';

@Component
export struct HomeFeedPage {
  repository: FeedRepository | undefined = new DefaultFeedRepository();
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  @Prop @Watch('reloadAfterAuthentication') reloadToken: number = 0;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private phase: HomeFeedPhase = HomeFeedPhase.IDLE;
  @State private items: Array<FeedItem> = [];
  @State private refreshing: boolean = false;
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  @State private pendingUserBlock?: BlockingUserCandidate = undefined;
  @State private keywordBlockVisible: boolean = false;
  @State private keywordBlockInput: string = '';
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  private controller: HomeFeedController | undefined = undefined;
  private blockingAction?: BlockingActionController;
  private pendingBlockItem?: FeedItem = undefined;

  aboutToAppear(): void {
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载列表导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    const repository = this.repository;
    if (repository === undefined) {
      this.phase = HomeFeedPhase.ERROR;
      this.errorMessage = '首页数据源未配置';
      return;
    }
    this.controller = new HomeFeedController(repository, (state: HomeFeedViewState): void => {
      this.applyState(state);
    });
    this.controller.activate();
    this.controller.loadInitial();
    this.createBlockingAction();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.blockingAction = undefined;
    this.pendingUserBlock = undefined;
    this.keywordBlockVisible = false;
    this.keywordBlockInput = '';
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

  private reloadAfterAuthentication(): void {
    this.controller?.refresh();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Button('搜索')
            .id('p2_home_search')
            .fontSize($r('app.float.p1_body_font_size'))
            .layoutWeight(1)
            .accessibilityText('打开搜索')
            .onClick(() => this.navigate({ name: P1DestinationName.SEARCH, query: '' }))

          Button('显示')
            .id('p2_home_settings')
            .fontSize($r('app.float.p1_body_font_size'))
            .accessibilityText('打开显示与阅读设置')
            .onClick(() => this.navigate({ name: P1DestinationName.SETTINGS }))

          Button(this.refreshing ? '刷新中…' : '刷新')
            .id('p2_home_refresh')
            .fontSize($r('app.float.p1_body_font_size'))
            .enabled(!this.refreshing && !this.loadingMore && this.phase !== HomeFeedPhase.INITIAL_LOADING)
            .accessibilityText(this.refreshing ? '首页正在刷新' : '刷新首页')
            .onClick(() => this.controller?.refresh())
        }
        .id('p2_home_top_actions')
        .width('100%')

        Row({ space: $r('app.float.p1_spacing_small') }) {
          Button('关注')
            .id('p2_home_following')
            .layoutWeight(1)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .onClick(() => this.navigate({ name: P1DestinationName.FOLLOWING }))
          Button('热榜')
            .id('p2_home_hot')
            .layoutWeight(1)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .onClick(() => this.navigate({ name: P1DestinationName.HOT }))
          Button('日报')
            .id('p2_home_daily')
            .layoutWeight(1)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .onClick(() => this.navigate({ name: P1DestinationName.DAILY }))
        }
        .id('p2_home_channels')
        .width('100%')

        if (this.phase === HomeFeedPhase.INITIAL_LOADING || this.phase === HomeFeedPhase.IDLE) {
          this.centeredStatus('正在加载首页…', false, 'p2_home_initial_loading');
        } else if (this.phase === HomeFeedPhase.ERROR) {
          this.centeredStatus(this.errorMessage, true, 'p2_home_error');
          if (this.requiresLogin) {
            Button('去登录')
              .id('p2_home_error_login')
              .fontSize($r('app.float.p1_body_font_size'))
              .onClick(() => this.navigate({ name: P1DestinationName.LOGIN }))
          }
        } else if (this.phase === HomeFeedPhase.EMPTY) {
          this.centeredStatus('暂时没有可显示的内容', true, 'p2_home_empty');
        } else {
          if (this.errorMessage.length > 0) {
            Row({ space: $r('app.float.p1_spacing_small') }) {
              Text(this.errorMessage)
                .id('p2_home_recoverable_error_text')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .layoutWeight(1)
              Button('重试')
                .id('p2_home_recoverable_error_retry')
                .onClick(() => this.controller?.retry())
            }
            .width('100%')
            .padding($r('app.float.p1_spacing_small'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
          }

          Refresh({ refreshing: this.refreshing, offset: 80, friction: 100 }) {
            List() {
              ForEach(this.items, (item: FeedItem) => {
                ListItem() {
                  this.feedCard(item);
                }
                .margin({ bottom: $r('app.float.p1_spacing_medium') })
              }, (item: FeedItem): string => feedItemIdentity(item))

              if (this.loadingMore || this.canLoadMore) {
                ListItem() {
                  Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                    .id('p2_home_load_more')
                    .width('100%')
                    .fontSize($r('app.float.p1_secondary_font_size'))
                    .enabled(!this.loadingMore)
                    .onClick(() => this.controller?.loadMore())
                }
              }
            }
            .id('p2_home_feed_list')
            .width('100%')
            .height('100%')
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => this.controller?.loadMore())
          }
          .id('p2_home_pull_refresh')
          .width('100%')
          .layoutWeight(1)
          .onRefreshing(() => this.controller?.refresh())
        }

        if (this.blockingMessage.length > 0) {
          Text(this.blockingMessage)
            .id('p3_home_blocking_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        if (this.pendingUserBlock !== undefined) {
          this.userBlockDialog()
        }
        if (this.keywordBlockVisible) {
          this.keywordBlockDialog()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: $r('app.float.p1_spacing_medium'),
        bottom: $r('app.float.p1_page_padding')
      })
    }
    .id('p2_home_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private centeredStatus(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (!retry) {
        LoadingProgress()
          .id('p2_home_loading_progress')
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      }
      Text(message)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        Button('重新加载')
          .id(`${testId}_retry`)
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick(() => this.controller?.retry())
      }
    }
    .id(testId)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private feedCard(item: FeedItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(homeFeedActionLabel(item))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .layoutWeight(1)
          Text(feedKindLabel(item.target.kind))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.brand_primary'))

          // 对齐上游 FeedCardMenuBox：右上角紧凑“更多”符号图标，屏蔽等操作收进菜单。
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id(`p3_home_feed_block_${item.target.kind}_${item.target.id}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .enabled(!this.blockingBusy && this.blockingAction !== undefined)
          .bindMenu(this.feedBlockMenu(item))
          .accessibilityText('屏蔽作者或关键词')
        }
        .width('100%')

        Text(item.target.title)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')

        if (item.target.excerpt.trim().length > 0) {
          Text(item.target.excerpt)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        Row({ space: $r('app.float.p1_spacing_medium') }) {
          if (item.target.author !== undefined) {
            Text(item.target.author.name)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
          Text(`${item.target.voteupCount} 赞同`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
          Text(`${item.target.commentCount} 评论`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p2_home_feed_card_${item.target.kind}_${item.target.id}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`打开${feedKindLabel(item.target.kind)}：${item.target.title}`)
    .onClick(() => this.navigate(homeFeedDestination(item)))
  }

  private feedBlockMenu(item: FeedItem): Array<MenuElement> {
    const menu: Array<MenuElement> = [];
    const author = item.target.author;
    if (author !== undefined) {
      menu.push({
        value: '屏蔽作者',
        action: (): void => {
          this.pendingBlockItem = item;
          this.pendingUserBlock = { userId: author.id, userName: author.name };
        }
      });
    }
    menu.push({
      value: '屏蔽关键词',
      action: (): void => {
        this.pendingBlockItem = item;
        this.keywordBlockInput = '';
        this.keywordBlockVisible = true;
      }
    });
    return menu;
  }

  private blockContext(item: FeedItem): BlockingActionContext {
    return {
      contentTitle: item.target.title,
      contentKind: item.target.kind,
      contentId: item.target.id
    };
  }

  private confirmUserBlock(): void {
    const pending = this.pendingUserBlock;
    const action = this.blockingAction;
    const item = this.pendingBlockItem;
    if (pending === undefined || action === undefined || item === undefined) {
      return;
    }
    this.pendingUserBlock = undefined;
    this.pendingBlockItem = undefined;
    const identity = feedItemIdentity(item);
    action.blockUser(pending.userId, pending.userName, this.blockContext(item)).then((): void => {
      if (action.snapshot().phase === BlockingActionPhase.SUCCESS) {
        this.controller?.removeItem(identity);
      }
    });
  }

  private confirmKeywordBlock(): void {
    const action = this.blockingAction;
    const input = this.keywordBlockInput;
    const item = this.pendingBlockItem;
    this.keywordBlockVisible = false;
    this.keywordBlockInput = '';
    this.pendingBlockItem = undefined;
    if (action === undefined || input.trim().length === 0 || item === undefined) {
      return;
    }
    const identity = feedItemIdentity(item);
    action.blockKeyword(input, this.blockContext(item)).then((): void => {
      if (action.snapshot().phase === BlockingActionPhase.SUCCESS) {
        this.controller?.removeItem(identity);
      }
    });
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
          .id('p3_home_confirm_block_user')
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
        .id('p3_home_keyword_block_input')
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
          .id('p3_home_confirm_block_keyword')
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

  private applyState(state: HomeFeedViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    this.refreshing = state.refreshing;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
  }
}

export function homeFeedDestination(item: FeedItem): P1Destination {
  switch (item.target.kind) {
    case FeedTargetKind.QUESTION:
      return { name: P1DestinationName.QUESTION, id: item.target.id };
    case FeedTargetKind.ANSWER:
      return { name: P1DestinationName.ANSWER, id: item.target.id };
    case FeedTargetKind.ARTICLE:
      return { name: P1DestinationName.ARTICLE, id: item.target.id };
  }
}

export function feedKindLabel(kind: FeedTargetKind): string {
  switch (kind) {
    case FeedTargetKind.QUESTION:
      return '问题';
    case FeedTargetKind.ANSWER:
      return '回答';
    case FeedTargetKind.ARTICLE:
      return '文章';
  }
}

export function homeFeedActionLabel(item: FeedItem): string {
  const actionText = item.actionText?.trim() ?? '';
  return actionText.length > 0 ? actionText : '推荐内容';
}
