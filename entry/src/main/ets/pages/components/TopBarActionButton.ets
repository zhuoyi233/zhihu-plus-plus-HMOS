import { TOP_BAR_ACTION_GLASS_MATERIAL } from '../../common/style/TopBarGlass';
import { TOP_BAR_BUTTON_DIAMETER_VP, TOP_BAR_ICON_FONT_SIZE } from '../../common/style/TopBarMaterial';

/**
 * 顶栏自定义动作按钮：main 设置页「更多」的几何与两档材质，外加与 HDS 原生返回键
 * 一致的按压形变（计划 §3.4 修订口径）。
 *
 * 固定 40×40vp `ButtonType.Circle`、20fp Symbol、`padding(0)`、透明底；
 * 材质只有两档（§4.1）：系统材质对象存在时 `.systemMaterial()` + 关闭普通模糊，否则透明底 +
 * `COMPONENT_ULTRA_THIN` 模糊兜底。材质对象带 `interactive: true`，按下时由系统材质给出
 * 与左侧原生返回键同一套交互形变与跟手反馈；此时关闭 `stateEffect`，避免再叠一层灰色
 * 按压遮罩（两种反馈叠加会与返回键表现不一致）。材质不可用时自动退回 `stateEffect`，
 * 保证低版本降级路径仍有按压反馈。不启用 `lightEffect`，不加 44vp 外壳、HDS 画布或半透明底色。
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
    // 有系统材质时按压反馈交给材质自身的交互形变（与 HDS 原生返回键同一套），不再叠灰色遮罩；
    // 无材质（API 23–25 或创建失败）时退回 stateEffect，保证降级路径仍有可用反馈。
    Button({ type: ButtonType.Circle, stateEffect: TOP_BAR_ACTION_GLASS_MATERIAL === undefined }) {
      SymbolGlyph(this.icon)
        .fontSize(TOP_BAR_ICON_FONT_SIZE)
        .fontColor([this.iconColor])
    }
      .id(this.elementId)
      .width(TOP_BAR_BUTTON_DIAMETER_VP)
      .height(TOP_BAR_BUTTON_DIAMETER_VP)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(TOP_BAR_ACTION_GLASS_MATERIAL === undefined
        ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
      .systemMaterial(TOP_BAR_ACTION_GLASS_MATERIAL)
      .enabled(!this.disabled)
      .accessibilityText(this.label)
      .onClick((): void => {
        this.onAction();
      })
  }
}
