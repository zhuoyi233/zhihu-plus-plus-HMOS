import { DEFAULT_THEME_COLOR, onThemeColor } from 'data';

@Component
export struct SystemUpdateSettingsPage {
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @Prop installedVersionLabel: string = '';
  @Prop updateCheckBusy: boolean = false;
  @Prop updateCheckMessage: string = '';
  @Prop availableVersion: string = '';
  onCheckUpdate: () => void = (): void => {};
  onOpenDownload: () => void = (): void => {};
  onOpenProject: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        Text('版本与更新').fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text')).width('100%')
        Column({ space: $r('app.float.p1_spacing_medium') }) {
          Row() {
            Column({ space: 4 }) {
              Text('知乎++鸿蒙版').fontSize($r('app.float.p1_body_font_size'))
                .fontColor($r('app.color.primary_text'))
              Text(this.installedVersionLabel).id('p5_system_installed_version')
                .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.updateCheckBusy) {
              LoadingProgress().width(24).height(24).color(this.resolvedThemeColor)
            }
          }.width('100%').alignItems(VerticalAlign.Center)

          Button(this.updateCheckBusy ? '正在检查…' : '检查更新')
            .id('p5_system_check_update').width('100%').enabled(!this.updateCheckBusy)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .backgroundColor(this.resolvedThemeColor)
            .onClick((): void => this.onCheckUpdate())

          if (this.updateCheckMessage.length > 0) {
            Text(this.updateCheckMessage).id('p5_system_update_status')
              .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
              .width('100%')
          }
          if (this.availableVersion.length > 0) {
            Button(`前往下载 ${this.availableVersion}`).id('p5_system_update_download').width('100%')
              .fontColor(onThemeColor(this.resolvedThemeColor))
              .backgroundColor(this.resolvedThemeColor)
              .onClick((): void => this.onOpenDownload())
          }
        }.width('100%').padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius')).backgroundColor($r('app.color.surface_background'))

        Text('支持与诊断').fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text')).width('100%')
        Column() {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row() {
              Column({ space: 4 }) {
                Text('GitHub 项目与问题反馈').fontSize($r('app.float.p1_body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                Text('查看发行说明、提交问题或获取诊断帮助')
                  .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18)
                .fontColor([$r('app.color.secondary_text')])
            }.width('100%').alignItems(VerticalAlign.Center)
          }.id('p5_system_open_project').width('100%').padding($r('app.float.p1_card_padding'))
            .backgroundColor(Color.Transparent).onClick((): void => this.onOpenProject())
        }.width('100%').borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: 16, bottom: 40 })
    }
    .id('p5_system_update_scroll').width('100%').height('100%').scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_background'))
  }
}
