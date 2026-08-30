import { DividerMode, hdsMaterial, HdsTabs } from '@kit.UIDesignKit';

/**
 * 沉浸光感玻璃画布：空的 HdsTabs 仅作为浮动材质承载层（对齐 PR 的 ZhihuHdsActionBar 思路），
 * 透过 HDS 组件自身的材质渲染路径呈现真机玻璃效果，规避 uiMaterial.systemMaterial 的
 * 白底遮挡问题。画布不响应点击。
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
    .barOverlap(true)
    .clip(false)
    .backgroundColor(Color.Transparent)
    .vertical(false)
    .divider({ mode: DividerMode.NONE })
    .hitTestBehavior(HitTestMode.None)
    .barFloatingStyle({
      barBottomMargin: 0,
      barSideMargin: 0,
      lightColor: Color.White,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
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
  @State private canvasWidth: number = 240;
  private readonly canvasHeight: number = 64;

  @Builder
  private emptyContent(): void {
  }

  build() {
    if (this.useMaterial) {
      Stack({ alignContent: Alignment.Center }) {
        materialCanvas(this.canvasWidth, this.canvasHeight)
        Row() {
          this.content()
        }
        .onAreaChange((_: Area, newValue: Area): void => {
          const width = Number(newValue.width);
          if (width > 1 && Math.abs(width - this.canvasWidth) > 1) {
            this.canvasWidth = width;
          }
        })
      }
      .borderRadius(24)
      .clip(true)
    } else {
      // 降级：组件模糊（不支持的设备上沉浸材质不可用）
      Row() {
        this.content()
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .borderRadius(24)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    }
  }
}
