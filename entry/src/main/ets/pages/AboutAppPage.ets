/**
 * “关于应用”页：收拢应用与版本、GitHub、项目协议、开源许可与免责声明。
 * 版本弹层与许可弹层仍由 AppShell 统一承载，避免同一弹层出现两个有效宿主。
 */
import { FeedCardStyle } from 'data';
import { AppNavigationRow, floatingTitleBarOffset } from './AppPageChrome';
import {
  settingsGroupBackground,
  settingsGroupRadius
} from './AccountSettingsLayout';
import { SettingsHighlightGroup } from '../components/SettingsSearchHighlight';
import { SettingsSearchLocationRunner } from './SettingsSearchLocationRunner';
import { readLocationRequest, SettingsPaneId, SettingsSearchLocationRequest } from './SettingsSearchTarget';

@Component
export struct AboutAppPage {
  @Prop installedVersionLabel: string = '';
  @Prop developerModeEnabled: boolean = false;
  /** 嵌入设置右栏时为 true：标题与顶部让位由宿主标题行承担，本页不再预留悬浮标题栏高度。 */
  @Prop embedded: boolean = false;
  onVersionRowClick: () => void = (): void => {};
  onOpenProject: () => void = (): void => {};
  onOpenProjectLicense: () => void = (): void => {};
  onOpenOpenSourceLicenses: () => void = (): void => {};
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  /** 搜索定位：本页滚动容器执行器与请求 tick 监听。 */
  private scroller: Scroller = new Scroller();
  private locator: SettingsSearchLocationRunner | undefined = undefined;
  @StorageProp('settingsSearchLocationTick') @Watch('onSearchLocationRequest')
  private searchLocationTick: number = 0;

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  aboutToAppear(): void {
    this.consumeSearchLocation();
  }

  aboutToDisappear(): void {
    this.locator?.cancel(false);
    this.locator = undefined;
  }

  private onSearchLocationRequest(): void {
    this.consumeSearchLocation();
  }

  /** 消费定位请求：只定位行，不自动执行行操作（不打开网页或许可弹层）。 */
  private consumeSearchLocation(): void {
    const request = readLocationRequest();
    if (request === undefined || request.paneId !== SettingsPaneId.ABOUT || !this.embedded) {
      return;
    }
    this.locator?.cancel(false);
    this.locator = new SettingsSearchLocationRunner({
      getUIContext: (): UIContext => this.getUIContext(),
      isEmbedded: (): boolean => this.embedded,
      isReady: (): boolean => true,
      getScroller: (): Scroller => this.scroller,
      scrollId: 'about_app_scroll',
      contentId: 'about_app_content',
      desiredTop: (): number => floatingTitleBarOffset() + 12,
      onFailed: (): void => this.getUIContext().getPromptAction().showToast({
        message: '暂时无法定位，请稍后重试', duration: 2000
      }),
      onFallback: (): void => this.getUIContext().getPromptAction().showToast({
        message: '该项当前被隐藏，已定位到前置开关', duration: 2000
      })
    });
    this.locator.consume(request);
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        Column({ space: $r('app.float.spacing_large') }) {
          Column({ space: $r('app.float.spacing_xsmall') }) {
            Text($r('app.string.EntryAbility_label'))
              .id('about_app_name')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            Text(this.installedVersionLabel)
              .id('about_app_version')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({
            left: $r('app.float.page_padding'),
            right: $r('app.float.page_padding'),
            top: $r('app.float.spacing_small'),
            bottom: $r('app.float.spacing_small')
          })

          SettingsHighlightGroup({ groupId: 'about_group_project' }) {
            Column() {
              AppNavigationRow({
                title: '应用与版本',
                description: this.installedVersionLabel,
                testId: 'open_about_version',
                grouped: true,
                showLeadingIcon: true,
                leadingIcon: $r('sys.symbol.info_circle'),
                onRowClick: (): void => this.onVersionRowClick()
              });
              Divider().color($r('app.color.divider_color'))
              AppNavigationRow({
                title: 'GitHub',
                description: '查看项目主页',
                testId: 'open_project_home',
                grouped: true,
                showLeadingIcon: true,
                leadingIcon: $r('app.media.github_mark'),
                leadingIconIsMedia: true,
                onRowClick: (): void => this.onOpenProject()
              });
              Divider().color($r('app.color.divider_color'))
              AppNavigationRow({
                title: '项目协议',
                description: 'GNU AGPL v3.0',
                testId: 'open_project_license',
                grouped: true,
                showLeadingIcon: true,
                leadingIcon: $r('sys.symbol.checkmark_square'),
                onRowClick: (): void => this.onOpenProjectLicense()
              });
              Divider().color($r('app.color.divider_color'))
              AppNavigationRow({
                title: '开源许可',
                description: '3 个本地 HAR 模块 · GNU AGPL v3.0',
                testId: 'open_open_source_licenses',
                grouped: true,
                showLeadingIcon: true,
                leadingIcon: $r('sys.symbol.doc_text'),
                onRowClick: (): void => this.onOpenOpenSourceLicenses()
              });
            }
            .width('100%')
            .backgroundColor(settingsGroupBackground(this.feedCardStyle))
            .borderRadius(settingsGroupRadius(this.feedCardStyle))
            .clip(this.isCardStyle())
          }

          if (this.developerModeEnabled) {
            Text('开发者选项已开启，可在设置首页底部进入。')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
              .padding({ left: $r('app.float.spacing_xsmall') })
          }

          Text('本软件仅供学习交流使用，应用内内容由知乎网站提供，著作权归其对应作者所有。')
            .id('account_disclaimer')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .padding({ left: $r('app.float.spacing_xsmall'), right: $r('app.float.spacing_xsmall') })
        }
        .width('100%')
        .constraintSize({ maxWidth: 720 })
        .id('about_app_content')
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          bottom: 40
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .align(Alignment.TopStart)
    .id('about_app_scroll')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentStartOffset(floatingTitleBarOffset())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.page_background'))
    .onScrollStart((): void => {
      this.locator?.onScrollStarted();
    })
    .onScrollStop((): void => {
      this.locator?.onScrollStopped();
    })
  }
}
