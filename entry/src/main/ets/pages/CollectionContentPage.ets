import { P1Destination, P1DestinationName } from 'core';
import {
  CollectionContentItem,
  CollectionContentKind,
  CollectionRepository,
  CollectionSummary,
  LoginSessionGateway
} from 'data';
import {
  CollectionContentController,
  CollectionContentPhase,
  CollectionContentViewState
} from './CollectionContentState';

@Component
export struct CollectionContentPage {
  collectionId: string = '';
  repository: CollectionRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private phase: CollectionContentPhase = CollectionContentPhase.IDLE;
  @State private collection?: CollectionSummary = undefined;
  @State private items: Array<CollectionContentItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  private controller?: CollectionContentController;

  aboutToAppear(): void {
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = CollectionContentPhase.ERROR;
      this.errorMessage = '收藏夹内容数据源未配置';
      return;
    }
    this.controller = new CollectionContentController(
      this.collectionId,
      repository,
      session,
      (state: CollectionContentViewState): void => this.applyState(state)
    );
    this.controller.activate();
    this.controller.loadInitial();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (this.phase === CollectionContentPhase.IDLE || this.phase === CollectionContentPhase.LOADING) {
        this.statusPanel('正在加载收藏夹内容…', false, 'p3_collection_content_loading')
      } else if (this.phase === CollectionContentPhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'p3_collection_content_error')
      } else if (this.phase === CollectionContentPhase.EMPTY) {
        this.statusPanel('这个收藏夹还没有内容', true, 'p3_collection_content_empty')
      } else {
        this.header()
        if (this.errorMessage.length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Text(this.errorMessage)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
            if (this.requiresLogin) {
              Button('去登录')
                .id('p3_collection_content_login')
                .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
            } else {
              Button('重试')
                .id('p3_collection_content_retry_more')
                .onClick(() => this.controller?.retry())
            }
          }
          .width('100%')
          .padding($r('app.float.p1_spacing_small'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }

        List({ space: 10 }) {
          ForEach(this.items, (item: CollectionContentItem) => {
            ListItem() {
              this.contentCard(item)
            }
          }, (item: CollectionContentItem): string => `${item.kind}:${item.id}`)

          if (this.loadingMore || this.canLoadMore) {
            ListItem() {
              Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                .id('p3_collection_content_load_more')
                .width('100%')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .enabled(!this.loadingMore)
                .onClick(() => this.controller?.loadMore())
            }
          }
        }
        .id('p3_collection_content_list')
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.controller?.loadMore())
      }
    }
    .id('p3_collection_content_page')
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
  private header() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text(this.collection?.title ?? '收藏夹')
        .id('p3_collection_content_title')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      if ((this.collection?.description ?? '').trim().length > 0) {
        Text(this.collection?.description ?? '')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .maxLines(3)
      }
      Text(collectionStats(this.collection))
        .id('p3_collection_content_stats')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private contentCard(item: CollectionContentItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text(collectionContentKindLabel(item.kind))
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.brand_primary'))
          if (item.authorName !== undefined) {
            Text(item.authorName)
              .fontSize($r('app.float.p1_caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
        }
        .width('100%')
        Text(item.title)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        if (item.excerpt.trim().length > 0) {
          Text(item.excerpt)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .maxLines(3)
        }
        Text(item.details)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p3_collection_content_${item.kind}_${item.id}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .onClick((): void => this.navigate(collectionContentDestination(item)))
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (testId === 'p3_collection_content_loading') {
        LoadingProgress()
          .id('p3_collection_content_loading_progress')
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
            .id('p3_collection_content_status_login')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .id(`${testId}_retry`)
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick(() => this.controller?.retry())
        }
      }
    }
    .id(testId)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }

  private applyState(state: CollectionContentViewState): void {
    this.phase = state.phase;
    this.collection = state.collection;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
  }
}

function collectionContentKindLabel(kind: CollectionContentKind): string {
  switch (kind) {
    case CollectionContentKind.ANSWER:
      return '回答';
    case CollectionContentKind.ARTICLE:
      return '文章';
    case CollectionContentKind.QUESTION:
      return '问题';
    case CollectionContentKind.PIN:
      return '想法';
  }
}

function collectionStats(collection: CollectionSummary | undefined): string {
  if (collection === undefined) {
    return '';
  }
  const parts: Array<string> = [`${collection.itemCount} 条收藏`];
  if (collection.likeCount > 0) {
    parts.push(`${collection.likeCount} 个赞同`);
  }
  if (collection.commentCount > 0) {
    parts.push(`${collection.commentCount} 条评论`);
  }
  return parts.join(' · ');
}

function collectionContentDestination(item: CollectionContentItem): P1Destination {
  if (item.kind === CollectionContentKind.ANSWER) {
    return { name: P1DestinationName.ANSWER, id: item.id };
  }
  if (item.kind === CollectionContentKind.ARTICLE) {
    return { name: P1DestinationName.ARTICLE, id: item.id };
  }
  if (item.kind === CollectionContentKind.QUESTION) {
    return { name: P1DestinationName.QUESTION, id: item.id };
  }
  return { name: P1DestinationName.PIN, id: item.id };
}
