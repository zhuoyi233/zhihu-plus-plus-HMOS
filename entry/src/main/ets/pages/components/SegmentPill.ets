import { DEFAULT_THEME_COLOR, onThemeColor, themeColorContainerColor } from 'data';

/**
 * 划线弹层互动胶囊（点赞/评论共用）。
 *
 * 为什么是独立 @Component 而不是页面里的带参 @Builder：@Builder 的参数是"按值传入"，
 * 已挂载的节点不会因为父级 @State 变化重新求值，实测点赞成功后胶囊仍停留在旧状态
 * （计数与实心态都不刷新）。这里用 @Prop 承接，父级重渲染时属性会同步刷新。
 *
 * 配色口径（与全项目主题色规则一致，不写死资源色）：
 * - 底色一律由生效主色派生（12% 主题容器底）。
 * - `active` 为选中态开关（点赞已赞）：整块主题色实心底 + onThemeColor 前景。
 * - `iconAccent` 为无状态动作入口（评论）：图标取强调色，计数保持正文色便于读数。
 */
@Component
export struct SegmentPill {
  @Prop icon: Resource;
  @Prop count: string;
  @Prop active: boolean;
  @Prop iconAccent: boolean;
  @Prop testId: string;
  @Prop label: string;
  onTap: () => void = (): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 6 }) {
        SymbolGlyph(this.icon)
          .fontSize(18)
          .fontColor([this.active
            ? onThemeColor(this.resolvedThemeColor)
            : (this.iconAccent ? this.resolvedThemeColor : $r('app.color.primary_text'))])
        Text(this.count)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor(this.active ? onThemeColor(this.resolvedThemeColor) : $r('app.color.primary_text'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .id(this.testId)
    .layoutWeight(1)
    .height($r('app.float.segment_action_button_height'))
    .padding(0)
    .backgroundColor(this.active ? this.resolvedThemeColor : themeColorContainerColor(this.resolvedThemeColor))
    .borderRadius($r('app.float.segment_action_button_radius'))
    .accessibilityText(this.label)
    .onClick(this.onTap)
  }
}
