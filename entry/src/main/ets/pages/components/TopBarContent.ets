import {
  TOP_BAR_CONTENT_ROW_HEIGHT_VP,
  TOP_BAR_HDS_BACK_RESERVE_VP,
  TOP_BAR_HORIZONTAL_PADDING_VP,
  TOP_BAR_SEARCH_PILL_HEIGHT_VP
} from '../../common/style/TopBarMaterial';
import { TOP_BAR_GLASS_MATERIAL } from '../../common/style/TopBarGlass';

/**
 * 顶栏返回键归属：每个可见页面只能有一个顶栏所有者。
 *
 * 普通导航一律由 HDS 原生 `backIcon` 承载（计划 §3.1）：本组件不绘制返回按钮，
 * 只按模式决定标题需要让出多少横向空间。
 */
export enum TopBarBackMode {
  /** 一级页：没有返回键，标题从 12vp 基础留白起排。 */
  NONE = 'none',
  /** HDS 自带返回键：标题让出 main 设置页同款 80vp 预留（不再自绘按钮）。 */
  HDS = 'hds'
}

/**
 * 顶栏内容行：main 设置页的等价封装。
 *
 * 48vp 内容行、左对齐 20fp Medium 标题（单行省略、`layoutWeight(1)`、跟随系统字号、
 * 不设 1.3 倍上限）、标题与动作之间 10vp、右侧 12vp；没有可见动作时保留一个 40×40vp
 * `Blank`（不删除尾部区域，也不让标题居中）。多个动作只按同一 40vp 几何与 10vp 间距并排。
 *
 * 组件不拥有业务导航：返回由 HDS 承担，标题可用 `hasTitleSlot` 换成自定义 Builder
 * （问题页折叠切换、回答页身份行），动作放在 `trailingSlot` 里。
 */
@Component
export struct TopBarContent {
  @Prop backMode: TopBarBackMode = TopBarBackMode.HDS;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 标题/副标题的测试 id：设备回归按 id 定位节点，必须落在真实文本节点上。 */
  titleId: string = 'top_bar_title';
  subtitleId: string = 'top_bar_subtitle';
  /** 标题被省略时仍要能被完整朗读。 */
  @Prop titleAccessibility: string = '';
  @Prop hasTitleSlot: boolean = false;
  @BuilderParam titleSlot: () => void = this.emptySlot;
  @Prop hasTrailingSlot: boolean = false;
  @BuilderParam trailingSlot: () => void = this.emptySlot;

  @Builder
  private emptySlot(): void {
  }

  private horizontalPadding(): Padding {
    const left: number = this.backMode === TopBarBackMode.HDS
      ? TOP_BAR_HDS_BACK_RESERVE_VP : TOP_BAR_HORIZONTAL_PADDING_VP;
    return { left: left, right: TOP_BAR_HORIZONTAL_PADDING_VP };
  }

  @Builder
  private titleText() {
    // 与 main 设置页一致：20fp Medium、单行省略、跟随系统字号，不额外限制放大倍数。
    Text(this.title)
      .fontSize($r('app.float.heading_font_size'))
      .id(this.titleId)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.primary_text'))
      .layoutWeight(1)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .accessibilityText(this.titleAccessibility.length > 0 ? this.titleAccessibility : this.title)
  }

  @Builder
  private titleWithSubtitle() {
    Column({ space: $r('app.float.spacing_xsmall') }) {
      Text(this.title)
        .fontSize($r('app.float.heading_font_size'))
        .id(this.titleId)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .accessibilityText(this.titleAccessibility.length > 0 ? this.titleAccessibility : this.title)
      Text(this.subtitle)
        .fontSize($r('app.float.secondary_font_size'))
        .id(this.subtitleId)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  build() {
    Row({ space: $r('app.float.spacing_small') }) {
      if (this.hasTitleSlot) {
        Row() {
          this.titleSlot()
        }
        // 尺寸属性必须紧跟构造器，layoutWeight 放在其后。
        .height(TOP_BAR_CONTENT_ROW_HEIGHT_VP)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .clip(true)
      } else if (this.subtitle.length > 0) {
        this.titleWithSubtitle()
      } else {
        this.titleText()
      }

      if (this.hasTrailingSlot) {
        // 动作之间的间距沿用外层 Row 的 10vp；此处只做尺寸随内容的等比封装。
        Row({ space: $r('app.float.spacing_small') }) {
          this.trailingSlot()
        }
        .alignItems(VerticalAlign.Center)
      } else {
        // 无动作时保留 main 设置页同款空占位，避免标题可用区域被拉长。
        Blank()
          .width(40)
          .height(40)
      }
    }
    .width('100%')
    .height(TOP_BAR_CONTENT_ROW_HEIGHT_VP)
    .padding(this.horizontalPadding())
    .alignItems(VerticalAlign.Center)
    // 背景装饰与空白不截获点击，按下与禁用由真实控件承担。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

/**
 * 顶栏悬浮胶囊（首页搜索、搜索页输入框、关注页签切换组）。
 *
 * 与圆按钮同一套两档材质（系统材质 / 普通模糊兜底，见 TopBarGlass.ets）：不读 HDS 沉浸
 * 能力、不加半透明兜底色；圆角恒为高度的一半，降级前后只减光效不改轮廓。宽度默认填满
 * 父容器，由父容器决定占位（避免把布局属性挂在自定义组件上）。
 */
@Component
export struct TopBarGlassPill {
  @BuilderParam content: () => void = this.emptySlot;
  @Prop heightVp: number = TOP_BAR_SEARCH_PILL_HEIGHT_VP;
  @Prop elementId: string = '';
  @Prop label: string = '';
  @Prop disabled: boolean = false;
  /** 输入框类胶囊由内部控件自行处理点击，此时不再套 Button。 */
  @Prop interactive: boolean = true;
  contentPadding: Padding = { left: 12, right: 12, top: 0, bottom: 0 };
  /** 胶囊宽度：默认填满父容器；紧凑导航组按显式宽度悬浮。 */
  widthVp: Length = '100%';
  onAction: () => void = (): void => {
  };

  @Builder
  private emptySlot(): void {
  }

  private surfaceBackground(): ResourceColor {
    // 两档路径都保持透明底：有材质时由系统材质绘制，无材质时由模糊兜底，不加遮挡色。
    return Color.Transparent;
  }

  @Builder
  private surface(contentWidth: Length) {
    if (this.interactive) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        this.content()
      }
      // Button 的宽高必须紧跟构造器或 padding()，否则不满足组件尺寸规则。
      .padding(this.contentPadding)
      .width(contentWidth)
      .height(this.heightVp)
      .id(this.elementId)
      .backgroundColor(this.surfaceBackground())
      .backgroundBlurStyle(TOP_BAR_GLASS_MATERIAL === undefined
        ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
      .systemMaterial(TOP_BAR_GLASS_MATERIAL)
      .borderRadius(this.heightVp / 2)
      .clip(true)
      .enabled(!this.disabled)
      .accessibilityText(this.label)
      .onClick((): void => {
        this.onAction();
      })
    } else {
      Row() {
        this.content()
      }
      .width(contentWidth)
      .height(this.heightVp)
      .id(this.elementId)
      .padding(this.contentPadding)
      .backgroundColor(this.surfaceBackground())
      .backgroundBlurStyle(TOP_BAR_GLASS_MATERIAL === undefined
        ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
      .systemMaterial(TOP_BAR_GLASS_MATERIAL)
      .borderRadius(this.heightVp / 2)
      .clip(true)
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    this.surface(this.widthVp)
  }
}
