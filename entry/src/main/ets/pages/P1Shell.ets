import {
  AppPreferencesStore,
  AppThemeMode,
  AppUpdateCheckResult,
  AppUpdateCheckStatus,
  AppUpdateClient,
  AppUpdateRelease,
  LoginSessionGateway,
  SessionStatus
} from 'data';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import bundleManager from '@ohos.bundle.bundleManager';
import { Want } from '@kit.AbilityKit';
import {
  SegmentButton,
  SegmentButtonOptions,
  SymbolGlyphModifier,
  uiMaterial
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import {
  decodeP1Destination,
  findP1DestinationStackIndex,
  isInfrastructureDestination,
  LatestOperationGuard,
  P1Destination,
  P1DestinationName,
  shouldReloadAfterAuthentication,
  startupDestinationChannel,
  StartupDestinationListener
} from 'core';
import { AppNavigationRow } from './AppPageChrome';
import {
  isP1TopLevelTabIndex,
  P1TopLevelTab,
  p1TopLevelTabForDestination
} from './P1TopLevelTabs';
import { DividerShowType, hdsMaterial, HdsNavDestination, HdsNavigation, HdsNavigationAttribute, HdsNavigationTitleMode, HdsTabsController } from '@kit.UIDesignKit';
import { getImmersiveTitleBarStyle } from '../common/style/NavStyles';
import { ZhihuHdsTabs } from './components/ZhihuHdsTabs';
import { materialCanvas } from './components/MaterialCanvas';
import { ChannelFeedInteractionBridge } from './ChannelFeedState';

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
  @BuilderParam technicalLabContent: (navigate: (destination: P1Destination) => void) => void =
    this.emptyTechnicalLab;
  @BuilderParam searchContent: (query: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void =
    this.emptySearch;
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
  @BuilderParam notificationSettingsContent: (navigate: (destination: P1Destination) => void) => void = this.emptyHome;
  @BuilderParam blockingRulesContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam blockedFeedHistoryContent: (onBack: () => void) => void = this.emptyPage;
  @BuilderParam readHistoryContent: (navigate: (destination: P1Destination) => void, onBack: () => void) => void =
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
  @State private themeMode: AppThemeMode = AppThemeMode.SYSTEM;
  @State private installedVersionLabel: string = '正在读取已安装版本…';
  @State private aboutVersionSheetShown: boolean = false;
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
  @State private homeReloadToken: number = 0;
  @State private followingReloadToken: number = 0;
  @State private hotReloadToken: number = 0;
  @State private dailyReloadToken: number = 0;
  // SegmentButtonOptions is an @ObjectLink in the framework component. Keep
  // the options in observed state instead of passing an inline object, which
  // otherwise renders the control but drops its tap callback on device.
  @State private followingSegmentOptions: SegmentButtonOptions = this.createFollowingSegmentOptions();
  @Provide('dailyDatePickerRequest') private dailyDatePickerRequest: number = 0;
  @Provide('dailyDateCursor') private dailyDateCursor: string = '';
  @Provide('channelFeedInteractionBridge') private channelFeedInteractionBridge: ChannelFeedInteractionBridge =
    new ChannelFeedInteractionBridge();
  @State @Watch('onTopLevelTabIndexChanged') private topLevelTabIndex: number = P1TopLevelTab.HOME;
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  @Provide('p1PathStack') pathStack: NavPathStack = new NavPathStack();
  private unsubscribeStartupDestination: (() => void) | undefined = undefined;
  private readonly themeOperationGuard: LatestOperationGuard = new LatestOperationGuard();
  private themeMounted: boolean = false;
  private themeSaveQueue: Promise<void> = Promise.resolve();

  aboutToAppear(): void {
    this.themeMounted = true;
    this.restoreThemeMode();
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
  emptyTechnicalLab(_navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptySearch(_query: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '显示与阅读' }, divider: { showType: DividerShowType.OFF } } })
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '已读记录' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.TECHNICAL_LAB) {
      HdsNavDestination() {
        this.technicalLabContent((destination: P1Destination): void => this.navigate(destination));
      }
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '技术实验室' }, divider: { showType: DividerShowType.OFF } } })
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '搜索' }, divider: { showType: DividerShowType.OFF } } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.FOLLOWING) {
      HdsNavDestination() {
        this.followingContent(this.followingReloadToken,
          (destination: P1Destination): void => this.navigate(destination),
          this.followingTitleBarIndexes[0]);
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.detailTitleBar('问题'), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.detailTitleBar('回答'), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { stackBuilder: (): void => this.detailTitleBar('文章'), divider: { showType: DividerShowType.OFF } } })
      .hideBackButton(true)
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '用户主页' }, divider: { showType: DividerShowType.OFF } } })
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
      .titleBar({ style: getImmersiveTitleBarStyle(), avoidLayoutSafeArea: true, content: { title: { mainTitle: '通知' }, divider: { showType: DividerShowType.OFF } } })
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
      ZhihuHdsTabs({ currentIndex: $topLevelTabIndex, controller: this.tabsController }) {
        TabContent() {
          this.homeContent(this.homeReloadToken, (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_home_content')
        .tabBar(this.topLevelTabBarStyle(P1TopLevelTab.HOME))

        TabContent() {
          this.followingContent(this.followingReloadToken,
            (destination: P1Destination): void => this.navigate(destination),
            this.followingTitleBarIndexes[0]);
        }
        .id('p1_top_level_following_content')
        .tabBar(this.topLevelTabBarStyle(P1TopLevelTab.FOLLOWING))

        TabContent() {
          this.hotContent(this.hotReloadToken, (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_hot_content')
        .tabBar(this.topLevelTabBarStyle(P1TopLevelTab.HOT))

        TabContent() {
          this.dailyContent(this.dailyReloadToken, this.dailyDateCursor,
            (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_daily_content')
        .tabBar(this.topLevelTabBarStyle(P1TopLevelTab.DAILY))

        TabContent() {
          this.settingsPage();
        }
        .id('p1_top_level_account_content')
        .tabBar(this.topLevelTabBarStyle(P1TopLevelTab.ACCOUNT))
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

  private topLevelTabBarStyle(tab: P1TopLevelTab): BottomTabBarStyle {
    // 图标语义直白优先：house/person_2/flame/doc_text/person（经系统符号表核实）。
    let icon: Resource = $r('sys.symbol.house');
    if (tab === P1TopLevelTab.FOLLOWING) {
      icon = $r('sys.symbol.person_2');
    } else if (tab === P1TopLevelTab.HOT) {
      icon = $r('sys.symbol.flame');
    } else if (tab === P1TopLevelTab.DAILY) {
      icon = $r('sys.symbol.doc_text');
    } else if (tab === P1TopLevelTab.ACCOUNT) {
      icon = $r('sys.symbol.person');
    }

    const normal: SymbolGlyphModifier = new SymbolGlyphModifier(icon)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.secondary_text')]);
    const selected: SymbolGlyphModifier = new SymbolGlyphModifier(icon)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.zhihu_blue')]);
    return BottomTabBarStyle.of({ normal, selected }, this.tabLabel(tab))
      .labelStyle({
        selectedColor: $r('app.color.zhihu_blue'),
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
      case P1TopLevelTab.ACCOUNT:
        return '我的';
    }
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
    if (this.topLevelTabIndex === P1TopLevelTab.HOME) {
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
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          colorInvert: true,
          applyShadow: true,
          interactive: true,
          lightEffect: {}
        }))
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
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          colorInvert: true,
          applyShadow: true,
          interactive: true,
          lightEffect: {}
        }))
        .accessibilityText('打开通知')
        .onClick((): void => this.navigate({ name: P1DestinationName.NOTIFICATION }))
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.topLevelTabIndex === P1TopLevelTab.FOLLOWING) {
      Column() {
        SegmentButton({
          options: this.followingSegmentOptions,
          selectedIndexes: $followingTitleBarIndexes,
          onItemClicked: (index: number): void => this.selectFollowingTitleBarTab(index)
        })
          .width('52%')
          .height(44)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.topLevelTabIndex === P1TopLevelTab.HOT) {
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
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          colorInvert: true,
          applyShadow: true,
          interactive: true,
          lightEffect: {}
        }))
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
    } else if (this.topLevelTabIndex === P1TopLevelTab.DAILY) {
      Row() {
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
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          colorInvert: true,
          applyShadow: true,
          interactive: true,
          lightEffect: {}
        }))
        .accessibilityText('选择日报日期')
        .onClick((): void => {
          this.openDailyDatePicker();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    }
    .id('p2_root_titlebar_content')
    .width('100%')
    .height('100%')
    .monopolizeEvents(false)
  }

  // SegmentButton uses two-way binding; keep the selected index as observable
  // component state so taps immediately rebuild the following feed content.
  @State private followingTitleBarIndexes: number[] = [0];

  private selectFollowingTitleBarTab(index: number): void {
    if (index < 0 || index > 1) {
      return;
    }
    this.followingTitleBarIndexes = [index];
    this.channelFeedInteractionBridge.selectFollowingTab(index);
  }

  private createFollowingSegmentOptions(): SegmentButtonOptions {
    return SegmentButtonOptions.tab({
      buttons: [{ text: '推荐' }, { text: '动态' }],
      backgroundColor: Color.Transparent,
      selectedBackgroundColor: $r('app.color.brand_primary_container'),
      backgroundSystemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        colorInvert: true,
        applyShadow: true,
        interactive: false,
        lightEffect: {}
      }),
      buttonPadding: 10
    });
  }

  private openDailyDatePicker(): void {
    const selectedDate: Date = new Date();
    this.getUIContext().showDatePickerDialog({
      selected: selectedDate,
      start: new Date(2000, 0, 1),
      end: new Date(),
      onDateAccept: (date: Date): void => {
        this.dailyDateCursor = this.formatDailyDateCursor(date);
        this.dailyReloadToken += 1;
        this.channelFeedInteractionBridge.selectDailyDate(this.dailyDateCursor);
      }
    });
  }

  private formatDailyDateCursor(date: Date): string {
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}${month}${day}`;
  }

  @Builder
  settingsPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
          TextInput({ text: this.settingsSearchQuery, placeholder: '搜索设置' })
            .id('p3_settings_search')
            .width('100%')
            .onChange((value: string): void => {
              this.settingsSearchQuery = value;
            })

          if (this.hasSettingsSearchQuery()) {
            this.settingsSearchResults()
          } else {
            this.accountOverview()
            this.accountQuickActions()

          Text('创作')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column() {
            AppNavigationRow({ title: '发布想法', description: '创建一条新的想法', testId: 'p4_open_pin_publish', grouped: true,
              onRowClick: (): void => this.openPinComposer() });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '想法草稿', description: '继续编辑本地保存的草稿', testId: 'p4_open_pin_drafts', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.PIN_DRAFTS }) });
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('内容与隐私')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column() {
            AppNavigationRow({ title: '历史', description: '查看已打开的内容', testId: 'p2_open_read_history', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.READ_HISTORY }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '内容屏蔽', description: '管理作者与关键词屏蔽规则', testId: 'p2_open_blocking_rules', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKING_RULES }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '屏蔽记录', description: '查看最近隐藏的内容', testId: 'p3_open_blocked_feed_history', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKED_FEED_HISTORY }) });
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('通知与外观')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column({ space: $r('app.float.p1_spacing_small') }) {
            AppNavigationRow({ title: '通知', description: '查看互动和系统消息', testId: 'p3_open_notifications', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION }) });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '通知设置', description: '设置提醒和推送偏好', testId: 'p3_open_notification_settings', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION_SETTINGS }) });
            Divider().color($r('app.color.divider_color'))
            Column({ space: $r('app.float.p1_spacing_small') }) {
              Text('主题模式')
                .fontSize($r('app.float.p1_body_font_size'))
                .fontColor($r('app.color.primary_text'))
              Text('跟随系统会响应系统深浅色。')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
              Row({ space: $r('app.float.p1_spacing_small') }) {
                this.themeButton('跟随系统', AppThemeMode.SYSTEM, 'p1_theme_system');
                this.themeButton('浅色', AppThemeMode.LIGHT, 'p1_theme_light');
                this.themeButton('深色', AppThemeMode.DARK, 'p1_theme_dark');
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding($r('app.float.p1_card_padding'))
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
              onRowClick: (): void => {
                this.refreshInstalledVersionLabel();
                this.aboutVersionSheetShown = true;
              } });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: 'GitHub', description: '查看项目主页', testId: 'p3_open_project_home', grouped: true,
              onRowClick: (): void => this.openProjectHome() });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '项目协议', description: 'GNU AGPL v3.0',
              testId: 'p3_open_project_license', grouped: true,
              onRowClick: (): void => {
                this.projectLicenseSheetShown = true;
              } });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '开源许可', description: '3 个本地 HAR 模块 · GNU AGPL v3.0',
              testId: 'p3_open_open_source_licenses', grouped: true,
              onRowClick: (): void => {
                this.openSourceLicensesSheetShown = true;
              } });
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '技术实验室', description: '仅用于本机诊断与验证', testId: 'p1_open_technical_lab', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.TECHNICAL_LAB }) });
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }
        }
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: 94,
        bottom: $r('app.float.p1_page_padding')
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
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.accountAvatarLetter())
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor($r('app.color.brand_primary_container'))
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_primary'))
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
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(this.accountTitle())
            .id('p3_account_overview_title')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.accountSummary())
            .id('p3_account_overview_summary')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.secondary_text')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id('p2_open_login')
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText('账号与登录')
    .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
  }

  @Builder
  private accountQuickActions() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(20)
            .fontColor([$r('app.color.brand_primary')])
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
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(20)
            .fontColor([$r('app.color.brand_primary')])
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
            .fontColor([$r('app.color.brand_primary')])
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
  themeButton(label: string, mode: AppThemeMode, testId: string) {
    Button(label)
      .id(testId)
      .layoutWeight(1)
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.themeMode === mode ? $r('app.color.on_brand') : $r('app.color.primary_text'))
      .backgroundColor(this.themeMode === mode ? $r('app.color.brand_primary') : $r('app.color.control_background'))
      .onClick(() => {
        this.selectThemeMode(mode);
      })
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
          onRowClick: (): void => this.navigate({ name: P1DestinationName.LOGIN }) });
      }
      if (this.settingsSearchMatches('发布想法', '创建一条新的想法')) {
        AppNavigationRow({ title: '发布想法', description: '创建一条新的想法', testId: 'p4_open_pin_publish',
          onRowClick: (): void => this.openPinComposer() });
      }
      if (this.settingsSearchMatches('想法草稿', '继续编辑本地保存的草稿')) {
        AppNavigationRow({ title: '想法草稿', description: '继续编辑本地保存的草稿', testId: 'p4_open_pin_drafts',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.PIN_DRAFTS }) });
      }
      if (this.settingsSearchMatches('我的收藏夹', '查看自己的知乎收藏夹')) {
        AppNavigationRow({ title: '我的收藏夹', description: '查看自己的知乎收藏夹', testId: 'p3_open_my_collections',
          onRowClick: (): void => this.openMyCollections() });
      }
      if (this.settingsSearchMatches('历史', '查看已打开的内容')) {
        AppNavigationRow({ title: '历史', description: '查看已打开的内容', testId: 'p2_open_read_history',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.READ_HISTORY }) });
      }
      if (this.settingsSearchMatches('内容屏蔽', '管理作者与关键词屏蔽规则')) {
        AppNavigationRow({ title: '内容屏蔽', description: '管理作者与关键词屏蔽规则', testId: 'p2_open_blocking_rules',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKING_RULES }) });
      }
      if (this.settingsSearchMatches('屏蔽记录', '查看最近隐藏的内容')) {
        AppNavigationRow({ title: '屏蔽记录', description: '查看最近隐藏的内容', testId: 'p3_open_blocked_feed_history',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKED_FEED_HISTORY }) });
      }
      if (this.settingsSearchMatches('通知', '查看互动和系统消息')) {
        AppNavigationRow({ title: '通知', description: '查看互动和系统消息', testId: 'p3_open_notifications',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION }) });
      }
      if (this.settingsSearchMatches('通知设置', '设置提醒和推送偏好')) {
        AppNavigationRow({ title: '通知设置', description: '设置提醒和推送偏好', testId: 'p3_open_notification_settings',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION_SETTINGS }) });
      }
      if (this.settingsSearchMatches('主题模式', '跟随系统 浅色 深色')) {
        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('主题模式')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
          Text('跟随系统、浅色或深色')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
          Row({ space: $r('app.float.p1_spacing_small') }) {
            this.themeButton('跟随系统', AppThemeMode.SYSTEM, 'p1_theme_system');
            this.themeButton('浅色', AppThemeMode.LIGHT, 'p1_theme_light');
            this.themeButton('深色', AppThemeMode.DARK, 'p1_theme_dark');
          }
          .width('100%')
        }
        .id('p3_settings_search_theme_mode')
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))
      }
      if (this.settingsSearchMatches('应用与版本', this.installedVersionLabel)) {
        AppNavigationRow({ title: '应用与版本', description: this.installedVersionLabel,
          testId: 'p3_open_about_version', onRowClick: (): void => {
            this.refreshInstalledVersionLabel();
            this.aboutVersionSheetShown = true;
          } });
      }
      if (this.settingsSearchMatches('GitHub', '查看项目主页')) {
        AppNavigationRow({ title: 'GitHub', description: '查看项目主页', testId: 'p3_open_project_home',
          onRowClick: (): void => this.openProjectHome() });
      }
      if (this.settingsSearchMatches('项目协议', 'GNU AGPL v3.0')) {
        AppNavigationRow({ title: '项目协议', description: 'GNU AGPL v3.0',
          testId: 'p3_open_project_license', onRowClick: (): void => {
            this.projectLicenseSheetShown = true;
          } });
      }
      if (this.settingsSearchMatches('开源许可', '3 个本地 HAR 模块 GNU AGPL v3.0')) {
        AppNavigationRow({ title: '开源许可', description: '3 个本地 HAR 模块 · GNU AGPL v3.0',
          testId: 'p3_open_open_source_licenses', onRowClick: (): void => {
            this.openSourceLicensesSheetShown = true;
          } });
      }
      if (this.settingsSearchMatches('技术实验室', '仅用于本机诊断与验证')) {
        AppNavigationRow({ title: '技术实验室', description: '仅用于本机诊断与验证', testId: 'p1_open_technical_lab',
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
      Text('知乎++ HarmonyOS 版')
        .id('p3_about_version_app_name')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.installedVersionLabel)
        .id('p3_about_version_value')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Text('版本信息来自当前已安装的 HAP，便于核对本机安装结果。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Button('检查更新')
        .id('p3_check_update')
        .fontSize($r('app.float.p1_body_font_size'))
        .enabled(!this.updateCheckBusy)
        .onClick((): void => {
          void this.runUpdateCheck(true);
        })
      if (this.updateCheckMessage.length > 0) {
        Text(this.updateCheckMessage)
          .id('p3_update_check_status')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      if (this.pendingUpdateRelease !== undefined) {
        Button('前往下载新版 HAP')
          .id('p3_update_download')
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick((): void => {
            const release = this.pendingUpdateRelease;
            const url = release !== undefined && release.htmlUrl.length > 0
              ? release.htmlUrl
              : PROJECT_HOME_URI + '/releases/latest';
            this.openExternalUrl(url, '无法打开发布页');
          })
      }
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

  /** verbose=true 供“应用与版本”弹层手动检查（展示状态）；false 供启动静默检查（仅检出新版本时提示）。 */
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
    this.updateCheckBusy = true;
    if (verbose) {
      this.updateCheckMessage = '正在检查更新…';
    }
    try {
      const result: AppUpdateCheckResult =
        await this.updateClient.checkLatestRelease(this.installedVersionName);
      if (result.status === AppUpdateCheckStatus.UPDATE_AVAILABLE && result.release !== undefined) {
        this.pendingUpdateRelease = result.release;
        if (verbose) {
          this.updateCheckMessage = `发现新版本 ${result.release.versionName}，可前往下载`;
        }
      } else if (result.status === AppUpdateCheckStatus.UP_TO_DATE) {
        this.pendingUpdateRelease = undefined;
        if (verbose) {
          this.updateCheckMessage = '当前已是最新版本';
        }
      } else if (verbose) {
        this.updateCheckMessage = result.message.length > 0 ? result.message : '检查更新失败，请稍后重试';
      }
    } finally {
      this.updateCheckBusy = false;
    }
  }

  private pendingUpdateTitle(): string {
    const release = this.pendingUpdateRelease;
    return release !== undefined ? `发现新版本 ${release.versionName}` : '';
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
      this.settingsSearchMatches('历史', '查看已打开的内容') ||
      this.settingsSearchMatches('内容屏蔽', '管理作者与关键词屏蔽规则') ||
      this.settingsSearchMatches('屏蔽记录', '查看最近隐藏的内容') ||
      this.settingsSearchMatches('通知', '查看互动和系统消息') ||
      this.settingsSearchMatches('通知设置', '设置提醒和推送偏好') ||
      this.settingsSearchMatches('主题模式', '跟随系统 浅色 深色') ||
      this.settingsSearchMatches('应用与版本', this.installedVersionLabel) ||
      this.settingsSearchMatches('GitHub', '查看项目主页') ||
      this.settingsSearchMatches('项目协议', 'GNU AGPL v3.0') ||
      this.settingsSearchMatches('开源许可', '3 个本地 HAR 模块 GNU AGPL v3.0') ||
      this.settingsSearchMatches('技术实验室', '仅用于本机诊断与验证');
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

  private accountSummary(): string {
    const state = this.session?.getState();
    if (state?.status !== SessionStatus.AUTHENTICATED) {
      return '管理当前知乎账号的登录状态';
    }
    const profileName = state.profile?.name.trim() ?? '';
    return profileName.length > 0 ? `已登录：${profileName}` : '已登录';
  }

  private accountTitle(): string {
    const state = this.session?.getState();
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
    const state = this.session?.getState();
    if (state?.status !== SessionStatus.AUTHENTICATED) {
      return '';
    }
    return state.profile?.avatarUrl?.trim() ?? '';
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

  private navigate(destination: P1Destination): void {
    const topLevelTab = p1TopLevelTabForDestination(destination);
    if (topLevelTab !== undefined) {
      this.pathStack.clear();
      this.topLevelTabIndex = topLevelTab;
      return;
    }
    const paths: Array<NavPathInfo> | undefined = this.pathStack.getPathStack();
    if (paths !== undefined && paths.length > 0) {
      // P3-7：同一目标（name+参数）已在返回栈任何位置时不再重复入栈，
      // 防止「返回时只是露出前一个重复页面」（CLAUDE.md 返回栈教训）。
      // 参数化页面不能使用按 name 匹配的 MOVE_TO_TOP_SINGLETON，必须按身份查重。
      if (findP1DestinationStackIndex(paths, destination) >= 0) {
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
      this.reloadCurrentTopLevelTab();
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

  private reloadCurrentTopLevelTab(): void {
    switch (this.topLevelTabIndex) {
      case P1TopLevelTab.HOME:
        this.homeReloadToken += 1;
        return;
      case P1TopLevelTab.FOLLOWING:
        this.followingReloadToken += 1;
        return;
      case P1TopLevelTab.HOT:
        this.hotReloadToken += 1;
        return;
      case P1TopLevelTab.DAILY:
        this.dailyReloadToken += 1;
        return;
      default:
        return;
    }
  }

  private destinationDescription(destination: P1Destination): string {
    switch (destination.name) {
      case P1DestinationName.SEARCH:
        return `搜索：${destination.query}`;
      case P1DestinationName.COMMENT:
        return `内容：${destination.contentId}`;
      case P1DestinationName.NOTIFICATION:
        return '查看知乎账号的通知消息';
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
      return true;
    } catch (_error) {
      return false;
    }
  }

}
