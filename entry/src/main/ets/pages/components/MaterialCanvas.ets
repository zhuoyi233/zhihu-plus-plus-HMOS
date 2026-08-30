import { DividerMode, hdsMaterial, HdsTabs } from '@kit.UIDesignKit';

/**
 * 沉浸光感玻璃画布：空的 HdsTabs 仅作为浮动材质承载层（对齐 PR 的 ZhihuHdsActionBar 思路），
 * 透过 HDS 组件自身的材质渲染路径呈现真机玻璃效果，规避 uiMaterial.systemMaterial 的
 * 白底遮挡问题。画布不响应点击。
 *
 * 关键：必须给 barFloatingStyle.barWidth 显式传三档断点宽度并设置组件级 barWidth/barHeight，
 * 否则无页签内容的 bar 会塌缩成最小宽度的竖条（真机上表现为“玻璃细棍”）。
 *
 * 用法：GlassCapsule() { 内容组件 }，或单独以 materialCanvas(w, h) 铺底。
 */
@Builder
export function materialCanvas(widthVp: Length, heightVp: Length) {
  HdsTabs({ barPosition: BarPosition.End }) {
  }
    .width(widthVp)
    .height(heightVp)
    .barPosition(BarPosition.End)
    .barWidth(widthVp)
    .barHeight(heightVp)
    .barOverlap(true)
    .clip(false)
    .backgroundColor(Color.Transparent)
    .vertical(false)
    .divider({ mode: DividerMode.NONE })
    .hitTestBehavior(HitTestMode.None)
    .barFloatingStyle({
      barWidth: {
        smallWidth: widthVp,
        mediumWidth: widthVp,
        largeWidth: widthVp
      },
      barBottomMargin: 0,
      barSideMargin: 0,
      lightColor: Color.White,
      systemMaterialEffect: {
        // ADAPTIVE 跟随系统材质策略（自 6.1.0(23) 起可用），由系统按设备能力自选
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      thermoCtrl: true
    })
}

/**
 * 玻璃胶囊容器：内容决定尺寸，玻璃画布随实测宽度贴合（首帧用默认宽度，次帧校正）。
 */
@Component
export struct GlassCapsule {
  @BuilderParam content: () => void = this.emptyContent;
  @Prop useMaterial: boolean = true;
  @State private canvasWidth: number = 320;
  private readonly canvasHeight: number = 64;

  @Builder
  private emptyContent(): void {
  }

  build() {
    if (this.useMaterial) {
      // 画布比内容宽 48vp：HDS 悬浮 bar 相对画布存在内部右侧预留，按内容宽度画会让玻璃
      // 右缘切进内容（真机表现为“包裹不完全”）；多画的部分被 Stack 裁掉。内容测量另加
      // 8vp 呼吸边距，玻璃不紧贴图标。
      Stack({ alignContent: Alignment.Center }) {
        materialCanvas(this.canvasWidth + 48, this.canvasHeight)
        Row() {
          this.content()
        }
        .onAreaChange((_: Area, newValue: Area): void => {
          const width = Number(newValue.width);
          const padded = width + 8;
          if (padded > 1 && Math.abs(padded - this.canvasWidth) > 1) {
            this.canvasWidth = padded;
          }
        })
      }
      .width(this.canvasWidth)
      .borderRadius(24)
      .clip(true)
    } else {
      // 降级：组件模糊（不支持的设备上沉浸材质不可用）
      Row() {
        this.content()
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(24)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    }
  }
}
