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

/** HDS 标题栏自身高度（vp）：首屏让位 = 状态栏高度 + 该值。 */
export const ROOT_TITLE_BAR_CONTENT_HEIGHT: number = 56;

/**
 * 顶栏让位高度（vp）：状态栏高度 + HDS 标题栏自身高度（56vp），按固定常量兜底。
 *
 * 根顶栏已按华为官方样例改成「透明底 + HDS 自带滚动模糊」，玻璃只在标题栏自身
 * 高度内生效，因此让位不再跟随标题栏下方那段模糊蒙层（maskExtraHeight，默认
 * 32vp），内容可以像系统应用一样紧贴顶栏下沿。
 */
export function floatingTitleBarOffset(): number {
  const statusBar: number = AppStorage.get<number>('statusBarHeightVp') ?? 0;
  return Math.max(FLOATING_TITLE_BAR_OFFSET, statusBar + ROOT_TITLE_BAR_CONTENT_HEIGHT);
}

/** 加载更多时给悬浮底栏及系统手势区留出空间，圆圈完整停在底栏上方。 */
@Component
export struct FeedLoadMoreIndicator {
  elementId: string = '';
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('bottomRectHeight') private bottomRectHeightVp: number = 0;

  build() {
    Column() {
      LoadingProgress()
        .id(this.elementId)
        .width(40)
        .height(40)
        .color(this.resolvedThemeColor)
    }
    .width('100%')
    // 与 ZhihuHdsTabs 的 64vp 底栏同口径，另留 12vp 间隔。
    .padding({ top: 12, bottom: 64 + Math.max(0, this.bottomRectHeightVp) + 12 })
  }
}

@Component
export struct AppPageHeader {
  /** 当前生效主题色（AppShell 广播），驱动标题栏动作按钮强调色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  title: string = '';
  actionLabel: string = '';
  actionId: string = '';
  actionEnabled: boolean = true;
  actionAccessibilityText: string = '';
  onAction: () => void = (): void => {
  };

  build() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(this.title)
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .id(this.actionId)
          .fontSize($r('app.float.body_font_size'))
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
  /** 当前生效主题色（AppShell 启动时广播），驱动加载指示器颜色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (this.kind === AppPageStatusKind.LOADING) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
          .accessibilityText('正在加载')
      }
      Text(this.message)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .id(this.actionId)
          .fontSize($r('app.float.body_font_size'))
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
      Row({ space: $r('app.float.spacing_medium') }) {
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
        Column({ space: $r('app.float.spacing_xsmall') }) {
          Text(this.title)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.description.length > 0) {
            Text(this.description)
              .fontSize($r('app.float.secondary_font_size'))
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
            .fontSize($r('app.float.secondary_font_size'))
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
    .padding($r('app.float.card_padding'))
    .backgroundColor(this.grouped ? Color.Transparent : $r('app.color.surface_background'))
    // 分组只决定静态底色，单行按压反馈始终使用圆角矩形。
    .borderRadius($r('app.float.card_radius'))
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
   * 各页签不同——首页是启动那一帧就渲染的（此时 AppShell 的 restoreThemeColor 仍在异步
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
 * 下拉间隙的空占位（Refresh 的 builder）。
 *
 * Refresh 不指定 builder 时会画系统默认的圆形箭头（形似“刷新”图标），任何下拉——包括
 * 未达刷新阈值、以及拉到顶回弹后再次下滑——都会出现，松手即消失，容易被误认为正在
 * 刷新但内容没变。所有页面的 Refresh 都接本占位顶掉默认箭头，只在真正越过阈值/刷新时
 * 由 refreshingContent（主题色圆圈）给出反馈。
 */
@Builder
export function pullDownRefreshPlaceholder() {
}

/**
 * 触发下拉刷新所需的下拉距离（vp）：远大于普通回弹的越界量，需明显下拉才会刷新。
 * 替代已废弃的 Refresh offset（其语义是下拉起点距组件顶部距离，且被钳到 64vp）。
 */
export const PULL_REFRESH_TRIGGER_OFFSET_VP: number = 112;

/** 下拉跟手比例：固定 0.8，避免动态衰减让“轻拉也够阈值”。替代已废弃的 friction。 */
export const PULL_REFRESH_PULL_DOWN_RATIO: number = 0.8;

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
    // 只有下拉超过触发阈值（OverDrag）或已进入刷新（Refresh）才显示圆圈：
    // 未达阈值的普通下拉/回弹松手后不会刷新，露出“正在刷新”的圆圈会误导。
    this.dragging = status === RefreshStatus.OverDrag || status === RefreshStatus.Refresh;
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
