import { QuestionTitleBar } from './QuestionTitleBar';
import { SearchTitleBar } from './SearchTitleBar';
import { HistoryTitleBar } from './HistoryTitleBar';
import { AnswerTitleBar } from './AnswerTitleBar';
import { ArticleTitleBar } from './ArticleTitleBar';
import { peopleTitleText, PeopleTitleState } from './PeopleTitleBar';
import { CommentTitleBar, commentTitleStateId } from './CommentTitleBar';
import { NotificationTitleBar } from './NotificationTitleBar';
import {
  onThemeColor,
  AppearancePreferences,
  AnswerDoubleTapAction,
  AppPreferencesStore,
  BlockedFeedHistoryStore,
  ContentFilterRuntimeStore,
  AppThemeMode,
  DEFAULT_THEME_COLOR,
  FORMULA_FOREGROUND_DARK,
  FORMULA_FOREGROUND_LIGHT,
  ExperiencePreferences,
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
  SessionState,
  SessionStatus,
  shouldAutoCheckForUpdate,
  getAppDatabase
} from 'data';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import bundleManager from '@ohos.bundle.bundleManager';
import { Want } from '@kit.AbilityKit';
import {
  SymbolGlyphModifier
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resourceManager } from '@kit.LocalizationKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import {
  decodeP1Destination,
  findP1DestinationStackIndex,
  isInfrastructureDestination,
  LatestOperationGuard,
  NotificationEntryDestination,
  P1Destination,
  PrivateMessageDestination,
  P1DestinationName,
  shouldReloadAfterAuthentication,
  startupDestinationChannel,
  StartupDestinationListener
} from 'core';
import { AppNavigationRow } from './AppPageChrome';
import {
  P1TopLevelTab,
  p1TopLevelTabForDestination
} from './P1TopLevelTabs';
import { DividerShowType, hdsMaterial, HdsNavDestination, HdsNavigation, HdsNavigationAttribute, HdsNavigationTitleMode, HdsTabsController } from '@kit.UIDesignKit';
import { getImmersiveTitleBarStyle, getPersistentImmersiveTitleBarStyle } from '../common/style/NavStyles';
import { ZhihuHdsTabs } from './components/ZhihuHdsTabs';
import { AppearanceSettingsPage } from './AppearanceSettingsPage';
import { ThemeColorSettingsPage } from './ThemeColorSettingsPage';
import { ContentFilterSettingsPage } from './ContentFilterSettingsPage';
import { IdentityManagementPage } from './IdentityManagementPage';
import { ReadingSettingsPage } from './ReadingSettingsPage';
import { SystemUpdateSettingsPage } from './SystemUpdateSettingsPage';
import { materialCanvas } from './components/MaterialCanvas';
import { ChannelFeedInteractionBridge } from './ChannelFeedState';
import { dailyDateCursor, dailyPickerDate, formatDailyDate } from './DailyFeedDates';

const PROJECT_HOME_URI: string = 'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS';

@Component
export struct P1Shell {
  @BuilderParam homeContent: (reloadToken: number, navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam followingContent: (reloadToken: number, navigate: (destination: P1Destination) => void,
    selectedTabIndex: number) => void =
    this.emptyReloadableHome;
  @BuilderParam hotContent: (reloadToken: number, navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam dailyContent: (reloadToken: number, dateCursor: string,
    navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableDaily;
  @BuilderParam dailyStoryContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam technicalLabContent: (navigate: (destination: P1Destination) => void,
    onDeveloperModeDisabled: () => void) => void =
    this.emptyTechnicalLab;
  @BuilderParam searchContent: (query: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void =
    this.emptySearch;
  @BuilderParam commentContent: (destination: P1Destination,
    navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyComment;
  @BuilderParam questionContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam answerContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam articleContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam videoContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyDetailContent;
  @BuilderParam writeAnswerContent: (questionId: string, answerId: string | undefined,
    navigate: (destination: P1Destination) => void, onBack: () => void) => void = this.emptyWriteAnswer;
  @BuilderParam writePinContent: (draftId: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void = this.emptyWritePin;
  @BuilderParam pinDraftInboxContent: (navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyPinDraftInbox;
  @BuilderParam peopleContent: (id: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void = this.emptyPeople;
  @BuilderParam pinContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyPinContent;
  @BuilderParam collectionsContent: (id: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void = this.emptyCollections;
  @BuilderParam collectionContentContent: (id: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void = this.emptyCollectionContent;
  @BuilderParam notificationContent: (navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyHome;
  @BuilderParam notificationEntryContent: (entryName: string, title: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyNotificationEntry;
  @BuilderParam privateMessageContent: (peerId: string, peerName: string, avatarUrl: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyPrivateMessage;
  @BuilderParam notificationSettingsContent: (navigate: (destination: P1Destination) => void) => void = this.emptyHome;
  @BuilderParam blockingRulesContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam blockedFeedHistoryContent: (onBack: () => void) => void = this.emptyPage;
  @BuilderParam readHistoryContent: (navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyHome;
  @BuilderParam localHistoryContent: (navigate: (destination: P1Destination) => void, onBack: () => void) => void =
    this.emptyHome;
  @BuilderParam loginContent: (onBack: () => void, onAuthenticated: () => void,
    onScanDesktopLogin: () => void) => void = this.emptyLogin;
  @BuilderParam readerProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam imageProbeContent: (onBack: () => void) => void = this.emptyProbe;
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
  @StorageProp('peopleTitleStates') private peopleTitleStates: PeopleTitleState[] = [];
  /** 全屏图片查看器打开中（详情页广播）：同样隐藏顶栏，使查看器真全屏。 */
  @StorageProp('p2ImagePreviewUrl') private imagePreviewUrl: string = '';
  @State private installedVersionLabel: string = '正在读取已安装版本…';
  @State private aboutVersionSheetShown: boolean = false;
  @State private developerModeEnabled: boolean = false;
  @State private versionTapCount: number = 0;
  /** GitHub 最新 Release 检出有新版本时非空：驱动“我的”页横幅与版本弹层下载入口。 */
  @State private pendingUpdateRelease: AppUpdateRelease | undefined = undefined;
  @State private updateCheckBusy: boolean = false;
  @State private updateCheckMessage: string = '';
  private installedVersionName: string = '';
  private readonly updateClient: AppUpdateClient = new AppUpdateClient();
  @State private projectLicenseSheetShown: boolean = false;
  @State private openSourceLicensesSheetShown: boolean = false;
  @State private projectHomeHelpShown: boolean = false;
  @State private projectHomeLaunchStatus: string = '';
  @State private settingsSearchQuery: string = '';
  @State private accountLogoutBusy: boolean = false;
  @State private homeReloadToken: number = 0;
  @State private followingReloadToken: number = 0;
  @State private hotReloadToken: number = 0;
  @State private dailyReloadToken: number = 0;
  // 关注页子页签（推荐/动态）当前选中项：经 AppStorage 与关注页 Swiper 双向同步
  // （标题栏点选写 tick，关注页滑动写 index），@Consume 在 HdsTabs 树下实测不链接。
  @StorageProp('followingSelectedTabIndex') private followingTitleSelectedIndex: number = 0;
  @StorageProp('dailyViewingDate') private dailyViewingDate: string = '';
  @State private dailyDateCursor: string = '';
  @Provide('channelFeedInteractionBridge') private channelFeedInteractionBridge: ChannelFeedInteractionBridge =
    new ChannelFeedInteractionBridge();
  @State @Watch('onTopLevelTabIndexChanged') private topLevelTabIndex: number = P1TopLevelTab.HOME;
  @State private bottomBarOrder: number[] = [P1TopLevelTab.HOME, P1TopLevelTab.FOLLOWING,
    P1TopLevelTab.HOT, P1TopLevelTab.DAILY, P1TopLevelTab.ACCOUNT];
  @StorageProp('bottomBarItems') @Watch('onBottomBarItemsChanged') private bottomBarItems: string =
    'Home,Following,Hot,Daily,Settings';
  @StorageProp('tapToRefresh') private tapToRefresh: boolean = true;
  /** 当前生效主题色（启动时广播，深浅色已解析），驱动全壳强调色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 主题色 seed：设置页选择/拖动时写入，@Watch 重新解析生效色并广播（否则换色不生效）。 */
  @StorageProp('themeColor') @Watch('onThemeColorSeedChanged') private themeColorSeed: string =
    DEFAULT_THEME_COLOR;
  private startDestinationApplied: boolean = false;
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  @Provide('p1PathStack') pathStack: NavPathStack = new NavPathStack();
  private unsubscribeStartupDestination: (() => void) | undefined = undefined;
  private readonly themeOperationGuard: LatestOperationGuard = new LatestOperationGuard();
  private themeMounted: boolean = false;
  private themeSaveQueue: Promise<void> = Promise.resolve();
  /** 排版偏好专用 store 实例：滑块拖动会高频写盘，需单实例 saveQueue 串行化。 */

  aboutToAppear(): void {
    this.themeMounted = true;
    // 主题恢复完成前先按跟随系统广播（EntryAbility.onConfigurationUpdate 依赖该键判断是否联动公式换色）。
    AppStorage.setOrCreate('appThemeMode', AppThemeMode.SYSTEM);
    AppStorage.setOrCreate('formulaForegroundColor', this.resolveFormulaForegroundColor(AppThemeMode.SYSTEM));
    AppStorage.setOrCreate('appearanceThemeTick', AppStorage.get<number>('appearanceThemeTick') ?? 0);
    // 主题色恢复前先广播默认 seed 与按当前模式解析的生效色，保证组件挂载即有值。
    AppStorage.setOrCreate('themeColor', DEFAULT_THEME_COLOR);
    AppStorage.setOrCreate('resolvedThemeColor', this.resolveThemeColorForMode(AppThemeMode.SYSTEM, DEFAULT_THEME_COLOR));
    this.sessionSnapshot = this.session?.getState();
    this.restoreThemeMode();
    void this.restoreThemeColor();
    void this.restoreAnswerDoubleTapAction();
    void this.restoreReaderTypography();
    void this.restoreAppearancePreferences();
    void this.restoreExperiencePreferences();
    void this.restoreDeveloperMode();
    this.refreshInstalledVersionLabel();
    this.unsubscribeStartupDestination?.();
    const listener: StartupDestinationListener = (destination: P1Destination): void => {
      this.navigate(destination);
    };
    this.unsubscribeStartupDestination = startupDestinationChannel.subscribe(listener);
    // 诊断：输出当前设备支持的沉浸材质类型（含 IMMERSIVE 即支持沉浸光感流动光效）。
    hilog.info(0x0000, 'ImmersiveLight', 'systemMaterialTypes=%{public}s',
      JSON.stringify(hdsMaterial.getSystemMaterialTypes()));
    // 每次启动静默检查 GitHub 最新 Release；失败不打扰，检出新版本时在“我的”页提示。
    void this.runUpdateCheck(false);
  }

  aboutToDisappear(): void {
    this.themeMounted = false;
    this.themeOperationGuard.invalidate();
    this.unsubscribeStartupDestination?.();
    this.unsubscribeStartupDestination = undefined;
  }

  @Builder
  emptyHome(_navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptyNotificationEntry(_entryName: string, _title: string, _navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptyPrivateMessage(_peerId: string, _peerName: string, _avatarUrl: string, _navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptyReloadableHome(_reloadToken: number, _navigate: (destination: P1Destination) => void,
    _selectedTabIndex: number = 0) {
    Blank();
  }

  @Builder
  emptyReloadableDaily(_reloadToken: number, _dateCursor: string,
    _navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptyTechnicalLab(_navigate: (destination: P1Destination) => void, _onDeveloperModeDisabled: () => void) {
    Blank();
  }

  @Builder
  emptySearch(_query: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyComment(_destination: P1Destination,
    _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyContent(_id: string, _navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptyDetailContent(_id: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPinContent(_id: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyWriteAnswer(_questionId: string, _answerId: string | undefined,
    _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyWritePin(_draftId: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPinDraftInbox(_navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyCollections(_id: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyCollectionContent(_id: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyPeople(_id: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
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

  @Builder
  emptyLogin(_onBack: () => void, _onAuthenticated: () => void, _onScanDesktopLogin: () => void) {
    Blank();
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    this.destinationContent(decodeP1Destination(name, param));
  }

  @Builder
  private destinationContent(destination: P1Destination | undefined) {
    if (destination === undefined) {
      HdsNavDestination() {
        this.invalidDestinationPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '无法打开页面' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.SETTINGS) {
      HdsNavDestination() {
        this.settingsPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '我的' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.APPEARANCE_SETTINGS) {
      HdsNavDestination() {
        AppearanceSettingsPage({
          themeMode: this.themeMode,
          onThemeModeChange: (mode: AppThemeMode): void => {
            void this.selectThemeMode(mode);
          },
          onOpenThemeColorSettings: (): void => this.navigate({ name: P1DestinationName.THEME_COLOR_SETTINGS })
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '外观与阅读体验' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.THEME_COLOR_SETTINGS) {
      HdsNavDestination() {
        ThemeColorSettingsPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '主题颜色' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.IDENTITY_MANAGEMENT) {
      HdsNavDestination() {
        IdentityManagementPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '身份管理' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.READING_SETTINGS) {
      HdsNavDestination() {
        ReadingSettingsPage();
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '朗读与播放' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.SYSTEM_UPDATE_SETTINGS) {
      HdsNavDestination() {
        SystemUpdateSettingsPage({
          installedVersionLabel: this.installedVersionLabel,
          updateCheckBusy: this.updateCheckBusy,
          updateCheckMessage: this.updateCheckMessage,
          availableVersion: this.pendingUpdateRelease?.versionName ?? '',
          onCheckUpdate: (): void => { void this.runUpdateCheck(true); },
          onOpenDownload: (): void => this.openPendingUpdate(),
          onOpenProject: (): void => this.openProjectHome()
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '系统与更新' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.RECOMMENDATION_FILTER_SETTINGS) {
      HdsNavDestination() {
        ContentFilterSettingsPage({
          preferences: this.createPreferencesStore(),
          runtime: this.createFilterRuntimeStore(),
          onOpenBlocklist: (): void => this.navigate({ name: P1DestinationName.BLOCKING_RULES }),
          onOpenBlockedHistory: (): void => this.navigate({ name: P1DestinationName.BLOCKED_FEED_HISTORY })
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '推荐系统与内容过滤' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.BLOCKING_RULES) {
      HdsNavDestination() {
        this.blockingRulesContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '内容屏蔽' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.BLOCKED_FEED_HISTORY) {
      HdsNavDestination() {
        this.blockedFeedHistoryContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '屏蔽记录' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.READ_HISTORY) {
      HdsNavDestination() {
        this.readHistoryContent((nextDestination: P1Destination): void => this.navigate(nextDestination), (): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({
        style: getImmersiveTitleBarStyle(),
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
    } else if (destination.name === P1DestinationName.LOCAL_HISTORY) {
      HdsNavDestination() {
        this.localHistoryContent((nextDestination: P1Destination): void => this.navigate(nextDestination),
          (): void => {
            this.pathStack.pop();
          });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '本地历史记录' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.TECHNICAL_LAB) {
      HdsNavDestination() {
        this.technicalLabContent((destination: P1Destination): void => this.navigate(destination), (): void => {
          this.disableDeveloperMode();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '开发者选项' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.LOGIN) {
      HdsNavDestination() {
        this.loginContent((): void => {
          this.pathStack.pop();
        }, (): void => {
          this.returnFromSuccessfulLogin();
        }, (): void => {
          this.navigate({ name: P1DestinationName.QR_DESKTOP_LOGIN_SCAN });
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '登录' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.SEARCH) {
      HdsNavDestination() {
        this.searchContent(
          destination.query,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({
        style: getImmersiveTitleBarStyle(),
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
    } else if (destination.name === P1DestinationName.COMMENT) {
      HdsNavDestination() {
        this.commentContent(
          destination,
          (nextDestination: P1Destination): void => this.navigate(nextDestination),
          (): void => { this.pathStack.pop(); }
        );
      }
      .titleBar({
        style: getPersistentImmersiveTitleBarStyle(),
        avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => this.commentTitleBar(destination.contentType, destination.contentId),
          divider: { showType: DividerShowType.OFF }
        }
      })
      .hideBackButton(true)
      .hideTitleBar(false)
      .onBackPressed((): boolean => {
        this.requestCommentPageBack(destination.contentType, destination.contentId);
        return true;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.FOLLOWING) {
      HdsNavDestination() {
        this.followingContent(this.followingReloadToken,
          (destination: P1Destination): void => this.navigate(destination),
          this.followingTitleSelectedIndex);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '关注' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.HOT) {
      HdsNavDestination() {
        this.hotContent(this.hotReloadToken, (destination: P1Destination): void => this.navigate(destination));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '热榜' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(false)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DAILY) {
      HdsNavDestination() {
        this.dailyContent(this.dailyReloadToken, this.dailyDateCursor,
          (destination: P1Destination): void => this.navigate(destination));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '知乎日报' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(false)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DAILY_STORY) {
      HdsNavDestination() {
        this.dailyStoryContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '日报正文' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.QUESTION) {
      HdsNavDestination() {
        this.questionContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getPersistentImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.questionTitleBar(destination.id), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
      // 问题页正文图片同样可打开全屏查看器：隐藏顶栏，返回键优先关查看器。
      .hideTitleBar(this.detailImmersiveActive || this.detailTitleHiddenByScroll || this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('p2ImagePreviewUrl', '');
          return true;
        }
        return false;
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.ANSWER) {
      HdsNavDestination() {
        this.answerContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getPersistentImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.answerTitleBar(destination.id), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
      // 沉浸式/图片查看器中隐藏顶栏（对齐上游 topBar={}）；返回键优先关查看器、再退沉浸式。
      .hideTitleBar(this.detailImmersiveActive || this.detailTitleHiddenByScroll || this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('p2ImagePreviewUrl', '');
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
    } else if (destination.name === P1DestinationName.ARTICLE) {
      HdsNavDestination() {
        this.articleContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getPersistentImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.articleTitleBar(destination.id), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
      // 与回答页一致：沉浸式/图片查看器中隐藏顶栏，返回键优先关查看器。
      .hideTitleBar(this.detailImmersiveActive || this.detailTitleHiddenByScroll || this.imagePreviewUrl.length > 0)
      .onBackPressed((): boolean => {
        if (this.imagePreviewUrl.length > 0) {
          AppStorage.setOrCreate('p2ImagePreviewUrl', '');
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
    } else if (destination.name === P1DestinationName.VIDEO) {
      HdsNavDestination() {
        this.videoContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '视频' }, divider: { showType: DividerShowType.OFF } } })
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.WRITE_ANSWER) {
      HdsNavDestination() {
        this.writeAnswerContent(
          destination.questionId,
          destination.answerId,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '写回答' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.WRITE_PIN) {
      HdsNavDestination() {
        this.writePinContent(
          destination.draftId,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '发布想法' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PIN_DRAFTS) {
      HdsNavDestination() {
        this.pinDraftInboxContent(
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '想法草稿' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PEOPLE) {
      HdsNavDestination() {
        this.peopleContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: peopleTitleText(this.peopleTitleStates, destination.id) },
          divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PIN) {
      HdsNavDestination() {
        this.pinContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '想法' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.COLLECTIONS) {
      HdsNavDestination() {
        this.collectionsContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '收藏夹' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.COLLECTION) {
      HdsNavDestination() {
        this.collectionContentContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '收藏夹内容' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.NOTIFICATION) {
      HdsNavDestination() {
        this.notificationContent(
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      // 消息中心标题栏对齐上游：标题「消息」+ 右上角已读/设置动作（同搜索页 stackBuilder 模式）。
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => this.notificationTitleBar(),
          backIcon: { action: (): void => { this.pathStack.pop(); } },
          divider: { showType: DividerShowType.OFF }
        }
      })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.NOTIFICATION_ENTRY) {
      HdsNavDestination() {
        this.notificationEntryContent(
          (destination as NotificationEntryDestination).entryName,
          (destination as NotificationEntryDestination).title,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: (destination as NotificationEntryDestination).title },
          divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PRIVATE_MESSAGE) {
      HdsNavDestination() {
        this.privateMessageContent(
          (destination as PrivateMessageDestination).peerId,
          (destination as PrivateMessageDestination).peerName ?? '',
          (destination as PrivateMessageDestination).avatarUrl ?? '',
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle:
          ((destination as PrivateMessageDestination).peerName ?? '').length > 0
            ? ((destination as PrivateMessageDestination).peerName as string) : '私信' },
          divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.NOTIFICATION_SETTINGS) {
      HdsNavDestination() {
        this.notificationSettingsContent((destination: P1Destination): void => this.navigate(destination));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '通知设置' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.READER_PROBE) {
      HdsNavDestination() {
        this.readerProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '阅读器诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.IMAGE_PROBE) {
      HdsNavDestination() {
        this.imageProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '图片诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DATABASE_PROBE) {
      HdsNavDestination() {
        this.databaseProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '数据库诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DEEP_LINK_PROBE) {
      HdsNavDestination() {
        this.deepLinkProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '深链诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.QR_SCAN_PROBE) {
      HdsNavDestination() {
        this.qrScanProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '二维码诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.QR_DESKTOP_LOGIN_SCAN) {
      HdsNavDestination() {
        this.qrDesktopLoginScanContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '扫描电脑端登录码' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.BACKGROUND_TASK_PROBE) {
      HdsNavDestination() {
        this.backgroundTaskProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '后台任务诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DOMAIN_FIXTURE_PROBE) {
      HdsNavDestination() {
        this.domainFixtureProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '领域数据诊断' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else {
      HdsNavDestination() {
        this.businessPlaceholder(destination);
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true,
        content: { title: { mainTitle: destination.name }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    }
  }

  build() {
    HdsNavigation(this.pathStack) {
      ZhihuHdsTabs({
        currentIndex: $topLevelTabIndex,
        controller: this.tabsController,
        onTabDoubleTap: (index: number): void => {
          // 双击页签刷新对应 feed（“我的”除外）；跨页面信号经 AppStorage 广播。
          const tab = this.tabAtDisplayIndex(index);
          if (tab < P1TopLevelTab.HOME || tab > P1TopLevelTab.DAILY) {
            return;
          }
          const nextTick = (AppStorage.get<number>('tabRefreshTick') ?? 0) + 1;
          AppStorage.setOrCreate('tabRefreshTick', nextTick);
          AppStorage.setOrCreate('tabRefreshTabIndex', tab);
        },
        onCurrentTabTap: (index: number): void => {
          const tab = this.tabAtDisplayIndex(index);
          if (!this.tapToRefresh || tab < P1TopLevelTab.HOME || tab > P1TopLevelTab.DAILY) {
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
            this.topLevelTabPage(tab as P1TopLevelTab)
          }
          .id(`p1_top_level_${this.tabKey(tab as P1TopLevelTab)}_content`)
          .tabBar(this.topLevelTabBarStyle(tab as P1TopLevelTab))
        }, (tab: number): string => `${tab}`)
      }
    }
    .titleBar({
      style: getImmersiveTitleBarStyle(),
      avoidLayoutSafeArea: true,
      content: {
        stackBuilder: (): void => this.rootTitleBarContent(),
        divider: { showType: DividerShowType.OFF }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .monopolizeEvents(false)
    .navDestination(this.destinationBuilder)
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private topLevelTabPage(tab: P1TopLevelTab) {
    if (tab === P1TopLevelTab.HOME) {
      this.homeContent(this.homeReloadToken, (destination: P1Destination): void => this.navigate(destination))
    } else if (tab === P1TopLevelTab.FOLLOWING) {
      this.followingContent(this.followingReloadToken,
        (destination: P1Destination): void => this.navigate(destination), this.followingTitleSelectedIndex)
    } else if (tab === P1TopLevelTab.HOT) {
      this.hotContent(this.hotReloadToken, (destination: P1Destination): void => this.navigate(destination))
    } else if (tab === P1TopLevelTab.DAILY) {
      this.dailyContent(this.dailyReloadToken, this.dailyDateCursor,
        (destination: P1Destination): void => this.navigate(destination))
    } else if (tab === P1TopLevelTab.HISTORY) {
      this.readHistoryContent((destination: P1Destination): void => this.navigate(destination), (): void => {})
    } else if (tab === P1TopLevelTab.COLLECTIONS) {
      this.topLevelCollectionsPage()
    } else {
      this.settingsPage()
    }
  }

  @Builder
  private topLevelCollectionsPage() {
    if (this.currentAccountIdentifier().length > 0) {
      this.collectionsContent(this.currentAccountIdentifier(),
        (destination: P1Destination): void => this.navigate(destination), (): void => {})
    } else {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        Text('登录后查看收藏夹')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontColor($r('app.color.primary_text'))
        Button('去登录').onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    }
  }

  private topLevelTabBarStyle(tab: P1TopLevelTab): BottomTabBarStyle {
    // 图标语义直白优先：house/person_2/flame/doc_text/person（经系统符号表核实）。
    let icon: Resource = $r('sys.symbol.house');
    if (tab === P1TopLevelTab.FOLLOWING) {
      icon = $r('sys.symbol.person_2');
    } else if (tab === P1TopLevelTab.HOT) {
      icon = $r('sys.symbol.flame');
    } else if (tab === P1TopLevelTab.DAILY) {
      icon = $r('sys.symbol.doc_text');
    } else if (tab === P1TopLevelTab.HISTORY) {
      icon = $r('sys.symbol.clock');
    } else if (tab === P1TopLevelTab.COLLECTIONS) {
      icon = $r('sys.symbol.bookmark');
    } else if (tab === P1TopLevelTab.ACCOUNT) {
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

  private tabLabel(tab: P1TopLevelTab): string {
    switch (tab) {
      case P1TopLevelTab.HOME:
        return '首页';
      case P1TopLevelTab.FOLLOWING:
        return '关注';
      case P1TopLevelTab.HOT:
        return '热榜';
      case P1TopLevelTab.DAILY:
        return '日报';
      case P1TopLevelTab.HISTORY:
        return '历史';
      case P1TopLevelTab.COLLECTIONS:
        return '收藏夹';
      case P1TopLevelTab.ACCOUNT:
        return '我的';
    }
  }

  private tabAtDisplayIndex(index: number): P1TopLevelTab {
    const value = this.bottomBarOrder[index];
    return value === undefined ? P1TopLevelTab.HOME : value as P1TopLevelTab;
  }

  private activeTopLevelTab(): P1TopLevelTab {
    return this.tabAtDisplayIndex(this.topLevelTabIndex);
  }

  private tabKey(tab: P1TopLevelTab): string {
    if (tab === P1TopLevelTab.FOLLOWING) return 'following';
    if (tab === P1TopLevelTab.HOT) return 'hot';
    if (tab === P1TopLevelTab.DAILY) return 'daily';
    if (tab === P1TopLevelTab.HISTORY) return 'history';
    if (tab === P1TopLevelTab.COLLECTIONS) return 'collections';
    if (tab === P1TopLevelTab.ACCOUNT) return 'account';
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
    NotificationTitleBar({ navigate: (destination: P1Destination): void => this.navigate(destination) })
  }

  /** 回答页标题栏：滚动折叠时在返回键右侧显示问题单行 + 答主摘要（对齐上游折叠顶栏）。 */
  @Builder
  private answerTitleBar(id: string) {
    AnswerTitleBar({ answerId: id, onBack: (): void => { this.pathStack.pop(); } })
  }

  /** 文章页标题栏：滚动折叠时在返回键右侧显示文章标题单行（对齐问题页折叠模式）。 */
  @Builder
  private articleTitleBar(id: string) {
    ArticleTitleBar({ articleId: id, onBack: (): void => { this.pathStack.pop(); } })
  }

  @Builder
  private detailTitleBar(title: string) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
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
        .fontSize($r('app.float.p1_heading_font_size'))
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
    .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding') })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private rootTitleBarContent() {
    Stack({ alignContent: Alignment.Center }) {
    if (this.activeTopLevelTab() === P1TopLevelTab.HOME) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
            Text('搜索内容')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .id('p2_home_titlebar_search')
        .layoutWeight(1)
        .height(40)
        .padding($r('app.float.p1_spacing_small'))
        .backgroundColor(Color.Transparent)
        // uiMaterial 全家族为 API 26 专属；工程最低兼容 API 23，标题栏玻璃一律走模糊兜底
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .borderRadius($r('app.float.p1_card_radius'))
        .accessibilityText('打开搜索')
        .onClick((): void => this.navigate({ name: P1DestinationName.SEARCH, query: '' }))

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p2_home_titlebar_notifications')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .accessibilityText('打开通知')
        .onClick((): void => this.navigate({ name: P1DestinationName.NOTIFICATION }))
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.activeTopLevelTab() === P1TopLevelTab.FOLLOWING) {
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
    } else if (this.activeTopLevelTab() === P1TopLevelTab.HOT) {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p2_hot_titlebar_refresh')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .accessibilityText('刷新热榜')
        .onClick((): void => {
          this.hotReloadToken += 1;
          this.channelFeedInteractionBridge.refreshHot();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.activeTopLevelTab() === P1TopLevelTab.DAILY) {
      Row() {
        Column({ space: 2 }) {
          Text('知乎日报')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          if (this.dailyViewingDate.length > 0) {
            Text(formatDailyDate(this.dailyViewingDate))
              .id('p2_daily_titlebar_current_date')
              .fontSize($r('app.float.p1_secondary_font_size'))
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
        .id('p2_daily_titlebar_date')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .accessibilityText('选择日报日期')
        .onClick((): void => {
          this.openDailyDatePicker();
        })
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    }
    .id('p2_root_titlebar_content')
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
      .id(`p2_following_titlebar_tab_${index}`)
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
  settingsPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
          this.accountOverview()
          this.accountQuickActions()

          Text('创作')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column() {
            AppNavigationRow({ title: '发布想法', description: '创建一条新的想法', testId: 'p4_open_pin_publish', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.square_and_pencil'),
              onRowClick: (): void => this.openPinComposer() });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '想法草稿', description: '继续编辑本地保存的草稿', testId: 'p4_open_pin_drafts', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.doc_text'),
              onRowClick: (): void => this.navigate({ name: P1DestinationName.PIN_DRAFTS }) });
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          TextInput({ text: this.settingsSearchQuery, placeholder: '搜索设置' })
            .id('p3_settings_search')
            .width('100%')
            .onChange((value: string): void => {
              this.settingsSearchQuery = value;
            })

          if (this.hasSettingsSearchQuery()) {
            this.settingsSearchResults()
          } else {
          Text('设置')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column({ space: $r('app.float.p1_spacing_small') }) {
            if (this.sessionSnapshot?.status === SessionStatus.AUTHENTICATED) {
              AppNavigationRow({ title: '身份管理', description: '创建马甲号或切换当前身份',
                testId: 'p5_open_identity_management', grouped: true,
                showLeadingIcon: true, leadingIcon: $r('sys.symbol.person_2'),
                onRowClick: (): void => this.navigate({ name: P1DestinationName.IDENTITY_MANAGEMENT }) });
              Divider().color($r('app.color.divider_color'))
            }
            AppNavigationRow({ title: '外观与阅读体验', description: '主题、阅读排版与信息流显示',
              testId: 'p3_open_appearance_settings', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.eye'),
              onRowClick: (): void => this.navigate({ name: P1DestinationName.APPEARANCE_SETTINGS }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '朗读与播放', description: '语音、语速与当前播放控制',
              testId: 'p5_open_reading_settings', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.mic'),
              onRowClick: (): void => this.navigate({ name: P1DestinationName.READING_SETTINGS }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '推荐系统与内容过滤', description: '推荐来源、质量规则与内容屏蔽',
              testId: 'p3_open_recommendation_filter_settings', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.eye_slash'),
              onRowClick: (): void => this.navigate({ name: P1DestinationName.RECOMMENDATION_FILTER_SETTINGS }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '通知设置', description: '设置提醒和推送偏好', testId: 'p3_open_notification_settings', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.bell_badge_gearshape'),
              onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION_SETTINGS }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '系统与更新', description: '版本信息、检查更新与问题反馈',
              testId: 'p5_open_system_update_settings', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.arrow_clockwise'),
              onRowClick: (): void => this.navigate({ name: P1DestinationName.SYSTEM_UPDATE_SETTINGS }) });
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('关于与诊断')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column() {
            if (this.pendingUpdateRelease !== undefined) {
              AppNavigationRow({ title: this.pendingUpdateTitle(),
                description: '点击前往 GitHub 下载新版 HAP', testId: 'p3_open_update_download', grouped: true,
                showLeadingIcon: true, leadingIcon: $r('sys.symbol.arrow_clockwise'),
                onRowClick: (): void => {
                  const release = this.pendingUpdateRelease;
                  const url = release !== undefined && release.htmlUrl.length > 0
                    ? release.htmlUrl
                    : PROJECT_HOME_URI + '/releases/latest';
                  this.openExternalUrl(url, '无法打开发布页');
                } });
              Divider().color($r('app.color.divider_color'))
            }
            AppNavigationRow({ title: '应用与版本', description: this.installedVersionLabel,
              testId: 'p3_open_about_version', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.info_circle'),
              onRowClick: (): void => {
                this.onVersionRowClicked();
              } });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: 'GitHub', description: '查看项目主页', testId: 'p3_open_project_home', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('app.media.github_mark'), leadingIconIsMedia: true,
              onRowClick: (): void => this.openProjectHome() });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '项目协议', description: 'GNU AGPL v3.0',
              testId: 'p3_open_project_license', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.checkmark_square'),
              onRowClick: (): void => {
                this.projectLicenseSheetShown = true;
              } });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '开源许可', description: '3 个本地 HAR 模块 · GNU AGPL v3.0',
              testId: 'p3_open_open_source_licenses', grouped: true,
              showLeadingIcon: true, leadingIcon: $r('sys.symbol.doc_text'),
              onRowClick: (): void => {
                this.openSourceLicensesSheetShown = true;
              } });
            if (this.developerModeEnabled) {
              Divider().color($r('app.color.divider_color'))
              AppNavigationRow({ title: '开发者选项', description: 'Cookie、网络与调试工具',
                testId: 'p1_open_developer_options', grouped: true,
                showLeadingIcon: true, leadingIcon: $r('sys.symbol.gearshape'),
                onRowClick: (): void => this.navigate({ name: P1DestinationName.TECHNICAL_LAB }) });
            }
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('本软件仅供学习交流使用，应用内内容由知乎网站提供，著作权归其对应作者所有。')
            .id('p3_account_disclaimer')
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .padding({ left: $r('app.float.p1_spacing_medium'), right: $r('app.float.p1_spacing_medium') })
        }
        }
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: 94,
        // HdsTabs 的悬浮底栏会覆盖滚动区末端；为最后一个设置项预留可点击空间。
        bottom: 96
      })
      .id('p1_settings_scroll')
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
      Column()
        .bindSheet(this.aboutVersionSheetShown, this.aboutVersionSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
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
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
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
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
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
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
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
    .id('p1_settings_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private accountOverview() {
    if (this.accountSessionState()?.status === SessionStatus.AUTHENTICATED) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Stack({ alignContent: Alignment.Center }) {
              Text(this.accountAvatarLetter())
                .width(56)
                .height(56)
                .borderRadius(28)
                .backgroundColor(themeColorContainerColor(this.resolvedThemeColor))
                .fontSize($r('app.float.p1_heading_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.resolvedThemeColor)
                .textAlign(TextAlign.Center)
              // 有头像地址时叠加真实头像；加载失败露出首字占位。
              if (this.accountAvatarUrl().length > 0) {
                Image(this.accountAvatarUrl())
                  .id('p3_account_overview_avatar')
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .objectFit(ImageFit.Cover)
              }
            }
            .id('p3_account_overview_avatar_box')
            Text(this.accountTitle())
              .id('p3_account_overview_title')
              .fontSize($r('app.float.p1_heading_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('打开个人主页')
        .onClick((): void => this.openCurrentProfile())

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.barcode_viewfinder'))
            .fontSize(22)
            .fontColor([this.resolvedThemeColor])
        }
          .id('p4_account_scan_desktop_login')
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(themeColorContainerColor(this.resolvedThemeColor))
          .accessibilityText('扫描电脑端登录二维码')
          .onClick((): void => this.navigate({ name: P1DestinationName.QR_DESKTOP_LOGIN_SCAN }))

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_right_and_square'))
            .fontSize(22)
            .fontColor([$r('app.color.error_text')])
        }
          .id('p2_account_logout')
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor($r('app.color.control_background'))
          .enabled(!this.accountLogoutBusy)
          .accessibilityText('退出登录')
          .onClick((): void => this.confirmAccountLogout())
      }
      .id('p3_account_overview')
      .width('100%')
      .alignItems(VerticalAlign.Center)
    } else {
      AppNavigationRow({ title: '登录知乎', description: '管理当前知乎账号的登录状态', testId: 'p2_open_login',
        grouped: false, showLeadingIcon: true, leadingIcon: $r('sys.symbol.person'),
        onRowClick: (): void => this.navigate({ name: P1DestinationName.LOGIN }) })
    }
  }

  @Builder
  private accountQuickActions() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(20)
            .fontColor([this.resolvedThemeColor])
          Text('收藏夹')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.primary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .id('p3_open_my_collections')
      .layoutWeight(1)
      .height(72)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius($r('app.float.p1_card_radius'))
      .accessibilityText('打开我的收藏夹')
      .onClick((): void => this.openMyCollections())

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise_clock'))
            .fontSize(20)
            .fontColor([this.resolvedThemeColor])
          Text('历史')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.primary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .id('p3_account_quick_history')
      .layoutWeight(1)
      .height(72)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius($r('app.float.p1_card_radius'))
      .accessibilityText('打开历史')
      .onClick((): void => this.navigate({ name: P1DestinationName.READ_HISTORY }))

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(20)
            .fontColor([this.resolvedThemeColor])
          Text('通知')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.primary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .id('p3_account_quick_notifications')
      .layoutWeight(1)
      .height(72)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius($r('app.float.p1_card_radius'))
      .accessibilityText('打开通知')
      .onClick((): void => this.navigate({ name: P1DestinationName.NOTIFICATION }))
    }
    .id('p3_account_quick_actions')
    .width('100%')
  }

  @Builder
  private settingsSearchResults() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('搜索结果')
        .id('p3_settings_search_result_title')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      if (this.settingsSearchMatches('账号与登录', this.accountSummary())) {
        AppNavigationRow({ title: '账号与登录', description: this.accountSummary(), testId: 'p2_open_login',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.person'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.LOGIN }) });
      }
      if (this.settingsSearchMatches('发布想法', '创建一条新的想法')) {
        AppNavigationRow({ title: '发布想法', description: '创建一条新的想法', testId: 'p4_open_pin_publish',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.square_and_pencil'),
          onRowClick: (): void => this.openPinComposer() });
      }
      if (this.settingsSearchMatches('想法草稿', '继续编辑本地保存的草稿')) {
        AppNavigationRow({ title: '想法草稿', description: '继续编辑本地保存的草稿', testId: 'p4_open_pin_drafts',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.doc_text'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.PIN_DRAFTS }) });
      }
      if (this.settingsSearchMatches('我的收藏夹', '查看自己的知乎收藏夹')) {
        AppNavigationRow({ title: '我的收藏夹', description: '查看自己的知乎收藏夹', testId: 'p3_open_my_collections',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.bookmark'),
          onRowClick: (): void => this.openMyCollections() });
      }
      if (this.settingsSearchMatches('内容屏蔽', '管理作者与关键词屏蔽规则')) {
        AppNavigationRow({ title: '内容屏蔽', description: '管理作者与关键词屏蔽规则', testId: 'p2_open_blocking_rules',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.eye_slash'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKING_RULES }) });
      }
      if (this.settingsSearchMatches('屏蔽记录', '查看最近隐藏的内容')) {
        AppNavigationRow({ title: '屏蔽记录', description: '查看最近隐藏的内容', testId: 'p3_open_blocked_feed_history',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.arrow_counterclockwise_clock'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKED_FEED_HISTORY }) });
      }
      if (this.settingsSearchMatches('通知设置', '设置提醒和推送偏好')) {
        AppNavigationRow({ title: '通知设置', description: '设置提醒和推送偏好', testId: 'p3_open_notification_settings',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.bell_badge_gearshape'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION_SETTINGS }) });
      }
      if (this.settingsSearchMatches('外观与阅读体验', '主题 阅读排版 信息流 字号 行高 段间距')) {
        AppNavigationRow({ title: '外观与阅读体验', description: '主题、阅读排版与信息流显示',
          testId: 'p3_search_open_appearance_settings',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.eye'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.APPEARANCE_SETTINGS }) });
      }
      if (this.sessionSnapshot?.status === SessionStatus.AUTHENTICATED &&
        this.settingsSearchMatches('身份管理', '创建马甲号 切换当前身份')) {
        AppNavigationRow({ title: '身份管理', description: '创建马甲号或切换当前身份',
          testId: 'p5_open_identity_management',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.person_2'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.IDENTITY_MANAGEMENT }) });
      }
      if (this.settingsSearchMatches('朗读与播放', '语音 语速 音调 播放')) {
        AppNavigationRow({ title: '朗读与播放', description: '语音、语速与当前播放控制',
          testId: 'p5_open_reading_settings',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.mic'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.READING_SETTINGS }) });
      }
      if (this.settingsSearchMatches('推荐系统与内容过滤', '推荐算法 质量过滤 智能过滤 关键词 用户 主题 广告 盐选')) {
        AppNavigationRow({ title: '推荐系统与内容过滤', description: '推荐来源、质量规则与内容屏蔽',
          testId: 'p3_search_open_recommendation_filter_settings',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.eye_slash'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.RECOMMENDATION_FILTER_SETTINGS }) });
      }
      if (this.settingsSearchMatches('系统与更新', '版本信息 检查更新 问题反馈')) {
        AppNavigationRow({ title: '系统与更新', description: '版本信息、检查更新与问题反馈',
          testId: 'p5_open_system_update_settings',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.arrow_clockwise'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.SYSTEM_UPDATE_SETTINGS }) });
      }
      if (this.settingsSearchMatches('应用与版本', this.installedVersionLabel)) {
        AppNavigationRow({ title: '应用与版本', description: this.installedVersionLabel,
          testId: 'p3_open_about_version', showLeadingIcon: true, leadingIcon: $r('sys.symbol.info_circle'),
          onRowClick: (): void => {
            this.onVersionRowClicked();
          } });
      }
      if (this.settingsSearchMatches('GitHub', '查看项目主页')) {
        AppNavigationRow({ title: 'GitHub', description: '查看项目主页', testId: 'p3_open_project_home',
          showLeadingIcon: true, leadingIcon: $r('app.media.github_mark'), leadingIconIsMedia: true,
          onRowClick: (): void => this.openProjectHome() });
      }
      if (this.settingsSearchMatches('项目协议', 'GNU AGPL v3.0')) {
        AppNavigationRow({ title: '项目协议', description: 'GNU AGPL v3.0',
          testId: 'p3_open_project_license', showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.checkmark_square'), onRowClick: (): void => {
            this.projectLicenseSheetShown = true;
          } });
      }
      if (this.settingsSearchMatches('开源许可', '3 个本地 HAR 模块 GNU AGPL v3.0')) {
        AppNavigationRow({ title: '开源许可', description: '3 个本地 HAR 模块 · GNU AGPL v3.0',
          testId: 'p3_open_open_source_licenses', showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.doc_text'), onRowClick: (): void => {
            this.openSourceLicensesSheetShown = true;
          } });
      }
      if (this.developerModeEnabled &&
        this.settingsSearchMatches('开发者选项', 'Cookie 网络 调试工具 技术实验室')) {
        AppNavigationRow({ title: '开发者选项', description: 'Cookie、网络与调试工具', testId: 'p1_open_developer_options',
          showLeadingIcon: true, leadingIcon: $r('sys.symbol.gearshape'),
          onRowClick: (): void => this.navigate({ name: P1DestinationName.TECHNICAL_LAB }) });
      }
      if (!this.hasSettingsSearchResults()) {
        Text('没有匹配的设置项')
          .id('p3_settings_search_empty')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
      }
    }
    .id('p3_settings_search_results')
    .width('100%')
  }

  @Builder
  private aboutVersionSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('应用与版本')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_about_version_close')
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
      Text('知乎++鸿蒙版')
        .id('p3_about_version_app_name')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.installedVersionLabel)
        .id('p3_about_version_value')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .onClick((): void => this.onVersionTapped())
      Text('版本信息来自当前已安装的 HAP，便于核对本机安装结果。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Text(this.developerModeEnabled ? '开发者选项已开启。检查更新已移至“系统与更新”。' :
        '连续点击“应用与版本”设置行 5 次可开启开发者选项。检查更新已移至“系统与更新”。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private projectLicenseSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('项目协议')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_project_license_close')
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
        .id('p3_project_license_name')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('本项目以 GNU AGPL v3.0 许可发布。使用、修改或分发时应遵守该协议；对修改后的版本提供网络服务时，也应按协议向相应用户提供源代码。')
        .id('p3_project_license_summary')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Text('完整法律条款以项目随源代码分发的 LICENSE 文件为准。')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private openSourceLicensesSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('开源许可')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_open_source_licenses_close')
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
        .id('p3_open_source_licenses_summary')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Column() {
        this.openSourceLicenseRow('core', '共享策略、导航与启动 · GNU AGPL v3.0');
        Divider().color($r('app.color.divider_color'))
        this.openSourceLicenseRow('data', '领域模型、网络、会话与本地数据 · GNU AGPL v3.0');
        Divider().color($r('app.color.divider_color'))
        this.openSourceLicenseRow('reader', '原生阅读、数据源与媒体加载 · GNU AGPL v3.0');
      }
      .id('p3_open_source_licenses_list')
      .width('100%')
      .borderRadius($r('app.float.p1_card_radius'))
      .backgroundColor($r('app.color.control_background'))
      Text('HarmonyOS 系统 Kit 为平台 API，不作为第三方打包依赖列入此处。许可名称以各模块 oh-package.json5 的声明为准。')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private projectHomeHelpSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('项目主页')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_project_home_close')
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
        .id('p3_project_home_url')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.projectHomeLaunchStatus)
        .id('p3_project_home_status')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private openSourceLicenseRow(name: string, description: string) {
    Column({ space: $r('app.float.p1_spacing_xsmall') }) {
      Text(name)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(description)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
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
    await this.markUpdateCheckedNow();
    this.updateCheckBusy = true;
    if (verbose) {
      this.updateCheckMessage = '正在检查更新…';
    }
    try {
      const result: AppUpdateCheckResult =
        await this.updateClient.checkLatestRelease(this.installedVersionName);
      if (result.status === AppUpdateCheckStatus.UPDATE_AVAILABLE && result.release !== undefined) {
        this.pendingUpdateRelease = result.release;
        this.broadcastHomeUpdateAnnouncement(result.release.versionName, this.releaseDownloadUrl(result.release));
        if (verbose) {
          this.updateCheckMessage = `发现新版本 ${result.release.versionName}，可前往下载`;
        }
      } else if (result.status === AppUpdateCheckStatus.UP_TO_DATE) {
        this.pendingUpdateRelease = undefined;
        this.broadcastHomeUpdateAnnouncement('', '');
        if (verbose) {
          this.updateCheckMessage = '当前已是最新版本';
        }
      } else if (verbose) {
        this.updateCheckMessage = result.message.length > 0 ? result.message : '检查更新失败，请稍后重试';
      }
      hilog.info(0x0000, 'AppUpdate', 'check status=%{public}s remoteVersion=%{public}s',
        result.status, result.release !== undefined ? result.release.versionName : '');
    } finally {
      this.updateCheckBusy = false;
    }
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
  private broadcastHomeUpdateAnnouncement(version: string, url: string): void {
    AppStorage.setOrCreate('homeUpdateAnnouncementVersion', version);
    AppStorage.setOrCreate('homeUpdateAnnouncementUrl', url);
  }

  private releaseDownloadUrl(release: AppUpdateRelease): string {
    return release.htmlUrl.length > 0 ? release.htmlUrl : PROJECT_HOME_URI + '/releases/latest';
  }

  private pendingUpdateTitle(): string {
    const release = this.pendingUpdateRelease;
    return release !== undefined ? `发现新版本 ${release.versionName}` : '';
  }

  private openPendingUpdate(): void {
    const release = this.pendingUpdateRelease;
    const url = release !== undefined ? this.releaseDownloadUrl(release) : PROJECT_HOME_URI + '/releases/latest';
    this.openExternalUrl(url, '无法打开发布页');
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

  private disableDeveloperMode(): void {
    this.developerModeEnabled = false;
    this.versionTapCount = 0;
    const context = getAbilityContext();
    if (context !== undefined) {
      void new AppPreferencesStore(context).saveDeveloperMode(false);
    }
    this.pathStack.pop();
    this.getUIContext().getPromptAction().showToast({ message: '开发者选项已关闭' });
  }

  private hasSettingsSearchQuery(): boolean {
    return this.settingsSearchQuery.trim().length > 0;
  }

  private settingsSearchMatches(title: string, description: string): boolean {
    const query = this.settingsSearchQuery.trim().toLowerCase();
    return query.length > 0 && `${title} ${description}`.toLowerCase().includes(query);
  }

  private hasSettingsSearchResults(): boolean {
    return this.settingsSearchMatches('账号与登录', this.accountSummary()) ||
      this.settingsSearchMatches('发布想法', '创建一条新的想法') ||
      this.settingsSearchMatches('想法草稿', '继续编辑本地保存的草稿') ||
      this.settingsSearchMatches('我的收藏夹', '查看自己的知乎收藏夹') ||
      this.settingsSearchMatches('内容屏蔽', '管理作者与关键词屏蔽规则') ||
      this.settingsSearchMatches('屏蔽记录', '查看最近隐藏的内容') ||
      this.settingsSearchMatches('通知设置', '设置提醒和推送偏好') ||
      (this.sessionSnapshot?.status === SessionStatus.AUTHENTICATED &&
        this.settingsSearchMatches('身份管理', '创建马甲号 切换当前身份')) ||
      this.settingsSearchMatches('外观与阅读体验', '主题 阅读排版 信息流 字号 行高 段间距') ||
      this.settingsSearchMatches('朗读与播放', '语音 语速 音调 播放') ||
      this.settingsSearchMatches('推荐系统与内容过滤', '推荐算法 质量过滤 智能过滤 关键词 用户 主题 广告 盐选') ||
      this.settingsSearchMatches('系统与更新', '版本信息 检查更新 问题反馈') ||
      this.settingsSearchMatches('应用与版本', this.installedVersionLabel) ||
      this.settingsSearchMatches('GitHub', '查看项目主页') ||
      this.settingsSearchMatches('项目协议', 'GNU AGPL v3.0') ||
      this.settingsSearchMatches('开源许可', '3 个本地 HAR 模块 GNU AGPL v3.0') ||
      (this.developerModeEnabled &&
        this.settingsSearchMatches('开发者选项', 'Cookie 网络 调试工具 技术实验室'));
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

  private accountSummary(): string {
    const state = this.accountSessionState();
    if (state?.status !== SessionStatus.AUTHENTICATED) {
      return '管理当前知乎账号的登录状态';
    }
    const profileName = state.profile?.name.trim() ?? '';
    return profileName.length > 0 ? `已登录：${profileName}` : '已登录';
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
      this.navigate({ name: P1DestinationName.PEOPLE, id: identifier });
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
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Text('导航参数无效')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontColor($r('app.color.primary_text'))
        Text('页面参数未通过校验，请返回后重试。')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
      .align(Alignment.TopStart)
    }
    .id('p1_invalid_destination_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  businessPlaceholder(destination: P1Destination) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Text(destination.name)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        Text(this.destinationDescription(destination))
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
      .align(Alignment.TopStart)
    }
    .id('p1_business_destination_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  private onTopLevelTabIndexChanged(): void {
    this.tabsController.changeIndex(this.topLevelTabIndex);
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
  }

  private navigate(destination: P1Destination): void {
    const topLevelTab = p1TopLevelTabForDestination(destination);
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
      // 防止「返回时只是露出前一个重复页面」（CLAUDE.md 返回栈教训）。
      // 参数化页面不能使用按 name 匹配的 MOVE_TO_TOP_SINGLETON，必须按身份查重。
      const existingIndex = findP1DestinationStackIndex(paths, destination);
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
      this.navigate({ name: P1DestinationName.LOGIN });
      return;
    }
    this.navigate({ name: P1DestinationName.COLLECTIONS, id: identifier });
  }

  /** 路由只持有随机本地草稿键；账号范围和正文均由目标页在认证后解析。 */
  private openPinComposer(): void {
    this.navigate({ name: P1DestinationName.WRITE_PIN, draftId: this.createLocalDraftId() });
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
    const destination = decodeP1Destination(current.name, current.param);
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

  private destinationDescription(destination: P1Destination): string {
    switch (destination.name) {
      case P1DestinationName.SEARCH:
        return `搜索：${destination.query}`;
      case P1DestinationName.COMMENT:
        return `内容：${destination.contentId}`;
      case P1DestinationName.NOTIFICATION:
        return '查看知乎账号的通知消息';
      case P1DestinationName.NOTIFICATION_ENTRY:
        return '查看知乎通知分类消息';
      case P1DestinationName.PRIVATE_MESSAGE:
        return '查看知乎私信会话';
      case P1DestinationName.QUESTION:
      case P1DestinationName.ANSWER:
      case P1DestinationName.ARTICLE:
      case P1DestinationName.VIDEO:
      case P1DestinationName.PIN:
      case P1DestinationName.PEOPLE:
      case P1DestinationName.COLLECTION:
      case P1DestinationName.DAILY_STORY:
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
    } catch (_error) {
      this.developerModeEnabled = false;
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

  private topLevelTabFromPreference(value: string): P1TopLevelTab {
    if (value === 'Following') return P1TopLevelTab.FOLLOWING;
    if (value === 'Hot') return P1TopLevelTab.HOT;
    if (value === 'Daily') return P1TopLevelTab.DAILY;
    if (value === 'ReadHistory') return P1TopLevelTab.HISTORY;
    if (value === 'Collections') return P1TopLevelTab.COLLECTIONS;
    if (value === 'Settings') return P1TopLevelTab.ACCOUNT;
    return P1TopLevelTab.HOME;
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
    if (result.length < 3 || result.length > 5 || !result.includes(P1TopLevelTab.ACCOUNT)) {
      return [P1TopLevelTab.HOME, P1TopLevelTab.FOLLOWING, P1TopLevelTab.HOT,
        P1TopLevelTab.DAILY, P1TopLevelTab.ACCOUNT];
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
    const generation = this.themeOperationGuard.next();
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const seed = await new AppPreferencesStore(context).loadThemeColor();
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
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
