import {
  decodeImmersiveMaterialSupport,
  ImmersiveMaterialSupportState
} from '../../common/style/ImmersiveMaterialStyles';
import { TOP_BAR_GLASS_MATERIAL } from '../../common/style/TopBarGlass';
import {
  TOP_BAR_BUTTON_DIAMETER_VP,
  TOP_BAR_CANVAS_CLIP_VP,
  TOP_BAR_CANVAS_DIAMETER_VP,
  TOP_BAR_HIT_TARGET_VP,
  TOP_BAR_ICON_FONT_SIZE,
  TopBarMaterialPath,
  resolveTopBarMaterialPath
} from '../../common/style/TopBarMaterial';
import { materialCanvas } from './MaterialCanvas';

/**
 * 顶栏圆按钮：40vp 可见轮廓 + 20vp 图标 + ≥44vp 方形热区，三档渲染路径互斥。
 *
 * 材质路径由「设备 HDS 沉浸能力（AppStorage 广播，不在 build 里查询）」与
 * 「API 26 系统材质对象是否创建成功」共同决定（策略见 TopBarMaterial.ets）：
 * - 系统材质：与设置页一致的 uiMaterial 薄玻璃，关闭普通模糊，避免双路径叠加；
 * - HDS 画布：API 23–25 沉浸真机沿用已验证的 52vp 画布 + 44vp 裁剪窗几何；
 * - 模糊兜底：COMPONENT_ULTRA_THIN + 半透明中性底，降级后轮廓、尺寸、热区不变。
 *
 * 菜单/弹层由宿主页面负责，但必须绑在内置节点上（如包一层尺寸随内容的 Row）：
 * 绑到本组件实例上收不到触发，实测点击无任何弹层。
 */
@Component
export struct TopBarActionButton {
  /** Symbol 图标；普通导航动作不使用主题色。 */
  icon: Resource = $r('sys.symbol.circle');
  /** 透传到真实可点击节点的测试 id 与朗读名称（id 不能为空串）。 */
  elementId: string = 'top_bar_action';
  /** 朗读名称随宿主标题变化（如「外观与阅读体验更多操作」），必须是可观察属性。 */
  @Prop label: string = '';
  @Prop disabled: boolean = false;
  /** 提交中：显示加载指示并屏蔽重复点击。 */
  @Prop busy: boolean = false;
  /** 图标前景（默认 primary_text；选中态由调用方按主题色传入）。 */
  iconColor: ResourceColor = $r('app.color.primary_text');
  onAction: () => void = (): void => {
  };
  @StorageProp('immersiveMaterialSupport') private immersiveMaterialSupport: string = 'unknown';

  private materialPath(): TopBarMaterialPath {
    return resolveTopBarMaterialPath({
      hdsImmersiveSupported: decodeImmersiveMaterialSupport(this.immersiveMaterialSupport)
        === ImmersiveMaterialSupportState.SUPPORTED,
      systemMaterialCreated: TOP_BAR_GLASS_MATERIAL !== undefined
    });
  }

  private isCanvasPath(): boolean {
    return this.materialPath() === TopBarMaterialPath.HDS_CANVAS;
  }

  private isSystemPath(): boolean {
    return this.materialPath() === TopBarMaterialPath.SYSTEM_MATERIAL;
  }

  private buttonBackground(): ResourceColor {
    // 画布分支的玻璃由画布绘制；系统材质分支由材质接管底色；只有兜底分支需要中性半透明底。
    if (this.isCanvasPath() || this.isSystemPath()) {
      return Color.Transparent;
    }
    return $r('app.color.top_bar_button_fallback_background');
  }

  @Builder
  private iconContent() {
    if (this.busy) {
      LoadingProgress()
        .width(TOP_BAR_ICON_FONT_SIZE)
        .height(TOP_BAR_ICON_FONT_SIZE)
        .color($r('app.color.primary_text'))
    } else {
      SymbolGlyph(this.icon)
        .fontSize($r('app.float.top_bar_icon_font_size'))
        .fontColor([this.iconColor])
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isCanvasPath()) {
        materialCanvas(TOP_BAR_CANVAS_DIAMETER_VP, TOP_BAR_CANVAS_DIAMETER_VP)
      }
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        this.iconContent()
      }
      // Button 的宽高必须紧跟构造器，否则不满足组件尺寸规则。
      .width(TOP_BAR_BUTTON_DIAMETER_VP)
      .height(TOP_BAR_BUTTON_DIAMETER_VP)
      .padding(0)
      .borderRadius(TOP_BAR_BUTTON_DIAMETER_VP / 2)
      .backgroundColor(this.buttonBackground())
      .backgroundBlurStyle(this.isSystemPath() || this.isCanvasPath()
        ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
      .systemMaterial(this.isSystemPath() ? TOP_BAR_GLASS_MATERIAL : undefined)
      .id(this.elementId)
      .enabled(!this.disabled && !this.busy)
      .accessibilityText(this.label)
      .onClick((): void => {
        this.onAction();
      })
    }
    .width(TOP_BAR_HIT_TARGET_VP)
    .height(TOP_BAR_HIT_TARGET_VP)
    .borderRadius(TOP_BAR_CANVAS_CLIP_VP / 2)
    .clip(this.isCanvasPath())
    // 根节点只做热区与裁剪，点击与禁用态由内部真实 Button 承担。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
