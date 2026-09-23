/**
 * 全应用页面壳的基础构件。
 *
 * 页面只传递语义（标题、状态、尾部文本和操作），颜色、间距和可访问性保持一致，
 * 避免各业务页继续复制一套标题行、空态和设置导航行。
 */
import { DEFAULT_THEME_COLOR, onThemeColor } from 'data';

export enum AppPageStatusKind {
  LOADING = 'loading',
  EMPTY = 'empty',
  ERROR = 'error'
}

/**
 * 悬浮标题栏让位高度（状态栏 + 标题栏占位）。
 *
 * 统一约定（覆盖式顶栏，2026-09-23 起）：页面内容容器**不设** top padding，滚动视口
 * 一直延伸到屏幕顶端，滚动内容因此能穿过玻璃标题栏形成沉浸光感；首屏内容的起始
 * 位置改由滚动容器的 `.contentStartOffset(FLOATING_TITLE_BAR_OFFSET)` 内缩——未滚动
 * 时内容仍从标题栏下沿开始，滚起来后才从标题栏后面穿过。
 *
 * 不要把让位写回内容容器的 top padding：那会把整个滚动视口压到标题栏下方，内容
 * 永远到不了标题栏后面（详情页改造前的表现，dumpLayout 实测 List top ≈ 标题栏底）。
 *
 * 带下拉刷新的页面同样适用：下拉只发生在列表处于顶部（未滚动）时，此刻标题栏走
 * originalStyle 的透明底，Refresh 指示圆圈不会被滚动态白纱遮住，因此 Refresh 的
 * offset/friction 无需为让位做补偿。
 */
export const FLOATING_TITLE_BAR_OFFSET: number = 94;

@Component
export struct AppPageHeader {
  /** 当前生效主题色（P1Shell 广播），驱动标题栏动作按钮强调色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
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
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .backgroundColor(this.resolvedThemeColor)
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
  /** 当前生效主题色（P1Shell 启动时广播），驱动加载指示器颜色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (this.kind === AppPageStatusKind.LOADING) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
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
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .backgroundColor(this.resolvedThemeColor)
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
  showLeadingIcon: boolean = false;
  leadingIcon: Resource = $r('sys.symbol.circle');
  leadingIconIsMedia: boolean = false;
  onRowClick: () => void = (): void => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        if (this.showLeadingIcon) {
          if (this.leadingIconIsMedia) {
            Image(this.leadingIcon)
              .width(24)
              .height(24)
              .fillColor($r('app.color.primary_text'))
              .objectFit(ImageFit.Contain)
          } else {
            SymbolGlyph(this.leadingIcon)
              .fontSize(24)
              .fontColor([$r('app.color.primary_text')])
          }
        }
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

/** 下拉刷新自定义区域的构造参数（ComponentContent 传参用）。 */
export class FeedPullDownIndicatorOptions {
  /**
   * 圆圈额外的绘制下移量（vp）。覆盖式顶栏页面传 FLOATING_TITLE_BAR_OFFSET：
   * Refresh 头部区域从页面顶端展开，圆圈会贴着状态栏出现，需要把它挪到悬浮
   * 标题栏下沿；占位式页面 Refresh 组件本身已在标题栏下方，保持 0。
   */
  topInset: number = 0;
}

/**
 * 下拉刷新区域的蓝色加载圆圈：与上拉加载更多同款同尺寸。
 * 容器高度自适应 Refresh 指示区域（下拉间隙），justifyContent End 让圆圈贴着
 * 间隙底部、跟随下拉距离移动（等价上游 Material3 指示器随拖拽平移的行为）。
 * 注意：不要给容器设固定高度——固定高度会让内容锚定位置失控（圆圈曾因此
 * 钉在状态栏一栏，见 2026-09-15 修复）。
 * 覆盖式顶栏下（2026-09-23 起）Refresh 头部区域从页面顶端展开，圆圈会贴着状态栏
 * 出现；覆盖式页面经 options.topInset 传 FLOATING_TITLE_BAR_OFFSET，用绘制偏移
 * （translate，不占布局、不影响下拉触发距离）把圆圈挪到悬浮标题栏下沿；占位式
 * 页面 Refresh 本身已在标题栏下方，topInset 保持 0。
 */
@Builder
export function feedPullDownIndicator(options: FeedPullDownIndicatorOptions) {
  Column() {
    LoadingProgress()
      .width(40)
      .height(40)
      // 文件级 @Builder 无组件上下文，直接读 AppStorage 当前生效主题色；
      // 指示器随每次刷新动作重新构建，主题切换后下一次下拉即生效。
      .color(AppStorage.get<string>('resolvedThemeColor') ?? DEFAULT_THEME_COLOR)
  }
  .width('100%')
  .constraintSize({ minHeight: 48 })
  .justifyContent(FlexAlign.End)
  .padding({ bottom: 12 })
  .translate({ y: options.topInset })
}
