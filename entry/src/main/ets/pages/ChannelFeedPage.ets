import {
  buildFeedFlowLayout,
  feedAnchorFlowIndex,
  FeedColumnSpec,
  feedDailyMinCardWidthVp,
  feedMinCardWidthVp,
  FEED_DAILY_COLUMN_TARGET,
  FEED_THREE_COLUMN_MIN_WIDTH,
  FeedFlowEntry,
  FeedFlowLayout,
  feedFlowItemIndex,
  feedSectionSignature,
  FEED_ESTIMATED_CARD_HEIGHT_VP,
  resolveFeedColumnSpec
} from './FeedWaterfallLayout';
import { FeedAnchorRestorer } from './FeedColumnAnchorRestore';
import {
  feedRenderChrome,
  FeedFlowDataSource,
  FeedRenderItem,
  FeedRenderKind,
  feedRenderContent,
  feedRenderDailyStory,
  feedRenderDateHeading
} from './FeedFlowDataSource';
import { FeedContentSummary } from './components/FeedContentSummary';
import { HotQuestionStatistics } from './components/HotQuestionStatistics';
import { isSafeDecimalContentId, AppDestination, AppDestinationName } from 'core';
import {
  onThemeColor,
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  ChannelContentItem,
  ChannelDailyStoryItem,
  ChannelFeedItem,
  ChannelFeedItemKind,
  channelFeedItemIdentity,
  ChannelFeedRepository,
  ChannelFeedSource,
  ContentRepository,
  DailyStoryRepository,
  DEFAULT_THEME_COLOR,
  DefaultChannelFeedRepository,
  FeedColumnMode,
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
  AppPageStatusKind,
  AppPageStatusPanel,
  FeedLoadMoreIndicator,
  FeedPullDownIndicatorHost,
  floatingTitleBarOffset,
  PULL_REFRESH_PULL_DOWN_RATIO,
  PULL_REFRESH_TRIGGER_OFFSET_VP,
  pullDownRefreshPlaceholder
} from './AppPageChrome';
import {
  ChannelFeedController,
  ChannelFeedPhase,
  channelFeedTitle,
  ChannelFeedViewState,
  ChannelFeedInteractionBridge
} from './ChannelFeedState';
import { dailyStoryDetailErrorMessage } from './DailyStoryDetailState';
import { dailyFeedDateAtIndex, formatDailyDate } from './DailyFeedDates';
import { DraggableRefreshButton } from './components/DraggableRefreshButton';
import { topLevelScrollRegistry } from './TopLevelScrollRegistry';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { Want } from '@kit.AbilityKit';

/** 下拉头回弹/收起后的静默窗口（ms）：期间再往下滑不触发刷新。 */
const REFRESH_SETTLE_QUIET_MS: number = 500;

@Component
export struct ChannelFeedPage {
  source: ChannelFeedSource = ChannelFeedSource.HOT;
  /** 关注页的两个子 Tab 共用列表实现，标题由外层 Tabs 提供。 */
  showHeader: boolean = true;
  /**
   * 列表顶部内容插槽（随列表滚动），关注推荐页用于渲染“最近更新的关注用户”一行；
   * 需与 topContentVisible 同时开启，否则不占列表项。
   */
  @BuilderParam topContent: () => void = this.emptyTopContent;
  topContentVisible: boolean = false;
  repository: ChannelFeedRepository | undefined = new DefaultChannelFeedRepository();
  questionRepositoryFactory: () => ContentRepository | undefined = () => undefined;
  dailyStoryRepository: DailyStoryRepository | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  @Prop @Watch('reloadAfterAuthentication') reloadToken: number = 0;
  @Prop dateCursor: string = '';
  @StorageProp('dailySelectedDate') dailySelectedDate: string = '';
  @StorageProp('dailyDateSelectionTick') @Watch('loadDateFromTitleBar') dailyDateSelectionTick: number = 0;
  // 登录成功重载信号：经 AppStorage 广播（@Consume 在 HdsTabs 树下实测不链接）
  @StorageProp('loginFeedReloadTick') @Watch('onLoginFeedReloadTick') loginFeedReloadTick: number = 0;
  // 双击底栏页签刷新：关注=1、热榜=2、日报=3（TopLevelTab），复用下拉刷新链路
  @StorageProp('tabRefreshTick') @Watch('onTabRefreshRequested') tabRefreshTick: number = 0;
  @StorageProp('tabRefreshTabIndex') tabRefreshTabIndex: number = -1;
  @StorageProp('tabScrollTopTick') @Watch('onTabScrollTopRequested') private tabScrollTopTick: number = 0;
  @StorageProp('tabScrollTopTabIndex') private tabScrollTopTabIndex: number = -1;
  @StorageProp('showFeedThumbnail') private showFeedThumbnail: boolean = true;
  @StorageProp('showRefreshFab') private showRefreshFab: boolean = true;
  @StorageProp('feedCardStyle') @Watch('rebuildFlowLayout') private feedCardStyle: string = 'divider';
  @StorageProp('fabOpacity') private fabOpacity: number = 100;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('followingTimeOrder') @Watch('applyFollowingOrder') private followingTimeOrder: boolean = false;
  // 下拉刷新自定义加载圆圈（refreshingContent 需 ComponentContent，随页面销毁释放）
  private indicator?: FeedPullDownIndicatorHost = undefined;
  @Consume('channelFeedInteractionBridge') private interactionBridge: ChannelFeedInteractionBridge =
    new ChannelFeedInteractionBridge();
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  @State private phase: ChannelFeedPhase = ChannelFeedPhase.IDLE;
  @State @Watch('rebuildFlowLayout') private items: Array<ChannelFeedItem> = [];
  @State private refreshing: boolean = false;
  @State @Watch('rebuildFlowLayout') private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State @Watch('rebuildFlowLayout') private errorMessage: string = '';
  @State private pendingUserBlock?: BlockingUserCandidate = undefined;
  @State private keywordBlockVisible: boolean = false;
  @State private keywordBlockInput: string = '';
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  @State private dailyStoryOpening: boolean = false;
  @State private dailyStoryOpenError: string = '';
  /** 无法原生阅读时的日报原文地址：有值时错误弹窗提供“用浏览器打开”。 */
  @State private dailyStoryOpenUrl: string = '';
  private controller?: ChannelFeedController;
  private blockingAction?: BlockingActionController;
  private pendingBlockItem?: ChannelContentItem = undefined;
  private readonly listScroller: Scroller = new Scroller();
  @State @Watch('rebuildFlowLayout') private feedWidthVp: number = 0;
  // 状态栏高度（vp）晚于首帧到达时重算首屏让位（让位 = 状态栏 + 顶栏 56vp）
  @StorageProp('statusBarHeightVp') @Watch('rebuildFlowLayout') private statusBarHeightVp: number = 0;
  // 系统字号缩放：放大时提高最小卡宽，必要时自动减少列数
  @StorageProp('systemFontSizeScale') @Watch('rebuildFlowLayout') private systemFontSizeScale: number = 1;
  // 信息流列数偏好：auto 随断点，手动档位作为期望值仍受宽度保护（AppStorage + @StorageProp + @Watch）
  @StorageProp('feedColumnMode') @Watch('rebuildFlowLayout') private feedColumnMode: string = FeedColumnMode.AUTO;
  // 最终列数与卡宽保存在页面本地（不用全局单值，避免离屏缓存页互相覆盖）
  @State private feedColumns: number = 1;
  private feedCardWidthVp: number = 0;
  private feedHeightVp: number = 0;
  @State private flowSections: WaterFlowSections = new WaterFlowSections();
  @State private flowLayout: FeedFlowLayout = buildFeedFlowLayout([], [], 1, 1, false, 0);
  // LazyForEach 数据源：通栏项、日期标题、内容与加载尾统一协调，通知与 sections 同源
  private readonly flowDataSource: FeedFlowDataSource = new FeedFlowDataSource();
  private lastSectionSignature: string = '';
  private readonly anchorRestorer: FeedAnchorRestorer = new FeedAnchorRestorer();
  // 不足一屏补屏的限次计数：内容有增长才重置，防止过滤稀少或重复游标时循环请求
  private fillAttempts: number = 0;
  private fillAttemptSize: number = 0;
  private firstVisibleIndex: number = 0;
  private handledDateSelectionTick: number = 0;
  private pageActive: boolean = false;
  /** 本次手势按下时列表是否已在顶部：只有顶部起手才算有意下拉刷新。 */
  private pullGestureFromTop: boolean = true;
  /** 下拉头最近一次回弹/收起的时刻：此后的短静默期内不响应下拉刷新。 */
  private lastRefreshSettleTime: number = 0;

  aboutToAppear(): void {
    this.pageActive = true;
    // 登记给根 HdsNavigation 做 bindToScrollable：驱动标题栏滚动模糊（以 source 为页签标识，
    // 根标题栏只绑定当前可见页签，关注页两个子页签因此不会互相带出模糊）。
    topLevelScrollRegistry.register(this.source, this.listScroller);
    // 覆盖式顶栏：Refresh 头部从页面顶端展开，把刷新圆圈绘制偏移到悬浮标题栏下沿
    this.indicator = new FeedPullDownIndicatorHost(this.getUIContext(), floatingTitleBarOffset());
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载列表导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.setFollowingTimeOrder(this.followingTimeOrder);
      this.controller.activate();
      this.registerTitleBarActions();
      this.loadDateFromTitleBar();
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
    this.controller.setFollowingTimeOrder(this.followingTimeOrder);
    this.registerTitleBarActions();
    this.controller.activate();
    if (this.source === ChannelFeedSource.DAILY && this.dailyDateSelectionTick > 0) {
      this.loadDateFromTitleBar();
    } else {
      this.controller.loadInitial();
    }
    this.createBlockingAction();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.indicator?.dispose();
    this.indicator = undefined;
    this.controller?.deactivate();
    this.anchorRestorer.cancel();
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

  private registerTitleBarActions(): void {
    const controller = this.controller;
    if (controller === undefined) {
      return;
    }
    if (this.source === ChannelFeedSource.HOT) {
      this.interactionBridge.registerHotRefresh((): void => {
        controller.reloadNow();
      });
    }
  }

  private reloadAfterAuthentication(): void {
    this.controller?.refresh();
  }

  private applyFollowingOrder(): void {
    this.controller?.setFollowingTimeOrder(this.followingTimeOrder);
  }

  /** 本页所属的顶级页签：关注页两个子源都挂在“关注”页签下。 */
  private tabIndexOfSource(): number {
    if (this.source === ChannelFeedSource.HOT) {
      return 2;
    }
    if (this.source === ChannelFeedSource.DAILY) {
      return 3;
    }
    return 1;
  }

  private onTabRefreshRequested(): void {
    if (this.tabRefreshTabIndex === this.tabIndexOfSource()) {
      this.controller?.refresh();
    }
  }

  private onTabScrollTopRequested(): void {
    if (this.tabScrollTopTabIndex !== this.tabIndexOfSource()) {
      return;
    }
    // 单击只回到顶部，不再在顶部时刷新：刷新改为连续点击两次页签触发（双击路径）。
    // 必须滚到内容起点（offset 0）而不是 scrollToIndex(0)：首个瀑布流分组带标题栏让位边距，
    // 按下标对齐会把首行卡片顶到屏幕最上沿、盖住标题栏与下拉刷新圆圈。
    this.firstVisibleIndex = 0;
    this.listScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: true });
  }

  private onLoginFeedReloadTick(): void {
    this.controller?.reloadNow();
  }

  private loadDateFromTitleBar(): void {
    if (this.source === ChannelFeedSource.DAILY && this.pageActive && this.controller !== undefined &&
      this.dailyDateSelectionTick !== this.handledDateSelectionTick && /^\d{8}$/.test(this.dailySelectedDate)) {
      this.handledDateSelectionTick = this.dailyDateSelectionTick;
      this.controller.loadDate(this.dailySelectedDate);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.spacing_medium') }) {
      if (this.phase === ChannelFeedPhase.IDLE || this.phase === ChannelFeedPhase.INITIAL_LOADING) {
        this.centeredStatus(`正在加载${channelFeedTitle(this.source)}…`, false);
      } else if (this.phase === ChannelFeedPhase.ERROR) {
        this.centeredStatus(this.errorMessage, true);
      } else if (this.phase === ChannelFeedPhase.EMPTY) {
        this.centeredStatus(`暂时没有${channelFeedTitle(this.source)}内容`, true);
      } else {
        Refresh({
          refreshing: this.refreshing,
          builder: pullDownRefreshPlaceholder,
          refreshingContent: this.indicator?.view()
        }) {
          WaterFlow({ scroller: this.listScroller, sections: this.flowSections,
              layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW }) {
            // 通栏项（错误横幅/顶部插槽/加载尾）、日期标题与内容统一进数据源
            LazyForEach(this.flowDataSource, (renderItem: FeedRenderItem) => {
              FlowItem() {
                this.flowRenderItem(renderItem)
              }
              .width('100%')
            }, (renderItem: FeedRenderItem): string => renderItem.key)
          }
          .cachedCount(Math.max(5, this.feedColumns * 2))
          .id(`channel_${this.source}_list`)
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
            // 容器挂到组件后再登记一次：aboutToAppear 时 Scroller 还没挂上组件，
            // 根标题栏绑定它拿不到偏移，必须等挂载后才能建立订阅。
            .onAppear((): void => {
              topLevelScrollRegistry.register(this.source, this.listScroller);
            })
          .height('100%')
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => this.controller?.loadMore())
          .onScrollIndex((start: number, end: number): void => {
            this.firstVisibleIndex = start;
            if (this.source === ChannelFeedSource.DAILY) {
              this.publishDailyViewingDate();
            }
            // 关注、热榜等有分页能力的来源与日报一致：按列数保留两行余量提前请求；
            // 已结束或不支持继续分页的来源由 canLoadMore 与控制器兜底拦截。
            const lastItem: number = feedFlowItemIndex(this.flowLayout, end);
            if (this.canLoadMore && this.items.length > 0 &&
              lastItem >= this.items.length - this.prefetchMargin()) {
              this.controller?.loadMore();
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        // 官方属性（offset/friction 已于 API 11 废弃）：把刷新阈值抬到明显高于普通回弹，
        // 普通下拉只回弹、不刷新；需要下拉约半屏高才触发。
        .refreshOffset(PULL_REFRESH_TRIGGER_OFFSET_VP)
        .pullDownRatio(PULL_REFRESH_PULL_DOWN_RATIO)
        .onRefreshing((): void => {
          // 程序化刷新（双击页签/热榜按钮）把 refreshing 置 true 时也会回调本事件：
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
          .id(`channel_${this.source}_blocking_status`)
          .fontSize($r('app.float.secondary_font_size'))
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
        // 视口变化后补判内容是否不足一屏（单列切多列、宽窗首屏等）
        this.maybeFillViewport();
      })

      if (this.showRefreshFab && this.phase === ChannelFeedPhase.READY) {
        DraggableRefreshButton({
          elementId: `channel_${this.source}_refresh_fab`,
          accessibilityLabel: `刷新${channelFeedTitle(this.source)}`,
          fabOpacity: this.fabOpacity,
          loading: this.refreshing,
          onRefresh: (): void => {
            void this.controller?.refresh();
          }
        })
      }

      // 打开日报正文时的加载提示：只显示刷新圆圈，不压暗整页（避免点击瞬间整屏发黑）。
      if (this.dailyStoryOpening) {
        Column() {
          Column({ space: $r('app.float.spacing_small') }) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color(this.resolvedThemeColor)
            Text('正在打开日报原文…')
              .id(`channel_${this.source}_daily_opening`)
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .padding($r('app.float.card_padding'))
          .borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // 打开失败提示。
      if (this.dailyStoryOpenError.length > 0) {
        Column() {
          Column({ space: $r('app.float.spacing_medium') }) {
            Text('打开日报失败')
              .fontSize($r('app.float.body_font_size'))
              .fontWeight(FontWeight.Medium)
            Text(this.dailyStoryOpenError)
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
            if (this.dailyStoryOpenUrl.length > 0) {
              Button('用浏览器打开')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id(`channel_${this.source}_daily_open_browser`)
                .width('100%')
                .onClick((): void => {
                  this.openDailyStoryInBrowser();
                })
              Button('取消')
                .backgroundColor($r('app.color.surface_background'))
                .fontColor($r('app.color.primary_text'))
                .id(`channel_${this.source}_daily_open_cancel`)
                .width('100%')
                .onClick((): void => {
                  this.dismissDailyStoryOpenError();
                })
            } else {
              Button('确定')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id(`channel_${this.source}_daily_open_error_ok`)
                .width('100%')
                .onClick((): void => {
                  this.dismissDailyStoryOpenError();
                })
            }
          }
          .width('80%')
          .padding($r('app.float.card_padding'))
          .borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#33000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private emptyTopContent() {
  }

  @Builder
  private centeredStatus(message: string, retry: boolean) {
    AppPageStatusPanel({
      kind: retry ? AppPageStatusKind.ERROR : AppPageStatusKind.LOADING,
      message: message,
      testId: `channel_${this.source}_status`,
      actionLabel: retry ? (this.requiresLogin ? '去登录' : '重新加载') : '',
      actionId: this.requiresLogin ? `channel_${this.source}_login` : `channel_${this.source}_retry`,
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
  private contentCard(item: ChannelContentItem, index: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.spacing_small') }) {
        Row({ space: $r('app.float.spacing_xsmall') }) {
          if (this.source === ChannelFeedSource.HOT) {
            Text(`${index + 1}`)
              .id(`channel_hot_rank_${item.feedItem.target.id}`)
              .fontSize($r('app.float.heading_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.resolvedThemeColor)
          }
          Text(channelActionLabel(item.feedItem, this.source))
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(channelKindLabel(item.feedItem.target.kind))
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor(this.resolvedThemeColor)

          // 对齐上游 FeedCardMenuBox：右上角紧凑“更多”符号图标，屏蔽等操作收进菜单。
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id(`channel_${this.source}_block_${item.feedItem.target.kind}_${item.feedItem.target.id}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .enabled(!this.blockingBusy && this.blockingAction !== undefined)
          .bindMenu(this.contentBlockMenu(item))
          .accessibilityText('屏蔽作者或关键词')
        }
        .width('100%')
        // 热榜条目是问题（接口只给 question，无作者）：不渲染作者行，避免「空头像 + 知乎用户」；
        // 统计改由 HotQuestionStatistics 呈现热度/回答/关注（对齐安卓上游问题卡的详情行）。
        FeedContentSummary({
          target: item.feedItem.target,
          showStatistics: this.source !== ChannelFeedSource.HOT,
          showAuthor: this.source !== ChannelFeedSource.HOT,
          summaryMaxLines: this.feedColumns > 1 ? 2 : 3
        })
        if (this.showFeedThumbnail && (item.feedItem.target.thumbnailUrl ?? '').length > 0) {
          Image(item.feedItem.target.thumbnailUrl)
            .width('100%')
            .height(128)
            .borderRadius($r('app.float.spacing_small'))
            .objectFit(ImageFit.Cover)
            .alt('内容缩略图')
        }
        if (this.source === ChannelFeedSource.HOT) {
          HotQuestionStatistics({ target: item.feedItem.target, repositoryFactory: this.questionRepositoryFactory })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`channel_content_${item.feedItem.target.kind}_${item.feedItem.target.id}`)
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
    .accessibilityText(`打开${channelKindLabel(item.feedItem.target.kind)}：${item.feedItem.target.title}`)
    .onClick(() => {
      const destination = channelFeedDestination(item);
      if (destination !== undefined) {
        this.navigate(destination);
      }
    })
  }

  @Builder
  private dailyDateDivider(date: string) {
    Row({ space: 16 }) {
      Divider().layoutWeight(1).color($r('app.color.secondary_text')).opacity(0.2)
      Text(formatDailyDate(date))
        .id(`daily_section_${date}`)
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvedThemeColor)
      Divider().layoutWeight(1).color($r('app.color.secondary_text')).opacity(0.2)
    }
    .width('100%')
    .padding({ top: 12, bottom: 4 })
  }

  @Builder
  private dailyCard(item: ChannelDailyStoryItem) {
    // 日报卡：多列走 4×1 竖排等高网格卡；单列回落为原有“图左文右”横排（窄屏单卡占满整行）。
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      if (this.feedColumns > 1) {
        Column({ space: $r('app.float.spacing_small') }) {
          if (this.showFeedThumbnail && item.story.imageUrl !== undefined && /^https:\/\/[^\s]+$/i.test(item.story.imageUrl)) {
            Image(item.story.imageUrl)
              .width('100%')
              .aspectRatio(1.6)
              .borderRadius($r('app.float.spacing_small'))
              .objectFit(ImageFit.Cover)
              .alt('日报缩略图')
          } else {
            // 无缩略图（或偏好关闭）时的等比占位，维持整卡高度一致
            Column()
              .width('100%')
              .aspectRatio(1.6)
              .borderRadius($r('app.float.spacing_small'))
              .backgroundColor($r('app.color.control_background'))
          }
          Text(item.story.title)
            .fontSize($r('app.float.body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .lineHeight('24fp')
            .height('72fp')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(item.story.hint)
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .lineHeight('22fp')
            .height('22fp')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      } else {
        Row({ space: $r('app.float.spacing_medium') }) {
          if (this.showFeedThumbnail && item.story.imageUrl !== undefined && /^https:\/\/[^\s]+$/i.test(item.story.imageUrl)) {
            Image(item.story.imageUrl)
              .width('28%')
              .aspectRatio(1)
              .borderRadius($r('app.float.spacing_small'))
              .objectFit(ImageFit.Cover)
              .alt('日报缩略图')
          }
          Column({ space: $r('app.float.spacing_small') }) {
            Text(item.story.title)
              .fontSize($r('app.float.body_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (item.story.hint.trim().length > 0) {
              Text(item.story.hint)
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
      }
    }
    .id(`channel_daily_${item.story.id}`)
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
    .accessibilityText(`知乎日报：${item.story.title}`)
    .onClick((): void => {
      this.openDailyStory(item.story.id, item.story.url);
    })
  }

  /**
   * 直接打开日报正文：先取目标（问题/回答/文章）再一步导航，避免经过
   * DailyStoryDetailPage 中间跳转页（用户看到“多了一个页面”）。
   * 知乎部分日报（如「瞎扯」合集）的 originUrl 是 question/None/answer/None，
   * 没有单一原生正文可跳，此时改为提供浏览器打开原文。
   */
  private async openDailyStory(storyId: string, storyUrl: string): Promise<void> {
    const repository = this.dailyStoryRepository;
    if (repository === undefined) {
      this.navigate({ name: AppDestinationName.DAILY_STORY, id: storyId });
      return;
    }
    if (this.dailyStoryOpening) {
      return;
    }
    this.dailyStoryOpening = true;
    this.dailyStoryOpenError = '';
    this.dailyStoryOpenUrl = '';
    let unsupportedUrl: string = '';
    try {
      const destination: AppDestination | undefined = await repository.getDestination(storyId);
      if (destination !== undefined) {
        this.navigate(destination);
      } else {
        unsupportedUrl = storyUrl.length > 0 ? storyUrl : `https://daily.zhihu.com/story/${storyId}`;
        this.dailyStoryOpenError = '该日报暂不支持原生阅读，可在浏览器中查看原文';
      }
    } catch (error) {
      this.dailyStoryOpenError = dailyStoryDetailErrorMessage(error);
    } finally {
      this.dailyStoryOpening = false;
      this.dailyStoryOpenUrl = unsupportedUrl;
    }
  }

  private dismissDailyStoryOpenError(): void {
    this.dailyStoryOpenError = '';
    this.dailyStoryOpenUrl = '';
  }

  /** 用系统浏览器打开日报原文（对齐上游「由于知乎的 Bug，无法找到原文」的兜底）。 */
  private openDailyStoryInBrowser(): void {
    const url = this.dailyStoryOpenUrl;
    const context = getAbilityContext();
    this.dismissDailyStoryOpenError();
    if (context === undefined || url.length === 0) {
      return;
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    context.startAbility(want).catch((_error: Error): void => {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开浏览器' });
    });
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
    Column({ space: $r('app.float.spacing_small') }) {
      Text(`确定要屏蔽用户「${this.pendingUserBlock?.userName ?? ''}」吗？`)
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
      Text('屏蔽后，该作者的内容将不再显示。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => {
            this.pendingUserBlock = undefined;
          })
        Button('确定屏蔽')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id(`channel_${this.source}_confirm_block_user`)
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => this.confirmUserBlock())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private keywordBlockDialog() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('输入要屏蔽的关键词（普通文本，不区分大小写）')
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
      TextInput({ text: this.keywordBlockInput, placeholder: '输入关键词' })
        .id(`channel_${this.source}_keyword_block_input`)
        .maxLength(200)
        .onChange((value: string): void => {
          this.keywordBlockInput = value;
        })
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => {
            this.keywordBlockVisible = false;
            this.keywordBlockInput = '';
          })
        Button('确认屏蔽')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id(`channel_${this.source}_confirm_block_keyword`)
          .layoutWeight(1)
          .enabled(!this.blockingBusy && this.keywordBlockInput.trim().length > 0)
          .onClick((): void => this.confirmKeywordBlock())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private flowRenderItem(renderItem: FeedRenderItem) {
    if (renderItem.kind === FeedRenderKind.TOP_SPACER) {
      // 用真实条目让位，系统点状态栏回顶时也能保留悬浮标题栏空间。
      Row()
        .width('100%')
        .height(floatingTitleBarOffset())
    } else if (renderItem.kind === FeedRenderKind.ERROR_BANNER) {
      this.channelErrorBanner()
    } else if (renderItem.kind === FeedRenderKind.TOP_CONTENT) {
      this.topContent()
    } else if (renderItem.kind === FeedRenderKind.DATE_HEADING) {
      this.dailyDateDivider(renderItem.date)
    } else if (renderItem.kind === FeedRenderKind.LOADING_FOOTER) {
      // 与首页共用加载区，避让悬浮底栏和系统手势区。
      FeedLoadMoreIndicator({ elementId: `channel_${this.source}_load_more` })
    } else if (renderItem.kind === FeedRenderKind.CONTENT) {
      this.contentCard(renderItem.payload as ChannelContentItem, renderItem.itemIndex)
    } else {
      this.dailyCard(renderItem.payload as ChannelDailyStoryItem)
    }
  }

  @Builder
  private channelErrorBanner() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(this.errorMessage)
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      if (this.requiresLogin) {
        Button('去登录')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id(`channel_${this.source}_login`)
          .onClick(() => this.navigate({ name: AppDestinationName.LOGIN }))
      } else {
        Button('重试')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id(`channel_${this.source}_retry_more`)
          .onClick(() => this.controller?.retry())
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_small'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  private usesCardSurface(): boolean {
    return this.feedColumns > 1 || this.feedCardStyle === 'card';
  }

  private flowGapVp(): number {
    return this.getUIContext().px2vp(this.getUIContext().getHostContext()!.resourceManager
      .getNumber($r('app.float.spacing_medium').id));
  }

  /** 可见索引预取余量：至少保留原 3 条，多列时保留两行内容。 */
  private prefetchMargin(): number {
    return Math.max(3, this.feedColumns * 2);
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
    if (this.phase !== ChannelFeedPhase.READY || !this.canLoadMore || this.refreshing || this.loadingMore) {
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
    return this.phase === ChannelFeedPhase.READY && !this.refreshing && !this.loadingMore &&
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
    if (this.topContentVisible) {
      renderItems.push(feedRenderChrome('chrome:top', FeedRenderKind.TOP_CONTENT));
    }
    const items: Array<ChannelFeedItem> = this.items;
    this.flowLayout.entries.forEach((entry: FeedFlowEntry): void => {
      const item: ChannelFeedItem = items[entry.itemIndex];
      // 键内带源索引：热榜排名按位置展示，索引位移时对齐原 ForEach 的重建语义
      if (entry.date.length > 0) {
        renderItems.push(feedRenderDateHeading(entry.key, entry.itemIndex, entry.date));
      } else if (item.kind === ChannelFeedItemKind.CONTENT) {
        renderItems.push(feedRenderContent(`${entry.key}@${entry.itemIndex}`, entry.itemIndex, item));
      } else {
        renderItems.push(feedRenderDailyStory(`${entry.key}@${entry.itemIndex}`, entry.itemIndex, item));
      }
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
    // 日报：≥840vp 宽屏启用 4×1 目标（竖排等高小卡，专属最小卡宽）；窄于 840vp
    // 禁用该布局，回到常规自动断点——手机横屏 816vp 即 2 列、竖屏单列横排卡。
    // 通栏项（日期标题等）始终单列；非日报源沿用信息流列数偏好与常规最小卡宽。
    const daily: boolean = this.source === ChannelFeedSource.DAILY;
    const spec: FeedColumnSpec = daily
      ? (this.feedWidthVp >= FEED_THREE_COLUMN_MIN_WIDTH
        ? resolveFeedColumnSpec(this.feedWidthVp, {
          columnGapVp: this.flowGapVp(),
          minCardWidthVp: feedDailyMinCardWidthVp(this.systemFontSizeScale),
          requestedColumns: FEED_DAILY_COLUMN_TARGET
        })
        : resolveFeedColumnSpec(this.feedWidthVp, {
          columnGapVp: this.flowGapVp(),
          minCardWidthVp: feedDailyMinCardWidthVp(this.systemFontSizeScale)
        }))
      : resolveFeedColumnSpec(this.feedWidthVp, {
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
      (this.topContentVisible ? 1 : 0);
    const gap: number = this.usesCardSurface() ? this.flowGapVp() : 0;
    this.flowLayout = buildFeedFlowLayout(
      this.items.map((item: ChannelFeedItem): string => channelFeedItemIdentity(item)),
      this.items.map((item: ChannelFeedItem): string => item.kind === ChannelFeedItemKind.DAILY_STORY ? item.story.date : ''),
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

  private applyState(state: ChannelFeedViewState): void {
    const replacedDailyPage = this.source === ChannelFeedSource.DAILY &&
      (this.phase === ChannelFeedPhase.INITIAL_LOADING || this.refreshing) &&
      !state.refreshing && (state.phase === ChannelFeedPhase.READY || state.phase === ChannelFeedPhase.EMPTY) &&
      state.errorMessage === undefined;
    if (replacedDailyPage) {
      this.firstVisibleIndex = 0;
      if (this.refreshing) {
        this.listScroller.scrollToIndex(0, false, ScrollAlign.START);
      }
    }
    this.phase = state.phase;
    this.items = state.items;
    this.refreshing = state.refreshing;
    this.indicator?.setRefreshing(state.refreshing);
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
    if (this.source === ChannelFeedSource.DAILY &&
      (state.phase === ChannelFeedPhase.READY || state.phase === ChannelFeedPhase.EMPTY)) {
      this.publishDailyViewingDate();
    }
    // 数据变化（含屏蔽移除）后补判内容是否不足一屏
    this.maybeFillViewport();
  }

  private publishDailyViewingDate(): void {
    const date = dailyFeedDateAtIndex(this.items, Math.max(0, feedFlowItemIndex(this.flowLayout, this.firstVisibleIndex)));
    if (AppStorage.get<string>('dailyViewingDate') !== date) {
      AppStorage.setOrCreate('dailyViewingDate', date);
    }
  }
}

export function channelFeedDestination(item: ChannelContentItem): AppDestination | undefined {
  if (!isSafeDecimalContentId(item.feedItem.target.id)) {
    return undefined;
  }
  switch (item.feedItem.target.kind) {
    case FeedTargetKind.QUESTION:
      return { name: AppDestinationName.QUESTION, id: item.feedItem.target.id };
    case FeedTargetKind.ANSWER:
      return { name: AppDestinationName.ANSWER, id: item.feedItem.target.id };
    case FeedTargetKind.ARTICLE:
      return { name: AppDestinationName.ARTICLE, id: item.feedItem.target.id };
    case FeedTargetKind.VIDEO:
      return { name: AppDestinationName.VIDEO, id: item.feedItem.target.id };
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
    case FeedTargetKind.VIDEO:
      return '视频';
  }
}

export function channelActionLabel(item: FeedItem, source: ChannelFeedSource): string {
  const actionText = item.actionText?.trim() ?? '';
  if (actionText.length > 0) {
    return actionText;
  }
  if (source === ChannelFeedSource.FOLLOWING) {
    return '关注动态';
  }
  if (source === ChannelFeedSource.FOLLOWING_RECOMMEND) {
    return '推荐内容';
  }
  return '热榜内容';
}
