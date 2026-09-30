import { DividerMode, hdsMaterial, HdsTabs } from '@kit.UIDesignKit';
import { decodeImmersiveMaterialModeText } from 'data';
import {
  decodeImmersiveMaterialSupport,
  resolveImmersiveMaterialLevel
} from '../../common/style/ImmersiveMaterialStyles';
import { hdsMaterialLevelFor } from '../../common/style/HdsMaterialLevels';

/**
 * 沉浸光感玻璃画布组件：空的 HdsTabs 仅作为浮动材质承载层（对齐 PR 的 ZhihuHdsActionBar 思路），
 * 透过 HDS 组件自身的材质渲染路径呈现真机玻璃效果，规避 uiMaterial.systemMaterial 的
 * 白底遮挡问题。画布不响应点击。挡位经 @StorageProp 自行订阅 AppStorage 广播，
 * 材质等级走统一策略解析（ImmersiveMaterialStyles）。
 *
 * 关键：必须给 barFloatingStyle.barWidth 显式传三档断点宽度并设置组件级 barWidth/barHeight，
 * 否则无页签内容的 bar 会塌缩成最小宽度的竖条（真机上表现为“玻璃细棍”）。
 *
 * 用法：GlassCapsule() { 内容组件 }，或单独以 materialCanvas(w, h) 铺底。
 */
@Component
export struct MaterialCanvas {
  @Prop widthVp: number = 0;
  @Prop heightVp: number = 0;
  @StorageProp('immersiveMaterialLevel') private immersiveMaterialLevel: string = 'adaptive';
  @StorageProp('immersiveMaterialSupport') private immersiveMaterialSupport: string = 'unknown';

  build() {
    HdsTabs({ barPosition: BarPosition.End }) {
    }
      .width(this.widthVp)
      .height(this.heightVp)
      .barPosition(BarPosition.End)
      .barWidth(this.widthVp)
      .barHeight(this.heightVp)
      .barOverlap(true)
      .clip(false)
      .backgroundColor(Color.Transparent)
      .vertical(false)
      .divider({ mode: DividerMode.NONE })
      .hitTestBehavior(HitTestMode.None)
      .barFloatingStyle({
        barWidth: {
          smallWidth: this.widthVp,
          mediumWidth: this.widthVp,
          largeWidth: this.widthVp
        },
        barBottomMargin: 0,
        barSideMargin: 0,
        lightColor: Color.White,
        systemMaterialEffect: {
          // materialType 恒为 ADAPTIVE；materialLevel 按用户挡位 + 设备能力统一策略解析。
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterialLevelFor(resolveImmersiveMaterialLevel(
            decodeImmersiveMaterialModeText(this.immersiveMaterialLevel),
            decodeImmersiveMaterialSupport(this.immersiveMaterialSupport)))
        },
        thermoCtrl: true
      })
  }
}

/**
 * 全局 builder 包装：保留既有外部调用形态（GlassCapsule / 各标题栏 / 评论输入胶囊 /
 * AppShell 返回胶囊），内部组件自行订阅挡位；宽高经 @Prop 随调用方实测宽度更新。
 */
@Builder
export function materialCanvas(widthVp: number, heightVp: number) {
  MaterialCanvas({ widthVp: widthVp, heightVp: heightVp })
}

/**
 * 玻璃胶囊容器：内容决定尺寸，玻璃画布随实测宽度贴合（首帧用默认宽度，次帧校正）。
 */
@Component
export struct GlassCapsule {
  @BuilderParam content: () => void = this.emptyContent;
  @Prop useMaterial: boolean = true;
  @State private canvasWidth: number = 240;
  // 酷安式加高胶囊：36vp 上游标准 → 48vp 大胶囊（圆角同步 18 → 24），内容在玻璃内垂直居中
  private readonly canvasHeight: number = 48;

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
          // 对齐酷安观感：内容与胶囊两端留 12vp 呼吸空隙（+24 平摊两侧），
          // 圆弧端部不被内容顶着，胶囊显得更圆润
          const padded = width + 24;
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
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(24)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    }
  }
}
