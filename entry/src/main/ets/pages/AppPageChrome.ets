/**
 * 全应用页面壳的基础构件。
 *
 * 页面只传递语义（标题、状态、尾部文本和操作），颜色、间距和可访问性保持一致，
 * 避免各业务页继续复制一套标题行、空态和设置导航行。
 */
import { DEFAULT_THEME_COLOR, onThemeColor } from 'data';
import { ComponentContent, UIContext } from '@kit.ArkUI';

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
  /**
   * 下拉间隙是否处于展开态。ArkUI 收起头部后不会裁剪 refreshingContent——实测头部
   * 节点已是 0×0 而圆圈仍按自身尺寸绘制，所以不展开时必须什么都不画，否则刷新结束
   * 圆圈会常驻页面（2026-09-25 修复）。
   */
  active: boolean = false;
}

/**
 * 下拉刷新区域的加载圆圈：与上拉加载更多同款同尺寸，颜色跟随当前生效主题色。
 * 容器高度自适应 Refresh 指示区域（下拉间隙），justifyContent End 让圆圈贴着
 * 间隙底部、跟随下拉距离移动（等价上游 Material3 指示器随拖拽平移的行为）。
 * 注意：不要给容器设固定高度——固定高度会让内容锚定位置失控（圆圈曾因此
 * 钉在状态栏一栏，见 2026-09-15 修复）。
 * 覆盖式顶栏下（2026-09-23 起）Refresh 头部区域从页面顶端展开，圆圈会贴着状态栏
 * 出现；覆盖式页面经 topInset 传 FLOATING_TITLE_BAR_OFFSET，用绘制偏移
 * （translate，不占布局、不影响下拉触发距离）把圆圈挪到悬浮标题栏下沿；占位式
 * 页面 Refresh 本身已在标题栏下方，topInset 保持 0。
 */
@Component
struct FeedPullDownIndicatorView {
  /**
   * 主题色必须经 @StorageProp 订阅，不能在 feedPullDownIndicator 里直读 AppStorage：
   * 按值传参的 @Builder 只在首次渲染时求值、之后 params 不变就不再重算，而首次渲染时机
   * 各页签不同——首页是启动那一帧就渲染的（此时 P1Shell 的 restoreThemeColor 仍在异步
   * 等待，生效色还是默认知乎蓝），圆圈因此永久停在默认色；其余页签首次渲染发生在主题
   * 恢复之后，看起来才"正常"（2026-09-25 主页下拉刷新不跟随主题色的根因）。
   */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 必须用 @Prop：ComponentContent.update() 换新参数实例后，普通成员不会再同步进来。 */
  @Prop active: boolean = false;
  @Prop topInset: number = 0;

  build() {
    Column() {
      if (this.active) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .justifyContent(FlexAlign.End)
    .padding({ bottom: 12 })
    .translate({ y: this.topInset })
  }
}

/**
 * Refresh 的 refreshingContent 要求 ComponentContent，故经文件级 @Builder 包一层；
 * 主题色与展开态由 FeedPullDownIndicatorView 自己订阅/接收，不依赖这里的求值时机。
 */
@Builder
export function feedPullDownIndicator(options: FeedPullDownIndicatorOptions) {
  FeedPullDownIndicatorView({ topInset: options.topInset, active: options.active })
}

/**
 * 下拉刷新圆圈的生命周期宿主：持有 ComponentContent，并把“间隙是否展开”同步给它。
 * 展开态有两个来源，缺一不可——onStateChange 覆盖手势下拉（Drag/OverDrag），
 * setRefreshing 覆盖程序化刷新（双击页签、登录重载等不经过手势的路径）。
 */
export class FeedPullDownIndicatorHost {
  private readonly content: ComponentContent<FeedPullDownIndicatorOptions>;
  private readonly topInset: number;
  private dragging: boolean = false;
  private refreshing: boolean = false;
  private active: boolean = false;

  constructor(uiContext: UIContext, topInset: number) {
    this.topInset = topInset;
    this.content = new ComponentContent(uiContext, wrapBuilder(feedPullDownIndicator),
      FeedPullDownIndicatorHost.buildOptions(topInset, false));
  }

  /** 传给 Refresh 的 refreshingContent。 */
  view(): ComponentContent<FeedPullDownIndicatorOptions> {
    return this.content;
  }

  onStateChange(status: RefreshStatus): void {
    this.dragging = status === RefreshStatus.Drag || status === RefreshStatus.OverDrag
      || status === RefreshStatus.Refresh;
    this.apply();
  }

  setRefreshing(refreshing: boolean): void {
    this.refreshing = refreshing;
    this.apply();
  }

  dispose(): void {
    this.content.dispose();
  }

  private apply(): void {
    const active = this.dragging || this.refreshing;
    if (active === this.active) {
      return;
    }
    this.active = active;
    this.content.update(FeedPullDownIndicatorHost.buildOptions(this.topInset, active));
  }

  private static buildOptions(topInset: number, active: boolean): FeedPullDownIndicatorOptions {
    const options = new FeedPullDownIndicatorOptions();
    options.topInset = topInset;
    options.active = active;
    return options;
  }
}
