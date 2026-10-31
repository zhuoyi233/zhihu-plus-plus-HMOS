import { TOP_BAR_GLASS_MATERIAL } from '../../common/style/TopBarGlass';
import { TOP_BAR_BUTTON_DIAMETER_VP, TOP_BAR_ICON_FONT_SIZE } from '../../common/style/TopBarMaterial';

/**
 * 顶栏自定义动作按钮：main 设置页「更多」的等价封装。
 *
 * 固定 40×40vp `ButtonType.Circle`、20fp Symbol、`padding(0)`、透明底与 `stateEffect: true`；
 * 材质只有两档（计划 §4.1）：系统材质对象存在时 `.systemMaterial()` + 关闭普通模糊，
 * 否则透明底 + `COMPONENT_ULTRA_THIN` 模糊兜底。不新增 44vp 外壳、HDS 画布、半透明底色、
 * `interactive`／`lightEffect` 或加载指示——多按钮只按 §3.7 的 10vp 间距并排。
 *
 * 菜单／弹层由宿主页面负责，且必须绑在内置节点上（如尺寸随内容的 Row）：绑到本组件
 * 实例上收不到触发。
 */
@Component
export struct TopBarActionButton {
  /** Symbol 图标；普通导航动作不使用主题色。 */
  icon: Resource = $r('sys.symbol.circle');
  /** 透传到真实可点击节点的测试 id。 */
  elementId: string = 'top_bar_action';
  /** 朗读名称（如「外观与阅读体验更多操作」），随宿主标题变化。 */
  @Prop label: string = '';
  /** 业务禁用（如通知页忙碌时的「全部已读」）；不使用加载图标替换。 */
  @Prop disabled: boolean = false;
  /** 图标前景（默认为 primary_text；只有强调语义才由调用方传主题色）。 */
  iconColor: ResourceColor = $r('app.color.primary_text');
  onAction: () => void = (): void => {
  };

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(this.icon)
        .fontSize(TOP_BAR_ICON_FONT_SIZE)
        .fontColor([this.iconColor])
    }
      .id(this.elementId)
      .width(TOP_BAR_BUTTON_DIAMETER_VP)
      .height(TOP_BAR_BUTTON_DIAMETER_VP)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(TOP_BAR_GLASS_MATERIAL === undefined
        ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
      .systemMaterial(TOP_BAR_GLASS_MATERIAL)
      .enabled(!this.disabled)
      .accessibilityText(this.label)
      .onClick((): void => {
        this.onAction();
      })
  }
}
