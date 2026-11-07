import { CenteredOverlayDialog } from './CenteredOverlayDialog';
import { AppDestinationName } from 'core';
import { destinationScrollKey, destinationScrollRegistry } from './DestinationScrollRegistry';
import { READ_HISTORY_SCROLL_KEY, topLevelScrollRegistry } from './TopLevelScrollRegistry';
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
  onThemeColor,
  DEFAULT_THEME_COLOR,
  LoginSessionGateway,
  OnlineHistoryRepository,
  ReadHistoryGateway,
  SessionStatus
} from 'data';
import {
  floatingTitleBarOffset,
  FeedPullDownIndicatorHost,
  PULL_REFRESH_PULL_DOWN_RATIO,
  PULL_REFRESH_TRIGGER_OFFSET_VP,
  pullDownRefreshPlaceholder
} from './AppPageChrome';
import {
  ReadHistoryController,
  ReadHistoryItem,
  ReadHistoryOpenTarget,
  ReadHistoryPhase,
  ReadHistoryViewState
} from './ReadHistoryState';

/** 通栏 section（登录横幅/加载圈/到底提示）的段间距：维持本页面既有 10vp 口径。 */
const CHROME_SECTION_GAP_VP: number = 10;

export type OpenReadHistoryItem = (target: ReadHistoryOpenTarget) => void;

/** 在线历史记录页：对齐上游 OnlineHistoryScreen 的卡片信息流。 */
@Component
export struct ReadHistoryPage {
  topLevel: boolean = false;
  history: ReadHistoryGateway | undefined = undefined;
  onlineHistory: OnlineHistoryRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  onOpen: OpenReadHistoryItem = (_target: ReadHistoryOpenTarget): void => {};
  onGoLogin: () => void = (): void => {};
  onNavigateLocal: () => void = (): void => {};
  @State private viewState: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在加载历史记录',
    requiresLogin: false,
    loadingMore: false,
    canLoadMore: false
  };
  @State @Watch('syncRefreshIndicator') private refreshing: boolean = false;
  @State @Watch('clearDialogChanged') private confirmClear: boolean = false;
  // 标题栏溢出菜单在 stackBuilder 子树内，动作经 AppStorage tick 广播到本页（同 loginFeedReloadTick 模式）。
  // @StorageProp 键用字面量（装饰器要求编译期常量），值与 HistoryTitleActions.ets 导出常量一一对应。
  @StorageProp('readHistoryOpenLocalTick') @Watch('onOpenLocalTick') private openLocalTick: number = 0;
  @StorageProp('readHistoryClearTick') @Watch('onClearTick') private clearTick: number = 0;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('systemFontSizeScale') @Watch('onLayoutDriverChanged') private systemFontSizeScale: number = 1;
  @State @Watch('onLayoutDriverChanged') private pageWidthVp: number = 0;
  // 卡片外观与缩略图偏好与主页/收藏内容共用同一 AppStorage 键：设置变更即时生效，
  // 不重新拉取历史接口、不清空已有记录、不主动回顶。
  @StorageProp('feedCardStyle') @Watch('onAppearanceChanged') private feedCardStyle: string = 'divider';
  @StorageProp('showFeedThumbnail') @Watch('onAppearanceChanged') private showFeedThumbnail: boolean = true;
  private readonly flowSource: FlowListSource = new FlowListSource();
  private readonly flowScroller: Scroller = new Scroller();
  @State private flowSections: WaterFlowSections = new WaterFlowSections();
  private controller?: ReadHistoryController;
  private readonly anchorRestorer: FeedAnchorRestorer = new FeedAnchorRestorer();
  // 首个可见条目的 flow 索引（onScrollIndex 采集），供样式/图片开关重排后恢复阅读位置。
  private firstVisibleFlowIndex: number = 0;
  private lastEntries: FlowListItem[] = [];
  private lastColumns: number = 0;
  // 样式/图片开关只能经外观设置页触发，本页必然被覆盖在返回栈里：挂起锚点身份，
  // 回到页面（aboutToAppear）且布局稳定后再恢复，避免对隐藏窗口做无效滚动。
  private pendingAnchorIdentity: string = '';

  /** 宽屏多列规格：内容 1120vp 居中，历史卡按信息流断点分列（列数按 14vp 列间距求取）。 */
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

  /** 首个可见内容条目的身份：可见窗口起点落在通栏 chrome（横幅/加载圈）上时向后跳过。 */
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

  /** 瀑布流布局快照：历史卡进内容列 section，登录横幅/加载圈/到底提示通栏；同份快照供数据源与 sections 使用。 */
  private rebuildFlowLayout(preserveAnchor: boolean): void {
    const columns: number = this.wideSpec().columns;
    const columnsChanged: boolean = columns !== this.lastColumns;
    this.lastColumns = columns;
    // 变化前记录首个可见内容身份；重排后按身份映射回新索引，不用旧偏移直接恢复。
    const anchorIdentity: string = preserveAnchor && this.canPreserveAnchor()
      ? this.firstVisibleContentIdentity() : '';
    const entries: FlowListItem[] = [];
    if (this.viewState.requiresLogin) {
      entries.push(flowListChrome('read_history_login_banner', 'login'));
    }
    for (let index = 0; index < this.viewState.items.length; index += 1) {
      const item: ReadHistoryItem = this.viewState.items[index];
      entries.push(flowListCard(`read_history_${item.contentKey}`, index, item));
    }
    if (this.viewState.loadingMore) {
      entries.push(flowListChrome('read_history_loading_more', 'loading'));
    } else if (!this.viewState.canLoadMore) {
      entries.push(flowListChrome('read_history_end', 'end'));
    }
    this.lastEntries = entries;
    this.flowSections.splice(0, this.flowSections.length(),
      buildFlowListSections(entries, columns, this.contentGap(), CHROME_SECTION_GAP_VP));
    // applyLayout 增量通知：分页/样式切换不再整表重载，已有卡片保留。
    this.flowSource.applyLayout(entries);
    if (anchorIdentity.length > 0) {
      this.scheduleAnchorRestore(anchorIdentity, !columnsChanged);
    }
  }
  // 下拉刷新自定义加载圆圈（refreshingContent 需 ComponentContent，随页面销毁释放）
  private indicator?: FeedPullDownIndicatorHost = undefined;

  private clearDialog: CustomDialogController = new CustomDialogController({
    builder: CenteredOverlayDialog({ content: (): void => { this.clearConfirmation(); } }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: '#99000000',
    backgroundColor: $r('app.color.surface_background'),
    cancel: (): void => { this.confirmClear = false; }
  });

  private clearDialogChanged(): void {
    if (this.confirmClear) {
      this.clearDialog.open();
    } else {
      this.clearDialog.close();
    }
  }

  aboutToAppear(): void {
    // 返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载记录导致滚动位置丢失。
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
        message: '历史记录数据源未配置',
        requiresLogin: false,
        loadingMore: false,
        canLoadMore: false
      };
      return;
    }
    const session = this.session;
    const onlineEnabled = session !== undefined &&
      session.getState().status === SessionStatus.AUTHENTICATED;
    this.controller = new ReadHistoryController(history, this.onlineHistory, onlineEnabled,
      (state: ReadHistoryViewState): void => {
        this.viewState = state;
        // 对齐上游 FeedPullToRefresh：指示器 = 下拉触发 && 加载中，加载结束（无论成败）才停。
        // Refresh 必须用 $$ 双向绑定：手势触发的 refreshing=true 会回写到本状态，
        // 单向绑定时手势不回写、这里的赋值因值未变化而不生效，刷新圈会永远卡住。
        this.refreshing = state.busy && state.phase === ReadHistoryPhase.LOADING;
        this.rebuildFlowLayout(false);
      });
    this.indicator = new FeedPullDownIndicatorHost(this.getUIContext(), floatingTitleBarOffset());
    this.controller.activate();
  }

  aboutToDisappear(): void {
    if (this.topLevel) {
      topLevelScrollRegistry.unregister(READ_HISTORY_SCROLL_KEY, this.flowScroller);
    } else {
      destinationScrollRegistry.unregister(destinationScrollKey(AppDestinationName.READ_HISTORY), this.flowScroller);
    }
    this.anchorRestorer.cancel();
    this.controller?.deactivate();
    this.controller = undefined;
    this.indicator?.dispose();
    this.indicator = undefined;
    this.refreshing = false;
    this.confirmClear = false;
  }

  /** 圆圈只在间隙展开时绘制（ArkUI 收起头部后不裁剪自定义内容）。 */
  private syncRefreshIndicator(): void {
    this.indicator?.setRefreshing(this.refreshing);
  }

  private onOpenLocalTick(): void {
    if (this.openLocalTick > 0) {
      this.onNavigateLocal();
    }
  }

  private onClearTick(): void {
    if (this.clearTick > 0) {
      this.confirmClear = true;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.spacing_medium') }) {
        if (this.viewState.requiresLogin && this.viewState.items.length === 0) {
          Column() {
            this.loginBanner()
          }
          .width('100%')
          .padding({ top: floatingTitleBarOffset() })
        }
        if (this.viewState.phase === ReadHistoryPhase.LOADING && this.viewState.items.length === 0) {
          LoadingProgress()
            .id('read_history_loading')
            .width(40)
            .height(40)
            .color(this.resolvedThemeColor)
            .margin({ top: this.viewState.requiresLogin ? 0 : floatingTitleBarOffset() })
        } else if (this.viewState.items.length === 0) {
          Column({ space: $r('app.float.spacing_medium') }) {
            Text(this.viewState.message)
              .id('read_history_empty')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === ReadHistoryPhase.ERROR) {
              Button('重新加载')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id('read_history_retry')
                .enabled(!this.viewState.busy)
                .onClick((): void => {
                  void this.controller?.reload();
                })
            }
          }
          .justifyContent(FlexAlign.Center)
          .padding({ top: this.viewState.requiresLogin ? 0 : floatingTitleBarOffset() })
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
                  if (entry.label === 'login') {
                    this.loginBanner()
                  } else if (entry.label === 'loading') {
                    LoadingProgress()
                      .id('read_history_load_more')
                      .width(40)
                      .height(40)
                      .color(this.resolvedThemeColor)
                  } else if (entry.label === 'end') {
                    Text('已经到底啦')
                      .id('read_history_end')
                      .fontSize($r('app.float.secondary_font_size'))
                      .fontColor($r('app.color.secondary_text'))
                      .textAlign(TextAlign.Center)
                      .width('100%')
                      .padding({ top: 12, bottom: 12 })
                  } else {
                    this.historyCard(entry.payload as ReadHistoryItem)
                  }
                }
                .width('100%')
              }, (entry: FlowListItem): string => entry.key)
            }
            .id('read_history_list')
            .onAppear((): void => {
              if (this.topLevel) {
                topLevelScrollRegistry.register(READ_HISTORY_SCROLL_KEY, this.flowScroller);
              } else {
                destinationScrollRegistry.register(destinationScrollKey(AppDestinationName.READ_HISTORY),
                  this.flowScroller);
              }
            })
            .width('100%')
            .contentStartOffset(floatingTitleBarOffset())
            .scrollBar(BarState.Off)
            .cachedCount(Math.max(6, this.wideSpec().columns * 2))
            .edgeEffect(EdgeEffect.Spring)
            .onScrollIndex((start: number, _end: number): void => {
              this.firstVisibleFlowIndex = start;
            })
            .onReachEnd((): void => {
              void this.controller?.loadMore();
            })
          }
          .id('read_history_pull_refresh')
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
      // 视口延伸至顶栏后方，首屏让位由 WaterFlow 的 contentStartOffset 承担。
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
    .id('read_history_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 单条历史与主页信息流共用 FeedContentCard：排版/表面/页脚同源，信息顺序与主页一致
   * （标题→作者→摘要→页脚），原顶栏“类型 · 时间”元信息由适配器移入页脚。
   */
  @Builder
  private historyCard(item: ReadHistoryItem) {
    FeedContentCard({
      presentation: readHistoryCardPresentation(item),
      columns: this.wideSpec().columns,
      cardStyle: this.feedCardStyle,
      showThumbnail: this.showFeedThumbnail,
      cardTestId: `read_history_card_${item.contentKey}`,
      footerTestId: `read_history_footer_${item.contentKey}`,
      onOpen: (): void => this.onOpen({ kind: item.kind, id: item.id }),
      moreSlot: (): void => {
        this.historyMenuButton(item)
      }
    })
  }

  @Builder
  private historyMenuButton(item: ReadHistoryItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      feedCardMoreButtonContent()
    }
    .id(`read_history_item_menu_${item.contentKey}`)
    .width(32)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.viewState.busy)
    .bindMenu(this.itemMenu(item))
    .accessibilityText('该条历史记录操作')
  }

  private itemMenu(item: ReadHistoryItem): Array<MenuElement> {
    return [{
      value: '删除该条历史记录',
      action: (): void => {
        void this.controller?.deleteEntry(item.contentKey);
      }
    }];
  }

  @Builder
  private loginBanner() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text('登录后可同步查看知乎账号的浏览历史')
        .id('read_history_online_notice')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Button('去登录')
        .backgroundColor(this.resolvedThemeColor)
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .id('read_history_go_login')
        .fontSize($r('app.float.secondary_font_size'))
        .onClick((): void => this.onGoLogin())
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  /** 对齐上游清除确认对话框：一次清除当前账号在线 + 本地全部历史记录。 */
  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('确认清除历史记录')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('此操作会清除当前账号的在线和本地的全部历史记录。')
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
      Row({ space: $r('app.float.spacing_small') }) {
        Button('我再想想')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .id('read_history_clear_cancel')
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('read_history_clear_confirm')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => {
            this.confirmClear = false;
            void this.controller?.clearAll();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
  }
}
