/**
 * 独立“设置”页：目录、搜索、账户操作与设置详情宿主。
 *
 * 窄容器按整页逐级导航（目录 → 详情，详情内返回目录）；宽容器使用目录/详情双栏。
 * 详情内容复用既有设置页组件，由 AppShell 通过 @BuilderParam 注入，避免复制业务状态。
 *
 * 内部导航（父级、祖先选中、返回契约、开发者门禁）统一由 SettingsNavigationState 判定，
 * 宿主只负责渲染与状态托管；“内容屏蔽”“屏蔽记录”“开发者选项”都是设置内部 pane，
 * 不再以根路由整页跳出（docs/account-settings-redesign.md §11）。
 */
import { AppDestination, AppDestinationName } from 'core';
import { DEFAULT_THEME_COLOR, FeedCardStyle, onThemeColor } from 'data';
import { AppNavigationRow, floatingTitleBarOffset } from './AppPageChrome';
import {
  resolveSettingsLayout,
  SETTINGS_DETAIL_MAX_CONTENT_WIDTH_VP,
  SettingsLayoutMode,
  SettingsLayoutSpec,
  settingsGroupBackground,
  settingsGroupRadius
} from './AccountSettingsLayout';
import {
  hasInternalBack,
  isPaneAvailable,
  paneAfterDeveloperModeDisabled,
  paneForEntry,
  paneParent,
  paneTitle,
  SettingsPaneId
} from './SettingsNavigationState';
import {
  matchSettingsSearchEntries,
  SettingsEntryId,
  SettingsSearchEntry,
  SettingsSearchOptions,
  visibleSettingsSearchEntries
} from './SettingsSearchIndex';
import { ThemeColorSettingsPage } from './ThemeColorSettingsPage';

@Component
export struct SettingsHomePage {
  @Prop authenticated: boolean = false;
  @Prop logoutBusy: boolean = false;
  @Prop updateLabel: string = '';
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {};
  onLogout: () => void = (): void => {};
  @BuilderParam identityContent: () => void = this.emptyContent;
  @BuilderParam appearanceContent: (onOpenThemeColor: () => void) => void = this.emptyAppearanceContent;
  @BuilderParam readingContent: () => void = this.emptyContent;
  @BuilderParam filterContent: (onOpenBlocklist: () => void, onOpenBlockedHistory: () => void) => void =
    this.emptyFilterContent;
  @BuilderParam blockingRulesContent: (registerActions: (handler: () => void) => void,
    releaseActions: () => void) => void = this.emptyActionsContent;
  @BuilderParam blockedHistoryContent: (registerActions: (handler: () => void) => void,
    releaseActions: () => void) => void = this.emptyActionsContent;
  @BuilderParam developerContent: () => void = this.emptyContent;
  @BuilderParam notificationContent: () => void = this.emptyContent;
  @BuilderParam updateContent: () => void = this.emptyContent;
  @BuilderParam aboutContent: () => void = this.emptyContent;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('systemFontSizeScale') private systemFontSizeScale: number = 1;
  @StorageProp('developerModeEnabled') @Watch('onDeveloperModeChanged')
  private developerModeEnabled: boolean = false;
  /** 窄容器详情页返回信号：根导航先问当前是否处于设置内部详情，再决定离页或回目录。 */
  @StorageProp('settingsHomeBackTick') @Watch('onSettingsHomeBack') private settingsHomeBackTick: number = 0;
  /** 顶栏“更多”点击信号：动作实体由当前二级页注册，宿主只负责转调。 */
  @StorageProp('settingsHomeActionTick') @Watch('onDetailActionTick') private settingsHomeActionTick: number = 0;
  @State private searchQuery: string = '';
  @State private selectedPane: SettingsPaneId = SettingsPaneId.NONE;
  @State private containerWidth: number = 0;
  /** 详情标题栏的动作由子页注册（如“更多”菜单），宿主只画一次标题。 */
  @State private detailActionsAvailable: boolean = false;
  private detailAction: () => void = (): void => {};

  @Builder
  private emptyContent() {
  }

  @Builder
  private emptyAppearanceContent(_onOpenThemeColor: () => void) {
  }

  @Builder
  private emptyFilterContent(_onOpenBlocklist: () => void, _onOpenBlockedHistory: () => void) {
  }

  @Builder
  private emptyActionsContent(_registerActions: (handler: () => void) => void, _releaseActions: () => void) {
  }

  aboutToAppear(): void {
    // 顶栏内容由宿主广播：进入时先同步一次标题与动作可用性，避免沿用上一次的残留。
    this.publishTitleBarState();
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('settingsHomeDetailBackActive', false);
    AppStorage.setOrCreate('settingsHomeActionsAvailable', false);
    this.releaseDetailActions();
  }

  private hasInternalBack(): boolean {
    return hasInternalBack(this.selectedPane, this.isSplit());
  }

  private syncDetailBackState(): void {
    AppStorage.setOrCreate('settingsHomeDetailBackActive', this.hasInternalBack());
  }

  /** 顶栏标题与“更多”可用性统一广播，AppShell 只渲染不判断业务。 */
  private publishTitleBarState(): void {
    AppStorage.setOrCreate('settingsHomeTitle', paneTitle(this.selectedPane));
    AppStorage.setOrCreate('settingsHomeActionsAvailable', this.detailActionsAvailable);
  }

  /** 切换详情页：动作槽先失效，避免上一页的“更多”菜单作用到新页面。 */
  private selectPane(pane: SettingsPaneId): void {
    if (pane !== this.selectedPane) {
      this.releaseDetailActions();
    }
    if (!isPaneAvailable(pane, this.developerModeEnabled)) {
      // 开发者模式已关闭时，旧入口、恢复路径与搜索结果都不得重新打开开发者页。
      this.selectedPane = SettingsPaneId.NONE;
      this.syncDetailBackState();
      this.publishTitleBarState();
      return;
    }
    this.selectedPane = pane;
    this.syncDetailBackState();
    this.publishTitleBarState();
  }

  private registerDetailActions(handler: () => void): void {
    this.detailAction = handler;
    this.detailActionsAvailable = true;
    this.publishTitleBarState();
  }

  private releaseDetailActions(): void {
    this.detailAction = (): void => {};
    this.detailActionsAvailable = false;
    this.publishTitleBarState();
  }

  private goBackFromPane(): void {
    this.selectPane(paneParent(this.selectedPane));
  }

  private onSettingsHomeBack(): void {
    if (this.selectedPane !== SettingsPaneId.NONE) {
      this.goBackFromPane();
    }
  }

  /** 顶栏“更多”被点击：转调当前二级页注册的动作。 */
  private onDetailActionTick(): void {
    if (this.detailActionsAvailable) {
      this.detailAction();
    }
  }

  /** 开发者模式被关闭：目录、搜索与正文同步失效，宽窗回占位、窄窗回目录。 */
  private onDeveloperModeChanged(): void {
    if (this.developerModeEnabled) {
      return;
    }
    const fallback: SettingsPaneId = paneAfterDeveloperModeDisabled(this.selectedPane);
    if (fallback !== this.selectedPane) {
      this.releaseDetailActions();
      this.selectedPane = fallback;
      this.syncDetailBackState();
      this.publishTitleBarState();
    }
  }

  private layout(): SettingsLayoutSpec {
    return resolveSettingsLayout(this.containerWidth, this.systemFontSizeScale);
  }

  private isSplit(): boolean {
    return this.layout().mode === SettingsLayoutMode.SPLIT;
  }

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  private hasQuery(): boolean {
    return this.searchQuery.trim().length > 0;
  }

  private searchOptions(): SettingsSearchOptions {
    return {
      authenticated: this.authenticated,
      developerModeEnabled: this.developerModeEnabled
    };
  }

  private searchResults(): Array<SettingsSearchEntry> {
    return matchSettingsSearchEntries(visibleSettingsSearchEntries(this.searchOptions()), this.searchQuery);
  }

  private destinationForEntry(id: SettingsEntryId): AppDestination | undefined {
    if (id === SettingsEntryId.LOGIN) {
      return { name: AppDestinationName.LOGIN };
    }
    return undefined;
  }

  /** 目录/搜索入口统一解析：内部 pane 一律留在设置实例，其余才走根路由。 */
  private openEntry(id: SettingsEntryId): void {
    const pane: SettingsPaneId = paneForEntry(id);
    if (pane !== SettingsPaneId.NONE) {
      this.selectPane(pane);
      return;
    }
    const destination: AppDestination | undefined = this.destinationForEntry(id);
    if (destination !== undefined) {
      this.navigate(destination);
    }
  }

  build() {
    Row({ space: this.layout().columnGap }) {
      this.masterPane()
      this.detailPane()
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      left: this.isSplit() ? $r('app.float.page_padding') : 0,
      right: this.isSplit() ? $r('app.float.page_padding') : 0
    })
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.containerWidth = Number(newArea.width);
      // 跨越断点时同步返回行为：双栏下返回键直接退出设置，窄栏详情下先回目录。
      this.syncDetailBackState();
      this.publishTitleBarState();
    })
  }

  /** 双栏时的目录栏宽度；返回 0 表示占满整行。
   *  不用 @Builder 传参：按值传参会在首渲染后固化，平板首次进入时仍按单栏渲染。 */
  private masterPaneWidth(): number {
    return this.isSplit() ? this.layout().masterWidth : 0;
  }

  @Builder
  private masterPane() {
    Scroll() {
      Column({ space: 24 }) {
        this.searchBox()
        if (this.hasQuery()) {
          this.searchResultsSection()
        } else {
          this.categorySections()
        }
      }
      .width('100%')
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        top: $r('app.float.spacing_small'),
        bottom: 40
      })
    }
    .id('settings_master_pane')
    .width(this.masterPaneWidth() > 0 ? this.masterPaneWidth() : '100%')
    .height('100%')
    // 顶栏是覆盖式沉浸光感栏：首屏内容从栏下沿开始，滚动时穿过顶栏。
    .contentStartOffset(floatingTitleBarOffset())
    // 设置搜索结果往往不足一屏，Scroll 默认居中会让标题下空出大段；固定从顶部开始排。
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.page_background'))
    // 单栏进入详情时目录只隐藏不销毁，返回后滚动位置与搜索词都还在。
    .visibility(this.isSplit() || this.selectedPane === SettingsPaneId.NONE ?
      Visibility.Visible : Visibility.None)
  }

  @Builder
  private searchBox() {
    Row({ space: $r('app.float.spacing_small') }) {
      TextInput({ text: this.searchQuery, placeholder: '搜索设置' })
        .id('settings_home_search')
        .layoutWeight(1)
        .height(44)
        .onChange((value: string): void => {
          this.searchQuery = value;
        })
      if (this.hasQuery()) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.secondary_text')])
        }
        .id('settings_search_clear')
        .width(44)
        .height(44)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('清空设置搜索')
        .onClick((): void => {
          this.searchQuery = '';
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private categorySections() {
    this.sectionTitle('账户')
    Column() {
      if (this.authenticated) {
        AppNavigationRow({
          title: '身份管理',
          description: '创建马甲号或切换当前身份',
          testId: 'open_identity_management',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.person_2'),
          onRowClick: (): void => this.openEntry(SettingsEntryId.IDENTITY)
        });
      } else {
        AppNavigationRow({
          title: '登录知乎',
          description: '登录后管理身份、收藏与消息',
          testId: 'open_login',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.person'),
          onRowClick: (): void => this.openEntry(SettingsEntryId.LOGIN)
        });
      }
    }
    .width('100%')
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .clip(this.isCardStyle())

    this.sectionTitle('使用偏好')
    Column() {
      AppNavigationRow({
        title: '外观与阅读体验',
        description: '主题、排版与信息流',
        testId: 'open_appearance_settings',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.eye'),
        onRowClick: (): void => this.openEntry(SettingsEntryId.APPEARANCE)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '朗读与播放',
        description: '语音与播放控制',
        testId: 'open_reading_settings',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.mic'),
        onRowClick: (): void => this.openEntry(SettingsEntryId.READING)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '推荐系统与内容过滤',
        description: '推荐来源、质量与屏蔽',
        testId: 'open_recommendation_filter_settings',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.eye_slash'),
        onRowClick: (): void => this.openEntry(SettingsEntryId.FILTER)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '通知设置',
        description: '提醒与推送偏好',
        testId: 'open_notification_settings',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.bell_badge_gearshape'),
        onRowClick: (): void => this.openEntry(SettingsEntryId.NOTIFICATION)
      });
    }
    .width('100%')
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .clip(this.isCardStyle())

    this.sectionTitle('应用')
    Column() {
      AppNavigationRow({
        title: '系统与更新',
        description: '版本信息、检查更新与反馈',
        testId: 'open_system_update_settings',
        trailingText: this.updateLabel,
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.arrow_clockwise'),
        onRowClick: (): void => this.openEntry(SettingsEntryId.SYSTEM_UPDATE)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '关于应用',
        description: '版本、项目与开源许可',
        testId: 'settings_open_about',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.info_circle'),
        onRowClick: (): void => this.openEntry(SettingsEntryId.ABOUT)
      });
    }
    .width('100%')
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .clip(this.isCardStyle())

    if (this.developerModeEnabled) {
      this.sectionTitle('开发者选项')
      Column() {
        AppNavigationRow({
          title: '开发者选项',
          description: 'Cookie、网络与调试工具',
          testId: 'open_developer_options',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.gearshape'),
          onRowClick: (): void => this.openEntry(SettingsEntryId.DEVELOPER)
        });
      }
      .width('100%')
      .backgroundColor(settingsGroupBackground(this.feedCardStyle))
      .borderRadius(settingsGroupRadius(this.feedCardStyle))
      .clip(this.isCardStyle())
    }

    if (this.authenticated) {
      Button(this.logoutBusy ? '正在退出…' : '退出登录')
        .id('account_logout')
        .width('100%')
        .height(52)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.logoutBusy)
        .accessibilityText('退出登录')
        .onClick((): void => this.onLogout())
    }
  }

  @Builder
  private searchResultsSection() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('搜索结果')
        .id('settings_search_result_title')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      if (this.searchResults().length > 0) {
        Column() {
          ForEach(this.searchResults(), (entry: SettingsSearchEntry, index: number) => {
            if (index > 0) {
              Divider().color($r('app.color.divider_color'))
            }
            AppNavigationRow({
              title: entry.title,
              description: entry.path,
              testId: `settings_search_open_${entry.id}`,
              grouped: true,
              onRowClick: (): void => this.openEntry(entry.id)
            });
          }, (entry: SettingsSearchEntry): string => entry.id)
        }
        .width('100%')
        .backgroundColor(settingsGroupBackground(this.feedCardStyle))
        .borderRadius(settingsGroupRadius(this.feedCardStyle))
        .clip(this.isCardStyle())
      } else {
        Column({ space: $r('app.float.spacing_small') }) {
          Text('没有匹配的设置项')
            .id('settings_search_empty')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .width('100%')
          Text('试试“主题”“朗读”或“屏蔽”')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Button('清空搜索')
            .id('settings_search_empty_clear')
            .fontSize($r('app.float.body_font_size'))
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .backgroundColor(this.resolvedThemeColor)
            .onClick((): void => {
              this.searchQuery = '';
            })
        }
        .width('100%')
        .padding($r('app.float.card_padding'))
        .borderRadius($r('app.float.card_radius'))
        .backgroundColor($r('app.color.surface_background'))
      }
    }
    .id('settings_search_results')
    .width('100%')
  }

  @Builder
  private detailPane() {
    Column() {
      if (this.selectedPane === SettingsPaneId.NONE) {
        Column() {
          Text('选择左侧设置项')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          this.paneContent()
        }
        .width('100%')
        .constraintSize({ maxWidth: SETTINGS_DETAIL_MAX_CONTENT_WIDTH_VP })
        .layoutWeight(1)
      }
    }
    .id('settings_detail_pane')
    .width('100%')
    .layoutWeight(1)
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    // 顶栏是覆盖式沉浸光感栏：正文由各页自己的 contentStartOffset 让位，滚动时从栏后穿过。
    .visibility(this.isSplit() || this.selectedPane !== SettingsPaneId.NONE ?
      Visibility.Visible : Visibility.None)
  }

  @Builder
  private paneContent() {
    if (this.selectedPane === SettingsPaneId.IDENTITY) {
      this.identityContent()
    } else if (this.selectedPane === SettingsPaneId.APPEARANCE) {
      this.appearanceContent((): void => this.selectPane(SettingsPaneId.THEME_COLOR))
    } else if (this.selectedPane === SettingsPaneId.THEME_COLOR) {
      ThemeColorSettingsPage({ embedded: true })
    } else if (this.selectedPane === SettingsPaneId.READING) {
      this.readingContent()
    } else if (this.selectedPane === SettingsPaneId.FILTER) {
      this.filterContent((): void => this.selectPane(SettingsPaneId.BLOCKING_RULES),
        (): void => this.selectPane(SettingsPaneId.BLOCKED_HISTORY))
    } else if (this.selectedPane === SettingsPaneId.BLOCKING_RULES) {
      this.blockingRulesContent((handler: () => void): void => this.registerDetailActions(handler),
        (): void => this.releaseDetailActions())
    } else if (this.selectedPane === SettingsPaneId.BLOCKED_HISTORY) {
      this.blockedHistoryContent((handler: () => void): void => this.registerDetailActions(handler),
        (): void => this.releaseDetailActions())
    } else if (this.selectedPane === SettingsPaneId.NOTIFICATION) {
      this.notificationContent()
    } else if (this.selectedPane === SettingsPaneId.SYSTEM_UPDATE) {
      this.updateContent()
    } else if (this.selectedPane === SettingsPaneId.ABOUT) {
      this.aboutContent()
    } else if (this.selectedPane === SettingsPaneId.DEVELOPER) {
      this.developerContent()
    }
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize($r('app.float.secondary_font_size'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.secondary_text'))
      .width('100%')
      .padding({ left: $r('app.float.spacing_xsmall') })
  }
}
