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

/**
 * 悬浮标题栏让位高度（状态栏 + 标题栏占位）。
 *
 * 统一约定：所有带下拉刷新/滚动区域的页面，由页面内容容器统一
 * `.padding({ top: FLOATING_TITLE_BAR_OFFSET })` 下移到悬浮标题栏下方，
 * 使 Refresh 指示区域从标题栏下沿开始（对齐上游 FeedPullToRefresh 的
 * indicator padding）。不要把让位写进列表自身的 padding——那会让刷新
 * 指示区域仍从页面顶端开始，圆圈越过顶栏盖住状态栏。
 */
export const FLOATING_TITLE_BAR_OFFSET: number = 94;

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

/** 下拉刷新自定义区域的构造参数（无字段，仅用于 ComponentContent 类型标注）。 */
export class FeedPullDownIndicatorOptions {
}

/**
 * 下拉刷新区域的蓝色加载圆圈：与上拉加载更多同款同尺寸。
 * 容器高度自适应 Refresh 指示区域（下拉间隙），justifyContent End 让圆圈贴着
 * 间隙底部、跟随下拉距离移动（等价上游 Material3 指示器随拖拽平移的行为）。
 * 注意：不要给容器设固定高度——固定高度会让内容锚定位置失控（圆圈曾因此
 * 钉在状态栏一栏，见 2026-09-15 修复）；指示区域的整体下移由各页面把
 * Refresh 组件 margin 到悬浮标题栏下方完成。
 */
@Builder
export function feedPullDownIndicator(_options: FeedPullDownIndicatorOptions) {
  Column() {
    LoadingProgress()
      .width(40)
      .height(40)
      .color($r('app.color.brand_primary'))
  }
  .width('100%')
  .constraintSize({ minHeight: 48 })
  .justifyContent(FlexAlign.End)
  .padding({ bottom: 12 })
}
