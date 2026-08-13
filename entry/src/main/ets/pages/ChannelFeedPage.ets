import { isSafeDecimalContentId, P1Destination, P1DestinationName } from 'core';
import {
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
  ChannelFeedController,
  ChannelFeedPhase,
  channelFeedTitle,
  ChannelFeedViewState
} from './ChannelFeedState';

@Component
export struct ChannelFeedPage {
  source: ChannelFeedSource = ChannelFeedSource.HOT;
  repository: ChannelFeedRepository | undefined = new DefaultChannelFeedRepository();
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private phase: ChannelFeedPhase = ChannelFeedPhase.IDLE;
  @State private items: Array<ChannelFeedItem> = [];
  @State private refreshing: boolean = false;
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  private controller?: ChannelFeedController;

  aboutToAppear(): void {
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
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
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
    .id(`p2_channel_daily_${item.story.id}`)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`知乎日报：${item.story.title}`)
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
