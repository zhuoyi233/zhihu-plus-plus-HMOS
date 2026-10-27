/**
 * “我的”一级页内容：个人资料、快捷入口、创作与工具。
 *
 * 页面只负责展示与点击回调，登录态、账号资料、更新提示和业务动作仍由 AppShell 提供；
 * 列数按实际容器宽度与字体缩放判定，不读取设备型号。
 */
import { DEFAULT_THEME_COLOR, FeedCardStyle, themeColorContainerColor } from 'data';
import { AppNavigationRow, floatingTitleBarOffset } from './AppPageChrome';
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
  scroller: Scroller = new Scroller();
  onOpenProfile: () => void = (): void => {};
  onOpenLogin: () => void = (): void => {};
  onOpenCollections: () => void = (): void => {};
  onOpenHistory: () => void = (): void => {};
  onOpenMessages: () => void = (): void => {};
  onOpenPinPublish: () => void = (): void => {};
  onOpenPinDrafts: () => void = (): void => {};
  onOpenScan: () => void = (): void => {};
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('systemFontSizeScale') private systemFontSizeScale: number = 1;
  @StorageProp('bottomRectHeight') private bottomRectHeightVp: number = 0;
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
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentStartOffset(floatingTitleBarOffset())
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
  private sectionTitle(title: string) {
    Text(title)
      .fontSize($r('app.float.secondary_font_size'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.secondary_text'))
      .width('100%')
      .padding({ left: $r('app.float.spacing_xsmall') })
  }
}
