import {
  resolveTopBarMaterialPath,
  TOP_BAR_CONTENT_ROW_HEIGHT_VP,
  TOP_BAR_HDS_BACK_RESERVE_VP,
  TOP_BAR_HORIZONTAL_PADDING_VP,
  TOP_BAR_SEARCH_PILL_HEIGHT_VP,
  TopBarMaterialPath
} from '../../common/style/TopBarMaterial';
import { TOP_BAR_GLASS_MATERIAL } from '../../common/style/TopBarGlass';
import {
  decodeImmersiveMaterialSupport,
  ImmersiveMaterialSupportState
} from '../../common/style/ImmersiveMaterialStyles';
import { TopBarActionButton } from './TopBarActionButton';

/** 顶栏返回键归属：三种模式互斥，保证每个可见页面只有一个顶栏所有者。 */
export enum TopBarBackMode {
  /** 一级页：没有返回键，标题贴着横向留白起排。 */
  NONE = 'none',
  /** 自绘返回：共享圆按钮，标题在其右侧统一间距起排。 */
  CUSTOM = 'custom',
  /** HDS 自带返回键：内容只让出返回热区，不再自绘按钮。 */
  HDS = 'hds'
}

/**
 * 顶栏内容行：48vp 行高、左对齐标题、右侧动作槽位。
 *
 * 组件不拥有业务导航——返回语义由宿主注入（编辑器、设置双栏、图片预览各有自己的
 * 返回顺序），这里只负责结构与几何。标题可用 `hasTitleSlot` 换成自定义 Builder
 * （问题页折叠切换、回答页身份行），动作放在 `trailingContent` 槽位里。
 */
@Component
export struct TopBarContent {
  @Prop backMode: TopBarBackMode = TopBarBackMode.CUSTOM;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 标题/副标题的测试 id：设备回归按 id 定位节点，必须落在真实文本节点上。 */
  titleId: string = 'top_bar_title';
  subtitleId: string = 'top_bar_subtitle';
  /** 标题被省略时仍要能被完整朗读。 */
  @Prop titleAccessibility: string = '';
  @Prop backId: string = 'top_bar_back';
  @Prop backLabel: string = '返回';
  /** 返回动作不可用（如编辑器已发布）时禁用返回键。 */
  @Prop backDisabled: boolean = false;
  onBack: () => void = (): void => {
  };
  @Prop hasTitleSlot: boolean = false;
  @BuilderParam titleSlot: () => void = this.emptySlot;
  @Prop hasTrailingSlot: boolean = false;
  @BuilderParam trailingSlot: () => void = this.emptySlot;
  /** 长标题需要压缩时，返回键与动作保持不收缩。 */
  @Prop centerTitle: boolean = false;

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
    Column({ space: $r('app.float.spacing_xsmall') }) {
      // fontSize() 必须紧跟 Text 构造器，测试 id 放在其后。
      Text(this.title)
        .fontSize($r('app.float.heading_font_size'))
        .id(this.titleId)
        .fontWeight(FontWeight.Medium)
        .maxFontScale(1.3)
        .fontColor($r('app.color.primary_text'))
        .textAlign(this.centerTitle ? TextAlign.Center : TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .accessibilityText(this.titleAccessibility.length > 0 ? this.titleAccessibility : this.title)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize($r('app.float.secondary_font_size'))
          .id(this.subtitleId)
          .maxFontScale(1.3)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .alignItems(this.centerTitle ? HorizontalAlign.Center : HorizontalAlign.Start)
    .layoutWeight(1)
  }

  build() {
    Row({ space: $r('app.float.top_bar_action_spacing') }) {
      if (this.backMode === TopBarBackMode.CUSTOM) {
        TopBarActionButton({
          icon: $r('sys.symbol.chevron_left'),
          elementId: this.backId,
          label: this.backLabel,
          disabled: this.backDisabled,
          onAction: (): void => {
            this.onBack();
          }
        })
      }
      if (this.hasTitleSlot) {
        Row() {
          this.titleSlot()
        }
        // 尺寸属性必须紧跟构造器，layoutWeight 放在其后。
        .height(TOP_BAR_CONTENT_ROW_HEIGHT_VP)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .clip(true)
      } else {
        this.titleText()
      }
      if (this.hasTrailingSlot) {
        Row({ space: $r('app.float.top_bar_action_spacing') }) {
          this.trailingSlot()
        }
        .alignItems(VerticalAlign.Center)
        .flexShrink(0)
      }
    }
    .width('100%')
    .height(TOP_BAR_CONTENT_ROW_HEIGHT_VP)
    .padding(this.horizontalPadding())
    .alignItems(VerticalAlign.Center)
    // 背景装饰与空白不截获点击，按下与禁用由真实 Button 承担。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

/**
 * 顶栏悬浮胶囊（首页搜索、搜索页输入框）：与圆按钮同一套材质路径判断，
 * 圆角恒为高度的一半——降级前后只减光效，不改轮廓。宽度恒填充父容器，
 * 由父容器决定占位（避免把 layoutWeight 之类的通用属性挂在自定义组件上）。
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
  @StorageProp('immersiveMaterialSupport') private immersiveMaterialSupport: string = 'unknown';

  @Builder
  private emptySlot(): void {
  }

  private usesSystemMaterial(): boolean {
    // 胶囊只做系统材质与普通模糊两档：HDS 画布分支的宽度补偿属于底部胶囊实现，不移植到顶栏。
    return resolveTopBarMaterialPath({
      hdsImmersiveSupported: decodeImmersiveMaterialSupport(this.immersiveMaterialSupport)
        === ImmersiveMaterialSupportState.SUPPORTED,
      systemMaterialCreated: TOP_BAR_GLASS_MATERIAL !== undefined
    }) === TopBarMaterialPath.SYSTEM_MATERIAL;
  }

  private pillRadius(): number {
    return this.heightVp / 2;
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
      .backgroundColor(this.usesSystemMaterial()
        ? Color.Transparent : $r('app.color.top_bar_button_fallback_background'))
      .backgroundBlurStyle(this.usesSystemMaterial() ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
      .systemMaterial(this.usesSystemMaterial() ? TOP_BAR_GLASS_MATERIAL : undefined)
      .borderRadius(this.pillRadius())
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
      .backgroundColor(this.usesSystemMaterial()
        ? Color.Transparent : $r('app.color.top_bar_button_fallback_background'))
      .backgroundBlurStyle(this.usesSystemMaterial() ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
      .systemMaterial(this.usesSystemMaterial() ? TOP_BAR_GLASS_MATERIAL : undefined)
      .borderRadius(this.pillRadius())
      .clip(true)
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    this.surface(this.widthVp)
  }
}
