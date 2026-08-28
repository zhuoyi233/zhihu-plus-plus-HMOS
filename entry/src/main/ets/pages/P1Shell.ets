import { AppPreferencesStore, AppThemeMode, LoginSessionGateway, SessionStatus } from 'data';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
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
import { AppNavigationRow, AppPageHeader } from './AppPageChrome';
import { isP1TopLevelTabIndex, P1TopLevelTab, p1TopLevelTabForDestination } from './P1TopLevelTabs';

@Component
export struct P1Shell {
  @BuilderParam homeContent: (reloadToken: number, navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam followingContent: (reloadToken: number, navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam hotContent: (reloadToken: number, navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam dailyContent: (reloadToken: number, navigate: (destination: P1Destination) => void) => void =
    this.emptyReloadableHome;
  @BuilderParam dailyStoryContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam technicalLabContent: (navigate: (destination: P1Destination) => void) => void =
    this.emptyTechnicalLab;
  @BuilderParam searchContent: (query: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void =
    this.emptySearch;
  @BuilderParam questionContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam answerContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam articleContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam videoContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam writeAnswerContent: (questionId: string, answerId: string | undefined,
    navigate: (destination: P1Destination) => void, onBack: () => void) => void = this.emptyWriteAnswer;
  @BuilderParam writePinContent: (draftId: string, navigate: (destination: P1Destination) => void,
    onBack: () => void) => void = this.emptyWritePin;
  @BuilderParam pinDraftInboxContent: (navigate: (destination: P1Destination) => void) => void = this.emptyHome;
  @BuilderParam peopleContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam pinContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam collectionsContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam collectionContentContent: (id: string, navigate: (destination: P1Destination) => void) => void =
    this.emptyContent;
  @BuilderParam notificationContent: (navigate: (destination: P1Destination) => void) => void = this.emptyHome;
  @BuilderParam notificationSettingsContent: (navigate: (destination: P1Destination) => void) => void = this.emptyHome;
  @BuilderParam blockingRulesContent: () => void = this.emptyPage;
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
  @State private themePersistenceStatus: string = '正在读取主题设置…';
  @State private homeReloadToken: number = 0;
  @State private followingReloadToken: number = 0;
  @State private hotReloadToken: number = 0;
  @State private dailyReloadToken: number = 0;
  @State private topLevelTabIndex: number = P1TopLevelTab.HOME;
  @Provide('p1PathStack') pathStack: NavPathStack = new NavPathStack();
  private unsubscribeStartupDestination: (() => void) | undefined = undefined;
  private readonly themeOperationGuard: LatestOperationGuard = new LatestOperationGuard();
  private themeMounted: boolean = false;
  private themeSaveQueue: Promise<void> = Promise.resolve();

  aboutToAppear(): void {
    this.themeMounted = true;
    this.themePersistenceStatus = '正在读取主题设置…';
    this.restoreThemeMode();
    this.unsubscribeStartupDestination?.();
    const listener: StartupDestinationListener = (destination: P1Destination): void => {
      this.navigate(destination);
    };
    this.unsubscribeStartupDestination = startupDestinationChannel.subscribe(listener);
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
  emptyReloadableHome(_reloadToken: number, _navigate: (destination: P1Destination) => void) {
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
  emptyWriteAnswer(_questionId: string, _answerId: string | undefined,
    _navigate: (destination: P1Destination) => void, _onBack: () => void) {
    Blank();
  }

  @Builder
  emptyWritePin(_draftId: string, _navigate: (destination: P1Destination) => void, _onBack: () => void) {
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
      NavDestination() {
        this.invalidDestinationPage();
      }
      .title('无法打开页面')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.SETTINGS) {
      NavDestination() {
        this.settingsPage();
      }
      .title('显示与阅读')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.BLOCKING_RULES) {
      NavDestination() {
        this.blockingRulesContent();
      }
      .title('内容屏蔽')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.BLOCKED_FEED_HISTORY) {
      NavDestination() {
        this.blockedFeedHistoryContent((): void => {
          this.pathStack.pop();
        });
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.READ_HISTORY) {
      NavDestination() {
        this.readHistoryContent((nextDestination: P1Destination): void => this.navigate(nextDestination), (): void => {
          this.pathStack.pop();
        });
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.TECHNICAL_LAB) {
      NavDestination() {
        this.technicalLabContent((destination: P1Destination): void => this.navigate(destination));
      }
      .title('技术实验室')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.LOGIN) {
      NavDestination() {
        this.loginContent((): void => {
          this.pathStack.pop();
        }, (): void => {
          this.returnFromSuccessfulLogin();
        }, (): void => {
          this.navigate({ name: P1DestinationName.QR_DESKTOP_LOGIN_SCAN });
        });
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.SEARCH) {
      NavDestination() {
        this.searchContent(
          destination.query,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.FOLLOWING) {
      NavDestination() {
        this.followingContent(this.followingReloadToken,
          (destination: P1Destination): void => this.navigate(destination));
      }
      .title('关注')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.HOT) {
      NavDestination() {
        this.hotContent(this.hotReloadToken, (destination: P1Destination): void => this.navigate(destination));
      }
      .title('热榜')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DAILY) {
      NavDestination() {
        this.dailyContent(this.dailyReloadToken, (destination: P1Destination): void => this.navigate(destination));
      }
      .title('知乎日报')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DAILY_STORY) {
      NavDestination() {
        this.dailyStoryContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('日报正文')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.QUESTION) {
      NavDestination() {
        this.questionContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('问题')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.ANSWER) {
      NavDestination() {
        this.answerContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('回答')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.ARTICLE) {
      NavDestination() {
        this.articleContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('文章')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.VIDEO) {
      NavDestination() {
        this.videoContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('视频')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.WRITE_ANSWER) {
      NavDestination() {
        this.writeAnswerContent(
          destination.questionId,
          destination.answerId,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.WRITE_PIN) {
      NavDestination() {
        this.writePinContent(
          destination.draftId,
          (destination: P1Destination): void => this.navigate(destination),
          (): void => {
            this.pathStack.pop();
          }
        );
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PIN_DRAFTS) {
      NavDestination() {
        this.pinDraftInboxContent((destination: P1Destination): void => this.navigate(destination));
      }
      .title('想法草稿')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PEOPLE) {
      NavDestination() {
        this.peopleContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('用户主页')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.PIN) {
      NavDestination() {
        this.pinContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('想法')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.COLLECTIONS) {
      NavDestination() {
        this.collectionsContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('收藏夹')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.COLLECTION) {
      NavDestination() {
        this.collectionContentContent(
          destination.id,
          (destination: P1Destination): void => this.navigate(destination)
        );
      }
      .title('收藏夹内容')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.NOTIFICATION) {
      NavDestination() {
        this.notificationContent((destination: P1Destination): void => this.navigate(destination));
      }
      .title('通知')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.NOTIFICATION_SETTINGS) {
      NavDestination() {
        this.notificationSettingsContent((destination: P1Destination): void => this.navigate(destination));
      }
      .title('通知设置')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.READER_PROBE) {
      NavDestination() {
        this.readerProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.IMAGE_PROBE) {
      NavDestination() {
        this.imageProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DATABASE_PROBE) {
      NavDestination() {
        this.databaseProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DEEP_LINK_PROBE) {
      NavDestination() {
        this.deepLinkProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.QR_SCAN_PROBE) {
      NavDestination() {
        this.qrScanProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.QR_DESKTOP_LOGIN_SCAN) {
      NavDestination() {
        this.qrDesktopLoginScanContent((): void => {
          this.pathStack.pop();
        });
      }
      .title('扫描电脑端登录码')
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.BACKGROUND_TASK_PROBE) {
      NavDestination() {
        this.backgroundTaskProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (destination.name === P1DestinationName.DOMAIN_FIXTURE_PROBE) {
      NavDestination() {
        this.domainFixtureProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else {
      NavDestination() {
        this.businessPlaceholder(destination);
      }
      .title(destination.name)
      .backgroundColor($r('app.color.page_background'))
    }
  }

  build() {
    Navigation(this.pathStack) {
      Tabs({ barPosition: BarPosition.End, index: $$this.topLevelTabIndex }) {
        TabContent() {
          this.homeContent(this.homeReloadToken, (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_home_content')
        .tabBar('首页')

        TabContent() {
          this.followingContent(this.followingReloadToken,
            (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_following_content')
        .tabBar('关注')

        TabContent() {
          this.hotContent(this.hotReloadToken, (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_hot_content')
        .tabBar('热榜')

        TabContent() {
          this.dailyContent(this.dailyReloadToken, (destination: P1Destination): void => this.navigate(destination));
        }
        .id('p1_top_level_daily_content')
        .tabBar('日报')

        TabContent() {
          this.settingsPage();
        }
        .id('p1_top_level_account_content')
        .tabBar('我的')
      }
      .id('p1_top_level_tabs')
      .width('100%')
      .height('100%')
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .onChange((index: number): void => {
        if (isP1TopLevelTabIndex(index)) {
          this.topLevelTabIndex = index;
        }
      })
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  settingsPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
        AppPageHeader({ title: '我的' });
        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('主题模式')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text('切换会立即更新颜色资源；“跟随系统”会响应系统深浅色。')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Column({ space: $r('app.float.p1_spacing_small') }) {
            this.themeButton('跟随系统', AppThemeMode.SYSTEM, 'p1_theme_system');
            this.themeButton('浅色', AppThemeMode.LIGHT, 'p1_theme_light');
            this.themeButton('深色', AppThemeMode.DARK, 'p1_theme_dark');
          }
          .width('100%')

          Text(this.themePersistenceStatus)
            .id('p1_theme_persistence_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('字体缩放预览')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text('标题文字会跟随系统字体大小')
            .id('p1_font_scale_heading')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontColor($r('app.color.primary_text'))

          Text('正文使用 fp 字体单位，支持换行且不限制最大行数。')
            .id('p1_font_scale_body')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Text('页面内容由 Navigation 约束在系统安全区内，背景延伸覆盖状态栏和底部系统区域。')
          .id('p1_safe_area_description')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))

        AppNavigationRow({ title: '账号与登录', description: '管理当前知乎账号的登录状态', testId: 'p2_open_login',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.LOGIN }) });

        AppNavigationRow({ title: '发布想法', description: '创建一条新的想法', testId: 'p4_open_pin_publish',
          onRowClick: (): void => this.openPinComposer() });

        AppNavigationRow({ title: '想法草稿', description: '继续编辑本地保存的草稿', testId: 'p4_open_pin_drafts',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.PIN_DRAFTS }) });

        AppNavigationRow({ title: '内容屏蔽', description: '管理作者与关键词屏蔽规则', testId: 'p2_open_blocking_rules',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKING_RULES }) });

        AppNavigationRow({ title: '屏蔽记录', description: '查看最近隐藏的内容', testId: 'p3_open_blocked_feed_history',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.BLOCKED_FEED_HISTORY }) });

        AppNavigationRow({ title: '已读记录', description: '查看已打开的内容', testId: 'p2_open_read_history',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.READ_HISTORY }) });

        AppNavigationRow({ title: '我的收藏夹', description: '查看自己的知乎收藏夹', testId: 'p3_open_my_collections',
          onRowClick: (): void => this.openMyCollections() });

        AppNavigationRow({ title: '通知', description: '查看互动和系统消息', testId: 'p3_open_notifications',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION }) });

        AppNavigationRow({ title: '通知设置', description: '设置提醒和推送偏好', testId: 'p3_open_notification_settings',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.NOTIFICATION_SETTINGS }) });

        AppNavigationRow({ title: '技术实验室', description: '仅用于本机诊断与验证', testId: 'p1_open_technical_lab',
          onRowClick: (): void => this.navigate({ name: P1DestinationName.TECHNICAL_LAB }) });
        }
        .width('100%')
        .padding($r('app.float.p1_page_padding'))
      }
      .id('p1_settings_scroll')
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))
    }
    .id('p1_settings_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  themeButton(label: string, mode: AppThemeMode, testId: string) {
    Button(label)
      .id(testId)
      .width('100%')
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.themeMode === mode ? $r('app.color.on_brand') : $r('app.color.primary_text'))
      .backgroundColor(this.themeMode === mode ? $r('app.color.brand_primary') : $r('app.color.control_background'))
      .onClick(() => {
        this.selectThemeMode(mode);
      })
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
        this.themePersistenceStatus = '无法访问应用上下文';
        return;
      }
      const mode = await new AppPreferencesStore(context).loadThemeMode();
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      this.themePersistenceStatus = this.applyThemeMode(mode)
        ? '主题设置已恢复'
        : '主题模式应用失败，请重试';
    } catch (_error) {
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      this.themePersistenceStatus = this.applyThemeMode(AppThemeMode.SYSTEM)
        ? '无法读取已保存主题，当前跟随系统'
        : '无法读取或应用主题设置，请重试';
    }
  }

  private async selectThemeMode(mode: AppThemeMode): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.themePersistenceStatus = '无法访问应用上下文';
      return;
    }
    const generation = this.themeOperationGuard.next();
    if (!this.applyThemeMode(mode)) {
      this.themePersistenceStatus = '主题模式应用失败，请重试';
      return;
    }
    this.themePersistenceStatus = '正在保存主题设置…';
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
      if (this.themeMounted && this.themeOperationGuard.isCurrent(generation)) {
        this.themePersistenceStatus = '主题设置已保存';
      }
    } catch (_error) {
      if (this.themeMounted && this.themeOperationGuard.isCurrent(generation)) {
        this.themePersistenceStatus = '主题已应用，但本次未保存；重启后可能恢复此前设置';
      }
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
