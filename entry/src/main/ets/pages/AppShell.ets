import { setFeedScrollOwner } from './FeedScrollOwnership';
import { updateStatusBarAppearance } from '../platform/SystemBars';
import { QuestionTitleBar } from './QuestionTitleBar';
import { SearchTitleBar } from './SearchTitleBar';
import { HistoryTitleBar } from './HistoryTitleBar';
import { AnswerTitleBar, AnswerTitleState } from './AnswerTitleBar';
import { ArticleTitleBar } from './ArticleTitleBar';
import { peopleTitleText, PeopleTitleState } from './PeopleTitleBar';
import { CommentTitleBar, CommentTitleState, commentTitleStateId } from './CommentTitleBar';
import { NotificationTitleBar, NOTIFICATION_HUB_REFRESH_TICK_KEY,
  NOTIFICATION_TIMELINE_REFRESH_TICK_KEY, NOTIFICATION_TIMELINE_ENTRY_KEY } from './NotificationTitleBar';
import {
  onThemeColor,
  AppearancePreferences,
  AnswerDoubleTapAction,
  AppPreferencesStore,
  BlockedFeedHistoryStore,
  ContentFilterRuntimeStore,
  AppThemeMode,
  decodeImmersiveMaterialModeText,
  DEFAULT_IMMERSIVE_MATERIAL_MODE,
  DEFAULT_DAILY_STORY_READER_MODE,
  DEFAULT_THEME_COLOR,
  FORMULA_FOREGROUND_DARK,
  FORMULA_FOREGROUND_LIGHT,
  ExperiencePreferences,
  ImmersiveMaterialMode,
  normalizeBottomBarItems,
  normalizeThemeColor,
  resolveThemeColorForDark,
  themeColorContainerColor,
  AppUpdateCheckResult,
  AppUpdateCheckStatus,
  AppUpdateClient,
  AppUpdateRelease,
  LoginSessionGateway,
  ReaderTypography,
  readerPositionKey,
  SessionState,
  SessionStatus,
  shouldAutoCheckForUpdate,
  shouldShowWhatsNewOnLaunch,
  getAppDatabase,
  ChannelFeedSource
} from 'data';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import bundleManager from '@ohos.bundle.bundleManager';
import { Want } from '@kit.AbilityKit';
import {
  SymbolGlyphModifier,
  uiMaterial
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resourceManager } from '@kit.LocalizationKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { seedBundledUpdateCatalog } from './BundledUpdateCatalog';
import {
  decodeAppDestination,
  findAppDestinationStackIndex,
  isInfrastructureDestination,
  LatestOperationGuard,
  NotificationEntryDestination,
  AppDestination,
  PrivateMessageDestination,
  ContinuousAnswerDestination,
  AppDestinationName,
  shouldReloadAfterAuthentication,
  startupDestinationChannel,
  StartupDestinationListener
} from 'core';
import { AppNavigationRow, floatingTitleBarOffset } from './AppPageChrome';
import {
  HOME_FEED_SCROLL_KEY,
  SETTINGS_SCROLL_KEY,
  topLevelScrollRegistry
} from './TopLevelScrollRegistry';
import {
  TopLevelTab,
  topLevelTabForDestination
} from './TopLevelTabs';
import { DividerShowType, hdsMaterial, HdsNavDestination, HdsNavigation, HdsNavigationAttribute, HdsNavigationTitleMode, HdsTabsController } from '@kit.UIDesignKit';
import { ContinuousAnswerTitleState, continuousAnswerRouteId, continuousAnswerTitle } from './ContinuousAnswerRouteState';
import { getAnswerTitleBarStyle, getContinuousAnswerTitleBarStyle, getChatTitleBarStyle, getImmersiveTitleBarStyle, getPersistentImmersiveTitleBarStyle, getRootChromeTitleBarStyle } from '../common/style/NavStyles';
import {
  decodeImmersiveMaterialSupport,
  ImmersiveMaterialSupportState
} from '../common/style/ImmersiveMaterialStyles';
import { HarmonyOSCapabilities } from '../common/platform/HarmonyOSCapabilities';
import { ZhihuHdsTabs } from './components/ZhihuHdsTabs';
import { AppearanceSettingsPage } from './AppearanceSettingsPage';
import { AccountPage } from './AccountPage';
import { SettingsHomePage } from './SettingsHomePage';
import { AboutAppPage } from './AboutAppPage';
import { ThemeColorSettingsPage } from './ThemeColorSettingsPage';
import { ContentFilterSettingsPage } from './ContentFilterSettingsPage';
import { IdentityManagementPage } from './IdentityManagementPage';
import { ReadingSettingsPage } from './ReadingSettingsPage';
import { SystemUpdateSettingsPage } from './SystemUpdateSettingsPage';
import { WhatsNewPage } from './WhatsNewPage';
import { materialCanvas } from './components/MaterialCanvas';
import { ChannelFeedInteractionBridge } from './ChannelFeedState';
import { dailyDateCursor, dailyPickerDate, formatDailyDate } from './DailyFeedDates';

const PROJECT_HOME_URI: string = 'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS';

/**
 * 顶栏玻璃材质（`uiMaterial`，API 26 专属）。
 * 兼容线仍是 API 23：低版本返回 undefined，调用点用 `backgroundBlurStyle` 兜底，
 * 系统材质只在高版本设备上生效。
 */
function createTitleBarGlassMaterial(): uiMaterial.Material | undefined {
  // 系统材质是 API 26 专属：低版本 kit 里没有该模块，构造会抛异常（实测 API 24 模拟器
  // 抛错但不崩），因此必须按版本门禁并兜底，低版本改用 backgroundBlurStyle。
  if (!HarmonyOSCapabilities.supportsSystemMaterial()) {
    return undefined;
  }
  try {
    return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN });
  } catch (_error) {
    return undefined;
  }
}

const TITLE_BAR_GLASS_MATERIAL: uiMaterial.Material | undefined = createTitleBarGlassMaterial();

@Component
export struct AppShell {
  @BuilderParam homeContent: (reloadToken: number, navigate: (destination: AppDestination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam followingContent: (reloadToken: number, navigate: (destination: AppDestination) => void,
    selectedTabIndex: number) => void =
    this.emptyReloadableHome;
  @BuilderParam hotContent: (reloadToken: number, navigate: (destination: AppDestination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam dailyContent: (reloadToken: number, dateCursor: string,
    navigate: (destination: AppDestination) => void) => void =
    this.emptyReloadableDaily;
  @BuilderParam dailyStoryContent: (id: string, navigate: (destination: AppDestination) => void) => void =
    this.emptyContent;
  @BuilderParam technicalLabContent: (navigate: (destination: AppDestination) => void,
    onDeveloperModeDisabled: () => void, embedded: boolean) => void =
    this.emptyTechnicalLab;
  @BuilderParam searchContent: (query: string, navigate: (destination: AppDestination) => void,
    onBack: () => void) => void =
    this.emptySearch;
  @BuilderParam commentContent: (destination: AppDestination,
    navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyComment;
  @BuilderParam questionContent: (id: string, navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam answerContent: (id: string, navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam articleContent: (id: string, navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam videoContent: (id: string, navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam writeAnswerContent: (questionId: string, answerId: string | undefined,
    navigate: (destination: AppDestination) => void, onBack: () => void) => void = this.emptyWriteAnswer;
  @BuilderParam writePinContent: (draftId: string, navigate: (destination: AppDestination) => void,
    onBack: () => void) => void = this.emptyWritePin;
  @BuilderParam pinDraftInboxContent: (navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyPinDraftInbox;
  @BuilderParam peopleContent: (id: string, navigate: (destination: AppDestination) => void,
    onBack: () => void) => void = this.emptyPeople;
  @BuilderParam pinContent: (id: string, navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyPinContent;
  @BuilderParam collectionsContent: (id: string, navigate: (destination: AppDestination) => void,
    onBack: () => void) => void = this.emptyCollections;
  @BuilderParam collectionContentContent: (id: string, navigate: (destination: AppDestination) => void,
    onBack: () => void) => void = this.emptyCollectionContent;
  @BuilderParam notificationContent: (navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyHome;
  @BuilderParam notificationEntryContent: (entryName: string, title: string, navigate: (destination: AppDestination) => void) => void =
    this.emptyNotificationEntry;
  @BuilderParam privateMessageContent: (peerId: string, peerName: string, avatarUrl: string, navigate: (destination: AppDestination) => void) => void =
    this.emptyPrivateMessage;
  @BuilderParam notificationSettingsContent: (navigate: (destination: AppDestination) => void,
    embedded: boolean) => void = this.emptyNotificationSettings;
  /** 屏蔽规则／屏蔽记录：根路由与设置右栏复用同一 Builder，embedded 决定标题与让位归属。 */
  @BuilderParam blockingRulesContent: (onBack: () => void, embedded: boolean,
    registerActions: (handler: () => void) => void, releaseActions: () => void) => void = this.emptyEmbeddedPage;
  @BuilderParam blockedFeedHistoryContent: (onBack: () => void, embedded: boolean,
    registerActions: (handler: () => void) => void, releaseActions: () => void) => void = this.emptyEmbeddedPage;
  @BuilderParam readHistoryContent: (navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyHome;
  @BuilderParam localHistoryContent: (navigate: (destination: AppDestination) => void, onBack: () => void) => void =
    this.emptyHome;
  @BuilderParam loginContent: (onBack: () => void, onAuthenticated: () => void,
    onScanDesktopLogin: () => void) => void = this.emptyLogin;
  @BuilderParam readerProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam imageProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam continuousReadingProtoContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam continuousAnswerContent: (questionId: string, answerId: string | undefined,
    sort: string | undefined, navigate: (destination: AppDestination) => void,
    onBack: () => void) => void = this.emptyPage;
  @BuilderParam databaseProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam deepLinkProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam qrScanProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam qrDesktopLoginScanContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam backgroundTaskProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam domainFixtureProbeContent: (onBack: () => void) => void = this.emptyProbe;
  session: LoginSessionGateway | undefined = undefined;
  // 登录/登出经 AppStorage 广播 sessionStateTick（LoginSessionGateway 非可观察对象，
  // 直接 getState() 不驱动 UI）；快照仅在 tick 变化时刷新，供账号概览等方法读取。
  @StorageProp('sessionStateTick') @Watch('onSessionStateTick') sessionStateTick: number = 0;
  @State private sessionSnapshot?: SessionState = undefined;
  @State private themeMode: AppThemeMode = AppThemeMode.SYSTEM;
  /** 回答页双击正文动作（对齐上游 answerDoubleTapAction）：AppStorage 广播与详情页双向同步。 */
  @StorageProp('answerDoubleTapAction') private answerDoubleTapAction: AnswerDoubleTapAction =
    AnswerDoubleTapAction.ASK;
  /** 回答/文章详情页沉浸式阅读中（页面广播）：隐藏 NavDestination 顶栏（对齐上游 topBar={}）。 */
  @StorageProp('detailImmersiveActive') private detailImmersiveActive: boolean = false;
  @StorageProp('detailTitleHiddenByScroll') private detailTitleHiddenByScroll: boolean = false;
  /** 正文发布的回答标题状态，以固定路由 ID 读取。 */
  @StorageProp('answerTitleStates') private answerTitleStates: AnswerTitleState[] = [];
  /** 连续阅读页问题标题（页面加载后广播；空串显示占位标题）。 */
  @StorageProp('continuousAnswerTitles') private continuousAnswerTitles: Array<ContinuousAnswerTitleState> = [];
  @StorageProp('peopleTitleStates') private peopleTitleStates: PeopleTitleState[] = [];
  @StorageProp('commentTitleStates') private commentTitleStates: CommentTitleState[] = [];
  /** 全屏图片查看器打开中（详情页广播）：同样隐藏顶栏，使查看器真全屏。 */
  @StorageProp('imagePreviewUrl') private imagePreviewUrl: string = '';
  /** 设置宿主广播的顶栏状态：标题、当前是否处于二级页、二级页是否注册了“更多”动作。 */
  @StorageProp('settingsHomeTitle') private settingsHomeTitle: string = '设置';
  @StorageProp('settingsHomeDetailBackActive') private settingsHomeDetailBackActive: boolean = false;
  @StorageProp('settingsHomeActionsAvailable') private settingsHomeActionsAvailable: boolean = false;
  @State private installedVersionLabel: string = '正在读取已安装版本…';
  @State private aboutVersionSheetShown: boolean = false;
  @State private developerModeEnabled: boolean = false;
  @State private versionTapCount: number = 0;
  /** GitHub 最新 Release 检出有新版本时非空：驱动“我的”页横幅与版本弹层下载入口。 */
  @State private pendingUpdateRelease: AppUpdateRelease | undefined = undefined;
  @State private latestUpdateRelease: AppUpdateRelease | undefined = undefined;
  @State private updateCheckBusy: boolean = false;
  @State private updateCheckMessage: string = '';
  private installedVersionName: string = '';
  private readonly updateClient: AppUpdateClient = new AppUpdateClient();
  /** 本次启动是否已送达深链等启动目标：有则不叠加“新版本更新”页。 */
  private startupDestinationArrived: boolean = false;
  @State private projectLicenseSheetShown: boolean = false;
  @State private openSourceLicensesSheetShown: boolean = false;
  @State private projectHomeHelpShown: boolean = false;
  @State private projectHomeLaunchStatus: string = '';
  @State private accountLogoutBusy: boolean = false;
  @State private homeReloadToken: number = 0;
  @State private followingReloadToken: number = 0;
  @State private hotReloadToken: number = 0;
  @State private dailyReloadToken: number = 0;
  // 关注页子页签（推荐/动态）当前选中项：经 AppStorage 与关注页 Swiper 双向同步
  // （标题栏点选写 tick，关注页滑动写 index），@Consume 在 HdsTabs 树下实测不链接。
  @StorageProp('followingSelectedTabIndex') @Watch('refreshTabScrollerBindings')
  private followingTitleSelectedIndex: number = 0;
  @StorageProp('dailyViewingDate') private dailyViewingDate: string = '';
  // 每个页签各有一套 HdsNavigation 顶栏，只绑定该页签自己的滚动容器：
  // 滚动模糊状态因此按页签隔离，切页签不会继承上一页的模糊。
  // 页签页登记容器后经 AppStorage 广播，这里重算各页签的绑定。
  @StorageProp('topLevelScrollableTick') @Watch('refreshTabScrollerBindings')
  private topLevelScrollableTick: number = 0;
  @State private tabScrollerBindings: Map<number, Array<Scroller>> = new Map<number, Array<Scroller>>();
  @State private dailyDateCursor: string = '';
  @Provide('channelFeedInteractionBridge') private channelFeedInteractionBridge: ChannelFeedInteractionBridge =
    new ChannelFeedInteractionBridge();
  @State @Watch('onTopLevelTabIndexChanged') private topLevelTabIndex: number = TopLevelTab.HOME;
  @State private bottomBarOrder: number[] = [TopLevelTab.HOME, TopLevelTab.FOLLOWING,
    TopLevelTab.HOT, TopLevelTab.DAILY, TopLevelTab.ACCOUNT];
  @StorageProp('bottomBarItems') @Watch('onBottomBarItemsChanged') private bottomBarItems: string =
    'Home,Following,Hot,Daily,Settings';
  @StorageProp('tapToRefresh') private tapToRefresh: boolean = true;
  /** 当前生效主题色（启动时广播，深浅色已解析），驱动全壳强调色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 状态栏时间/电量颜色（SystemBars 按主题广播），供 HdsNavigation.systemBarStyle 使用：
   * 导航转场由系统按栈顶页面应用并还原，避免详情页退出后图标色残留为白色。 */
  @StorageProp('systemBarContentColor') private systemBarContentColor: string = '#000000';
  /** 主题色 seed：设置页选择/拖动时写入，@Watch 重新解析生效色并广播（否则换色不生效）。 */
  @StorageProp('themeColor') @Watch('onThemeColorSeedChanged') private themeColorSeed: string =
    DEFAULT_THEME_COLOR;
  /** 沉浸光感挡位（用户选择，字符串为 ImmersiveMaterialMode 存储值）与设备能力三态：
   * 标题栏样式函数经本组件传入响应式值（函数内 AppStorage.get 不建立更新依赖）。 */
  @StorageProp('immersiveMaterialLevel') private immersiveMaterialLevel: string =
    DEFAULT_IMMERSIVE_MATERIAL_MODE;
  @StorageProp('immersiveMaterialSupport') private immersiveMaterialSupport: string =
    ImmersiveMaterialSupportState.UNKNOWN;
  private startDestinationApplied: boolean = false;
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  @Provide('appPathStack') pathStack: NavPathStack = new NavPathStack();
  private unsubscribeStartupDestination: (() => void) | undefined = undefined;
  private readonly themeOperationGuard: LatestOperationGuard = new LatestOperationGuard();
  private readonly themeColorOperationGuard: LatestOperationGuard = new LatestOperationGuard();
  private themeMounted: boolean = false;
  private themeSaveQueue: Promise<void> = Promise.resolve();
  /** 沉浸光感偏好唯一写入入口（aboutToAppear 创建）：复用 store 串行 saveQueue，
   * 快速切换最终保存最后一次选择；设置页退出后由本组件继续完成保存。 */
  private immersiveMaterialStore: AppPreferencesStore | undefined = undefined;
  /** “我的”页滚动容器：同样登记给根 HdsNavigation，滚动时顶栏才会出模糊。 */
  private readonly settingsScroller: Scroller = new Scroller();

  /** 某页签自己的滚动容器标识（关注页按当前子页签取推荐/动态）。 */
  private scrollKeysForTab(tab: number): string[] {
    if (tab === TopLevelTab.HOME) {
      return [HOME_FEED_SCROLL_KEY];
    }
    if (tab === TopLevelTab.FOLLOWING) {
      return [this.followingTitleSelectedIndex === 0
        ? ChannelFeedSource.FOLLOWING_RECOMMEND : ChannelFeedSource.FOLLOWING];
    }
    if (tab === TopLevelTab.HOT) {
      return [ChannelFeedSource.HOT];
    }
    if (tab === TopLevelTab.DAILY) {
      return [ChannelFeedSource.DAILY];
    }
    if (tab === TopLevelTab.ACCOUNT) {
      return [SETTINGS_SCROLL_KEY];
    }
    return [];
  }

  /** 重算各页签的滚动容器绑定：只取已挂到组件上的容器（Scroller 未挂载时
   * 绑定拿不到偏移，订阅会丢），未登记的页签保持空绑定，等容器 onAppear 再登记。 */
  private refreshTabScrollerBindings(): void {
    const tabs: number[] = [TopLevelTab.HOME, TopLevelTab.FOLLOWING, TopLevelTab.HOT,
      TopLevelTab.DAILY, TopLevelTab.HISTORY, TopLevelTab.COLLECTIONS, TopLevelTab.ACCOUNT];
    const next: Map<number, Array<Scroller>> = new Map<number, Array<Scroller>>();
    tabs.forEach((tab: number): void => {
      const mounted: Array<Scroller> = topLevelScrollRegistry.scrollersFor(this.scrollKeysForTab(tab))
        .filter((scroller: Scroller): boolean => scroller.currentOffset() !== undefined);
      if (mounted.length > 0) {
        next.set(tab, mounted);
      }
    });
    this.tabScrollerBindings = next;
    this.broadcastBottomBarScrollOwner();
  }

  private tabScrollerBinding(tab: number): Array<Scroller> {
    const binding: Array<Scroller> | undefined = this.tabScrollerBindings.get(tab);
    return binding === undefined ? [] : binding;
  }

  aboutToAppear(): void {
    this.themeMounted = true;
    topLevelScrollRegistry.register(SETTINGS_SCROLL_KEY, this.settingsScroller);
    this.refreshTabScrollerBindings();
    // 主题恢复完成前先按跟随系统广播（EntryAbility.onConfigurationUpdate 依赖该键判断是否联动公式换色）。
    AppStorage.setOrCreate('appThemeMode', AppThemeMode.SYSTEM);
    AppStorage.setOrCreate('formulaForegroundColor', this.resolveFormulaForegroundColor(AppThemeMode.SYSTEM));
    AppStorage.setOrCreate('appearanceThemeTick', AppStorage.get<number>('appearanceThemeTick') ?? 0);
    // 主题色恢复前先广播默认 seed 与按当前模式解析的生效色，保证组件挂载即有值。
    AppStorage.setOrCreate('themeColor', DEFAULT_THEME_COLOR);
    AppStorage.setOrCreate('resolvedThemeColor', this.resolveThemeColorForMode(AppThemeMode.SYSTEM, DEFAULT_THEME_COLOR));
    // 沉浸光感：先广播默认挡位与能力三态（组件挂载即有值），就绪前设置控件不可操作；
    // 异步读取持久化值后再次发布（初始化广播与用户变更经就绪状态区分，恢复不触发保存）。
    const immersiveContext = getAbilityContext();
    this.immersiveMaterialStore = immersiveContext === undefined
      ? undefined : new AppPreferencesStore(immersiveContext);
    AppStorage.setOrCreate('immersiveMaterialLevel', DEFAULT_IMMERSIVE_MATERIAL_MODE);
    AppStorage.setOrCreate('immersiveMaterialSupport', HarmonyOSCapabilities.immersiveMaterialSupportState());
    AppStorage.setOrCreate('immersiveMaterialNotice', '');
    AppStorage.setOrCreate('immersiveMaterialPreferencesReady', false);
    // 开发者选项可见性经 AppStorage 广播，设置首页/搜索索引在页面挂载后也能同步。
    AppStorage.setOrCreate('developerModeEnabled', false);
    this.sessionSnapshot = this.session?.getState();
    this.restoreThemeMode();
    void this.restoreThemeColor();
    void this.restoreAnswerDoubleTapAction();
    void this.restoreReaderTypography();
    void this.restoreAppearancePreferences();
    void this.restoreExperiencePreferences();
    void this.restoreImmersiveMaterialLevel();
    void this.restoreDeveloperMode();
    void this.restoreAnswerReadingMode();
    void this.restoreDailyStoryReaderMode();
    this.refreshInstalledVersionLabel();
    this.unsubscribeStartupDestination?.();
    const listener: StartupDestinationListener = (destination: AppDestination): void => {
      this.startupDestinationArrived = true;
      this.navigate(destination);
    };
    this.unsubscribeStartupDestination = startupDestinationChannel.subscribe(listener);
    // 诊断：输出当前设备支持的沉浸材质类型（含 IMMERSIVE 即支持沉浸光感流动光效）。
    hilog.info(0x0000, 'ImmersiveLight', 'systemMaterialTypes=%{public}s',
      JSON.stringify(hdsMaterial.getSystemMaterialTypes()));
    // 版本更迭后首次启动展示“新版本更新”页；本次启动带深链目标时让位，不叠加弹页。
    void this.evaluateWhatsNewOnLaunch();
    // 每次启动静默检查 GitHub 最新 Release；失败不打扰，检出新版本时在“我的”页提示。
    void this.runUpdateCheck(false);
  }

  aboutToDisappear(): void {
    this.themeMounted = false;
    this.themeOperationGuard.invalidate();
    this.themeColorOperationGuard.invalidate();
    this.unsubscribeStartupDestination?.();
    this.unsubscribeStartupDestination = undefined;
  }

  @Builder
  emptyHome(_navigate: (destination: AppDestination) => void) {
    Blank();
  }

  @Builder
  emptyNotificationSettings(_navigate: (destination: AppDestination) => void, _embedded: boolean) {
    Blank();
  }

  @Builder
  emptyNotificationEntry(_entryName: string, _title: string, _navigate: (destination: AppDestination) => void) {
    Blank();
  }

  @Builder
  emptyPrivateMessage(_peerId: string, _peerName: string, _avatarUrl: string, _navigate: (destination: AppDestination) => void) {
    Blank();
  }

  @Builder
  emptyReloadableHome(_reloadToken: number, _navigate: (destination: AppDestination) => void,
    _selectedTabIndex: number = 0) {
    Blank();
  }

  @Builder
  emptyReloadableDaily(_reloadToken: number, _dateCursor: string,
    _navigate: (destination: AppDestination) => void) {
    Blank();
  }

  @Builder
  emptyTechnicalLab(_navigate: (destination: AppDestination) => void, _onDeveloperModeDisabled: () => void,
    _embedded: boolean) {
    Blank();
  }

  @Builder
  emptyEmbeddedPage(_onBack: () => void, _embedded: boolean,
    _registerActions: (handler: () => void) => void, _releaseActions: () => void) {
    Blank();
  }

  @Builder
  emptySearch(_query: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyComment(_destination: AppDestination,
    _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyContent(_id: string, _navigate: (destination: AppDestination) => void) {
    Blank();
  }

  @Builder
  emptyDetailContent(_id: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPinContent(_id: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyWriteAnswer(_questionId: string, _answerId: string | undefined,
    _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyWritePin(_draftId: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPinDraftInbox(_navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyCollections(_id: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyCollectionContent(_id: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPeople(_id: string, _navigate: (destination: AppDestination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPage() {
    Blank();
  }

  @Builder
  emptyProbe(_onBack: () => void) {
    Blank();
  }

  /** 连续阅读页固定问题标题：点击进入问题页（计划 §2.1）；标题由页面异步广播。 */
  @Builder
  continuousAnswerTitleBar(questionId: string, answerId: string, sort: string) {
    // 与问题详情页一致：返回键与标题在同一 Row 中分配空间，隐藏外层 HDS 默认返回键。
    Row({ space: 8 }) {
      // 复用回答详情页的 HDS 玻璃画布；不支持沉浸材质时使用主题中性底色。
      Stack({ alignContent: Alignment.Center }) {
        if (this.supportsImmersiveMaterial()) {
          materialCanvas(52, 52)
        }
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('continuous_answer_back')
        .width(40)
        .height(40)
        .padding(0)
        .borderRadius(20)
        .backgroundColor(this.supportsImmersiveMaterial()
          ? Color.Transparent : $r('app.color.surface_background'))
        .accessibilityText('返回')
        .onClick((): void => { this.pathStack.pop(); })
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .clip(true)
      Text(continuousAnswerTitle(this.continuousAnswerTitles,
        continuousAnswerRouteId(questionId, answerId, sort)) || '连续阅读')
        .id('continuous_answer_title')
        .fontSize($r('app.float.heading_font_size'))
        .maxFontScale(1.3)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .height(40)
        .clip(true)
        .onClick((): void => {
          this.navigate({ name: AppDestinationName.QUESTION, id: questionId });
        })
        .accessibilityText('查看问题详情')
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
  }

  @Builder
  emptyLogin(_onBack: () => void, _onAuthenticated: () => void, _onScanDesktopLogin: () => void) {
    Blank();
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    this.destinationContent(decodeAppDestination(name, param));
  }

  @Builder
  private destinationContent(destination: AppDestination | undefined) {
    if (destination === undefined) {
      HdsNavDestination() {
        this.invalidDestinationPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '无法打开页面' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.SETTINGS) {
      HdsNavDestination() {
        this.accountPageContent();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '我的' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.SETTINGS_HOME) {
      HdsNavDestination() {
        this.settingsHomePageContent();
      }
      // 目录与二级页共用一条沉浸光感顶栏，返回键由 HDS backIcon 统一承载。
      .titleBar({
        style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()),
        avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => this.settingsTitleBar(),
          backIcon: {
            componentId: 'settings_detail_back',
            label: this.settingsHomeDetailBackActive ? '返回上一级设置' : '返回我的',
            action: (): void => this.onSettingsTitleBack()
          },
          divider: { showType: DividerShowType.OFF }
        }
      })
      .onBackPressed((): boolean => this.handleSettingsHomeBack())
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.ABOUT_APP) {
      HdsNavDestination() {
        this.aboutAppPageContent(false);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '关于应用' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.APPEARANCE_SETTINGS) {
      HdsNavDestination() {
        this.appearanceSettingsContent(false,
          (): void => this.navigate({ name: AppDestinationName.THEME_COLOR_SETTINGS }));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '外观与阅读体验' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.THEME_COLOR_SETTINGS) {
      HdsNavDestination() {
        ThemeColorSettingsPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '主题颜色' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.IDENTITY_MANAGEMENT) {
      HdsNavDestination() {
        IdentityManagementPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '身份管理' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.READING_SETTINGS) {
      HdsNavDestination() {
        this.readingSettingsContent(false);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '朗读与播放' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.SYSTEM_UPDATE_SETTINGS) {
      HdsNavDestination() {
        this.systemUpdateSettingsContent(false);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '系统与更新' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.WHATS_NEW) {
      HdsNavDestination() {
        WhatsNewPage({
          targetVersionName: destination.version ?? '',
          onClosed: (shownVersionName: string): void => this.markWhatsNewSeen(shownVersionName),
          onOpenLink: (url: string): void => this.openExternalUrl(url, '无法打开链接'),
          onOpenDownload: (): void => this.navigate({ name: AppDestinationName.SYSTEM_UPDATE_SETTINGS })
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: {
          title: { mainTitle: destination.version !== undefined ? '新版本描述' : '本版本更新内容' },
          divider: { showType: DividerShowType.OFF }
        } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.RECOMMENDATION_FILTER_SETTINGS) {
      HdsNavDestination() {
        this.filterSettingsContent(false,
          (): void => this.navigate({ name: AppDestinationName.BLOCKING_RULES }),
          (): void => this.navigate({ name: AppDestinationName.BLOCKED_FEED_HISTORY }));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '推荐系统与内容过滤' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.BLOCKING_RULES) {
      HdsNavDestination() {
        this.blockingRulesContent((): void => {
          this.pathStack.pop();
        }, false, (): void => {}, (): void => {});
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '内容屏蔽' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.BLOCKED_FEED_HISTORY) {
      HdsNavDestination() {
        this.blockedFeedHistoryContent((): void => {
          this.pathStack.pop();
        }, false, (): void => {}, (): void => {});
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '屏蔽记录' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.READ_HISTORY) {
      HdsNavDestination() {
        this.readHistoryContent((nextDestination: AppDestination): void => this.navigate(nextDestination), (): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({
        style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()),
        avoidLayoutSafeArea: true,
        // 返回键用 HDS 标题栏自带 backIcon，右上角选项菜单由 stackBuilder 注入（同搜索页模式）。
        content: {
          stackBuilder: (): void => this.readHistoryTitleBar(),
          backIcon: { action: (): void => { this.pathStack.pop(); } },
          divider: { showType: DividerShowType.OFF }
        }
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.LOCAL_HISTORY) {
      HdsNavDestination() {
        this.localHistoryContent((nextDestination: AppDestination): void => this.navigate(nextDestination),
          (): void => {
            this.pathStack.pop();
          });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '本地历史记录' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.TECHNICAL_LAB) {
      HdsNavDestination() {
        this.technicalLabContent((destination: AppDestination): void => this.navigate(destination), (): void => {
          this.disableDeveloperMode();
        }, false);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '开发者选项' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.LOGIN) {
      HdsNavDestination() {
        this.loginContent((): void => {
          this.pathStack.pop();
        }, (): void => {
          this.returnFromSuccessfulLogin();
        }, (): void => {
          this.navigate({ name: AppDestinationName.QR_DESKTOP_LOGIN_SCAN });
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '登录' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.SEARCH) {
      HdsNavDestination() {
        this.searchContent(
          destination.query,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({
        style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()),
        avoidLayoutSafeArea: true,
        // 返回键用 HDS 标题栏自带 backIcon（自定义 action 接管），避免与 stackBuilder 内自绘返回键重叠。
        content: {
          stackBuilder: (): void => this.searchTitleBar(),
          backIcon: { action: (): void => { this.pathStack.pop(); } },
          divider: { showType: DividerShowType.OFF }
        }
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.COMMENT) {
      HdsNavDestination() {
        this.commentContent(
          destination,
          (nextDestination: AppDestination): void => this.navigate(nextDestination),
          (): void => { this.pathStack.pop(); }
        );
      }
      .titleBar({
        style: getPersistentImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()),
        avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => this.commentTitleBar(destination.contentType, destination.contentId),
          divider: { showType: DividerShowType.OFF }
        }
      })
      .hideBackButton(true)
      .hideTitleBar(this.commentTitleStates.find((state: CommentTitleState): boolean =>
        state.id === commentTitleStateId(destination.contentType, destination.contentId))?.previewing ?? false)
      .onBackPressed((): boolean => {
        this.requestCommentPageBack(destination.contentType, destination.contentId);
        return true;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.FOLLOWING) {
      HdsNavDestination() {
        this.followingContent(this.followingReloadToken,
          (destination: AppDestination): void => this.navigate(destination),
          this.followingTitleSelectedIndex);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '关注' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.HOT) {
      HdsNavDestination() {
        this.hotContent(this.hotReloadToken, (destination: AppDestination): void => this.navigate(destination));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '热榜' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(false)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.DAILY) {
      HdsNavDestination() {
        this.dailyContent(this.dailyReloadToken, this.dailyDateCursor,
          (destination: AppDestination): void => this.navigate(destination));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '知乎日报' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(false)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.DAILY_STORY) {
      HdsNavDestination() {
        this.dailyStoryContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination)
        );
      }
      // 同问题/文章页：沉浸顶栏（静止透明、滚动出模糊），内容延伸到顶栏之后。
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '知乎日报' }, divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(false)
      .hideTitleBar(this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('imagePreviewUrl', '');
          return true;
        }
        return false;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.QUESTION) {
      HdsNavDestination() {
        this.questionContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      // 与首页/我的/设置等信息流页同一套沉浸顶栏：静止透明、滚动出渐变模糊，
      // 避免详情页用常驻半透明底时在顶栏下沿形成一条"挡"住正文的实边。
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.questionTitleBar(destination.id), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
      // 问题页正文图片同样可打开全屏查看器：隐藏顶栏，返回键优先关查看器。
      .hideTitleBar(this.detailImmersiveActive || this.detailTitleHiddenByScroll || this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('imagePreviewUrl', '');
          return true;
        }
        if (this.detailImmersiveActive) {
          AppStorage.setOrCreate('detailImmersiveExitTick',
            (AppStorage.get<number>('detailImmersiveExitTick') ?? 0) + 1);
          return true;
        }
        return false;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.ANSWER) {
      HdsNavDestination() {
        this.answerContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .onShown((): void => this.setReaderRouteVisible('answer', destination.id, true))
      .onHidden((): void => this.setReaderRouteVisible('answer', destination.id, false))
      // Native 列表显式广播材质态，避免 HDS 无法观察候选树内滚动而发生正文压字。
      .titleBar({ style: getAnswerTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState(),
        this.answerTitleStates.find((state: AnswerTitleState): boolean => state.id === destination.id)?.materialVisible ?? false), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.answerTitleBar(destination.id), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
      // 沉浸式/图片查看器中隐藏顶栏（对齐上游 topBar={}）；返回键优先关查看器、再退沉浸式。
      // 回答切换过滑（纵向/横向）顶栏都保持不动，相邻回答整页从顶栏下方滑入。
      .hideTitleBar(this.detailImmersiveActive || this.detailTitleHiddenByScroll ||
        this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('imagePreviewUrl', '');
          return true;
        }
        if (this.detailImmersiveActive) {
          AppStorage.setOrCreate('detailImmersiveExitTick',
            (AppStorage.get<number>('detailImmersiveExitTick') ?? 0) + 1);
          return true;
        }
        return false;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.ARTICLE) {
      HdsNavDestination() {
        this.articleContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .onShown((): void => this.setReaderRouteVisible('article', destination.id, true))
      .onHidden((): void => this.setReaderRouteVisible('article', destination.id, false))
      // 同问题/回答页：走与设置/首页一致的沉浸顶栏。
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.articleTitleBar(destination.id), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
      // 与回答页一致：沉浸式/图片查看器中隐藏顶栏，返回键优先关查看器。
      .hideTitleBar(this.detailImmersiveActive || this.detailTitleHiddenByScroll || this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('imagePreviewUrl', '');
          return true;
        }
        if (this.detailImmersiveActive) {
          AppStorage.setOrCreate('detailImmersiveExitTick',
            (AppStorage.get<number>('detailImmersiveExitTick') ?? 0) + 1);
          return true;
        }
        return false;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.VIDEO) {
      HdsNavDestination() {
        this.videoContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '视频' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.WRITE_ANSWER) {
      HdsNavDestination() {
        this.writeAnswerContent(
          destination.questionId,
          destination.answerId,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '写回答' }, divider: { showType: DividerShowType.OFF } } })
      // 页面自带返回键/标题/发布按钮的完整头部，注入标题栏会与之重叠（同视频页先例）。
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.WRITE_PIN) {
      HdsNavDestination() {
        this.writePinContent(
          destination.draftId,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '发布想法' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.PIN_DRAFTS) {
      HdsNavDestination() {
        this.pinDraftInboxContent(
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '想法草稿' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.PEOPLE) {
      HdsNavDestination() {
        this.peopleContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: peopleTitleText(this.peopleTitleStates, destination.id) },
          divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.PIN) {
      HdsNavDestination() {
        this.pinContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '想法' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.COLLECTIONS) {
      HdsNavDestination() {
        this.collectionsContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '收藏夹' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.COLLECTION) {
      HdsNavDestination() {
        this.collectionContentContent(
          destination.id,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '收藏夹内容' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.NOTIFICATION) {
      HdsNavDestination() {
        this.notificationContent(
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .onShown((): void => {
        const tick = AppStorage.get<number>(NOTIFICATION_HUB_REFRESH_TICK_KEY) ?? 0;
        AppStorage.setOrCreate(NOTIFICATION_HUB_REFRESH_TICK_KEY, tick + 1);
      })
      // 消息中心标题栏对齐上游：标题「消息」+ 右上角已读/设置动作（同搜索页 stackBuilder 模式）。
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => this.notificationTitleBar(),
          backIcon: { action: (): void => { this.pathStack.pop(); } },
          divider: { showType: DividerShowType.OFF }
        }
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.NOTIFICATION_ENTRY) {
      HdsNavDestination() {
        this.notificationEntryContent(
          (destination as NotificationEntryDestination).entryName,
          (destination as NotificationEntryDestination).title,
          (destination: AppDestination): void => this.navigate(destination)
        );
      }
      .onShown((): void => {
        AppStorage.setOrCreate(NOTIFICATION_TIMELINE_ENTRY_KEY,
          (destination as NotificationEntryDestination).entryName);
        const tick = AppStorage.get<number>(NOTIFICATION_TIMELINE_REFRESH_TICK_KEY) ?? 0;
        AppStorage.setOrCreate(NOTIFICATION_TIMELINE_REFRESH_TICK_KEY, tick + 1);
      })
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: (destination as NotificationEntryDestination).title },
          divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.PRIVATE_MESSAGE) {
      HdsNavDestination() {
        this.privateMessageContent(
          (destination as PrivateMessageDestination).peerId,
          (destination as PrivateMessageDestination).peerName ?? '',
          (destination as PrivateMessageDestination).avatarUrl ?? '',
          (destination: AppDestination): void => this.navigate(destination)
        );
      }
      // 私信为聊天页：首帧列表就定位到末尾，消息会落在标题栏下方；
      // 用不透明页面底色的顶栏，避免消息正文与标题叠字（见 NavStyles.getChatTitleBarStyle）。
      .titleBar({ style: getChatTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle:
          ((destination as PrivateMessageDestination).peerName ?? '').length > 0
            ? ((destination as PrivateMessageDestination).peerName as string) : '私信' },
          divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.NOTIFICATION_SETTINGS) {
      HdsNavDestination() {
        this.notificationSettingsContent((destination: AppDestination): void => this.navigate(destination), false);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '通知设置' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.READER_PROBE) {
      HdsNavDestination() {
        this.readerProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '阅读器诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.IMAGE_PROBE) {
      HdsNavDestination() {
        this.imageProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '图片诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.CONTINUOUS_READING_PROTOTYPE) {
      HdsNavDestination() {
        this.continuousReadingProtoContent((): void => {
          this.pathStack.pop();
        });
      }
      // 原型页自带控制栏与状态行：用不透明标题栏让正文排在标题栏下方（聊天页先例），
      // 避免沉浸悬浮标题栏压住页顶控件（whats-new 页已踩过同类坑）。
      .titleBar({ style: getChatTitleBarStyle(),
        content: { title: { mainTitle: '连续阅读原型' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.CONTINUOUS_ANSWER) {
      HdsNavDestination() {
        this.continuousAnswerContent(
          (destination as ContinuousAnswerDestination).questionId,
          (destination as ContinuousAnswerDestination).answerId,
          (destination as ContinuousAnswerDestination).sort,
          (destination: AppDestination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      // API 26 沿用回答详情页材质，API 23 由页面承载渐变模糊，避免 HDS 背板硬切正文。
      .titleBar({ style: getContinuousAnswerTitleBarStyle(
        this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => this.continuousAnswerTitleBar(
            (destination as ContinuousAnswerDestination).questionId,
            (destination as ContinuousAnswerDestination).answerId ?? '',
            (destination as ContinuousAnswerDestination).sort ?? 'default'),
          divider: { showType: DividerShowType.OFF }
        } })
      .hideBackButton(true)
      .hideTitleBar(this.imagePreviewUrl.length > 0 || this.detailImmersiveActive)
      .onShown((): void => {
        AppStorage.setOrCreate('continuousAnswerActiveRoute', continuousAnswerRouteId(
          (destination as ContinuousAnswerDestination).questionId,
          (destination as ContinuousAnswerDestination).answerId ?? '',
          (destination as ContinuousAnswerDestination).sort ?? 'default'));
      })
      .onHidden((): void => {
        if (AppStorage.get<string>('continuousAnswerActiveRoute') === continuousAnswerRouteId(
          (destination as ContinuousAnswerDestination).questionId,
          (destination as ContinuousAnswerDestination).answerId ?? '',
          (destination as ContinuousAnswerDestination).sort ?? 'default')) {
          AppStorage.setOrCreate('continuousAnswerActiveRoute', '');
        }
      })
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('imagePreviewUrl', '');
          return true;
        }
        // 沉浸阅读中先退出沉浸（对齐回答/文章页交互），再次返回才离页。
        if (this.detailImmersiveActive) {
          AppStorage.setOrCreate('detailImmersiveExitTick',
            (AppStorage.get<number>('detailImmersiveExitTick') ?? 0) + 1);
          return true;
        }
        return false;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.DATABASE_PROBE) {
      HdsNavDestination() {
        this.databaseProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '数据库诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.DEEP_LINK_PROBE) {
      HdsNavDestination() {
        this.deepLinkProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '深链诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.QR_SCAN_PROBE) {
      HdsNavDestination() {
        this.qrScanProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '二维码诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.QR_DESKTOP_LOGIN_SCAN) {
      HdsNavDestination() {
        this.qrDesktopLoginScanContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true, content: { title: { mainTitle: '扫描电脑端登录码' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.BACKGROUND_TASK_PROBE) {
      HdsNavDestination() {
        this.backgroundTaskProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '后台任务诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === AppDestinationName.DOMAIN_FIXTURE_PROBE) {
      HdsNavDestination() {
        this.domainFixtureProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '领域数据诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else {
      HdsNavDestination() {
        this.businessPlaceholder(destination);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(this.immersiveMaterialMode(), this.immersiveMaterialSupportState()), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: destination.name }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    }
  }

  build() {
    Stack() {
      HdsNavigation(this.pathStack) {
        ZhihuHdsTabs({
          currentIndex: $topLevelTabIndex,
          controller: this.tabsController,
          onTabDoubleTap: (index: number): void => {
            // 双击页签刷新对应 feed（“我的”除外）；跨页面信号经 AppStorage 广播。
            // 先广播回到顶部、再广播刷新：滑动数据时双击也按“先回顶 → 再刷新”执行。
            const tab = this.tabAtDisplayIndex(index);
            if (tab < TopLevelTab.HOME || tab > TopLevelTab.DAILY) {
              return;
            }
            AppStorage.setOrCreate('tabScrollTopTabIndex', tab);
            AppStorage.setOrCreate('tabScrollTopTick', (AppStorage.get<number>('tabScrollTopTick') ?? 0) + 1);
            // 先写目标页签再自增 tick：@Watch 在 tick 写入时同步触发，顺序反了会读到上一次的目标页签。
            AppStorage.setOrCreate('tabRefreshTabIndex', tab);
            const nextTick = (AppStorage.get<number>('tabRefreshTick') ?? 0) + 1;
            AppStorage.setOrCreate('tabRefreshTick', nextTick);
          },
          onCurrentTabTap: (index: number): void => {
            const tab = this.tabAtDisplayIndex(index);
            if (!this.tapToRefresh || tab < TopLevelTab.HOME || tab > TopLevelTab.DAILY) {
              return;
            }
            AppStorage.setOrCreate('tabScrollTopTabIndex', tab);
            AppStorage.setOrCreate('tabScrollTopTick', (AppStorage.get<number>('tabScrollTopTick') ?? 0) + 1);
          }
        }) {
          // 页签必须经 ForEach（key=tab 值）生成：@Builder 按值传参在 HdsTabs 的
          // TabContent 构建树下不会触发已挂载子组件更新，写死槽位会让“底部栏项目与顺序”
          // 实时变更后 TabContent 属性（id/tabBar）刷新但内容仍是旧顺序的页面。
          ForEach(this.bottomBarOrder, (tab: number): void => {
            TabContent() {
              // 每个页签一套独立 HdsNavigation 顶栏：滚动模糊状态跟着自己的容器走，
              // 互不继承（对齐华为原生应用的分页表现）。
              HdsNavigation() {
                this.topLevelTabPage(tab as TopLevelTab)
              }
              .titleBar({
                // 对齐华为原生应用的沉浸光感标题栏：支持 IMMERSIVE 材质的设备走材质 + 渐变模糊，
                // 不支持的设备（含模拟器）降级为均匀模糊 + 半透明底；两条路径让位一致。
                style: getRootChromeTitleBarStyle(this.immersiveMaterialMode(),
                  this.immersiveMaterialSupportState()),
                avoidLayoutSafeArea: true,
                content: {
                  stackBuilder: (): void => this.rootTitleBarContent(),
                  divider: { showType: DividerShowType.OFF }
                }
              })
              .titleMode(HdsNavigationTitleMode.MINI)
              .hideBackButton(true)
              // “我的”页不再使用顶部标题栏：设置入口移入页面内容（“扫码登录电脑端”下方）。
              .hideTitleBar((tab as TopLevelTab) === TopLevelTab.ACCOUNT)
              .mode(NavigationMode.Stack)
              .monopolizeEvents(false)
              // 只绑定本页签自己的滚动容器（未挂载时为空，容器 onAppear 登记后补上）。
              .bindToScrollable(this.tabScrollerBinding(tab))
              .backgroundColor($r('app.color.page_background'))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              // 顶栏透明后模糊层只跟随标题栏自身区域；TOP 也纳入 ignoreLayoutSafeArea 后，
              // 模糊才继续铺到状态栏区域（官方问答口径），否则状态栏那段内容不模糊。
              .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
                [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
              .systemBarStyle({ statusBarContentColor: this.systemBarContentColor },
                { statusBarContentColor: this.systemBarContentColor })
            }
            .id(`top_level_${this.tabKey(tab as TopLevelTab)}_content`)
            .tabBar(this.topLevelTabBarStyle(tab as TopLevelTab))
          }, (tab: number): string => `${tab}`)
        }
      }
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .monopolizeEvents(false)
      .navDestination(this.destinationBuilder)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .systemBarStyle({ statusBarContentColor: this.systemBarContentColor },
        { statusBarContentColor: this.systemBarContentColor })

      // 弹层统一挂在根壳上，任何页面触发版本/许可/项目主页说明都能弹出，
      // 不依赖“我的”页或某一个 NavDestination 是否仍在前台。
      Column()
        .bindSheet(this.aboutVersionSheetShown, this.aboutVersionSheet(), {
          preferType: SheetType.CENTER,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.aboutVersionSheetShown) {
              this.aboutVersionSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.projectLicenseSheetShown, this.projectLicenseSheet(), {
          preferType: SheetType.CENTER,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.projectLicenseSheetShown) {
              this.projectLicenseSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.openSourceLicensesSheetShown, this.openSourceLicensesSheet(), {
          preferType: SheetType.CENTER,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.openSourceLicensesSheetShown) {
              this.openSourceLicensesSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.projectHomeHelpShown, this.projectHomeHelpSheet(), {
          preferType: SheetType.CENTER,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.projectHomeHelpShown) {
              this.projectHomeHelpShown = false;
            }
          }
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private topLevelTabPage(tab: TopLevelTab) {
    if (tab === TopLevelTab.HOME) {
      this.homeContent(this.homeReloadToken, (destination: AppDestination): void => this.navigate(destination))
    } else if (tab === TopLevelTab.FOLLOWING) {
      this.followingContent(this.followingReloadToken,
        (destination: AppDestination): void => this.navigate(destination), this.followingTitleSelectedIndex)
    } else if (tab === TopLevelTab.HOT) {
      this.hotContent(this.hotReloadToken, (destination: AppDestination): void => this.navigate(destination))
    } else if (tab === TopLevelTab.DAILY) {
      this.dailyContent(this.dailyReloadToken, this.dailyDateCursor,
        (destination: AppDestination): void => this.navigate(destination))
    } else if (tab === TopLevelTab.HISTORY) {
      this.readHistoryContent((destination: AppDestination): void => this.navigate(destination), (): void => {})
    } else if (tab === TopLevelTab.COLLECTIONS) {
      this.topLevelCollectionsPage()
    } else {
      this.accountPageContent()
    }
  }

  @Builder
  private topLevelCollectionsPage() {
    if (this.currentAccountIdentifier().length > 0) {
      this.collectionsContent(this.currentAccountIdentifier(),
        (destination: AppDestination): void => this.navigate(destination), (): void => {})
    } else {
      Column({ space: $r('app.float.spacing_medium') }) {
        Text('登录后查看收藏夹')
          .fontSize($r('app.float.heading_font_size'))
          .fontColor($r('app.color.primary_text'))
        Button('去登录').onClick((): void => this.navigate({ name: AppDestinationName.LOGIN }))
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    }
  }

  private topLevelTabBarStyle(tab: TopLevelTab): BottomTabBarStyle {
    // 图标语义直白优先：house/person_2/flame/doc_text/person（经系统符号表核实）。
    let icon: Resource = $r('sys.symbol.house');
    if (tab === TopLevelTab.FOLLOWING) {
      icon = $r('sys.symbol.person_2');
    } else if (tab === TopLevelTab.HOT) {
      icon = $r('sys.symbol.flame');
    } else if (tab === TopLevelTab.DAILY) {
      icon = $r('sys.symbol.doc_text');
    } else if (tab === TopLevelTab.HISTORY) {
      icon = $r('sys.symbol.clock');
    } else if (tab === TopLevelTab.COLLECTIONS) {
      icon = $r('sys.symbol.bookmark');
    } else if (tab === TopLevelTab.ACCOUNT) {
      icon = $r('sys.symbol.person');
    }

    const normal: SymbolGlyphModifier = new SymbolGlyphModifier(icon)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.secondary_text')]);
    const selected: SymbolGlyphModifier = new SymbolGlyphModifier(icon)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([this.resolvedThemeColor]);
    return BottomTabBarStyle.of({ normal, selected }, this.tabLabel(tab))
      .labelStyle({
        selectedColor: this.resolvedThemeColor,
        unselectedColor: $r('app.color.secondary_text')
      });
  }

  private tabLabel(tab: TopLevelTab): string {
    switch (tab) {
      case TopLevelTab.HOME:
        return '首页';
      case TopLevelTab.FOLLOWING:
        return '关注';
      case TopLevelTab.HOT:
        return '热榜';
      case TopLevelTab.DAILY:
        return '日报';
      case TopLevelTab.HISTORY:
        return '历史';
      case TopLevelTab.COLLECTIONS:
        return '收藏夹';
      case TopLevelTab.ACCOUNT:
        return '我的';
    }
  }

  private tabAtDisplayIndex(index: number): TopLevelTab {
    const value = this.bottomBarOrder[index];
    return value === undefined ? TopLevelTab.HOME : value as TopLevelTab;
  }

  private activeTopLevelTab(): TopLevelTab {
    return this.tabAtDisplayIndex(this.topLevelTabIndex);
  }

  private tabKey(tab: TopLevelTab): string {
    if (tab === TopLevelTab.FOLLOWING) return 'following';
    if (tab === TopLevelTab.HOT) return 'hot';
    if (tab === TopLevelTab.DAILY) return 'daily';
    if (tab === TopLevelTab.HISTORY) return 'history';
    if (tab === TopLevelTab.COLLECTIONS) return 'collections';
    if (tab === TopLevelTab.ACCOUNT) return 'account';
    return 'home';
  }

  private currentAccountIdentifier(): string {
    const profile = this.session?.getState().profile;
    return profile?.urlToken ?? profile?.id ?? '';
  }

  private supportsImmersiveMaterial(): boolean {
    try {
      return hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_error) {
      return false;
    }
  }

  /** 详情页 HDS 标题栏内容：返回键 + 页面标题（替代各详情页自绘页头，消除标题栏空置占位）。 */
  @Builder
  private questionTitleBar(id: string) {
    QuestionTitleBar({ questionId: id, onBack: (): void => { this.pathStack.pop(); } })
  }

  @Builder
  private commentTitleBar(contentType: string, contentId: string) {
    CommentTitleBar({
      stateId: commentTitleStateId(contentType, contentId),
      onBack: (): void => this.requestCommentPageBack(contentType, contentId)
    })
  }

  private requestCommentPageBack(contentType: string, contentId: string): void {
    AppStorage.setOrCreate('commentPageBackContentType', contentType);
    AppStorage.setOrCreate('commentPageBackContentId', contentId);
    AppStorage.setOrCreate('commentPageBackTick',
      (AppStorage.get<number>('commentPageBackTick') ?? 0) + 1);
  }

  /** 搜索页 HDS 标题栏内容：返回键 + 搜索框 + 排序方式菜单（对齐上游搜索顶栏）。 */
  @Builder
  private searchTitleBar() {
    SearchTitleBar()
  }

  /** 历史记录页 HDS 标题栏内容：标题 + 右上角溢出菜单（查看本地历史记录/清除历史记录）。 */
  @Builder
  private readHistoryTitleBar() {
    HistoryTitleBar()
  }

  /** 消息中心标题栏：标题「消息」+ 右上角已读/设置（对齐上游 CenterAlignedTopAppBar actions）。 */
  @Builder
  private notificationTitleBar() {
    NotificationTitleBar({ navigate: (destination: AppDestination): void => this.navigate(destination) })
  }

  /** 回答页标题栏：滚动折叠时在返回键右侧显示问题单行 + 答主摘要（对齐上游折叠顶栏）。
   * 标题可点击：推入该问题页查看全部回答。 */
  @Builder
  private answerTitleBar(id: string) {
    AnswerTitleBar({
      answerId: id,
      onBack: (): void => { this.pathStack.pop(); },
      onOpenQuestion: (questionId: string): void => {
        this.navigate({ name: AppDestinationName.QUESTION, id: questionId });
      }
    })
  }

  /** 文章页标题栏：滚动折叠时在返回键右侧显示文章标题单行（对齐问题页折叠模式）。 */
  @Builder
  private articleTitleBar(id: string) {
    ArticleTitleBar({ articleId: id, onBack: (): void => { this.pathStack.pop(); } })
  }

  /** 设置顶栏只注入标题与“更多”，左侧让出 HDS 系统返回键的区域。 */
  @Builder
  private settingsTitleBar() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(this.settingsHomeTitle)
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.settingsHomeActionsAvailable) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('settings_detail_actions')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(TITLE_BAR_GLASS_MATERIAL === undefined
          ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
        .systemMaterial(TITLE_BAR_GLASS_MATERIAL)
        .accessibilityText(`${this.settingsHomeTitle}更多操作`)
        .onClick((): void => {
          this.onSettingsTitleActions();
        })
      } else {
        Blank()
          .width(40)
          .height(40)
      }
    }
    .width('100%')
    .height(48)
    // stackBuilder 覆盖整条标题栏，标题必须避开系统返回键及其点击区域。
    .padding({ left: 80, right: $r('app.float.page_padding') })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /** 顶栏返回：二级页回上一级（交给宿主），目录页退出设置。 */
  private onSettingsTitleBack(): void {
    if (this.settingsHomeDetailBackActive) {
      AppStorage.setOrCreate('settingsHomeBackTick',
        (AppStorage.get<number>('settingsHomeBackTick') ?? 0) + 1);
      return;
    }
    this.pathStack.pop();
  }

  /** 顶栏“更多”：交给宿主转调二级页注册的动作（例如屏蔽规则/记录的更多菜单）。 */
  private onSettingsTitleActions(): void {
    AppStorage.setOrCreate('settingsHomeActionTick',
      (AppStorage.get<number>('settingsHomeActionTick') ?? 0) + 1);
  }

  @Builder
  private detailTitleBar(title: string) {    Row({ space: $r('app.float.spacing_small') }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.supportsImmersiveMaterial()) {
          materialCanvas(52, 52)
        }
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .width(40)
          .height(40)
          .padding(0)
          .borderRadius(20)
          .backgroundColor(this.supportsImmersiveMaterial()
            ? Color.Transparent
            : $r('app.color.surface_background'))
          .accessibilityText('返回')
          .onClick((): void => {
            this.pathStack.pop();
          })
      }
        .width(44)
        .height(44)
        .borderRadius(22)
        .clip(true)
      Text(title)
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
        .width(40)
        .height(40)
    }
    .width('100%')
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /** 搜索胶囊内边距：有系统材质时用玻璃胶囊的收窄内边距，低版本保持原有模糊兜底样式。 */
  private searchPillPadding(): Padding {
    if (TITLE_BAR_GLASS_MATERIAL !== undefined) {
      return { left: 14, right: 14 };
    }
    return {
      top: $r('app.float.spacing_small'),
      bottom: $r('app.float.spacing_small'),
      left: $r('app.float.spacing_small'),
      right: $r('app.float.spacing_small')
    };
  }

  private searchPillRadius(): Length {
    return TITLE_BAR_GLASS_MATERIAL !== undefined ? 20 : $r('app.float.card_radius');
  }

  @Builder
  private rootTitleBarContent() {
    Stack({ alignContent: Alignment.Center }) {
    if (this.activeTopLevelTab() === TopLevelTab.HOME) {
      Row({ space: $r('app.float.spacing_small') }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: $r('app.float.spacing_small') }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
            Text('搜索内容')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .id('home_titlebar_search')
        .layoutWeight(1)
        .height(40)
        .padding(this.searchPillPadding())
        .backgroundColor(Color.Transparent)
        // API 26 起可给任意组件设置系统材质（薄玻璃胶囊）；低版本退回模糊兜底。
        .backgroundBlurStyle(TITLE_BAR_GLASS_MATERIAL === undefined
          ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
        .systemMaterial(TITLE_BAR_GLASS_MATERIAL)
        .borderRadius(this.searchPillRadius())
        .accessibilityText('打开搜索')
        .onClick((): void => this.navigate({ name: AppDestinationName.SEARCH, query: '' }))

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('home_titlebar_notifications')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        // 与搜索胶囊同款沉浸光感材质：圆形薄玻璃底；低版本退回模糊兜底。
        .backgroundBlurStyle(TITLE_BAR_GLASS_MATERIAL === undefined
          ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
        .systemMaterial(TITLE_BAR_GLASS_MATERIAL)
        .accessibilityText('打开通知')
        .onClick((): void => this.navigate({ name: AppDestinationName.NOTIFICATION }))
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.activeTopLevelTab() === TopLevelTab.HISTORY) {
      // #48：历史配置为底栏页时，“我的”入口也复用此页，必须保留本地历史菜单。
      HistoryTitleBar({ reserveBackButtonSpace: false })
    } else if (this.activeTopLevelTab() === TopLevelTab.FOLLOWING) {
      Column() {
        Row() {
          this.followingTitleTabItem('推荐', 0)
          this.followingTitleTabItem('动态', 1)
        }
          .width(180)
          .height(40)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.activeTopLevelTab() === TopLevelTab.HOT) {
      Row() {
        Text('热榜')
          .id('hot_titlebar_title')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('hot_titlebar_refresh')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        // 顶栏图标统一沉浸光感材质（圆形薄玻璃底），与搜索/通知一致；低版本退回模糊兜底。
        .backgroundBlurStyle(TITLE_BAR_GLASS_MATERIAL === undefined
          ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
        .systemMaterial(TITLE_BAR_GLASS_MATERIAL)
        .accessibilityText('刷新热榜')
        .onClick((): void => {
          this.hotReloadToken += 1;
          this.channelFeedInteractionBridge.refreshHot();
        })
      }
      .width('100%')
      .padding({ left: $r('app.float.page_padding'), right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.activeTopLevelTab() === TopLevelTab.DAILY) {
      Row() {
        Column({ space: 2 }) {
          Text('知乎日报')
            .fontSize($r('app.float.heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          if (this.dailyViewingDate.length > 0) {
            Text(formatDailyDate(this.dailyViewingDate))
              .id('daily_titlebar_current_date')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(1)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('daily_titlebar_date')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        // 顶栏图标统一沉浸光感材质（圆形薄玻璃底），与搜索/通知一致；低版本退回模糊兜底。
        .backgroundBlurStyle(TITLE_BAR_GLASS_MATERIAL === undefined
          ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
        .systemMaterial(TITLE_BAR_GLASS_MATERIAL)
        .accessibilityText('选择日报日期')
        .onClick((): void => {
          this.openDailyDatePicker();
        })
      }
      .width('100%')
      .padding({ left: $r('app.float.page_padding'), right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    }
    .id('root_titlebar_content')
    .width('100%')
    .height('100%')
    .monopolizeEvents(false)
  }

  // 关注子页签：鸿蒙规范的文字页签（选中加重 + 短下划线指示条），
  // 点选经 AppStorage 广播给关注页 Swiper。
  @Builder
  private followingTitleTabItem(title: string, index: number) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(this.followingTitleSelectedIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.followingTitleSelectedIndex === index
          ? $r('app.color.primary_text')
          : $r('app.color.secondary_text'))
      Row()
        .width(this.followingTitleSelectedIndex === index ? 24 : 0)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(this.resolvedThemeColor)
        .animation({ duration: 250, curve: Curve.EaseInOut })
    }
      .id(`following_titlebar_tab_${index}`)
      .layoutWeight(1)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .accessibilityText(`切换到${title}`)
      .onClick((): void => this.selectFollowingTitleBarTab(index))
  }

  private selectFollowingTitleBarTab(index: number): void {
    if (index < 0 || index > 1) {
      return;
    }
    AppStorage.setOrCreate('followingSelectedTabIndex', index);
    AppStorage.setOrCreate('followingTabSelectionTick',
      (AppStorage.get<number>('followingTabSelectionTick') ?? 0) + 1);
  }

  private openDailyDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      selected: dailyPickerDate(this.dailyViewingDate),
      start: new Date(2000, 0, 1),
      end: new Date(),
      onDateAccept: (date: Date): void => {
        // HdsTabs 下使用 AppStorage 先写日期再广播，重复选择同一天也能重新加载。
        this.dailyDateCursor = dailyDateCursor(date);
        AppStorage.setOrCreate('dailySelectedDate', this.dailyDateCursor);
        AppStorage.setOrCreate('dailyDateSelectionTick',
          (AppStorage.get<number>('dailyDateSelectionTick') ?? 0) + 1);
      }
    });
  }

  @Builder
  private accountPageContent() {
    AccountPage({
      authenticated: this.accountSessionState()?.status === SessionStatus.AUTHENTICATED,
      accountTitle: this.accountTitle(),
      avatarLetter: this.accountAvatarLetter(),
      avatarUrl: this.accountAvatarUrl(),
      hasPendingUpdate: this.pendingUpdateRelease !== undefined,
      scroller: this.settingsScroller,
      onOpenProfile: (): void => this.openCurrentProfile(),
      onOpenLogin: (): void => this.navigate({ name: AppDestinationName.LOGIN }),
      onOpenCollections: (): void => this.openMyCollections(),
      onOpenHistory: (): void => this.navigate({ name: AppDestinationName.READ_HISTORY }),
      onOpenMessages: (): void => this.navigate({ name: AppDestinationName.NOTIFICATION }),
      onOpenPinPublish: (): void => this.openPinComposer(),
      onOpenPinDrafts: (): void => this.navigate({ name: AppDestinationName.PIN_DRAFTS }),
      onOpenScan: (): void => this.navigate({ name: AppDestinationName.QR_DESKTOP_LOGIN_SCAN }),
      onOpenSettings: (): void => this.navigate({ name: AppDestinationName.SETTINGS_HOME })
    })
  }

  @Builder
  private settingsHomePageContent() {
    SettingsHomePage({
      authenticated: this.accountSessionState()?.status === SessionStatus.AUTHENTICATED,
      logoutBusy: this.accountLogoutBusy,
      updateLabel: this.pendingUpdateRelease !== undefined ? '有新版本' : '',
      navigate: (destination: AppDestination): void => this.navigate(destination),
      onLogout: (): void => this.confirmAccountLogout(),
      identityContent: (): void => {
        this.identityManagementContent();
      },
      appearanceContent: (onOpenThemeColor: () => void): void => {
        this.appearanceSettingsContent(true, onOpenThemeColor);
      },
      readingContent: (): void => {
        this.readingSettingsContent(true);
      },
      filterContent: (onOpenBlocklist: () => void, onOpenBlockedHistory: () => void): void => {
        this.filterSettingsContent(true, onOpenBlocklist, onOpenBlockedHistory);
      },
      blockingRulesContent: (registerActions: (handler: () => void) => void,
        releaseActions: () => void): void => {
        this.blockingRulesEmbeddedContent(registerActions, releaseActions);
      },
      blockedHistoryContent: (registerActions: (handler: () => void) => void,
        releaseActions: () => void): void => {
        this.blockedFeedHistoryEmbeddedContent(registerActions, releaseActions);
      },
      developerContent: (): void => {
        this.technicalLabEmbeddedContent();
      },
      notificationContent: (): void => {
        this.notificationSettingsContent((destination: AppDestination): void => this.navigate(destination), true);
      },
      updateContent: (): void => {
        this.systemUpdateSettingsContent(true);
      },
      aboutContent: (): void => {
        this.aboutAppPageContent(true);
      }
    })
  }

  /** 嵌入设置右栏的内容屏蔽：标题、返回与“更多”都由宿主提供，页面只登记动作。 */
  @Builder
  private blockingRulesEmbeddedContent(registerActions: (handler: () => void) => void, releaseActions: () => void) {
    this.blockingRulesContent((): void => {}, true, registerActions, releaseActions);
  }

  /** 嵌入设置右栏的屏蔽记录。 */
  @Builder
  private blockedFeedHistoryEmbeddedContent(registerActions: (handler: () => void) => void,
    releaseActions: () => void) {
    this.blockedFeedHistoryContent((): void => {}, true, registerActions, releaseActions);
  }

  /** 嵌入设置右栏的开发者选项：关闭模式只持久化，导航由设置宿主按入口来源处理。 */
  @Builder
  private technicalLabEmbeddedContent() {
    this.technicalLabContent((destination: AppDestination): void => this.navigate(destination),
      (): void => this.onEmbeddedDeveloperModeDisabled(), true);
  }

  @Builder
  private aboutAppPageContent(embedded: boolean) {
    AboutAppPage({
      installedVersionLabel: this.installedVersionLabel,
      developerModeEnabled: this.developerModeEnabled,
      embedded: embedded,
      onVersionRowClick: (): void => this.onVersionRowClicked(),
      onOpenProject: (): void => this.openProjectHome(),
      onOpenProjectLicense: (): void => {
        this.projectLicenseSheetShown = true;
      },
      onOpenOpenSourceLicenses: (): void => {
        this.openSourceLicensesSheetShown = true;
      }
    })
  }

  @Builder
  private identityManagementContent() {
    IdentityManagementPage({ embedded: true });
  }

  @Builder
  private appearanceSettingsContent(embedded: boolean, onOpenThemeColor: () => void) {
    AppearanceSettingsPage({
      themeMode: this.themeMode,
      embedded: embedded,
      onThemeModeChange: (mode: AppThemeMode): void => {
        void this.selectThemeMode(mode);
      },
      onOpenThemeColorSettings: (): void => onOpenThemeColor(),
      onImmersiveMaterialChange: (mode: ImmersiveMaterialMode): void => {
        this.selectImmersiveMaterialLevel(mode);
      }
    })
  }

  @Builder
  private readingSettingsContent(embedded: boolean) {
    ReadingSettingsPage({ embedded: embedded })
  }

  @Builder
  private filterSettingsContent(embedded: boolean, onOpenBlocklist: () => void, onOpenBlockedHistory: () => void) {
    ContentFilterSettingsPage({
      preferences: this.createPreferencesStore(),
      runtime: this.createFilterRuntimeStore(),
      embedded: embedded,
      onOpenBlocklist: (): void => onOpenBlocklist(),
      onOpenBlockedHistory: (): void => onOpenBlockedHistory()
    })
  }

  @Builder
  private systemUpdateSettingsContent(embedded: boolean) {
    SystemUpdateSettingsPage({
      installedVersionLabel: this.installedVersionLabel,
      updateCheckBusy: this.updateCheckBusy,
      updateCheckMessage: this.updateCheckMessage,
      availableVersion: this.pendingUpdateRelease?.versionName ?? '',
      latestVersion: this.latestUpdateRelease?.versionName ?? '',
      latestAssetUrl: this.latestUpdateRelease?.assetUrl ?? '',
      latestAssetSha256: this.latestUpdateRelease?.assetSha256 ?? '',
      embedded: embedded,
      onCheckUpdate: (): void => {
        void this.runUpdateCheck(true);
      },
      onOpenDownload: (url: string): void => this.openExternalUrl(url, '无法打开下载链接'),
      onOpenProject: (): void => this.openProjectHome(),
      onOpenWhatsNew: (): void => this.navigate({ name: AppDestinationName.WHATS_NEW }),
      onOpenUpdateWhatsNew: (): void => this.openUpdateWhatsNew()
    })
  }

  @Builder
  private aboutVersionSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('应用与版本')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('about_version_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭应用与版本')
          .onClick((): void => {
            this.aboutVersionSheetShown = false;
          })
      }
      .width('100%')
      Text($r('app.string.EntryAbility_label'))
        .id('about_version_app_name')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.installedVersionLabel)
        .id('about_version_value')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .onClick((): void => this.onVersionTapped())
      Text('版本信息来自当前已安装的 HAP，便于核对本机安装结果。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Text(this.developerModeEnabled ? '开发者选项已开启。检查更新已移至“系统与更新”。' :
        '连续点击“应用与版本”设置行 5 次可开启开发者选项。检查更新已移至“系统与更新”。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private projectLicenseSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('项目协议')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('project_license_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭项目协议')
          .onClick((): void => {
            this.projectLicenseSheetShown = false;
          })
      }
      .width('100%')
      Text('GNU Affero General Public License v3.0')
        .id('project_license_name')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('本项目以 GNU AGPL v3.0 许可发布。使用、修改或分发时应遵守该协议；对修改后的版本提供网络服务时，也应按协议向相应用户提供源代码。')
        .id('project_license_summary')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Text('完整法律条款以项目随源代码分发的 LICENSE 文件为准。')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private openSourceLicensesSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('开源许可')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('open_source_licenses_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭开源许可')
          .onClick((): void => {
            this.openSourceLicensesSheetShown = false;
          })
      }
      .width('100%')
      Text('当前 API 26 HAP 未打包第三方运行时 ohpm 依赖；以下是随应用打包的本地 HarmonyOS HAR 模块。')
        .id('open_source_licenses_summary')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Column() {
        this.openSourceLicenseRow('core', '共享策略、导航与启动 · GNU AGPL v3.0');
        Divider().color($r('app.color.divider_color'))
        this.openSourceLicenseRow('data', '领域模型、网络、会话与本地数据 · GNU AGPL v3.0');
        Divider().color($r('app.color.divider_color'))
        this.openSourceLicenseRow('reader', '原生阅读、数据源与媒体加载 · GNU AGPL v3.0');
      }
      .id('open_source_licenses_list')
      .width('100%')
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.control_background'))
      Text('HarmonyOS 系统 Kit 为平台 API，不作为第三方打包依赖列入此处。许可名称以各模块 oh-package.json5 的声明为准。')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private projectHomeHelpSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('项目主页')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('project_home_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭项目主页说明')
          .onClick((): void => {
            this.projectHomeHelpShown = false;
          })
      }
      .width('100%')
      Text(PROJECT_HOME_URI)
        .id('project_home_url')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.projectHomeLaunchStatus)
        .id('project_home_status')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private openSourceLicenseRow(name: string, description: string) {
    Column({ space: $r('app.float.spacing_xsmall') }) {
      Text(name)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(description)
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
  }

  private refreshInstalledVersionLabel(): void {
    try {
      const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.installedVersionName = bundle.versionName;
      this.installedVersionLabel = `版本 ${bundle.versionName}（版本号 ${bundle.versionCode}）`;
    } catch (_error) {
      this.installedVersionName = '';
      this.installedVersionLabel = '暂时无法读取已安装版本';
    }
  }

  /** verbose=true 供“系统与更新”页手动检查（展示状态、不受节流限制）；false 供启动静默检查
    * （3 小时节流，对齐上游 shouldPerformAutoCheck）。检出新版本时经 AppStorage 广播驱动首页更新卡片。 */
  private async runUpdateCheck(verbose: boolean): Promise<void> {
    if (this.updateCheckBusy) {
      return;
    }
    if (this.installedVersionName.length === 0) {
      if (verbose) {
        this.updateCheckMessage = '无法读取本机版本，暂时无法检查更新';
      }
      return;
    }
    if (!verbose && !(await this.shouldAutoCheckUpdateNow())) {
      return;
    }
    await seedBundledUpdateCatalog();
    await this.markUpdateCheckedNow();
    this.updateCheckBusy = true;
    if (verbose) {
      this.updateCheckMessage = '正在检查更新…';
    }
    try {
      const result: AppUpdateCheckResult =
        await this.updateClient.checkLatestRelease(this.installedVersionName, verbose);
      if (result.release !== undefined) {
        this.latestUpdateRelease = result.release;
      }
      if (result.status === AppUpdateCheckStatus.UPDATE_AVAILABLE && result.release !== undefined) {
        this.pendingUpdateRelease = result.release;
        this.broadcastHomeUpdateAnnouncement(result.release.versionName);
        if (verbose) {
          this.updateCheckMessage = `发现新版本 ${result.release.versionName}，可前往下载`;
        }
      } else if (result.status === AppUpdateCheckStatus.UP_TO_DATE) {
        this.pendingUpdateRelease = undefined;
        this.broadcastHomeUpdateAnnouncement('');
        if (verbose) {
          this.updateCheckMessage = '当前已是最新版本';
        }
      } else if (verbose) {
        this.updateCheckMessage = result.message.length > 0 ? result.message : '检查更新失败，请稍后重试';
      }
      hilog.info(0x0000, 'AppUpdate', 'check status=%{public}s remoteVersion=%{public}s assetSha256Len=%{public}d',
        result.status, result.release !== undefined ? result.release.versionName : '',
        result.release !== undefined && result.release.assetSha256 !== undefined ?
          result.release.assetSha256.length : -1);
    } finally {
      this.updateCheckBusy = false;
    }
  }

  /** 版本更迭后首次启动（含首次安装）推入“新版本更新”页；本次启动已带深链目标时让位。
    * 判定依据本机版本名与上次已展示版本（AppPreferencesStore），推送走 NavPathStack，
    * 与深链冷启动同一条时序已验证可靠。 */
  private async evaluateWhatsNewOnLaunch(): Promise<void> {
    if (this.installedVersionName.length === 0) {
      return;
    }
    if (this.startupDestinationArrived) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    try {
      const shownVersion = await new AppPreferencesStore(context).loadWhatsNewShownVersion();
      if (!this.startupDestinationArrived &&
        shouldShowWhatsNewOnLaunch(shownVersion, this.installedVersionName)) {
        this.navigate({ name: AppDestinationName.WHATS_NEW });
      }
    } catch (_error) {
      // 偏好读取失败时静默跳过，不打扰启动流程。
    }
  }

  /** “新版本更新”页（版本说明模式，展示本机版本）关闭后记录已展示版本，
    * 之后同版本启动不再自动弹出；更新预览模式（展示目标版本）不记录。 */
  private markWhatsNewSeen(shownVersionName: string): void {
    if (shownVersionName.length === 0 || shownVersionName !== this.installedVersionName) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    void new AppPreferencesStore(context).saveWhatsNewShownVersion(shownVersionName)
      .catch((_error: Error): void => {
      });
  }

  /** 主页更新卡片/“系统与更新”页入口：预览待更新目标版本（GitHub 最新 Release）的更新内容。 */
  private openUpdateWhatsNew(): void {
    const release = this.pendingUpdateRelease;
    if (release === undefined) {
      return;
    }
    this.navigate({ name: AppDestinationName.WHATS_NEW, version: release.versionName });
  }

  private async shouldAutoCheckUpdateNow(): Promise<boolean> {
    const context = getAbilityContext();
    if (context === undefined) {
      return true;
    }
    try {
      const lastUpdateCheckAt = await new AppPreferencesStore(context).loadLastUpdateCheckAt();
      return shouldAutoCheckForUpdate(lastUpdateCheckAt, Date.now());
    } catch (_error) {
      // 节流时间戳读取失败按未节流处理，宁可多检查一次。
      return true;
    }
  }

  private async markUpdateCheckedNow(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    try {
      await new AppPreferencesStore(context).saveLastUpdateCheckAt(Date.now());
    } catch (_error) {
      // 节流时间戳保存失败仅影响下次自动检查频率，不打扰用户。
    }
  }

  /** 首页更新卡片经 AppStorage 广播（HdsTabs 树下跨页面信号唯一可靠通道）。 */
  private broadcastHomeUpdateAnnouncement(version: string): void {
    AppStorage.setOrCreate('homeUpdateAnnouncementVersion', version);
  }

  private onVersionTapped(): void {
    if (this.developerModeEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: '开发者选项已开启' });
      return;
    }
    this.versionTapCount += 1;
    const remaining = 5 - this.versionTapCount;
    if (remaining > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `再点击 ${remaining} 次开启开发者选项` });
      return;
    }
    this.versionTapCount = 0;
    this.developerModeEnabled = true;
    AppStorage.setOrCreate('developerModeEnabled', true);
    const context = getAbilityContext();
    if (context !== undefined) {
      void new AppPreferencesStore(context).saveDeveloperMode(true);
    }
    this.getUIContext().getPromptAction().showToast({ message: '你已成为开发者' });
  }

  private onVersionRowClicked(): void {
    if (this.developerModeEnabled) {
      this.refreshInstalledVersionLabel();
      this.aboutVersionSheetShown = true;
      return;
    }
    this.onVersionTapped();
  }

  /**
   * 只做持久化与全局广播，不发导航：嵌入设置右栏时由设置宿主回到目录，
   * 独立入口由 disableDeveloperMode() 负责退出当前页（§11.1 拆分要求）。
   */
  private setDeveloperModeEnabled(enabled: boolean): void {
    this.developerModeEnabled = enabled;
    if (!enabled) {
      this.versionTapCount = 0;
    }
    AppStorage.setOrCreate('developerModeEnabled', enabled);
    const context = getAbilityContext();
    if (context !== undefined) {
      void new AppPreferencesStore(context).saveDeveloperMode(enabled);
    }
  }

  /** 嵌入设置宿主时的关闭动作：仅持久化并提示，导航由宿主按入口来源处理。 */
  private onEmbeddedDeveloperModeDisabled(): void {
    this.setDeveloperModeEnabled(false);
    this.getUIContext().getPromptAction().showToast({ message: '开发者选项已关闭' });
  }

  /** 独立开发者页关闭模式：持久化后退出该页。 */
  private disableDeveloperMode(): void {
    this.setDeveloperModeEnabled(false);
    this.pathStack.pop();
    this.getUIContext().getPromptAction().showToast({ message: '开发者选项已关闭' });
  }

  /** 窄容器设置详情优先回目录；双栏或目录根页交回导航栈退出设置。 */
  private handleSettingsHomeBack(): boolean {
    if (AppStorage.get<boolean>('settingsHomeDetailBackActive') === true) {
      AppStorage.setOrCreate('settingsHomeBackTick',
        (AppStorage.get<number>('settingsHomeBackTick') ?? 0) + 1);
      return true;
    }
    return false;
  }

  private openExternalUrl(url: string, fallbackPrefix: string): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showProjectHomeHelp(`${fallbackPrefix}，请在浏览器中打开此地址：${url}`);
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url
    };
    try {
      void context.startAbility(want).then((): void => {
      }, (): void => {
        this.showProjectHomeHelp(`${fallbackPrefix}，请在浏览器中打开此地址：${url}`);
      });
    } catch (_error) {
      this.showProjectHomeHelp(`${fallbackPrefix}，请在浏览器中打开此地址：${url}`);
    }
  }

  private openProjectHome(): void {
    this.openExternalUrl(PROJECT_HOME_URI, '当前无法调用系统浏览器');
  }

  private showProjectHomeHelp(status: string): void {
    this.projectHomeLaunchStatus = status;
    this.projectHomeHelpShown = true;
  }

  private onSessionStateTick(): void {
    this.sessionSnapshot = this.session?.getState();
  }

  private accountSessionState(): SessionState | undefined {
    return this.sessionSnapshot ?? this.session?.getState();
  }

  private accountTitle(): string {
    const state = this.accountSessionState();
    if (state?.status !== SessionStatus.AUTHENTICATED) {
      return '登录知乎';
    }
    const profileName = state.profile?.name.trim() ?? '';
    return profileName.length > 0 ? profileName : '已登录账号';
  }

  private accountAvatarLetter(): string {
    return this.accountTitle().charAt(0);
  }

  private accountAvatarUrl(): string {
    const state = this.accountSessionState();
    if (state?.status !== SessionStatus.AUTHENTICATED) {
      return '';
    }
    return state.profile?.avatarUrl?.trim() ?? '';
  }

  private openCurrentProfile(): void {
    const state = this.accountSessionState();
    const profile = state?.profile;
    const identifier = profile?.urlToken ?? profile?.id;
    if (state?.status === SessionStatus.AUTHENTICATED && identifier !== undefined && identifier.length > 0) {
      this.navigate({ name: AppDestinationName.PEOPLE, id: identifier });
    }
  }

  private confirmAccountLogout(): void {
    if (this.accountLogoutBusy) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '确定要退出登录吗？',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '退出', action: (): void => { void this.logoutCurrentAccount(); } }
    });
  }

  private async logoutCurrentAccount(): Promise<void> {
    const session = this.session;
    if (session === undefined || this.accountLogoutBusy) {
      return;
    }
    this.accountLogoutBusy = true;
    try {
      const state = await session.logout();
      this.sessionSnapshot = state;
      AppStorage.setOrCreate('sessionStateTick', (AppStorage.get<number>('sessionStateTick') ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: state.message });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: '退出登录失败，请重试' });
    } finally {
      this.accountLogoutBusy = false;
    }
  }

  @Builder
  invalidDestinationPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.spacing_small') }) {
        Text('导航参数无效')
          .fontSize($r('app.float.heading_font_size'))
          .fontColor($r('app.color.primary_text'))
        Text('页面参数未通过校验，请返回后重试。')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.page_padding'))
      .align(Alignment.TopStart)
    }
    .id('invalid_destination_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  businessPlaceholder(destination: AppDestination) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.spacing_small') }) {
        Text(destination.name)
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        Text(this.destinationDescription(destination))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.page_padding'))
      .align(Alignment.TopStart)
    }
    .id('business_destination_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  private onTopLevelTabIndexChanged(): void {
    this.tabsController.changeIndex(this.topLevelTabIndex);
    this.broadcastBottomBarScrollOwner();
  }

  /** 底栏"滚动自动隐藏"只归属于信息流页签：切换到"我的/历史/收藏夹"等页签时
   * 收回标记并强制回显，避免离屏信息流重建/惯性滚动留下的旧标记把底栏隐藏掉。 */
  private broadcastBottomBarScrollOwner(): void {
    const tab: number | undefined = this.bottomBarOrder[this.topLevelTabIndex];
    const feedTab: boolean = tab !== undefined && tab >= TopLevelTab.HOME && tab <= TopLevelTab.DAILY;
    setFeedScrollOwner(feedTab ? (this.scrollKeysForTab(tab ?? TopLevelTab.HOME)[0] ?? '') : '');
    AppStorage.setOrCreate('topLevelFeedTabActive', feedTab);
    if (!feedTab) {
      AppStorage.setOrCreate('bottomBarHiddenByScroll', false);
    }
  }

  private onBottomBarItemsChanged(): void {
    const activeTab = this.activeTopLevelTab();
    const nextBottomBarOrder = this.decodeBottomBarOrder(this.bottomBarItems);
    this.bottomBarOrder = nextBottomBarOrder;
    const activeDisplayIndex = nextBottomBarOrder.indexOf(activeTab);
    this.topLevelTabIndex = activeDisplayIndex >= 0 ? activeDisplayIndex : 0;
    // ForEach 重建页签后 Tabs 选中索引可能被重置/钳制（索引值未变时 @Watch 不触发），
    // 这里无条件用控制器再同步一次。
    this.tabsController.changeIndex(this.topLevelTabIndex);
    this.broadcastBottomBarScrollOwner();
  }

  private setReaderRouteVisible(kind: string, id: string, visible: boolean): void {
    const key = readerPositionKey(kind, id);
    if (visible) {
      AppStorage.setOrCreate('readerActiveRouteKey', key);
    } else if (AppStorage.get<string>('readerActiveRouteKey') === key) {
      AppStorage.setOrCreate('readerActiveRouteKey', '');
    }
  }

  private navigate(destination: AppDestination): void {
    const topLevelTab = topLevelTabForDestination(destination);
    if (topLevelTab !== undefined) {
      const displayIndex = this.bottomBarOrder.indexOf(topLevelTab);
      if (displayIndex >= 0) {
        this.pathStack.clear();
        this.topLevelTabIndex = displayIndex;
        return;
      }
    }
    const paths: Array<NavPathInfo> | undefined = this.pathStack.getPathStack();
    if (paths !== undefined && paths.length > 0) {
      // P3-7：同一目标（name+参数）已在返回栈任何位置时不再重复入栈，
      // 防止返回时只是露出前一个重复页面，而没有回到原来的浏览上下文。
      // 参数化页面不能使用按 name 匹配的 MOVE_TO_TOP_SINGLETON，必须按身份查重。
      const existingIndex = findAppDestinationStackIndex(paths, destination);
      if (existingIndex >= 0) {
        // 已在栈中时弹到栈顶（复用原页面实例与滚动状态），不能静默忽略——
        // 否则「答案页 → 问题页 → 点原答案」这类回访点击会无响应。
        if (existingIndex < paths.length - 1) {
          this.pathStack.popToIndex(existingIndex);
        }
        return;
      }
    }
    const path: NavPathInfo = { name: destination.name, param: destination };
    if (isInfrastructureDestination(destination)) {
      this.pathStack.pushPath(path, { launchMode: LaunchMode.MOVE_TO_TOP_SINGLETON });
    } else {
      this.pathStack.pushPath(path);
    }
  }

  private openMyCollections(): void {
    const session = this.session;
    const state = session?.getState();
    const profile = state?.profile;
    const identifier = profile?.urlToken ?? profile?.id;
    if (session === undefined || state?.status !== SessionStatus.AUTHENTICATED || identifier === undefined) {
      this.navigate({ name: AppDestinationName.LOGIN });
      return;
    }
    this.navigate({ name: AppDestinationName.COLLECTIONS, id: identifier });
  }

  /** 路由只持有随机本地草稿键；账号范围和正文均由目标页在认证后解析。 */
  private openPinComposer(): void {
    this.navigate({ name: AppDestinationName.WRITE_PIN, draftId: this.createLocalDraftId() });
  }

  private createLocalDraftId(): string {
    return `${this.randomHex(8)}-${this.randomHex(4)}-4${this.randomHex(3)}-8${this.randomHex(3)}-${this.randomHex(12)}`;
  }

  private randomHex(length: number): string {
    let value = '';
    for (let index = 0; index < length; index += 1) {
      value += Math.floor(Math.random() * 16).toString(16);
    }
    return value;
  }

  private returnFromSuccessfulLogin(): void {
    this.pathStack.pop();
    const paths: Array<NavPathInfo> | undefined = this.pathStack.getPathStack();
    if (paths === undefined || paths.length === 0) {
      this.reloadFeedsAfterLogin();
      return;
    }
    const current = paths[paths.length - 1];
    if (!(current.param instanceof Object)) {
      return;
    }
    const destination = decodeAppDestination(current.name, current.param);
    if (destination === undefined || !shouldReloadAfterAuthentication(destination)) {
      return;
    }
    this.pathStack.pop();
    this.pathStack.pushPath({ name: destination.name, param: destination });
  }

  /**
   * 登录成功后重载各 feed。reloadToken 走 Builder 参数传入，且 @Provide/@Consume 在
   * HdsTabs 的 TabContent 构建树下实测不链接（各页面会拿到自己的兜底实例），因此用
   * AppStorage 广播 loginFeedReloadTick，让已挂载的 feed 页各自触发重载；未挂载过的
   * feed 首次进入时自然加载。token 自增保留作为可生效场景的兜底。
   */
  private reloadFeedsAfterLogin(): void {
    this.homeReloadToken += 1;
    this.followingReloadToken += 1;
    this.hotReloadToken += 1;
    this.dailyReloadToken += 1;
    this.sessionSnapshot = this.session?.getState();
    const nextTick = (AppStorage.get<number>('loginFeedReloadTick') ?? 0) + 1;
    AppStorage.setOrCreate('loginFeedReloadTick', nextTick);
    const nextSessionTick = (AppStorage.get<number>('sessionStateTick') ?? 0) + 1;
    AppStorage.setOrCreate('sessionStateTick', nextSessionTick);
  }

  private destinationDescription(destination: AppDestination): string {
    switch (destination.name) {
      case AppDestinationName.SEARCH:
        return `搜索：${destination.query}`;
      case AppDestinationName.COMMENT:
        return `内容：${destination.contentId}`;
      case AppDestinationName.NOTIFICATION:
        return '查看知乎账号的通知消息';
      case AppDestinationName.NOTIFICATION_ENTRY:
        return '查看知乎通知分类消息';
      case AppDestinationName.PRIVATE_MESSAGE:
        return '查看知乎私信会话';
      case AppDestinationName.QUESTION:
      case AppDestinationName.ANSWER:
      case AppDestinationName.ARTICLE:
      case AppDestinationName.VIDEO:
      case AppDestinationName.PIN:
      case AppDestinationName.PEOPLE:
      case AppDestinationName.COLLECTION:
      case AppDestinationName.DAILY_STORY:
        return `内容 ID：${destination.id}`;
      default:
        return destination.name;
    }
  }

  private async restoreAnswerDoubleTapAction(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      this.answerDoubleTapAction = await new AppPreferencesStore(context).loadAnswerDoubleTapAction();
      AppStorage.setOrCreate('answerDoubleTapAction', this.answerDoubleTapAction);
    } catch (_error) {
      // 读取失败保持默认 Ask。
    }
  }

  /** 启动恢复沉浸光感挡位：成功则发布持久化值，失败保留默认自适应并给出简短提示；
   * 读取成功或失败都结束加载状态（就绪后设置控件方可操作）。恢复只读不写，
   * 不触发保存，避免旧读取结果覆盖用户刚选择的新值。 */
  private async restoreImmersiveMaterialLevel(): Promise<void> {
    if (this.immersiveMaterialStore === undefined) {
      AppStorage.setOrCreate('immersiveMaterialPreferencesReady', true);
      return;
    }
    try {
      const mode = await this.immersiveMaterialStore.loadImmersiveMaterialLevel();
      AppStorage.setOrCreate('immersiveMaterialLevel', mode);
    } catch (_error) {
      AppStorage.setOrCreate('immersiveMaterialNotice', '沉浸光感设置读取失败，已使用默认效果');
    } finally {
      AppStorage.setOrCreate('immersiveMaterialPreferencesReady', true);
    }
  }

  /** 设置页四挡选择唯一入口：先广播即时生效，再经唯一 store 串行保存。
   * 保存失败保留本次已生效的选择并提示；同一选项可重试，只有最新一次保存结果更新提示。 */
  selectImmersiveMaterialLevel(mode: ImmersiveMaterialMode): void {
    if (AppStorage.get<boolean>('immersiveMaterialPreferencesReady') !== true) {
      // 恢复完成前控件不可操作；防御性忽略，避免旧读取结果覆盖新选择。
      return;
    }
    if (this.immersiveMaterialStore === undefined) {
      AppStorage.setOrCreate('immersiveMaterialNotice', '沉浸光感设置暂不可用，本次调整未保存');
      return;
    }
    AppStorage.setOrCreate('immersiveMaterialLevel', mode);
    const store = this.immersiveMaterialStore;
    void store.saveImmersiveMaterialLevel(mode).then((): void => {
      AppStorage.setOrCreate('immersiveMaterialNotice', '');
    }).catch((_error: Object): void => {
      AppStorage.setOrCreate('immersiveMaterialNotice', '沉浸光感设置保存失败，本次调整仍已生效');
    });
  }

  private createPreferencesStore(): AppPreferencesStore | undefined {
    const context = getAbilityContext();
    return context === undefined ? undefined : new AppPreferencesStore(context);
  }

  private async restoreDeveloperMode(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    try {
      this.developerModeEnabled = await new AppPreferencesStore(context).loadDeveloperMode();
      AppStorage.setOrCreate('developerModeEnabled', this.developerModeEnabled);
    } catch (_error) {
      this.developerModeEnabled = false;
      AppStorage.setOrCreate('developerModeEnabled', false);
    }
  }

  /** 回答阅读模式（连续阅读计划 §2.2）：启动时恢复并广播，问题页/详情菜单按此路由。 */
  private async restoreAnswerReadingMode(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    try {
      AppStorage.setOrCreate('answerReadingMode',
        await new AppPreferencesStore(context).loadAnswerReadingMode());
    } catch (_error) {
      AppStorage.setOrCreate('answerReadingMode', 'single');
    }
  }

  /**
   * 日报阅读模式（日报原生渲染计划 §7 P4）：启动时恢复并广播。
   * 读取失败保持默认（原生阅读）——与设置里默认值一致，不因一次读取失败悄悄换链路。
   */
  private async restoreDailyStoryReaderMode(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      AppStorage.setOrCreate('dailyStoryReaderMode', DEFAULT_DAILY_STORY_READER_MODE);
      return;
    }
    try {
      AppStorage.setOrCreate('dailyStoryReaderMode',
        await new AppPreferencesStore(context).loadDailyStoryReaderMode());
    } catch (_error) {
      AppStorage.setOrCreate('dailyStoryReaderMode', DEFAULT_DAILY_STORY_READER_MODE);
    }
  }

  private createFilterRuntimeStore(): ContentFilterRuntimeStore | undefined {
    const context = getAbilityContext();
    if (context === undefined) return undefined;
    const database = getAppDatabase(context);
    return new ContentFilterRuntimeStore(database, new BlockedFeedHistoryStore(database));
  }

  /** 读取排版偏好并广播；失败保持默认 100/160/100（与改造前视觉一致）。 */
  private async restoreReaderTypography(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const typography = await new AppPreferencesStore(context).loadReaderTypography();
      this.broadcastReaderTypography(typography);
    } catch (_error) {
      // 读取失败保持默认值。
    }
  }

  private broadcastReaderTypography(value: ReaderTypography): void {
    AppStorage.setOrCreate('contentFontSize', value.fontSize);
    AppStorage.setOrCreate('contentLineHeight', value.lineHeight);
    AppStorage.setOrCreate('contentBlockSpacing', value.blockSpacing);
    AppStorage.setOrCreate('contentTypographyPreset', value.preset ?? 'comfortable');
  }

  private async restoreAppearancePreferences(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const value: AppearancePreferences = await new AppPreferencesStore(context).loadAppearancePreferences();
      AppStorage.setOrCreate('fabOpacity', value.fabOpacity);
      AppStorage.setOrCreate('showFeedThumbnail', value.showFeedThumbnail);
      AppStorage.setOrCreate('showRefreshFab', value.showRefreshFab);
      AppStorage.setOrCreate('feedCardStyle', value.feedCardStyle);
      AppStorage.setOrCreate('feedColumnMode', value.feedColumnMode);
    } catch (_error) {
      // 读取失败时沿用与上游一致的默认值。
    }
  }

  private async restoreExperiencePreferences(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const value: ExperiencePreferences = await new AppPreferencesStore(context).loadExperiencePreferences();
      this.broadcastExperiencePreferences(value);
      if (!this.startDestinationApplied) {
        this.startDestinationApplied = true;
        const tab = this.topLevelTabFromPreference(value.startDestination);
        const displayIndex = this.bottomBarOrder.indexOf(tab);
        this.topLevelTabIndex = displayIndex >= 0 ? displayIndex : 0;
        this.tabsController.changeIndex(this.topLevelTabIndex);
      }
    } catch (_error) {
      // 读取失败时沿用上游默认值。
    }
  }

  private topLevelTabFromPreference(value: string): TopLevelTab {
    if (value === 'Following') return TopLevelTab.FOLLOWING;
    if (value === 'Hot') return TopLevelTab.HOT;
    if (value === 'Daily') return TopLevelTab.DAILY;
    if (value === 'ReadHistory') return TopLevelTab.HISTORY;
    if (value === 'Collections') return TopLevelTab.COLLECTIONS;
    if (value === 'Settings') return TopLevelTab.ACCOUNT;
    return TopLevelTab.HOME;
  }

  private broadcastExperiencePreferences(value: ExperiencePreferences): void {
    const activeTab = this.activeTopLevelTab();
    const nextBottomBarOrder = this.decodeBottomBarOrder(value.bottomBarItems);
    this.bottomBarOrder = nextBottomBarOrder;
    const activeDisplayIndex = nextBottomBarOrder.indexOf(activeTab);
    if (activeDisplayIndex >= 0) {
      this.topLevelTabIndex = activeDisplayIndex;
    } else if (this.topLevelTabIndex >= nextBottomBarOrder.length) {
      this.topLevelTabIndex = 0;
    }
    this.broadcastBottomBarScrollOwner();
    AppStorage.setOrCreate('titleAutoHide', value.titleAutoHide);
    AppStorage.setOrCreate('autoHideArticleBottomBar', value.autoHideArticleBottomBar);
    AppStorage.setOrCreate('buttonSkipAnswer', value.buttonSkipAnswer);
    AppStorage.setOrCreate('autoHideSkipAnswerButton', value.autoHideSkipAnswerButton);
    AppStorage.setOrCreate('pinAnswerDate', value.pinAnswerDate);
    AppStorage.setOrCreate('answerSwitchMode', value.answerSwitchMode);
    AppStorage.setOrCreate('answerSwitchSensitivity', value.answerSwitchSensitivity);
    AppStorage.setOrCreate('startDestination', value.startDestination);
    AppStorage.setOrCreate('bottomBarItems', value.bottomBarItems);
    AppStorage.setOrCreate('tapToRefresh', value.tapToRefresh);
    AppStorage.setOrCreate('autoHideBottomBar', value.autoHideBottomBar);
    AppStorage.setOrCreate('volumeKeyPageTurn', value.volumeKeyPageTurn);
    AppStorage.setOrCreate('pageTurnSwitchAnswer', value.pageTurnSwitchAnswer);
    AppStorage.setOrCreate('showPageTurnFab', value.showPageTurnFab);
    AppStorage.setOrCreate('pageTurnPercent', value.pageTurnPercent);
    AppStorage.setOrCreate('showPageTurnGuide', value.showPageTurnGuide);
    AppStorage.setOrCreate('showContentEndMarker', value.showContentEndMarker);
    AppStorage.setOrCreate('shareActionMode', value.shareActionMode);
    AppStorage.setOrCreate('showSearchHotSearch', value.showSearchHotSearch);
    AppStorage.setOrCreate('showSearchHistory', value.showSearchHistory);
    AppStorage.setOrCreate('gripFollowActions', value.gripFollowActions);
    AppStorage.setOrCreate('showHotComments', value.showHotComments);
    AppStorage.setOrCreate('questionInTitleBar', value.questionInTitleBar);
  }

  private decodeBottomBarOrder(raw: string): number[] {
    const values: string[] = raw.split(',');
    const result: number[] = [];
    for (let index = 0; index < values.length; index += 1) {
      const tab = this.topLevelTabFromPreference(values[index]);
      if (!result.includes(tab)) {
        result.push(tab);
      }
    }
    if (result.length < 3 || result.length > 5 || !result.includes(TopLevelTab.ACCOUNT)) {
      return [TopLevelTab.HOME, TopLevelTab.FOLLOWING, TopLevelTab.HOT,
        TopLevelTab.DAILY, TopLevelTab.ACCOUNT];
    }
    return result;
  }

  private async restoreThemeMode(): Promise<void> {
    const generation = this.themeOperationGuard.next();
    try {
      await this.themeSaveQueue.catch((_error: Error): void => {
      });
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const mode = await new AppPreferencesStore(context).loadThemeMode();
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      this.applyThemeMode(mode);
    } catch (_error) {
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      this.applyThemeMode(AppThemeMode.SYSTEM);
    }
  }

  private async selectThemeMode(mode: AppThemeMode): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const generation = this.themeOperationGuard.next();
    if (!this.applyThemeMode(mode)) {
      return;
    }
    const pendingSave = this.themeSaveQueue.catch((_error: Error): void => {
    }).then((): Promise<void> => {
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return Promise.resolve();
      }
      return new AppPreferencesStore(context).saveThemeMode(mode);
    });
    this.themeSaveQueue = pendingSave;
    try {
      await pendingSave;
    } catch (_error) {
      // 保存失败时主题仍已应用，重启后可能恢复此前设置；不再展示状态文案。
    }
  }

  private applyThemeMode(mode: AppThemeMode): boolean {
    const context = getAbilityContext();
    if (context === undefined) {
      return false;
    }
    try {
      if (mode === AppThemeMode.DARK) {
        context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else if (mode === AppThemeMode.LIGHT) {
        context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else {
        context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
      this.themeMode = mode;
      // 广播当前主题模式：EntryAbility.onConfigurationUpdate 仅在跟随系统时联动公式换色。
      AppStorage.setOrCreate('appThemeMode', mode);
      updateStatusBarAppearance();
      AppStorage.setOrCreate('formulaForegroundColor', this.resolveFormulaForegroundColor(mode));
      AppStorage.setOrCreate('resolvedThemeColor', this.resolveThemeColorForMode(mode, this.currentThemeColorSeed()));
      AppStorage.setOrCreate('appearanceThemeTick',
        (AppStorage.get<number>('appearanceThemeTick') ?? 0) + 1);
      return true;
    } catch (_error) {
      return false;
    }
  }

  /** 设置页改动主题色 seed（选择预设/拖动色盘/亮度条）后重新解析生效色并广播。 */
  private onThemeColorSeedChanged(): void {
    if (!this.themeMounted) {
      return;
    }
    AppStorage.setOrCreate('resolvedThemeColor',
      this.resolveThemeColorForMode(this.themeMode, this.currentThemeColorSeed()));
  }

  private currentThemeColorSeed(): string {
    return normalizeThemeColor(AppStorage.get<string>('themeColor') ?? DEFAULT_THEME_COLOR);
  }

  /** 标题栏样式函数的响应式挡位入参：从 @StorageProp 字段解码，
   * 挡位/能力变化时所有 titleBar 样式随本组件重新求值。 */
  private immersiveMaterialMode(): ImmersiveMaterialMode {
    return decodeImmersiveMaterialModeText(this.immersiveMaterialLevel);
  }

  private immersiveMaterialSupportState(): ImmersiveMaterialSupportState {
    return decodeImmersiveMaterialSupport(this.immersiveMaterialSupport);
  }

  /** 解析主题色 seed 在指定模式下的生效色：深色提亮（对齐原深色品牌色观感），其余原样。 */
  private resolveThemeColorForMode(mode: AppThemeMode, seed: string): string {
    const normalized = normalizeThemeColor(seed);
    if (mode === AppThemeMode.DARK) {
      return resolveThemeColorForDark(normalized);
    }
    if (mode === AppThemeMode.LIGHT) {
      return normalized;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return normalized;
    }
    try {
      return context.resourceManager.getConfigurationSync().colorMode ===
        resourceManager.ColorMode.DARK ? resolveThemeColorForDark(normalized) : normalized;
    } catch (_error) {
      return normalized;
    }
  }

  private async restoreThemeColor(): Promise<void> {
    // 主题色与主题模式独立恢复，不能互相使对方的操作代次失效。
    const generation = this.themeColorOperationGuard.next();
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const seed = await new AppPreferencesStore(context).loadThemeColor();
      if (!this.themeMounted || !this.themeColorOperationGuard.isCurrent(generation)) {
        return;
      }
      AppStorage.setOrCreate('themeColor', seed);
      AppStorage.setOrCreate('resolvedThemeColor', this.resolveThemeColorForMode(this.themeMode, seed));
    } catch (_error) {
      // 读取失败保留启动时广播的默认主题色。
    }
  }

  private resolveFormulaForegroundColor(mode: AppThemeMode): string {
    if (mode === AppThemeMode.DARK) {
      return FORMULA_FOREGROUND_DARK;
    }
    if (mode === AppThemeMode.LIGHT) {
      return FORMULA_FOREGROUND_LIGHT;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      return FORMULA_FOREGROUND_LIGHT;
    }
    try {
      // 跟随系统时的初值按当下配置推导；后续系统切换由 EntryAbility.onConfigurationUpdate 纠正。
      return context.resourceManager.getConfigurationSync().colorMode ===
        resourceManager.ColorMode.DARK ? FORMULA_FOREGROUND_DARK : FORMULA_FOREGROUND_LIGHT;
    } catch (_error) {
      return FORMULA_FOREGROUND_LIGHT;
    }
  }

}
