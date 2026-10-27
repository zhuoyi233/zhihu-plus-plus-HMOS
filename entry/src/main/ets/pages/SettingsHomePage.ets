/**
 * 独立“设置”页：目录、搜索、账户操作与设置详情宿主。
 *
 * 窄容器按整页逐级导航（目录 → 详情，详情内返回目录）；宽容器使用目录/详情双栏。
 * 详情内容复用既有设置页组件，由 AppShell 通过 @BuilderParam 注入，避免复制业务状态。
 */
import { AppDestination, AppDestinationName } from 'core';
import { DEFAULT_THEME_COLOR, FeedCardStyle, onThemeColor } from 'data';
import { AppNavigationRow, floatingTitleBarOffset } from './AppPageChrome';
import {
  resolveSettingsLayout,
  SettingsLayoutMode,
  SettingsLayoutSpec,
  SETTINGS_DETAIL_MAX_CONTENT_WIDTH_VP,
  settingsGroupBackground,
  settingsGroupRadius
} from './AccountSettingsLayout';
import {
  matchSettingsSearchEntries,
  SettingsEntryId,
  SettingsSearchEntry,
  SettingsSearchOptions,
  visibleSettingsSearchEntries
} from './SettingsSearchIndex';
import { ThemeColorSettingsPage } from './ThemeColorSettingsPage';

export enum SettingsPaneId {
  NONE = 'none',
  IDENTITY = 'identity',
  APPEARANCE = 'appearance',
  THEME_COLOR = 'theme_color',
  READING = 'reading',
  FILTER = 'filter',
  NOTIFICATION = 'notification',
  SYSTEM_UPDATE = 'system_update',
  ABOUT = 'about'
}

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
  @BuilderParam notificationContent: () => void = this.emptyContent;
  @BuilderParam updateContent: () => void = this.emptyContent;
  @BuilderParam aboutContent: () => void = this.emptyContent;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('systemFontSizeScale') private systemFontSizeScale: number = 1;
  @StorageProp('developerModeEnabled') private developerModeEnabled: boolean = false;
  /** 窄容器详情页返回信号：根导航先问当前是否处于设置内部详情，再决定离页或回目录。 */
  @StorageProp('settingsHomeBackTick') @Watch('onSettingsHomeBack') private settingsHomeBackTick: number = 0;
  @State private searchQuery: string = '';
  @State private selectedPane: SettingsPaneId = SettingsPaneId.NONE;
  @State private containerWidth: number = 0;

  @Builder
  private emptyContent() {
  }

  @Builder
  private emptyAppearanceContent(_onOpenThemeColor: () => void) {
  }

  @Builder
  private emptyFilterContent(_onOpenBlocklist: () => void, _onOpenBlockedHistory: () => void) {
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('settingsHomeDetailBackActive', false);
  }

  private paneParent(pane: SettingsPaneId): SettingsPaneId {
    if (pane === SettingsPaneId.THEME_COLOR) {
      return SettingsPaneId.APPEARANCE;
    }
    return SettingsPaneId.NONE;
  }

  private hasInternalBack(): boolean {
    if (this.selectedPane === SettingsPaneId.NONE) {
      return false;
    }
    if (this.isSplit()) {
      // 双栏下分类根页返回即退出设置，只有下级页才在右栏内返回。
      return this.paneParent(this.selectedPane) !== SettingsPaneId.NONE;
    }
    return true;
  }

  private syncDetailBackState(): void {
    AppStorage.setOrCreate('settingsHomeDetailBackActive', this.hasInternalBack());
  }

  private selectPane(pane: SettingsPaneId): void {
    this.selectedPane = pane;
    this.syncDetailBackState();
  }

  private goBackFromPane(): void {
    const parent: SettingsPaneId = this.paneParent(this.selectedPane);
    this.selectPane(parent);
  }

  private onSettingsHomeBack(): void {
    if (this.selectedPane !== SettingsPaneId.NONE) {
      this.goBackFromPane();
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
    switch (id) {
      case SettingsEntryId.LOGIN:
        return { name: AppDestinationName.LOGIN };
      case SettingsEntryId.IDENTITY:
        return { name: AppDestinationName.IDENTITY_MANAGEMENT };
      case SettingsEntryId.APPEARANCE:
        return { name: AppDestinationName.APPEARANCE_SETTINGS };
      case SettingsEntryId.THEME_COLOR:
        return { name: AppDestinationName.THEME_COLOR_SETTINGS };
      case SettingsEntryId.READING:
        return { name: AppDestinationName.READING_SETTINGS };
      case SettingsEntryId.FILTER:
        return { name: AppDestinationName.RECOMMENDATION_FILTER_SETTINGS };
      case SettingsEntryId.BLOCKING_RULES:
        return { name: AppDestinationName.BLOCKING_RULES };
      case SettingsEntryId.BLOCKED_HISTORY:
        return { name: AppDestinationName.BLOCKED_FEED_HISTORY };
      case SettingsEntryId.NOTIFICATION:
        return { name: AppDestinationName.NOTIFICATION_SETTINGS };
      case SettingsEntryId.SYSTEM_UPDATE:
        return { name: AppDestinationName.SYSTEM_UPDATE_SETTINGS };
      case SettingsEntryId.ABOUT:
      case SettingsEntryId.ABOUT_VERSION:
      case SettingsEntryId.ABOUT_GITHUB:
      case SettingsEntryId.ABOUT_LICENSE:
      case SettingsEntryId.ABOUT_OPEN_SOURCE:
        return { name: AppDestinationName.ABOUT_APP };
      case SettingsEntryId.DEVELOPER:
        return { name: AppDestinationName.TECHNICAL_LAB };
      default:
        return undefined;
    }
  }

  private paneForEntry(id: SettingsEntryId): SettingsPaneId {
    switch (id) {
      case SettingsEntryId.IDENTITY:
        return SettingsPaneId.IDENTITY;
      case SettingsEntryId.APPEARANCE:
        return SettingsPaneId.APPEARANCE;
      case SettingsEntryId.THEME_COLOR:
        return SettingsPaneId.THEME_COLOR;
      case SettingsEntryId.READING:
        return SettingsPaneId.READING;
      case SettingsEntryId.FILTER:
        return SettingsPaneId.FILTER;
      case SettingsEntryId.NOTIFICATION:
        return SettingsPaneId.NOTIFICATION;
      case SettingsEntryId.SYSTEM_UPDATE:
        return SettingsPaneId.SYSTEM_UPDATE;
      case SettingsEntryId.ABOUT:
      case SettingsEntryId.ABOUT_VERSION:
      case SettingsEntryId.ABOUT_GITHUB:
      case SettingsEntryId.ABOUT_LICENSE:
      case SettingsEntryId.ABOUT_OPEN_SOURCE:
        return SettingsPaneId.ABOUT;
      default:
        return SettingsPaneId.NONE;
    }
  }

  private openCategory(destination: AppDestination, pane: SettingsPaneId): void {
    if (pane !== SettingsPaneId.NONE) {
      this.selectPane(pane);
      return;
    }
    this.navigate(destination);
  }

  private activateEntry(entry: SettingsSearchEntry): void {
    const pane: SettingsPaneId = this.paneForEntry(entry.id);
    if (pane !== SettingsPaneId.NONE) {
      this.selectPane(pane);
      return;
    }
    const destination: AppDestination | undefined = this.destinationForEntry(entry.id);
    if (destination !== undefined) {
      this.navigate(destination);
    }
  }

  private paneTitle(): string {
    switch (this.selectedPane) {
      case SettingsPaneId.IDENTITY:
        return '身份管理';
      case SettingsPaneId.APPEARANCE:
        return '外观与阅读体验';
      case SettingsPaneId.THEME_COLOR:
        return '主题颜色';
      case SettingsPaneId.READING:
        return '朗读与播放';
      case SettingsPaneId.FILTER:
        return '推荐系统与内容过滤';
      case SettingsPaneId.NOTIFICATION:
        return '通知设置';
      case SettingsPaneId.SYSTEM_UPDATE:
        return '系统与更新';
      case SettingsPaneId.ABOUT:
        return '关于应用';
      default:
        return '设置';
    }
  }

  build() {
    Column() {
      if (this.isSplit()) {
        Row({ space: this.layout().columnGap }) {
          this.masterPane(this.layout().masterWidth)
          this.detailPane(true)
        }
        .width('100%')
        .height('100%')
        .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
      } else if (this.selectedPane !== SettingsPaneId.NONE) {
        this.detailPane(false)
      } else {
        this.masterPane(0)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.containerWidth = Number(newArea.width);
      // 跨越断点时同步返回行为：双栏下返回键直接退出设置，窄栏详情下先回目录。
      this.syncDetailBackState();
    })
  }

  @Builder
  private masterPane(fixedWidth: number) {
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
        bottom: 40
      })
    }
    .id('settings_master_pane')
    .width(fixedWidth > 0 ? fixedWidth : '100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentStartOffset(floatingTitleBarOffset())
    .backgroundColor($r('app.color.page_background'))
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
          trailingText: this.selectedPane === SettingsPaneId.IDENTITY ? '已选择' : '',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.person_2'),
          onRowClick: (): void => this.openCategory({ name: AppDestinationName.IDENTITY_MANAGEMENT },
            SettingsPaneId.IDENTITY)
        });
      } else {
        AppNavigationRow({
          title: '登录知乎',
          description: '登录后管理身份、收藏与消息',
          testId: 'open_login',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.person'),
          onRowClick: (): void => this.navigate({ name: AppDestinationName.LOGIN })
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
        trailingText: this.selectedPane === SettingsPaneId.APPEARANCE ? '已选择' : '',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.eye'),
        onRowClick: (): void => this.openCategory({ name: AppDestinationName.APPEARANCE_SETTINGS },
          SettingsPaneId.APPEARANCE)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '朗读与播放',
        description: '语音与播放控制',
        testId: 'open_reading_settings',
        trailingText: this.selectedPane === SettingsPaneId.READING ? '已选择' : '',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.mic'),
        onRowClick: (): void => this.openCategory({ name: AppDestinationName.READING_SETTINGS },
          SettingsPaneId.READING)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '推荐系统与内容过滤',
        description: '推荐来源、质量与屏蔽',
        testId: 'open_recommendation_filter_settings',
        trailingText: this.selectedPane === SettingsPaneId.FILTER ? '已选择' : '',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.eye_slash'),
        onRowClick: (): void => this.openCategory({ name: AppDestinationName.RECOMMENDATION_FILTER_SETTINGS },
          SettingsPaneId.FILTER)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '通知设置',
        description: '提醒与推送偏好',
        testId: 'open_notification_settings',
        trailingText: this.selectedPane === SettingsPaneId.NOTIFICATION ? '已选择' : '',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.bell_badge_gearshape'),
        onRowClick: (): void => this.openCategory({ name: AppDestinationName.NOTIFICATION_SETTINGS },
          SettingsPaneId.NOTIFICATION)
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
        trailingText: this.updateLabel.length > 0 ? this.updateLabel :
          (this.selectedPane === SettingsPaneId.SYSTEM_UPDATE ? '已选择' : ''),
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.arrow_clockwise'),
        onRowClick: (): void => this.openCategory({ name: AppDestinationName.SYSTEM_UPDATE_SETTINGS },
          SettingsPaneId.SYSTEM_UPDATE)
      });
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({
        title: '关于应用',
        description: '版本、项目与开源许可',
        testId: 'settings_open_about',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.info_circle'),
        onRowClick: (): void => this.selectPane(SettingsPaneId.ABOUT)
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
          onRowClick: (): void => this.navigate({ name: AppDestinationName.TECHNICAL_LAB })
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
              onRowClick: (): void => this.activateEntry(entry)
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
  private detailPane(split: boolean) {
    Column() {
      Row({ space: $r('app.float.spacing_small') }) {
        if (!split || this.paneParent(this.selectedPane) !== SettingsPaneId.NONE) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([$r('app.color.primary_text')])
          }
          .id('settings_detail_back')
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.paneParent(this.selectedPane) !== SettingsPaneId.NONE
            ? '返回上一级设置' : '返回设置目录')
          .onClick((): void => {
            this.goBackFromPane();
          })
        }
        Text(this.paneTitle())
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
      .padding({ left: $r('app.float.spacing_xsmall'), right: $r('app.float.spacing_xsmall') })

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
    .layoutWeight(split ? 1 : 0)
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: floatingTitleBarOffset() })
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
      this.filterContent((): void => this.navigate({ name: AppDestinationName.BLOCKING_RULES }),
        (): void => this.navigate({ name: AppDestinationName.BLOCKED_FEED_HISTORY }))
    } else if (this.selectedPane === SettingsPaneId.NOTIFICATION) {
      this.notificationContent()
    } else if (this.selectedPane === SettingsPaneId.SYSTEM_UPDATE) {
      this.updateContent()
    } else if (this.selectedPane === SettingsPaneId.ABOUT) {
      this.aboutContent()
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
