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

@Component
export struct AboutAppPage {
  @Prop installedVersionLabel: string = '';
  @Prop developerModeEnabled: boolean = false;
  onVersionRowClick: () => void = (): void => {};
  onOpenProject: () => void = (): void => {};
  onOpenProjectLicense: () => void = (): void => {};
  onOpenOpenSourceLicenses: () => void = (): void => {};
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  build() {
    Scroll() {
      Column() {
        Column({ space: $r('app.float.spacing_large') }) {
          Column({ space: $r('app.float.spacing_xsmall') }) {
            Text('知乎++鸿蒙版')
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
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          bottom: 40
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .id('about_app_scroll')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentStartOffset(floatingTitleBarOffset())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.page_background'))
  }
}
