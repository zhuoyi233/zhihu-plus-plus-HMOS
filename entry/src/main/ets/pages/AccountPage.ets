/**
 * “我的”一级页内容：个人资料、快捷入口、创作与工具。
 *
 * 页面只负责展示与点击回调，登录态、账号资料、更新提示和业务动作仍由 AppShell 提供；
 * 列数按实际容器宽度与字体缩放判定，不读取设备型号。
 */
import { DEFAULT_THEME_COLOR, FeedCardStyle, themeColorContainerColor } from 'data';
import { AppNavigationRow } from './AppPageChrome';
import {
  AccountLayoutMode,
  AccountLayoutSpec,
  ACCOUNT_MAX_CONTENT_WIDTH_VP,
  resolveAccountLayout,
  settingsGroupBackground,
  settingsGroupRadius
} from './AccountSettingsLayout';

@Component
export struct AccountPage {
  @Prop authenticated: boolean = false;
  @Prop accountTitle: string = '登录知乎';
  @Prop avatarLetter: string = '';
  @Prop avatarUrl: string = '';
  /** 有新版本时在设置入口上提示（原顶部标题栏的红点语义）。 */
  @Prop hasPendingUpdate: boolean = false;
  scroller: Scroller = new Scroller();
  onOpenProfile: () => void = (): void => {};
  onOpenLogin: () => void = (): void => {};
  onOpenCollections: () => void = (): void => {};
  onOpenHistory: () => void = (): void => {};
  onOpenMessages: () => void = (): void => {};
  onOpenPinPublish: () => void = (): void => {};
  onOpenPinDrafts: () => void = (): void => {};
  onOpenScan: () => void = (): void => {};
  /** 设置入口：原顶部标题栏的齿轮按钮，现移入页面内容。 */
  onOpenSettings: () => void = (): void => {};
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('systemFontSizeScale') private systemFontSizeScale: number = 1;
  @StorageProp('bottomRectHeight') private bottomRectHeightVp: number = 0;
  @StorageProp('statusBarHeight') private statusBarHeightVp: number = 0;
  @State private containerWidth: number = 0;

  private layout(): AccountLayoutSpec {
    return resolveAccountLayout(this.containerWidth, this.systemFontSizeScale);
  }

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  private profileSubtitle(): string {
    return this.authenticated ? '查看个人主页' : '登录后查看收藏与消息';
  }

  private bottomInset(): number {
    // HdsTabs 悬浮底栏 64vp + 系统手势区，另留 12vp 间隔。
    return 64 + Math.max(0, this.bottomRectHeightVp) + 12;
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        Column({ space: 24 }) {
          this.profileSection()
          this.quickSection()
          if (this.layout().mode === AccountLayoutMode.TWO_COLUMN) {
            Row({ space: this.layout().columnGap }) {
              Column() {
                this.creationSection()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              if (this.authenticated) {
                Column() {
                  this.toolsSection()
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            this.creationSection()
            if (this.authenticated) {
              this.toolsSection()
            }
          }
          // 已登录时设置入口并入“工具”分组（紧跟“扫码登录电脑端”）；未登录时单独成组。
          if (!this.authenticated) {
            this.settingsSection()
          }
          // 页脚免责声明：与设置-关于应用同源，放在内容末尾、底栏留白之上。
          Text('本软件仅供学习交流使用，应用内内容由知乎网站提供，著作权归其对应作者所有。')
            .id('account_footer_disclaimer')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Start)
            .width('100%')
            .padding({ left: $r('app.float.spacing_xsmall'), right: $r('app.float.spacing_xsmall') })
        }
        .width('100%')
        .constraintSize({ maxWidth: ACCOUNT_MAX_CONTENT_WIDTH_VP })
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          bottom: this.bottomInset()
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .id('account_page_scroll')
    .width('100%')
    .height('100%')
    // 内容不足一屏时 Scroll 默认居中，会让标题下出现大段空白；固定从顶部开始排。
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    // 本页已隐藏顶部标题栏，内容从屏幕顶端开始绘制：让出状态栏后再留 24vp 呼吸空间，
    // 避免头像资料区贴着状态栏（原来 8vp 仍然偏挤）。
    .contentStartOffset(this.statusBarHeightVp + 24)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.containerWidth = Number(newArea.width);
    })
  }

  @Builder
  private profileSection() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.avatarLetter.length > 0 ? this.avatarLetter : '知')
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor(themeColorContainerColor(this.resolvedThemeColor))
            .fontSize($r('app.float.heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.resolvedThemeColor)
            .textAlign(TextAlign.Center)
          if (this.avatarUrl.length > 0) {
            Image(this.avatarUrl)
              .id('account_overview_avatar')
              .width(56)
              .height(56)
              .borderRadius(28)
              .objectFit(ImageFit.Cover)
          }
        }
        .id('account_overview_avatar_box')
        Column({ space: $r('app.float.spacing_xsmall') }) {
          Text(this.accountTitle)
            .id('account_overview_title')
            .fontSize($r('app.float.heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.profileSubtitle())
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
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
    .id(this.authenticated ? 'account_overview' : 'open_login')
    .width('100%')
    .padding({
      left: $r('app.float.page_padding'),
      right: $r('app.float.page_padding'),
      top: $r('app.float.spacing_small'),
      bottom: $r('app.float.spacing_small')
    })
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.authenticated ? '打开个人主页' : '登录知乎')
    .onClick((): void => {
      if (this.authenticated) {
        this.onOpenProfile();
      } else {
        this.onOpenLogin();
      }
    })
  }

  @Builder
  private quickSection() {
    Column() {
      Row({ space: $r('app.float.spacing_small') }) {
        this.quickEntry('收藏夹', $r('sys.symbol.bookmark'), '打开我的收藏夹', 'open_my_collections',
          (): void => this.onOpenCollections())
        this.quickEntry('历史', $r('sys.symbol.arrow_counterclockwise_clock'), '打开历史', 'account_quick_history',
          (): void => this.onOpenHistory())
        this.quickEntry('消息', $r('sys.symbol.bell'), '打开消息', 'account_quick_notifications',
          (): void => this.onOpenMessages())
      }
      .width('100%')

      if (!this.isCardStyle()) {
        Divider().color($r('app.color.divider_color'))
      }
    }
    .id('account_quick_actions')
    .width('100%')
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .clip(this.isCardStyle())
  }

  @Builder
  private quickEntry(title: string, icon: Resource, accessibility: string, testId: string, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.spacing_xsmall') }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([this.resolvedThemeColor])
        Text(title)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .id(testId)
    .layoutWeight(1)
    .height(72)
    .backgroundColor(Color.Transparent)
    .accessibilityText(accessibility)
    .onClick((): void => action())
  }

  @Builder
  private creationSection() {
    Column({ space: $r('app.float.spacing_small') }) {
      this.sectionTitle('创作')
      Column() {
        AppNavigationRow({
          title: '发布想法',
          testId: 'open_pin_publish',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.square_and_pencil'),
          onRowClick: (): void => this.onOpenPinPublish()
        });
        Divider().color($r('app.color.divider_color'))
        AppNavigationRow({
          title: '想法草稿',
          testId: 'open_pin_drafts',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.doc_text'),
          onRowClick: (): void => this.onOpenPinDrafts()
        });
      }
      .width('100%')
      .backgroundColor(settingsGroupBackground(this.feedCardStyle))
      .borderRadius(settingsGroupRadius(this.feedCardStyle))
      .clip(this.isCardStyle())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private toolsSection() {
    Column({ space: $r('app.float.spacing_small') }) {
      this.sectionTitle('工具')
      Column() {
        AppNavigationRow({
          title: '扫码登录电脑端',
          testId: 'account_scan_desktop_login',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.barcode_viewfinder'),
          rowAccessibilityText: '扫描电脑端登录二维码',
          onRowClick: (): void => this.onOpenScan()
        });
        Divider().color($r('app.color.divider_color'))
        // 原顶部标题栏的齿轮按钮移到这里：紧跟“扫码登录电脑端”，不再占用顶部空间。
        AppNavigationRow({
          title: '设置',
          description: this.settingsDescription(),
          testId: 'account_open_settings',
          grouped: true,
          showLeadingIcon: true,
          leadingIcon: $r('sys.symbol.gearshape'),
          onRowClick: (): void => this.onOpenSettings()
        });
      }
      .width('100%')
      .backgroundColor(settingsGroupBackground(this.feedCardStyle))
      .borderRadius(settingsGroupRadius(this.feedCardStyle))
      .clip(this.isCardStyle())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 未登录时工具分组不渲染，设置入口单独成组，保证未登录也能进入设置。 */
  @Builder
  private settingsSection() {
    Column() {
      AppNavigationRow({
        title: '设置',
        description: this.settingsDescription(),
        testId: 'account_open_settings',
        grouped: true,
        showLeadingIcon: true,
        leadingIcon: $r('sys.symbol.gearshape'),
        onRowClick: (): void => this.onOpenSettings()
      });
    }
    .width('100%')
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .clip(this.isCardStyle())
  }

  private settingsDescription(): string {
    return this.hasPendingUpdate ? '有新版本，前往设置查看' : '账户、外观、隐私';
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
