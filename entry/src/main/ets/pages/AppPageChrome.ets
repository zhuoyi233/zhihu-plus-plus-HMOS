/**
 * 全应用页面壳的基础构件。
 *
 * 页面只传递语义（标题、状态、尾部文本和操作），颜色、间距和可访问性保持一致，
 * 避免各业务页继续复制一套标题行、空态和设置导航行。
 */
export enum AppPageStatusKind {
  LOADING = 'loading',
  EMPTY = 'empty',
  ERROR = 'error'
}

@Component
export struct AppPageHeader {
  title: string = '';
  actionLabel: string = '';
  actionId: string = '';
  actionEnabled: boolean = true;
  actionAccessibilityText: string = '';
  onAction: () => void = (): void => {
  };

  build() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Text(this.title)
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .id(this.actionId)
          .fontSize($r('app.float.p1_body_font_size'))
          .enabled(this.actionEnabled)
          .accessibilityText(this.actionAccessibilityText.length > 0 ? this.actionAccessibilityText : this.actionLabel)
          .onClick((): void => this.onAction())
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct AppPageStatusPanel {
  kind: AppPageStatusKind = AppPageStatusKind.LOADING;
  message: string = '';
  testId: string = '';
  actionLabel: string = '';
  actionId: string = '';
  actionAccessibilityText: string = '';
  onAction: () => void = (): void => {
  };

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (this.kind === AppPageStatusKind.LOADING) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
          .accessibilityText('正在加载')
      }
      Text(this.message)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .id(this.actionId)
          .fontSize($r('app.float.p1_body_font_size'))
          .accessibilityText(this.actionAccessibilityText.length > 0 ? this.actionAccessibilityText : this.actionLabel)
          .onClick((): void => this.onAction())
      }
    }
    .id(this.testId)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }
}

@Component
export struct AppNavigationRow {
  title: string = '';
  description: string = '';
  trailingText: string = '';
  testId: string = '';
  rowAccessibilityText: string = '';
  grouped: boolean = false;
  onRowClick: () => void = (): void => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(this.title)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.description.length > 0) {
            Text(this.description)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.trailingText.length > 0) {
          Text(this.trailingText)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.secondary_text')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id(this.testId)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .backgroundColor(this.grouped ? Color.Transparent : $r('app.color.surface_background'))
    .borderRadius(this.grouped ? 0 : $r('app.float.p1_card_radius'))
    .accessibilityText(this.rowAccessibilityText.length > 0 ? this.rowAccessibilityText : this.title)
    .onClick((): void => this.onRowClick())
  }
}
