import { isSafeDecimalContentId, P1Destination, P1DestinationName } from 'core';
import {
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  ChannelContentItem,
  ChannelDailyStoryItem,
  ChannelFeedItem,
  ChannelFeedItemKind,
  channelFeedItemIdentity,
  ChannelFeedRepository,
  ChannelFeedSource,
  DefaultChannelFeedRepository,
  FeedItem,
  FeedTargetKind
} from 'data';
import {
  BlockingActionContext,
  BlockingActionController,
  BlockingActionPhase,
  BlockingActionViewState,
  BlockingUserCandidate
} from './BlockingActionState';
import {
  ChannelFeedController,
  ChannelFeedPhase,
  channelFeedTitle,
  ChannelFeedViewState
} from './ChannelFeedState';

@Component
export struct ChannelFeedPage {
  source: ChannelFeedSource = ChannelFeedSource.HOT;
  repository: ChannelFeedRepository | undefined = new DefaultChannelFeedRepository();
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private phase: ChannelFeedPhase = ChannelFeedPhase.IDLE;
  @State private items: Array<ChannelFeedItem> = [];
  @State private refreshing: boolean = false;
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @State private pendingUserBlock?: BlockingUserCandidate = undefined;
  @State private keywordBlockVisible: boolean = false;
  @State private keywordBlockInput: string = '';
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  private controller?: ChannelFeedController;
  private blockingAction?: BlockingActionController;
  private pendingBlockItem?: ChannelContentItem = undefined;

  aboutToAppear(): void {
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载列表导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    const repository = this.repository;
    if (repository === undefined) {
      this.phase = ChannelFeedPhase.ERROR;
      this.errorMessage = `${channelFeedTitle(this.source)}数据源未配置`;
      return;
    }
    this.controller = new ChannelFeedController(this.source, repository, (state: ChannelFeedViewState): void => {
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

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text(channelFeedTitle(this.source))
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button(this.refreshing ? '刷新中…' : '刷新')
          .id(`p2_channel_${this.source}_refresh`)
          .fontSize($r('app.float.p1_body_font_size'))
          .enabled(!this.refreshing && !this.loadingMore && this.phase !== ChannelFeedPhase.INITIAL_LOADING)
          .onClick(() => this.controller?.refresh())
      }
      .width('100%')

      if (this.phase === ChannelFeedPhase.IDLE || this.phase === ChannelFeedPhase.INITIAL_LOADING) {
        this.centeredStatus(`正在加载${channelFeedTitle(this.source)}…`, false);
      } else if (this.phase === ChannelFeedPhase.ERROR) {
        this.centeredStatus(this.errorMessage, true);
      } else if (this.phase === ChannelFeedPhase.EMPTY) {
        this.centeredStatus(`暂时没有${channelFeedTitle(this.source)}内容`, true);
      } else {
        if (this.errorMessage.length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Text(this.errorMessage)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
            if (this.requiresLogin) {
              Button('去登录')
                .id(`p2_channel_${this.source}_login`)
                .onClick(() => this.navigate({ name: P1DestinationName.LOGIN }))
            } else {
              Button('重试')
                .id(`p2_channel_${this.source}_retry_more`)
                .onClick(() => this.controller?.retry())
            }
          }
          .width('100%')
          .padding($r('app.float.p1_spacing_small'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }

        List() {
          ForEach(this.items, (item: ChannelFeedItem) => {
            ListItem() {
              if (item.kind === ChannelFeedItemKind.CONTENT) {
                this.contentCard(item);
              } else {
                this.dailyCard(item);
              }
            }
            .margin({ bottom: $r('app.float.p1_spacing_medium') })
          }, (item: ChannelFeedItem): string => channelFeedItemIdentity(item))

          if (this.loadingMore || this.canLoadMore) {
            ListItem() {
              Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                .id(`p2_channel_${this.source}_load_more`)
                .width('100%')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .enabled(!this.loadingMore)
                .onClick(() => this.controller?.loadMore())
            }
          }
        }
        .id(`p2_channel_${this.source}_list`)
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.controller?.loadMore())
      }

      if (this.blockingMessage.length > 0) {
        Text(this.blockingMessage)
          .id(`p3_channel_${this.source}_blocking_status`)
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
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private centeredStatus(message: string, retry: boolean) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (!retry) {
        LoadingProgress()
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
        if (this.requiresLogin) {
          Button('去登录')
            .id(`p2_channel_${this.source}_login`)
            .onClick(() => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .id(`p2_channel_${this.source}_retry`)
            .onClick(() => this.controller?.retry())
        }
      }
    }
    .id(`p2_channel_${this.source}_status`)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private contentCard(item: ChannelContentItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(channelActionLabel(item.feedItem, this.source))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .layoutWeight(1)
          Text(channelKindLabel(item.feedItem.target.kind))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.brand_primary'))

          // 对齐上游 FeedCardMenuBox：右上角紧凑“更多”符号图标，屏蔽等操作收进菜单。
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id(`p3_channel_${this.source}_block_${item.feedItem.target.kind}_${item.feedItem.target.id}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .enabled(!this.blockingBusy && this.blockingAction !== undefined)
          .bindMenu(this.contentBlockMenu(item))
          .accessibilityText('屏蔽作者或关键词')
        }
        .width('100%')
        Text(item.feedItem.target.title)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        if (item.feedItem.target.excerpt.trim().length > 0) {
          Text(item.feedItem.target.excerpt)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        Row({ space: $r('app.float.p1_spacing_medium') }) {
          if (item.feedItem.target.author !== undefined) {
            Text(item.feedItem.target.author.name)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
          Text(`${item.feedItem.target.voteupCount} 赞同`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
          Text(`${item.feedItem.target.commentCount} 评论`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p2_channel_content_${item.feedItem.target.kind}_${item.feedItem.target.id}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`打开${channelKindLabel(item.feedItem.target.kind)}：${item.feedItem.target.title}`)
    .onClick(() => {
      const destination = channelFeedDestination(item);
      if (destination !== undefined) {
        this.navigate(destination);
      }
    })
  }

  @Builder
  private dailyCard(item: ChannelDailyStoryItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('知乎日报')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.brand_primary'))
          .layoutWeight(1)
        Text(item.story.date)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      Text(item.story.title)
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      if (item.story.hint.trim().length > 0) {
        Text(item.story.hint)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p2_channel_daily_${item.story.id}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`知乎日报：${item.story.title}`)
    .onClick((): void => {
      this.navigate({ name: P1DestinationName.DAILY_STORY, id: item.story.id });
    })
  }

  private contentBlockMenu(item: ChannelContentItem): Array<MenuElement> {
    const menu: Array<MenuElement> = [];
    const author = item.feedItem.target.author;
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

  private blockContext(item: ChannelContentItem): BlockingActionContext {
    return {
      contentTitle: item.feedItem.target.title,
      contentKind: item.feedItem.target.kind,
      contentId: item.feedItem.target.id
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
    const identity = channelFeedItemIdentity(item);
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
    const identity = channelFeedItemIdentity(item);
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
          .id(`p3_channel_${this.source}_confirm_block_user`)
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
        .id(`p3_channel_${this.source}_keyword_block_input`)
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
          .id(`p3_channel_${this.source}_confirm_block_keyword`)
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

  private applyState(state: ChannelFeedViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    this.refreshing = state.refreshing;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
  }
}

export function channelFeedDestination(item: ChannelContentItem): P1Destination | undefined {
  if (!isSafeDecimalContentId(item.feedItem.target.id)) {
    return undefined;
  }
  switch (item.feedItem.target.kind) {
    case FeedTargetKind.QUESTION:
      return { name: P1DestinationName.QUESTION, id: item.feedItem.target.id };
    case FeedTargetKind.ANSWER:
      return { name: P1DestinationName.ANSWER, id: item.feedItem.target.id };
    case FeedTargetKind.ARTICLE:
      return { name: P1DestinationName.ARTICLE, id: item.feedItem.target.id };
  }
}

export function channelKindLabel(kind: FeedTargetKind): string {
  switch (kind) {
    case FeedTargetKind.QUESTION:
      return '问题';
    case FeedTargetKind.ANSWER:
      return '回答';
    case FeedTargetKind.ARTICLE:
      return '文章';
  }
}

export function channelActionLabel(item: FeedItem, source: ChannelFeedSource): string {
  const actionText = item.actionText?.trim() ?? '';
  if (actionText.length > 0) {
    return actionText;
  }
  return source === ChannelFeedSource.FOLLOWING ? '关注动态' : '热榜内容';
}
