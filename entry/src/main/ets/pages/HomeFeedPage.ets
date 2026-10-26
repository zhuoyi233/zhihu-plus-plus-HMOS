import {
  buildFeedFlowLayout,
  feedAnchorFlowIndex,
  FeedColumnSpec,
  feedMinCardWidthVp,
  FeedFlowEntry,
  FeedFlowLayout,
  feedFlowItemIndex,
  feedSectionSignature,
  FEED_ESTIMATED_CARD_HEIGHT_VP,
  homeFeedInitialItemTarget,
  resolveFeedColumnSpec
} from './FeedWaterfallLayout';
import { FeedAnchorRestorer } from './FeedColumnAnchorRestore';
import { feedRenderChrome, FeedFlowDataSource, FeedRenderItem, FeedRenderKind, feedRenderContent } from './FeedFlowDataSource';
import { AppDestination, AppDestinationName, isSafeDecimalContentId } from 'core';
import {
  onThemeColor,
  ContentRepository,
  QuestionTopicSummary,
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  DEFAULT_THEME_COLOR,
  DefaultFeedRepository,
  feedItemIdentity,
  FeedItem,
  FeedRepository,
  FeedTargetKind,
  FeedColumnMode,
  isUpdateAnnouncementVisible,
  OpenedContentStore,
  LastReadTouchEntry,
  LastReadTouchRepository
} from 'data';
import {
  BlockingActionContext,
  BlockingActionController,
  BlockingActionPhase,
  BlockingActionViewState,
  BlockingUserCandidate
} from './BlockingActionState';
import {
  AppPageStatusKind,
  AppPageStatusPanel,
  FeedLoadMoreIndicator,
  FeedPullDownIndicatorHost,
  floatingTitleBarOffset,
  PULL_REFRESH_PULL_DOWN_RATIO,
  PULL_REFRESH_TRIGGER_OFFSET_VP,
  pullDownRefreshPlaceholder
} from './AppPageChrome';
import { HomeFeedController, HomeFeedPhase, HomeFeedViewState } from './HomeFeedState';
import { HomeFeedMenuAction, HomeFeedMenuItem, homeFeedMenuItems, resolveHomeFeedBlockUser, resolveHomeFeedTopics } from './HomeFeedMenuState';
import { HOME_FEED_SCROLL_KEY, topLevelScrollRegistry } from './TopLevelScrollRegistry';
import { DraggableRefreshButton } from './components/DraggableRefreshButton';

/** 下拉头回弹/收起后的静默窗口（ms）：期间再往下滑不触发刷新。 */
const REFRESH_SETTLE_QUIET_MS: number = 500;

@Component
export struct HomeFeedPage {
  repository: FeedRepository | undefined = new DefaultFeedRepository();
  contentRepositoryFactory: () => ContentRepository | undefined = () => undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  /** 上次阅读上报仓库（对齐上游 lastread/touch；未配置或游客态时不上报）。 */
  lastReadTouch: LastReadTouchRepository | undefined = undefined;
  @Prop @Watch('reloadAfterAuthentication') reloadToken: number = 0;
  // 登录成功重载信号：reloadToken 走 Builder 参数、@Provide/@Consume 在 HdsTabs 的
  // TabContent 构建树下均实测不可靠，AppStorage 广播是可靠通道（同 bottomRectHeight）
  @StorageProp('loginFeedReloadTick') @Watch('onLoginFeedReloadTick') loginFeedReloadTick: number = 0;
  // 双击底栏“首页”页签刷新：复用下拉刷新链路
  @StorageProp('tabRefreshTick') @Watch('onTabRefreshRequested') tabRefreshTick: number = 0;
  @StorageProp('contentFilterSettingsTick') @Watch('onContentFilterSettingsChanged')
  private contentFilterSettingsTick: number = 0;
  @StorageProp('tabRefreshTabIndex') tabRefreshTabIndex: number = -1;
  @StorageProp('tabScrollTopTick') @Watch('onTabScrollTopRequested') private tabScrollTopTick: number = 0;
  @StorageProp('tabScrollTopTabIndex') private tabScrollTopTabIndex: number = -1;
  @StorageProp('showFeedThumbnail') private showFeedThumbnail: boolean = true;
  @StorageProp('showRefreshFab') private showRefreshFab: boolean = true;
  @StorageProp('feedCardStyle') @Watch('rebuildFlowLayout') private feedCardStyle: string = 'divider';
  @StorageProp('fabOpacity') private fabOpacity: number = 100;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  // 首页更新卡片（对齐上游 HomeScreen 顶部 AnnouncementCard）：AppShell 启动检查到新版本后经
  // AppStorage 广播（HdsTabs 树下跨页面信号唯一可靠通道）。“以后”仅本次会话内忽略，对齐上游。
  @StorageProp('homeUpdateAnnouncementVersion') @Watch('rebuildFlowLayout') private pendingUpdateVersion: string = '';
  @State @Watch('rebuildFlowLayout') private dismissedUpdateVersion: string = '';
  // 下拉刷新自定义加载圆圈（refreshingContent 需 ComponentContent，随页面销毁释放）
  private indicator?: FeedPullDownIndicatorHost = undefined;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  @State private phase: HomeFeedPhase = HomeFeedPhase.IDLE;
  @State @Watch('rebuildFlowLayout') private items: Array<FeedItem> = [];
  @State private refreshing: boolean = false;
  @State @Watch('rebuildFlowLayout') private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State @Watch('rebuildFlowLayout') private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  @State private resolvingMenuAuthor: boolean = false;
  @State private feedMenuVisible: boolean = false;
  @State private feedMenuIdentity: string = '';
  @State private feedMenuTopics: Array<QuestionTopicSummary> = [];
  @State private feedMenuTopicsLoading: boolean = false;
  @State private feedMenuTopicsFailed: boolean = false;
  private topicRepository?: ContentRepository = undefined;
  private topicRequestId: number = 0;
  private readonly menuTopicsCache: Map<string, Array<QuestionTopicSummary>> = new Map();
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  private controller: HomeFeedController | undefined = undefined;
  private blockingAction?: BlockingActionController;
  private menuRepository?: ContentRepository = undefined;
  private menuRequestId: number = 0;
  private openRequestId: number = 0;
  private openRepository: ContentRepository | undefined = undefined;
  /** 本会话已批量上报过曝光（touch）的条目，对齐上游 reportedTouchedItems 去重。 */
  private readonly reportedTouchIdentities: Set<string> = new Set<string>();
  private readonly listScroller: Scroller = new Scroller();
  @State @Watch('rebuildFlowLayout') private feedWidthVp: number = 0;
  // 状态栏高度（vp）晚于首帧到达时重算首屏让位（让位 = 状态栏 + 顶栏 56vp）
  @StorageProp('statusBarHeightVp') @Watch('rebuildFlowLayout') private statusBarHeightVp: number = 0;
  // 系统字号缩放：放大时提高最小卡宽，必要时自动减少列数
  @StorageProp('systemFontSizeScale') @Watch('rebuildFlowLayout') private systemFontSizeScale: number = 1;
  // 信息流列数偏好：auto 随断点，手动档位作为期望值仍受宽度保护（AppShell 冷启动广播，经
  // AppStorage + @StorageProp + @Watch 接收，不用 HdsTabs 树下不可靠的 Provide/Consume）
  @StorageProp('feedColumnMode') @Watch('rebuildFlowLayout') private feedColumnMode: string = FeedColumnMode.AUTO;
  // 最终列数与卡宽保存在页面本地（不用全局单值，避免离屏缓存页互相覆盖），经组件参数/状态传给卡片
  @State private feedColumns: number = 1;
  private feedCardWidthVp: number = 0;
  private feedHeightVp: number = 0;
  @State private flowSections: WaterFlowSections = new WaterFlowSections();
  @State private flowLayout: FeedFlowLayout = buildFeedFlowLayout([], [], 1, 1, false, 0);
  // LazyForEach 数据源：通栏项、内容与加载尾统一协调，通知与 sections 同源
  private readonly flowDataSource: FeedFlowDataSource = new FeedFlowDataSource();
  private lastSectionSignature: string = '';
  private readonly anchorRestorer: FeedAnchorRestorer = new FeedAnchorRestorer();
  // 不足一屏补屏的限次计数：内容有增长才重置，防止过滤稀少或重复游标时循环请求
  private fillAttempts: number = 0;
  private fillAttemptSize: number = 0;
  private firstVisibleIndex: number = 0;
  /** 本次手势按下时列表是否已在顶部：只有顶部起手才算有意下拉刷新。 */
  private pullGestureFromTop: boolean = true;
  /** 下拉头最近一次回弹/收起的时刻：此后的短静默期内不响应下拉刷新。 */
  private lastRefreshSettleTime: number = 0;

  aboutToAppear(): void {
    // 登记给根 HdsNavigation 做 bindToScrollable：驱动标题栏滚动模糊。
    topLevelScrollRegistry.register(HOME_FEED_SCROLL_KEY, this.listScroller);
    // 覆盖式顶栏：Refresh 头部从页面顶端展开，把刷新圆圈绘制偏移到悬浮标题栏下沿
    this.indicator = new FeedPullDownIndicatorHost(this.getUIContext(), floatingTitleBarOffset());
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
    this.updateInitialItemTarget();
    this.controller.activate();
    this.controller.loadInitial();
    this.createBlockingAction();
  }

  aboutToDisappear(): void {
    this.openRequestId += 1;
    this.openRepository?.cancel();
    this.openRepository = undefined;
    this.indicator?.dispose();
    this.indicator = undefined;
    this.controller?.deactivate();
    this.anchorRestorer.cancel();
    this.closeFeedMenu();
    this.menuRequestId += 1;
    this.menuRepository?.cancel();
    this.menuRepository = undefined;
    this.resolvingMenuAuthor = false;
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

  private onLoginFeedReloadTick(): void {
    this.controller?.refresh();
  }

  private onContentFilterSettingsChanged(): void {
    this.controller?.refresh();
  }

  private onTabRefreshRequested(): void {
    if (this.tabRefreshTabIndex === 0) {
      this.controller?.refresh();
    }
  }

  private onTabScrollTopRequested(): void {
    if (this.tabScrollTopTabIndex !== 0) {
      return;
    }
    // 单击只回到顶部，不再在顶部时刷新：刷新改为连续点击两次页签触发（双击路径）。
    // 必须滚到内容起点（offset 0）而不是 scrollToIndex(0)：首个瀑布流分组带标题栏让位边距，
    // 按下标对齐会把首行卡片顶到屏幕最上沿、盖住标题栏与下拉刷新圆圈。
    this.firstVisibleIndex = 0;
    this.listScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: true });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.spacing_medium') }) {
        if (this.phase === HomeFeedPhase.INITIAL_LOADING || this.phase === HomeFeedPhase.IDLE) {
          this.centeredStatus('正在加载首页…', false, 'home_initial_loading');
        } else if (this.phase === HomeFeedPhase.ERROR) {
          this.centeredStatus(this.errorMessage, true, 'home_error');
        } else if (this.phase === HomeFeedPhase.EMPTY) {
          this.centeredStatus('暂时没有可显示的内容', true, 'home_empty');
        } else {
          Refresh({
            refreshing: this.refreshing,
            builder: pullDownRefreshPlaceholder,
            refreshingContent: this.indicator?.view()
          }) {
            WaterFlow({ scroller: this.listScroller, sections: this.flowSections,
              layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW }) {
              // 通栏项（错误横幅/更新公告/加载尾）与内容统一进数据源，经同一份布局快照协调数量
              LazyForEach(this.flowDataSource, (renderItem: FeedRenderItem) => {
                FlowItem() {
                  this.flowRenderItem(renderItem)
                }
                .width('100%')
              }, (renderItem: FeedRenderItem): string => renderItem.key)
            }
            .cachedCount(Math.max(5, this.feedColumns * 2))
            .onScrollIndex((start: number, end: number): void => {
              const lastItem: number = feedFlowItemIndex(this.flowLayout, end);
              this.controller?.markVisibleThrough(lastItem);
              // 多列首屏可能容纳整页数据，按列数保留两行余量提前请求下一页，避免只能等待触底事件。
              if (lastItem >= this.items.length - this.prefetchMargin() && this.items.length > 0 &&
                this.canLoadMore) {
                this.controller?.loadMore();
              }
              this.firstVisibleIndex = start;
            })
            .id('home_feed_list')
            .width('100%')
            .onDidScroll((offset: number): void => {
              if (offset !== 0) {
                AppStorage.setOrCreate('bottomBarHiddenByScroll', offset > 0);
              }
            })
            // 记录手势起手时是否在顶部：从列表中间回滑到顶部后继续下拉的过冲
            // 也会被 Refresh 判成下拉刷新，需要据此区分。
            .onTouch((event: TouchEvent): void => {
              if (event.type === TouchType.Down) {
                this.pullGestureFromTop = this.listScroller.currentOffset().yOffset <= 1;
              }
            })
            .scrollBar(BarState.Off)
            .height('100%')
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => this.controller?.loadMore())
            // 容器挂到组件后再登记一次：aboutToAppear 时 Scroller 还没挂上组件，
            // 根标题栏绑定它拿不到偏移，必须等挂载后才能建立订阅。
            .onAppear((): void => {
              topLevelScrollRegistry.register(HOME_FEED_SCROLL_KEY, this.listScroller);
            })
          }
          .id('home_pull_refresh')
          .width('100%')
          .layoutWeight(1)
          // 官方属性（offset/friction 已于 API 11 废弃）：把刷新阈值抬到明显高于普通回弹，
          // 普通下拉只回弹、不刷新；需要下拉约半屏高才触发。
          .refreshOffset(PULL_REFRESH_TRIGGER_OFFSET_VP)
          .pullDownRatio(PULL_REFRESH_PULL_DOWN_RATIO)
          .onRefreshing(() => {
            // 程序化刷新（双击页签/登录重载）把 refreshing 置 true 时也会回调本事件：
            // 此时控制器已在刷新，再调 refresh() 会排队一次重复请求（表现为刷新两轮）。
            if (this.refreshing) {
              return;
            }
            // 回弹/下拉头收起后的短时间内不响应下拉：拉到顶回弹时再往下滑不应触发刷新。
            if (Date.now() - this.lastRefreshSettleTime <= REFRESH_SETTLE_QUIET_MS) {
              this.suppressPullRefresh();
              return;
            }
            // 非顶部起手（回滑到顶后继续下拉的过冲）同样不刷新。
            if (!this.pullGestureFromTop) {
              this.suppressPullRefresh();
              return;
            }
            this.controller?.refresh();
          })
          .onStateChange((status: RefreshStatus): void => {
            this.indicator?.onStateChange(status);
            // 下拉头回到 Inactive、或一次刷新收尾（Done）都算“回弹/收起”，记录时刻用于静默。
            if (status === RefreshStatus.Inactive || status === RefreshStatus.Done) {
              this.lastRefreshSettleTime = Date.now();
            }
          })
        }

        if (this.blockingMessage.length > 0) {
          Text(this.blockingMessage)
            .id('home_blocking_status')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      // 覆盖式顶栏：容器不设 top padding，滚动视口一直延伸到屏幕顶，卡片滚起来后
      // 穿过玻璃标题栏形成沉浸光感；首屏起始位置由首个瀑布流分组的上边距让位。
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        bottom: $r('app.float.page_padding')
      })
      .onAreaChange((_oldValue: Area, area: Area): void => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.feedWidthVp) > 0.5) {
          this.feedWidthVp = width;
        }
        this.feedHeightVp = Number(area.height);
        this.updateInitialItemTarget();
        // 视口变化后补判内容是否不足一屏（单列切多列、宽窗首屏等）
        this.maybeFillViewport();
      })

      if (this.showRefreshFab && this.phase === HomeFeedPhase.READY) {
        DraggableRefreshButton({
          elementId: 'home_refresh_fab',
          accessibilityLabel: '刷新首页',
          fabOpacity: this.fabOpacity,
          loading: this.refreshing,
          onRefresh: (): void => {
            void this.controller?.refresh();
          }
        })
      }
    }
    .id('home_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private flowRenderItem(renderItem: FeedRenderItem) {
    if (renderItem.kind === FeedRenderKind.TOP_SPACER) {
      // 用真实条目让位，系统点状态栏回顶时也能保留悬浮标题栏空间。
      Row()
        .width('100%')
        .height(floatingTitleBarOffset())
    } else if (renderItem.kind === FeedRenderKind.ERROR_BANNER) {
      this.recoverableErrorBanner()
    } else if (renderItem.kind === FeedRenderKind.UPDATE_ANNOUNCEMENT) {
      this.updateAnnouncementCard()
    } else if (renderItem.kind === FeedRenderKind.LOADING_FOOTER) {
      // 尾部留白避让悬浮底栏，加载动画保持完整可见。
      FeedLoadMoreIndicator({ elementId: 'home_load_more' })
    } else {
      this.feedCard(renderItem.payload as FeedItem)
    }
  }

  @Builder
  private recoverableErrorBanner() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(this.errorMessage)
        .id('home_recoverable_error_text')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Button('重试')
        .backgroundColor(this.resolvedThemeColor)
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .id('home_recoverable_error_retry')
        .onClick(() => this.controller?.retry())
    }
    .width('100%')
    .padding($r('app.float.spacing_small'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private updateAnnouncementCard() {
    // 对齐上游 AnnouncementCard colorsImportant：主色底、圆形图标位、右侧“以后/查看更新”操作区。
    Column({ space: $r('app.float.spacing_small') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(16)
            .fontColor([Color.White])
        }
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor('#33FFFFFF')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        Text(`发现新版本：${this.pendingUpdateVersion}`)
          .id('home_update_card_title')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
        .width('100%')
        .alignItems(VerticalAlign.Center)

      Row({ space: $r('app.float.spacing_small') }) {
        Button('以后', { type: ButtonType.ROUNDED_RECTANGLE, stateEffect: true })
          .id('home_update_card_dismiss')
          .fontSize($r('app.float.body_font_size'))
          .fontColor(Color.White)
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
          .onClick((): void => {
            this.dismissedUpdateVersion = this.pendingUpdateVersion;
          })
        Button('查看更新', { type: ButtonType.ROUNDED_RECTANGLE, stateEffect: true })
          .id('home_update_card_whats_new')
          .fontSize($r('app.float.body_font_size'))
          .fontColor(this.resolvedThemeColor)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .onClick((): void => {
            // 应用内查看待更新版本的说明与下载入口（非跳浏览器）。
            this.navigate({ name: AppDestinationName.WHATS_NEW, version: this.pendingUpdateVersion });
          })
      }
        .width('100%')
        .justifyContent(FlexAlign.End)
    }
      .width('100%')
      .padding($r('app.float.card_padding'))
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor(this.resolvedThemeColor)
      .accessibilityText('发现新版本，可查看更新或稍后忽略')
  }

  @Builder
  private centeredStatus(message: string, retry: boolean, testId: string) {
    // 登录动作必须走面板内置按钮（面板 layoutWeight(1) 居中）：作为 Column 兄弟节点会被
    // 挤到底部，与悬浮 HdsTabs 底栏重叠导致点不到
    AppPageStatusPanel({
      kind: retry ? AppPageStatusKind.ERROR : AppPageStatusKind.LOADING,
      message: message,
      testId: testId,
      actionLabel: retry ? (this.requiresLogin ? '去登录' : '重新加载') : '',
      actionId: this.requiresLogin ? 'home_error_login' : `${testId}_retry`,
      onAction: (): void => {
        if (this.requiresLogin) {
          this.navigate({ name: AppDestinationName.LOGIN });
          return;
        }
        this.controller?.retry();
      }
    });
  }

  @Builder
  private feedCard(item: FeedItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.spacing_xsmall') }) {
        if ((item.target.qualityFilterReason ?? '').length > 0) {
          // 对齐上游 FeedDisplayItem（isFiltered）：标题显示“已屏蔽”，原因放摘要位置，
          // 标题/摘要/作者/来源与图片均不展示，页脚与菜单行保留。
          Text('已屏蔽')
            .id(`home_quality_blocked_${item.target.kind}_${item.target.id}`)
            .fontSize($r('app.float.heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
          Text(item.target.qualityFilterReason ?? '')
            .id(`home_quality_rule_${item.target.kind}_${item.target.id}`)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        } else {
          this.feedCardContent(item)
        }
        // 对齐上游 FeedCardContent：页脚（details）行与右下角“更多”菜单同排。
        Row({ space: $r('app.float.spacing_small') }) {
          Text(homeFeedDetailsLabel(item))
            .id(`home_feed_footer_${item.target.kind}_${item.target.id}`)
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          this.feedCardMenuButton(item)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`home_feed_card_${item.target.kind}_${item.target.id}`)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius(this.usesCardSurface() ? $r('app.float.card_radius') : 0)
    .backgroundColor(this.usesCardSurface() ? $r('app.color.surface_background') : Color.Transparent)
    // border 的 radius 优先级高于 borderRadius 属性（未指定时按 0 处理），
    // 卡片模式必须把圆角同步写进 border，否则背景圆角被重置成直角。
    .border({
      width: { bottom: !this.usesCardSurface() ? 1 : 0 },
      color: $r('app.color.divider_color'),
      radius: this.usesCardSurface() ? $r('app.float.card_radius') : 0
    })
    .accessibilityText((item.target.qualityFilterReason ?? '').length > 0
      ? `已屏蔽：${item.target.qualityFilterReason}`
      : `打开${feedKindLabel(item.target.kind)}：${item.target.title}`)
    .onClick((): void => { void this.openFeedItem(item); })
  }

  @Builder
  private feedCardMenuButton(item: FeedItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(18)
        .fontColor([$r('app.color.secondary_text')])
    }
    .id(`home_feed_block_${item.target.kind}_${item.target.id}`)
    .width(32)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.blockingBusy && !this.resolvingMenuAuthor)
    .onClick((): void => this.openFeedMenu(item))
    .bindMenu(this.feedMenuVisible && this.feedMenuIdentity === feedItemIdentity(item), this.feedMenu(item), {
      onDisappear: (): void => {
        if (this.feedMenuIdentity === feedItemIdentity(item)) {
          this.closeFeedMenu();
        }
      }
    })
    .accessibilityText('更多选项')
  }

  @Builder
  private feedCardContent(item: FeedItem) {
    // 对齐上游 FeedCard 标准排版：标题 → 头像与昵称 → 摘要（3 行截断）→ 缩略图 → 页脚。
    Text(item.target.title)
      .fontSize($r('app.float.heading_font_size'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.primary_text'))
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')

    if (item.target.author !== undefined) {
      Row({ space: $r('app.float.spacing_xsmall') }) {
        if ((item.target.author.avatarUrl ?? '').length > 0) {
          Image(item.target.author.avatarUrl)
            .width(20)
            .height(20)
            .borderRadius(10)
            .alt('用户头像')
        }
        Text(item.target.author.name)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(VerticalAlign.Center)
    }

    Row({ space: $r('app.float.spacing_small') }) {
      Column({ space: $r('app.float.spacing_xsmall') }) {
        if (item.target.excerpt.trim().length > 0) {
          Text(item.target.excerpt)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            // 多列卡宽收窄，摘要由三行收至两行；单列保持现有行为
            .maxLines(this.feedColumns > 1 ? 2 : 3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if ((item.recommendationReason?.trim() ?? '').length > 0 ||
          (item.target.mobileFooterText === undefined && (item.actionText?.trim() ?? '').length > 0)) {
          Text(homeFeedActionLabel(item))
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(2)

      if (this.showFeedThumbnail && (item.target.thumbnailUrl ?? '').length > 0) {
        Image(item.target.thumbnailUrl)
          .width(60)
          .height(60)
          .borderRadius($r('app.float.spacing_small'))
          .objectFit(ImageFit.Cover)
          .alt('内容缩略图')
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private async openFeedItem(item: FeedItem): Promise<void> {
    const requestId = ++this.openRequestId;
    this.openRepository?.cancel();
    this.openRepository = undefined;
    try {
      // 点击时读取广播值，设置变更后已挂载的首页卡片也立即遵循最新模式。
      const mode = AppStorage.get<string>('answerReadingMode') ?? 'single';
      const destination = await resolveHomeFeedDestination(item, mode, async (answerId: string): Promise<string> => {
        const repository = this.contentRepositoryFactory();
        if (repository === undefined) {
          throw new Error('Answer repository unavailable');
        }
        this.openRepository = repository;
        const answer = await repository.getAnswer(answerId);
        return answer.questionId;
      });
      if (requestId !== this.openRequestId) {
        return;
      }
      void this.openedContentStore?.upsert({
        contentKey: `${item.target.kind}:${item.target.id}`,
        openedAt: Date.now(),
        contentType: item.target.kind,
        title: item.target.title
      }).catch((_error: Error): void => {});
      this.reportLastReadTouch(item, 'read');
      this.navigate(destination);
    } catch (_error) {
      if (requestId === this.openRequestId) {
        this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开回答，请稍后重试' });
      }
    } finally {
      if (requestId === this.openRequestId) {
        this.openRepository = undefined;
      }
    }
  }

  /** 对齐上游 lastread/touch：点击上报 read、feed 曝光批量上报 touch，游客态由仓库静默跳过。 */
  private reportLastReadTouch(item: FeedItem, action: string): void {
    const entry = lastReadTouchEntryOf(item, action);
    const repository = this.lastReadTouch;
    if (entry === undefined || repository === undefined) {
      return;
    }
    repository.report([entry]).catch((_error: Error): void => {});
  }

  private reportLastReadTouches(items: Array<FeedItem>): void {
    const repository = this.lastReadTouch;
    if (repository === undefined) {
      return;
    }
    const entries: Array<LastReadTouchEntry> = [];
    items.forEach((item: FeedItem): void => {
      const identity = feedItemIdentity(item);
      if (this.reportedTouchIdentities.has(identity)) {
        return;
      }
      const entry = lastReadTouchEntryOf(item, 'touch');
      if (entry !== undefined) {
        entries.push(entry);
        this.reportedTouchIdentities.add(identity);
      }
    });
    if (entries.length === 0) {
      return;
    }
    repository.report(entries).catch((_error: Error): void => {
      entries.forEach((entry: LastReadTouchEntry): void => {
        this.reportedTouchIdentities.delete(`${entry.kind}:${entry.id}`);
      });
    });
  }

  @Builder
  private feedMenu(item: FeedItem) {
    Menu() {
      ForEach(homeFeedMenuItems(item, this.feedMenuTopics), (entry: HomeFeedMenuItem) => {
        if (entry.action === HomeFeedMenuAction.APPEARANCE && this.feedMenuTopicsLoading) {
          MenuItem({ content: '正在加载话题…' }).enabled(false)
        }
        if (entry.action === HomeFeedMenuAction.APPEARANCE && this.feedMenuTopicsFailed) {
          MenuItem({ content: '话题暂时无法加载' }).enabled(false)
        }
        MenuItem({ content: entry.label })
          .id('home_menu_' + entry.action + (entry.topic?.id ?? ''))
          .onClick((): void => {
            this.feedMenuVisible = false;
            this.handleFeedMenu(item, entry);
          })
      }, (entry: HomeFeedMenuItem): string => entry.action + (entry.topic?.id ?? ''))
    }
  }

  private openFeedMenu(item: FeedItem): void {
    this.closeFeedMenu();
    const identity = feedItemIdentity(item);
    this.feedMenuIdentity = identity;
    const cached = this.menuTopicsCache.get(identity);
    this.feedMenuTopics = cached ?? item.target.topics ?? [];
    this.feedMenuTopicsFailed = false;
    this.feedMenuTopicsLoading = cached === undefined && this.feedMenuTopics.length === 0 &&
      item.target.kind !== FeedTargetKind.VIDEO;
    this.feedMenuVisible = true;
    if (this.feedMenuTopicsLoading) {
      void this.loadFeedMenuTopics(item, this.topicRequestId);
    }
  }

  private closeFeedMenu(): void {
    this.feedMenuVisible = false;
    this.topicRequestId += 1;
    this.topicRepository?.cancel();
    this.topicRepository = undefined;
    this.feedMenuTopicsLoading = false;
  }

  private async loadFeedMenuTopics(item: FeedItem, requestId: number): Promise<void> {
    try {
      this.topicRepository = this.contentRepositoryFactory();
      if (this.topicRepository === undefined) {
        throw new Error('Content repository unavailable');
      }
      const topics = await resolveHomeFeedTopics(item, this.topicRepository);
      if (requestId !== this.topicRequestId) {
        return;
      }
      this.feedMenuTopics = topics;
      // 本次菜单查询获得的真实元数据也供当前卡片的话题过滤与后续菜单复用。
      item.target.topics = topics;
      topics.forEach((topic: QuestionTopicSummary): void => {
        if (!item.target.topicIds.includes(topic.id)) {
          item.target.topicIds.push(topic.id);
        }
      });
      if (this.menuTopicsCache.size >= 100) {
        this.menuTopicsCache.clear();
      }
      this.menuTopicsCache.set(feedItemIdentity(item), topics);
    } catch (_error) {
      if (requestId === this.topicRequestId) {
        this.feedMenuTopicsFailed = true;
      }
    } finally {
      if (requestId === this.topicRequestId) {
        this.feedMenuTopicsLoading = false;
        this.topicRepository = undefined;
      }
    }
  }

  private handleFeedMenu(item: FeedItem, entry: HomeFeedMenuItem): void {
    if (entry.action === HomeFeedMenuAction.APPEARANCE) {
      this.navigate({ name: AppDestinationName.APPEARANCE_SETTINGS });
    } else if (entry.action === HomeFeedMenuAction.QUALITY_FILTER) {
      this.navigate({ name: AppDestinationName.RECOMMENDATION_FILTER_SETTINGS });
    } else if (entry.action === HomeFeedMenuAction.BLOCK_TOPIC && entry.topic !== undefined) {
      const action = this.blockingAction;
      if (action !== undefined) {
        void action.blockTopic(entry.topic.id, entry.topic.name, this.blockContext(item)).then((): void => {
          if (action.snapshot().phase === BlockingActionPhase.SUCCESS) {
            this.controller?.removeItem(feedItemIdentity(item));
            void this.controller?.refresh();
          }
        });
      }
    } else if (entry.action === HomeFeedMenuAction.BLOCK_USER ||
      entry.action === HomeFeedMenuAction.BLOCK_QUESTION_AUTHOR) {
      void this.requestUserBlock(item, entry.action === HomeFeedMenuAction.BLOCK_QUESTION_AUTHOR);
    }
  }

  private async requestUserBlock(item: FeedItem, questionAuthor: boolean): Promise<void> {
    if (this.resolvingMenuAuthor || this.blockingBusy || this.blockingAction === undefined) {
      return;
    }
    const requestId = ++this.menuRequestId;
    this.resolvingMenuAuthor = true;
    this.blockingMessage = '';
    try {
      this.menuRepository = this.contentRepositoryFactory();
      const candidate = await resolveHomeFeedBlockUser(item, this.menuRepository, questionAuthor);
      if (requestId !== this.menuRequestId) {
        return;
      }
      if (candidate === undefined) {
        this.showMissingBlockUser(questionAuthor);
        return;
      }
      this.getUIContext().showAlertDialog({
        title: questionAuthor ? '屏蔽提问者' : '屏蔽用户',
        message: questionAuthor
          ? `确定要屏蔽提问者「${candidate.userName}」吗？其提出的问题将不再显示，回答别人问题的内容不受影响。`
          : `确定要屏蔽用户「${candidate.userName}」吗？屏蔽后，该用户的内容将不再显示。`,
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: {
          value: '确定屏蔽',
          fontColor: this.resolvedThemeColor,
          action: (): void => {
            if (requestId === this.menuRequestId) {
              this.confirmUserBlock(item, candidate, questionAuthor);
            }
          }
        }
      });
    } catch (_error) {
      if (requestId === this.menuRequestId) {
        this.showMissingBlockUser(questionAuthor);
      }
    } finally {
      if (requestId === this.menuRequestId) {
        this.resolvingMenuAuthor = false;
        this.menuRepository = undefined;
      }
    }
  }

  private showMissingBlockUser(questionAuthor: boolean): void {
    this.blockingMessage = questionAuthor ? '当前条目没有可用的提问者数据，无法屏蔽提问者'
      : '无法获取屏蔽用户所需的数据，请尝试进入内容详情页操作';
    this.getUIContext().getPromptAction().showToast({ message: this.blockingMessage });
  }

  private blockContext(item: FeedItem): BlockingActionContext {
    return {
      contentTitle: item.target.title,
      contentKind: item.target.kind,
      contentId: item.target.id
    };
  }

  private confirmUserBlock(item: FeedItem, candidate: BlockingUserCandidate, questionAuthorOnly: boolean): void {
    const action = this.blockingAction;
    if (action === undefined) {
      return;
    }
    void action.blockUser(candidate.userId, candidate.userName, this.blockContext(item), questionAuthorOnly).then((): void => {
      if (action.snapshot().phase === BlockingActionPhase.SUCCESS) {
        this.controller?.removeItem(feedItemIdentity(item));
        void this.controller?.refresh();
      }
    });
  }

  private usesCardSurface(): boolean {
    return this.feedCardStyle === 'card';
  }

  private flowGapVp(): number {
    return this.getUIContext().px2vp(this.getUIContext().getHostContext()!.resourceManager
      .getNumber($r('app.float.spacing_medium').id));
  }

  /** 可见索引预取余量：至少保留原 3 条，多列时保留两行内容。 */
  private prefetchMargin(): number {
    return Math.max(3, this.feedColumns * 2);
  }

  private updateInitialItemTarget(): void {
    this.controller?.setInitialItemTarget(
      homeFeedInitialItemTarget(this.feedWidthVp, this.feedHeightVp, floatingTitleBarOffset(),
        feedMinCardWidthVp(this.systemFontSizeScale)));
  }

  /**
   * 视口估算容量（不带首屏缓冲）：按估高与列数推算铺满一屏所需条数，
   * 供数据/视口变化后补判；估高仅服务预取，不决定卡片实际高度。
   */
  private estimatedViewportItems(): number {
    if (this.feedHeightVp <= 0) {
      return 0;
    }
    const rows: number = Math.ceil(Math.max(0, this.feedHeightVp - floatingTitleBarOffset()) /
      FEED_ESTIMATED_CARD_HEIGHT_VP);
    return Math.max(1, rows) * this.feedColumns;
  }

  /** 数据或视口变化后内容不足一屏时补拉一页；限次且内容有增长才重置，防止循环请求。 */
  private maybeFillViewport(): void {
    if (this.phase !== HomeFeedPhase.READY || !this.canLoadMore || this.refreshing || this.loadingMore) {
      return;
    }
    if (this.estimatedViewportItems() <= 0 || this.items.length >= this.estimatedViewportItems()) {
      return;
    }
    if (this.items.length > this.fillAttemptSize) {
      this.fillAttempts = 0;
    }
    if (this.fillAttempts >= 3) {
      return;
    }
    this.fillAttempts += 1;
    this.fillAttemptSize = this.items.length;
    this.controller?.loadMore();
  }

  /** 换列保位仅在静止的 READY 态、且已滚动离开顶部时启动，避免与刷新、手势竞争。 */
  private canPreserveAnchor(): boolean {
    return this.phase === HomeFeedPhase.READY && !this.refreshing && !this.loadingMore &&
      this.firstVisibleIndex > 0 && this.items.length > 0;
  }

  private scheduleAnchorRestore(anchorItemIndex: number, spec: FeedColumnSpec): void {
    const flowIndex: number = feedAnchorFlowIndex(this.flowLayout, anchorItemIndex);
    if (flowIndex < 0) {
      return;
    }
    const entryIndex: number = flowIndex - this.flowLayout.leadingCount;
    const entry: FeedFlowEntry | undefined = this.flowLayout.entries[entryIndex];
    this.anchorRestorer.schedule({
      flowIndex: flowIndex,
      expectedItemWidth: entry !== undefined && entry.date.length > 0 ? spec.contentWidth : spec.cardWidth,
      extraOffsetVp: floatingTitleBarOffset()
    }, this.listScroller);
  }

  private spliceSectionsIfNeeded(): void {
    const signature: string = feedSectionSignature(this.flowLayout);
    if (signature === this.lastSectionSignature) {
      return;
    }
    this.lastSectionSignature = signature;
    this.flowSections.splice(0, this.flowSections.length(), this.flowLayout.sections);
  }

  /** 按当前布局快照构建渲染条目并做最小化通知（追加/删除/重载）。 */
  private applyRenderItems(): void {
    const renderItems: Array<FeedRenderItem> = [
      feedRenderChrome('chrome:spacer', FeedRenderKind.TOP_SPACER)
    ];
    if (this.errorMessage.length > 0) {
      renderItems.push(feedRenderChrome('chrome:error', FeedRenderKind.ERROR_BANNER));
    }
    if (isUpdateAnnouncementVisible(this.pendingUpdateVersion, this.dismissedUpdateVersion)) {
      renderItems.push(feedRenderChrome('chrome:announcement', FeedRenderKind.UPDATE_ANNOUNCEMENT));
    }
    const items: Array<FeedItem> = this.items;
    this.flowLayout.entries.forEach((entry: FeedFlowEntry): void => {
      renderItems.push(feedRenderContent(entry.key, entry.itemIndex, items[entry.itemIndex]));
    });
    if (this.loadingMore) {
      renderItems.push(feedRenderChrome('chrome:footer', FeedRenderKind.LOADING_FOOTER));
    }
    this.flowDataSource.applyLayout(renderItems);
  }

  /** 手动列数档位转期望值：0 表示自动断点，实际列数仍由 resolveFeedColumnSpec 钳制。 */
  private requestedFeedColumns(): number {
    if (this.feedColumnMode === FeedColumnMode.ONE) {
      return 1;
    }
    if (this.feedColumnMode === FeedColumnMode.TWO) {
      return 2;
    }
    if (this.feedColumnMode === FeedColumnMode.THREE) {
      return 3;
    }
    if (this.feedColumnMode === FeedColumnMode.FOUR) {
      return 4;
    }
    return 0;
  }

  private rebuildFlowLayout(): void {
    const spec: FeedColumnSpec = resolveFeedColumnSpec(this.feedWidthVp, {
      columnGapVp: this.flowGapVp(),
      minCardWidthVp: feedMinCardWidthVp(this.systemFontSizeScale),
      requestedColumns: this.requestedFeedColumns()
    });
    const columnsChanged: boolean = spec.columns !== this.feedColumns;
    const anchorItemIndex: number = columnsChanged && this.canPreserveAnchor()
      ? feedFlowItemIndex(this.flowLayout, this.firstVisibleIndex) : -1;
    this.feedColumns = spec.columns;
    this.feedCardWidthVp = spec.cardWidth;
    // +1：真实顶部让位条目也参与懒加载计数与锚点索引。
    const leading: number = 1 + (this.errorMessage.length > 0 ? 1 : 0) +
      (isUpdateAnnouncementVisible(this.pendingUpdateVersion, this.dismissedUpdateVersion) ? 1 : 0);
    // 多列始终保留列间距，卡片表面只由用户选择的样式决定。
    const gap: number = this.feedColumns > 1 || this.usesCardSurface() ? this.flowGapVp() : 0;
    this.flowLayout = buildFeedFlowLayout(
      this.items.map((item: FeedItem): string => feedItemIdentity(item)),
      [],
      spec.columns, leading, this.loadingMore, gap);
    this.spliceSectionsIfNeeded();
    this.applyRenderItems();
    if (anchorItemIndex >= 0) {
      this.scheduleAnchorRestore(anchorItemIndex, spec);
    }
  }

  /** 忽略本次下拉：Refresh 已自行进入刷新态，短暂置 true 再复位让它收起，不发起请求。 */
  private suppressPullRefresh(): void {
    this.refreshing = true;
    setTimeout((): void => {
      this.refreshing = false;
    }, 80);
  }

  private applyState(state: HomeFeedViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    if (state.items.length > 0) {
      this.reportLastReadTouches(state.items);
    }
    this.refreshing = state.refreshing;
    this.indicator?.setRefreshing(state.refreshing);
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
    // 数据变化（含过滤删除、屏蔽移除）后补判内容是否不足一屏
    this.maybeFillViewport();
  }
}

/** lastread/touch 仅支持回答/文章/想法（对齐上游 Feed target 白名单，问题/视频不报）。 */
function lastReadTouchEntryOf(item: FeedItem, action: string): LastReadTouchEntry | undefined {
  const kind = item.target.kind;
  if (kind !== FeedTargetKind.ANSWER && kind !== FeedTargetKind.ARTICLE) {
    return undefined;
  }
  return { kind: kind, id: item.target.id, action: action };
}

/** 首页回答遵循阅读偏好；摘要缺失/无效的问题 ID 只按需查询，不误退回单篇。 */
export async function resolveHomeFeedDestination(item: FeedItem, readingMode: string,
  loadQuestionId: (answerId: string) => Promise<string>): Promise<AppDestination> {
  if (item.target.kind !== FeedTargetKind.ANSWER || readingMode !== 'continuous') {
    return homeFeedDestination(item);
  }
  let questionId = item.target.questionId?.trim() ?? '';
  if (!isSafeDecimalContentId(questionId)) {
    questionId = (await loadQuestionId(item.target.id)).trim();
  }
  if (!isSafeDecimalContentId(questionId)) {
    throw new Error('Invalid answer question ID');
  }
  const destination: AppDestination = {
    name: AppDestinationName.CONTINUOUS_ANSWER,
    questionId: questionId,
    answerId: item.target.id
  };
  return destination;
}

export function homeFeedDestination(item: FeedItem): AppDestination {
  switch (item.target.kind) {
    case FeedTargetKind.QUESTION:
      return { name: AppDestinationName.QUESTION, id: item.target.id };
    case FeedTargetKind.ANSWER:
      return { name: AppDestinationName.ANSWER, id: item.target.id };
    case FeedTargetKind.ARTICLE:
      return { name: AppDestinationName.ARTICLE, id: item.target.id };
    case FeedTargetKind.VIDEO:
      return { name: AppDestinationName.VIDEO, id: item.target.id };
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
    case FeedTargetKind.VIDEO:
      return '视频';
  }
}

export function homeFeedActionLabel(item: FeedItem): string {
  // 对齐上游：LOCAL 模式显示本地推荐理由（reasonDisplay），其余模式显示来源标注
  // （移动端卡「手机版推荐」/ Web 卡 action_text），均缺失时兜底「推荐内容」。
  const reason = item.recommendationReason?.trim() ?? '';
  if (reason.length > 0) {
    return reason;
  }
  const actionText = item.actionText?.trim() ?? '';
  return actionText.length > 0 ? actionText : '推荐内容';
}

/** 对齐上游 details：类型标注（回答/文章等）与统计拼成页脚文字。 */
export function homeFeedDetailsLabel(item: FeedItem): string {
  if (item.target.mobileFooterText !== undefined) {
    // 移动卡片保留服务端页脚原文（已含“手机版推荐”来源标注），不重复拼接。
    return homeFeedFooterLabel(item);
  }
  // Web 卡对齐上游 detailsText：`回答 · N 赞同 · N 评论`。
  const stats = `${item.target.voteupCount ?? '—'} 赞同 · ${item.target.commentCount ?? '—'} 评论`;
  return `${feedKindLabel(item.target.kind)} · ${stats}`;
}

export function homeFeedFooterLabel(item: FeedItem): string {
  const mobileFooter = item.target.mobileFooterText;
  if (mobileFooter !== undefined) {
    return mobileFooter.trim().length > 0 ? `${mobileFooter} · 手机版推荐` : '手机版推荐';
  }
  return `${item.target.voteupCount ?? '—'} 赞同 · ${item.target.commentCount ?? '—'} 评论`;
}
