import { onThemeColor, DEFAULT_THEME_COLOR, ReadHistoryGateway } from 'data';
import { AppDestinationName } from 'core';
import { destinationScrollKey, destinationScrollRegistry } from './DestinationScrollRegistry';
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
import { FeedContentCard, feedCardMoreButtonContent } from './components/FeedContentCard';
import { readHistoryCardPresentation } from './FeedCardPresentation';
import {
  floatingTitleBarOffset,
  FeedPullDownIndicatorHost,
  PULL_REFRESH_PULL_DOWN_RATIO,
  PULL_REFRESH_TRIGGER_OFFSET_VP,
  pullDownRefreshPlaceholder
} from './AppPageChrome';
import {
  LocalHistoryController,
  ReadHistoryItem,
  ReadHistoryOpenTarget,
  ReadHistoryPhase,
  ReadHistoryViewState
} from './ReadHistoryState';

/** 通栏 section（隐私说明）的段间距：维持本页面既有 10vp 口径。 */
const CHROME_SECTION_GAP_VP: number = 10;

/** 本地历史记录页：对齐上游 LegacyLocalHistoryScreen，一次性读取本机已读记录的卡片列表。 */
@Component
export struct LocalHistoryPage {
  history: ReadHistoryGateway | undefined = undefined;
  onOpen: (target: ReadHistoryOpenTarget) => void = (_target: ReadHistoryOpenTarget): void => {};
  @State private viewState: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在读取本地历史记录',
    requiresLogin: false,
    loadingMore: false,
    canLoadMore: false
  };
  @State @Watch('syncRefreshIndicator') private refreshing: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('systemFontSizeScale') @Watch('onLayoutDriverChanged') private systemFontSizeScale: number = 1;
  @State @Watch('onLayoutDriverChanged') private pageWidthVp: number = 0;
  // 卡片外观与缩略图偏好与主页/收藏内容共用同一 AppStorage 键：设置变更即时生效，
  // 不重新读取本地记录、不清空已有条目、不主动回顶。
  @StorageProp('feedCardStyle') @Watch('onAppearanceChanged') private feedCardStyle: string = 'divider';
  @StorageProp('showFeedThumbnail') @Watch('onAppearanceChanged') private showFeedThumbnail: boolean = true;
  private readonly flowSource: FlowListSource = new FlowListSource();
  private readonly flowScroller: Scroller = new Scroller();
  @State private flowSections: WaterFlowSections = new WaterFlowSections();
  private controller?: LocalHistoryController;
  private readonly anchorRestorer: FeedAnchorRestorer = new FeedAnchorRestorer();
  // 首个可见条目的 flow 索引（onScrollIndex 采集），供样式/图片开关重排后恢复阅读位置。
  private firstVisibleFlowIndex: number = 0;
  private lastEntries: FlowListItem[] = [];
  private lastColumns: number = 0;
  // 样式/图片开关只能经外观设置页触发，本页必然被覆盖在返回栈里：挂起锚点身份，
  // 回到页面（aboutToAppear）且布局稳定后再恢复，避免对隐藏窗口做无效滚动。
  private pendingAnchorIdentity: string = '';

  /** 宽屏多列规格：内容 1120vp 居中，本地历史卡按信息流断点分列（列数按 14vp 列间距求取）。 */
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

  /** 换列/换样式保位仅在静止的 READY 态、非刷新中、且已滚动离开顶部时启动，避免与手势竞争。 */
  private canPreserveAnchor(): boolean {
    return this.viewState.phase === ReadHistoryPhase.READY && !this.viewState.busy && !this.refreshing &&
      this.firstVisibleFlowIndex > 0 && this.viewState.items.length > 0;
  }

  /** 首个可见内容条目的身份：可见窗口起点落在通栏 chrome（隐私说明）上时向后跳过。 */
  private firstVisibleContentIdentity(): string {
    for (let index = this.firstVisibleFlowIndex; index < this.lastEntries.length; index += 1) {
      const entry: FlowListItem = this.lastEntries[index];
      if (entry.label === 'card') {
        return entry.key;
      }
    }
    return '';
  }

  private flowIndexOf(identity: string): number {
    for (let index = 0; index < this.lastEntries.length; index += 1) {
      if (this.lastEntries[index].key === identity) {
        return index;
      }
    }
    return -1;
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

  /** 瀑布流布局快照：本地历史卡进内容列 section，隐私说明通栏（无分页尾）。 */
  private rebuildFlowLayout(preserveAnchor: boolean): void {
    const columns: number = this.wideSpec().columns;
    const columnsChanged: boolean = columns !== this.lastColumns;
    this.lastColumns = columns;
    // 变化前记录首个可见内容身份；重排后按身份映射回新索引，不用旧偏移直接恢复。
    const anchorIdentity: string = preserveAnchor && this.canPreserveAnchor()
      ? this.firstVisibleContentIdentity() : '';
    const entries: FlowListItem[] = [flowListChrome('local_history_privacy', 'privacy')];
    for (let index = 0; index < this.viewState.items.length; index += 1) {
      const item: ReadHistoryItem = this.viewState.items[index];
      entries.push(flowListCard(`local_history_${item.contentKey}`, index, item));
    }
    this.lastEntries = entries;
    this.flowSections.splice(0, this.flowSections.length(),
      buildFlowListSections(entries, columns, this.contentGap(), CHROME_SECTION_GAP_VP));
    // applyLayout 增量通知：删除/重读不再整表重载，已有卡片保留。
    this.flowSource.applyLayout(entries);
    if (anchorIdentity.length > 0) {
      this.scheduleAnchorRestore(anchorIdentity, !columnsChanged);
    }
  }
  // 下拉刷新自定义加载圆圈（refreshingContent 需 ComponentContent，随页面销毁释放）
  private indicator?: FeedPullDownIndicatorHost = undefined;

  aboutToAppear(): void {
    if (this.controller !== undefined) {
      this.controller.activate();
      this.flushPendingAnchorRestore();
      return;
    }
    const history = this.history;
    if (history === undefined) {
      this.viewState = {
        phase: ReadHistoryPhase.ERROR,
        items: [],
        busy: false,
        message: '本地历史记录数据源未配置',
        requiresLogin: false,
        loadingMore: false,
        canLoadMore: false
      };
      return;
    }
    this.controller = new LocalHistoryController(history, (state: ReadHistoryViewState): void => {
      this.viewState = state;
      // 对齐上游 FeedPullToRefresh：指示器 = 下拉触发 && 加载中，加载结束（无论成败）才停。
      // Refresh 需 $$ 双向绑定让手势回写生效，否则刷新圈会永远卡住（见 ReadHistoryPage 注释）。
      this.refreshing = state.busy && state.phase === ReadHistoryPhase.LOADING;
      this.rebuildFlowLayout(false);
    });
    this.indicator = new FeedPullDownIndicatorHost(this.getUIContext(), floatingTitleBarOffset());
    this.controller.activate();
  }

  aboutToDisappear(): void {
    destinationScrollRegistry.unregister(destinationScrollKey(AppDestinationName.LOCAL_HISTORY), this.flowScroller);
    this.anchorRestorer.cancel();
    this.controller?.deactivate();
    this.controller = undefined;
    this.indicator?.dispose();
    this.indicator = undefined;
  }

  /** 圆圈只在间隙展开时绘制（ArkUI 收起头部后不裁剪自定义内容）。 */
  private syncRefreshIndicator(): void {
    this.indicator?.setRefreshing(this.refreshing);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.spacing_medium') }) {
        if (this.viewState.items.length === 0) {
          Column() {
            this.privacyNotice()
          }
          .width('100%')
          .padding({ top: floatingTitleBarOffset() })
        }
        if (this.viewState.phase === ReadHistoryPhase.LOADING && this.viewState.items.length === 0) {
          LoadingProgress()
            .id('local_history_loading')
            .width(40)
            .height(40)
            .color(this.resolvedThemeColor)
        } else if (this.viewState.items.length === 0) {
          Column({ space: $r('app.float.spacing_medium') }) {
            Text(this.viewState.message)
              .id('local_history_empty')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === ReadHistoryPhase.ERROR) {
              Button('重新读取')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id('local_history_retry')
                .enabled(!this.viewState.busy)
                .onClick((): void => {
                  void this.controller?.reload();
                })
            }
          }
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .width('100%')
        } else {
          Refresh({
            refreshing: $$this.refreshing,
            builder: pullDownRefreshPlaceholder,
            refreshingContent: this.indicator?.view()
          }) {
            WaterFlow({ scroller: this.flowScroller, sections: this.flowSections,
              layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW }) {
              LazyForEach(this.flowSource, (entry: FlowListItem) => {
                FlowItem() {
                  if (entry.label === 'privacy') {
                    this.privacyNotice()
                  } else {
                    this.localHistoryCard(entry.payload as ReadHistoryItem)
                  }
                }
                .width('100%')
              }, (entry: FlowListItem): string => entry.key)
            }
            .id('local_history_list')
            .onAppear((): void => {
              destinationScrollRegistry.register(destinationScrollKey(AppDestinationName.LOCAL_HISTORY),
                this.flowScroller);
            })
            .width('100%')
            .contentStartOffset(floatingTitleBarOffset())
            .scrollBar(BarState.Off)
            .cachedCount(Math.max(6, this.wideSpec().columns * 2))
            .edgeEffect(EdgeEffect.Spring)
            .onScrollIndex((start: number, _end: number): void => {
              this.firstVisibleFlowIndex = start;
            })
          }
          .id('local_history_pull_refresh')
          .width('100%')
          .layoutWeight(1)
          .refreshOffset(PULL_REFRESH_TRIGGER_OFFSET_VP)
          .pullDownRatio(PULL_REFRESH_PULL_DOWN_RATIO)
          .onRefreshing((): void => {
            void this.controller?.reload();
          })
          .onStateChange((status: RefreshStatus): void => this.indicator?.onStateChange(status))
        }
      }
      .width('100%')
      .height('100%')
      // 隐私说明与卡片一起进入材质采样区；空态单独避让悬浮顶栏。
      .padding({ left: this.wideSpec().paddingVp, right: this.wideSpec().paddingVp,
        bottom: $r('app.float.page_padding') })
      .backgroundColor($r('app.color.page_background'))
      .onAreaChange((_oldArea: Area, area: Area): void => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.pageWidthVp) > 0.5) {
          this.pageWidthVp = width;
        }
      })
    }
    .id('local_history_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private privacyNotice() {
    Text('只保存在本机；不保存正文、Cookie、搜索词或账号信息。')
      .id('read_history_privacy')
      .fontSize($r('app.float.caption_font_size'))
      .fontColor($r('app.color.secondary_text'))
      .width('100%')
  }

  /**
   * 单条本地历史与主页信息流共用 FeedContentCard：排版/表面/页脚同源，
   * 原顶栏“类型 · 时间”元信息由适配器移入页脚；本地记录无作者/摘要，按缺失降级。
   */
  @Builder
  private localHistoryCard(item: ReadHistoryItem) {
    FeedContentCard({
      presentation: readHistoryCardPresentation(item),
      columns: this.wideSpec().columns,
      cardStyle: this.feedCardStyle,
      showThumbnail: this.showFeedThumbnail,
      cardTestId: `local_history_card_${item.contentKey}`,
      footerTestId: `local_history_footer_${item.contentKey}`,
      onOpen: (): void => this.onOpen({ kind: item.kind, id: item.id }),
      moreSlot: (): void => {
        this.localMenuButton(item)
      }
    })
  }

  @Builder
  private localMenuButton(item: ReadHistoryItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      feedCardMoreButtonContent()
    }
    .id(`local_history_item_menu_${item.contentKey}`)
    .width(32)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.viewState.busy)
    .bindMenu(this.itemMenu(item))
    .accessibilityText('该条本地记录操作')
  }

  private itemMenu(item: ReadHistoryItem): Array<MenuElement> {
    return [{
      value: '删除该条本地记录',
      action: (): void => {
        void this.controller?.delete(item.contentKey);
      }
    }];
  }
}
