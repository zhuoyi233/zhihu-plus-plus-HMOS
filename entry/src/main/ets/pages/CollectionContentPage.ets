import {
  buildFlowListSections,
  flowListCard,
  flowListChrome,
  FlowListItem,
  FlowListSource
} from './FlowListSource';
import {
  FEED_COLUMN_GAP_VP,
  feedMinCardWidthVp,
  resolveWideColumnSpec,
  WideColumnSpec
} from './FeedWaterfallLayout';
import { FeedAnchorRestorer } from './FeedColumnAnchorRestore';
import { LengthMetrics } from '@kit.ArkUI';
import { AppDestination, AppDestinationName } from 'core';
import { floatingTitleBarOffset } from './AppPageChrome';
import { destinationScrollKey, destinationScrollRegistry } from './DestinationScrollRegistry';
import { FeedContentCard, feedCardMoreButtonContent } from './components/FeedContentCard';
import { collectionFeedCardPresentation } from './FeedCardPresentation';
import {
  collectionContentIdentity,
  CollectionContentItem,
  CollectionContentKind,
  CollectionRepository,
  CollectionSummary,
  DEFAULT_THEME_COLOR,
  LoginSessionGateway,
  onThemeColor
} from 'data';
import {
  CollectionContentController,
  CollectionContentPhase,
  CollectionContentViewState
} from './CollectionContentState';

/** 通栏 section（错误横幅/加载尾）的段间距：维持本页面既有 10vp 口径，不随卡片样式变化。 */
const CHROME_SECTION_GAP_VP: number = 10;

@Component
export struct CollectionContentPage {
  collectionId: string = '';
  repository: CollectionRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  onBack: () => void = (): void => {};
  @State private phase: CollectionContentPhase = CollectionContentPhase.IDLE;
  @State private collection?: CollectionSummary = undefined;
  @State private items: Array<CollectionContentItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('systemFontSizeScale') @Watch('onLayoutDriverChanged') private systemFontSizeScale: number = 1;
  @State @Watch('onLayoutDriverChanged') private pageWidthVp: number = 0;
  // 卡片外观与缩略图偏好与主页共用同一 AppStorage 键：设置变更即时生效，
  // 不重新拉取收藏接口、不清空已有条目、不主动回顶。
  @StorageProp('feedCardStyle') @Watch('onAppearanceChanged') private feedCardStyle: string = 'divider';
  @StorageProp('showFeedThumbnail') @Watch('onAppearanceChanged') private showFeedThumbnail: boolean = true;
  private readonly flowSource: FlowListSource = new FlowListSource();
  private readonly flowScroller: Scroller = new Scroller();
  @State private flowSections: WaterFlowSections = new WaterFlowSections();
  private controller?: CollectionContentController;
  // 收藏项“更多”菜单：按内容稳定身份控制展开与关闭，返回栈重显后不残留。
  @State private contentMenuIdentity: string = '';
  private readonly anchorRestorer: FeedAnchorRestorer = new FeedAnchorRestorer();
  // 首个可见条目的 flow 索引（onScrollIndex 采集），供样式/图片开关重排后恢复阅读位置。
  private firstVisibleFlowIndex: number = 0;
  private lastEntries: FlowListItem[] = [];
  private lastColumns: number = 0;
  // 样式/图片开关只能经外观设置页触发，本页必然被覆盖在返回栈里：挂起锚点身份，
  // 回到页面（aboutToAppear）且布局稳定后再恢复，避免对隐藏窗口做无效滚动。
  private pendingAnchorIdentity: string = '';

  /** 宽屏多列规格：内容 1120vp 居中，列数按 14vp 列间距求取（与卡片/多列时的真实内容间距同口径）。 */
  private wideSpec(): WideColumnSpec {
    return resolveWideColumnSpec(this.pageWidthVp, feedMinCardWidthVp(this.systemFontSizeScale),
      FEED_COLUMN_GAP_VP);
  }

  private usesCardSurface(): boolean {
    return this.feedCardStyle === 'card';
  }

  /** 内容条目间距：多列或卡片表面 14vp（与列数计算同口径），单列分割线 0（由底线分隔）。 */
  private contentGap(): number {
    return this.wideSpec().columns > 1 || this.usesCardSurface() ? FEED_COLUMN_GAP_VP : 0;
  }

  private onLayoutDriverChanged(): void {
    this.rebuildFlowLayout(true);
  }

  private onAppearanceChanged(): void {
    this.rebuildFlowLayout(true);
  }

  /** 换列/换样式保位仅在静止的 READY 态、且已滚动离开顶部时启动，避免与手势竞争。 */
  private canPreserveAnchor(): boolean {
    return this.phase === CollectionContentPhase.READY && !this.loadingMore &&
      this.firstVisibleFlowIndex > 0 && this.items.length > 0;
  }

  /** 首个可见内容条目的身份：可见窗口起点落在通栏 chrome（横幅/加载尾）上时向后跳过。 */
  private firstVisibleContentIdentity(): string {
    for (let index = this.firstVisibleFlowIndex; index < this.lastEntries.length; index += 1) {
      const entry: FlowListItem = this.lastEntries[index];
      if (entry.label === 'card') {
        return entry.key;
      }
    }
    return '';
  }

  /**
   * 按身份恢复锚点。列数变化时 FeedAnchorRestorer 的宽度哨兵能识别新布局；
   * 同宽重排（样式/图片开关）无宽度差异可判，由 pendingAnchorIdentity 走页面重显恢复。
   */
  private scheduleAnchorRestore(identity: string, delayed: boolean): void {
    if (identity.length === 0) {
      return;
    }
    const flowIndex: number = this.flowIndexOf(identity);
    if (flowIndex < 0) {
      return;
    }
    if (delayed) {
      this.pendingAnchorIdentity = identity;
      return;
    }
    const spec: WideColumnSpec = this.wideSpec();
    this.anchorRestorer.schedule({
      flowIndex: flowIndex,
      expectedItemWidth: spec.cardWidth,
      extraOffsetVp: floatingTitleBarOffset()
    }, this.flowScroller);
  }

  private flowIndexOf(identity: string): number {
    for (let index = 0; index < this.lastEntries.length; index += 1) {
      if (this.lastEntries[index].key === identity) {
        return index;
      }
    }
    return -1;
  }

  /** 页面重显后消费挂起的锚点身份：等 WaterFlow 高度重排稳定再按索引对齐视口顶。 */
  private flushPendingAnchorRestore(): void {
    const identity: string = this.pendingAnchorIdentity;
    this.pendingAnchorIdentity = '';
    if (identity.length === 0) {
      return;
    }
    setTimeout((): void => {
      const flowIndex: number = this.flowIndexOf(identity);
      if (flowIndex < 0) {
        return;
      }
      this.flowScroller.scrollToIndex(flowIndex, false, ScrollAlign.START,
        { extraOffset: LengthMetrics.vp(-floatingTitleBarOffset()) });
    }, 300);
  }

  /** 瀑布流布局快照：内容卡进内容列 section，错误横幅与加载尾通栏；同份快照供数据源与 sections 使用。 */
  private rebuildFlowLayout(preserveAnchor: boolean): void {
    const columns: number = this.wideSpec().columns;
    const columnsChanged: boolean = columns !== this.lastColumns;
    this.lastColumns = columns;
    // 变化前记录首个可见内容身份；重排后按身份映射回新索引，不用旧偏移直接恢复。
    const anchorIdentity: string = preserveAnchor && this.canPreserveAnchor()
      ? this.firstVisibleContentIdentity() : '';
    const entries: FlowListItem[] = [];
    if (this.errorMessage.length > 0) {
      entries.push(flowListChrome('collection_content_error_banner', 'error'));
    }
    for (let index = 0; index < this.items.length; index += 1) {
      const item: CollectionContentItem = this.items[index];
      entries.push(flowListCard(`collection_content_${item.kind}_${item.id}`, index, item));
    }
    if (this.loadingMore || this.canLoadMore) {
      entries.push(flowListChrome('collection_content_load_more', 'footer'));
    }
    this.lastEntries = entries;
    this.flowSections.splice(0, this.flowSections.length(),
      buildFlowListSections(entries, columns, this.contentGap(), CHROME_SECTION_GAP_VP));
    // applyLayout 增量通知：分页/样式切换不再整表重载，已有卡片保留（同键负载引用不变）。
    this.flowSource.applyLayout(entries);
    if (anchorIdentity.length > 0) {
      this.scheduleAnchorRestore(anchorIdentity, !columnsChanged);
    }
  }

  aboutToAppear(): void {
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免 loadInitial 清空列表并重载导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      this.flushPendingAnchorRestore();
      return;
    }
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
    destinationScrollRegistry.unregister(destinationScrollKey(AppDestinationName.COLLECTION, this.collectionId),
      this.flowScroller);
    this.anchorRestorer.cancel();
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (this.phase === CollectionContentPhase.IDLE || this.phase === CollectionContentPhase.LOADING) {
        this.statusPanel('正在加载收藏夹内容…', false, 'collection_content_loading')
      } else if (this.phase === CollectionContentPhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'collection_content_error')
      } else if (this.phase === CollectionContentPhase.EMPTY) {
        this.statusPanel('这个收藏夹还没有内容', true, 'collection_content_empty')
      } else {
        WaterFlow({ scroller: this.flowScroller, sections: this.flowSections,
          layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW }) {
          LazyForEach(this.flowSource, (entry: FlowListItem) => {
            FlowItem() {
              if (entry.label === 'error') {
                this.recoverableErrorBanner()
              } else if (entry.label === 'footer') {
                Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                  .backgroundColor(this.resolvedThemeColor)
                  .fontColor(onThemeColor(this.resolvedThemeColor))
                  .id('collection_content_load_more')
                  .width('100%')
                  .fontSize($r('app.float.secondary_font_size'))
                  .enabled(!this.loadingMore)
                  .onClick(() => this.controller?.loadMore())
              } else {
                this.contentCard(entry.payload as CollectionContentItem)
              }
            }
            .width('100%')
          }, (entry: FlowListItem): string => entry.key)
        }
        .id('collection_content_list')
        .onAppear((): void => {
          destinationScrollRegistry.register(destinationScrollKey(AppDestinationName.COLLECTION, this.collectionId),
            this.flowScroller);
        })
        .width('100%')
        // 只给首屏内容让位，滚动视口延伸到原生顶栏之后，供沉浸材质采样。
        .contentStartOffset(floatingTitleBarOffset())
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .cachedCount(Math.max(6, this.wideSpec().columns * 2))
        .edgeEffect(EdgeEffect.Spring)
        .onScrollIndex((start: number, _end: number): void => {
          this.firstVisibleFlowIndex = start;
        })
        .onReachEnd(() => this.controller?.loadMore())
      }
    }
    .id('collection_content_page')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({
      left: this.wideSpec().paddingVp,
      right: this.wideSpec().paddingVp,
      bottom: $r('app.float.page_padding')
    })
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const width: number = Number(area.width);
      if (width > 0 && Math.abs(width - this.pageWidthVp) > 0.5) {
        this.pageWidthVp = width;
      }
    })
  }

  @Builder
  private recoverableErrorBanner() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(this.errorMessage)
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      if (this.requiresLogin) {
        Button('去登录')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('collection_content_login')
          .onClick((): void => this.navigate({ name: AppDestinationName.LOGIN }))
      } else {
        Button('重试')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('collection_content_retry_more')
          .onClick(() => this.controller?.retry())
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_small'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private header() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text(this.collection?.title ?? '收藏夹')
        .id('collection_content_title')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      if ((this.collection?.description ?? '').trim().length > 0) {
        Text(this.collection?.description ?? '')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .maxLines(3)
      }
      Text(collectionStats(this.collection))
        .id('collection_content_stats')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private contentCard(item: CollectionContentItem) {
    // 单条收藏内容与主页信息流共用 FeedContentCard：排版/表面/缩略图/页脚同源，
    // 本页只保留稳定测试 ID、按类型跳转与“外观设置”菜单槽位。
    FeedContentCard({
      presentation: collectionFeedCardPresentation(item),
      columns: this.wideSpec().columns,
      cardStyle: this.feedCardStyle,
      showThumbnail: this.showFeedThumbnail,
      cardTestId: `collection_content_${item.kind}_${item.id}`,
      footerTestId: `collection_content_footer_${item.kind}_${item.id}`,
      onOpen: (): void => this.navigate(collectionContentDestination(item)),
      moreSlot: (): void => {
        this.contentMenuButton(item)
      }
    })
  }

  @Builder
  private contentMenuButton(item: CollectionContentItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      feedCardMoreButtonContent()
    }
    .id(`collection_content_more_${item.kind}_${item.id}`)
    .width(32)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .onClick((): void => {
      this.contentMenuIdentity = collectionContentIdentity(item);
    })
    .bindMenu(this.contentMenuIdentity === collectionContentIdentity(item), this.collectionMenu(), {
      onDisappear: (): void => {
        if (this.contentMenuIdentity === collectionContentIdentity(item)) {
          this.contentMenuIdentity = '';
        }
      }
    })
    .accessibilityText('更多选项')
  }

  @Builder
  private collectionMenu() {
    Menu() {
      MenuItem({ content: '外观设置' })
        .id('collection_menu_appearance')
        .onClick((): void => this.openAppearanceSettings())
    }
  }

  /** 打开外观设置前先收起菜单：返回后旧菜单不应再次出现，新样式即时生效。 */
  private openAppearanceSettings(): void {
    this.contentMenuIdentity = '';
    this.navigate({ name: AppDestinationName.APPEARANCE_SETTINGS });
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (testId === 'collection_content_loading') {
        LoadingProgress()
          .id('collection_content_loading_progress')
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
      }
      Text(message)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        if (this.requiresLogin) {
          Button('去登录')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id('collection_content_status_login')
            .fontSize($r('app.float.body_font_size'))
            .onClick((): void => this.navigate({ name: AppDestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id(`${testId}_retry`)
            .fontSize($r('app.float.body_font_size'))
            .onClick(() => this.controller?.retry())
        }
      }
    }
    .id(testId)
    .padding({ top: floatingTitleBarOffset() })
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
    this.rebuildFlowLayout(false);
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

function collectionContentDestination(item: CollectionContentItem): AppDestination {
  if (item.kind === CollectionContentKind.ANSWER) {
    return { name: AppDestinationName.ANSWER, id: item.id };
  }
  if (item.kind === CollectionContentKind.ARTICLE) {
    return { name: AppDestinationName.ARTICLE, id: item.id };
  }
  if (item.kind === CollectionContentKind.QUESTION) {
    return { name: AppDestinationName.QUESTION, id: item.id };
  }
  return { name: AppDestinationName.PIN, id: item.id };
}
