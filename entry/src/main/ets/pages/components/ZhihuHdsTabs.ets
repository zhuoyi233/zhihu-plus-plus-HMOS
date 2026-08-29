import { DividerMode, hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';

@Component
export struct ZhihuHdsTabs {
  @Link currentIndex: number;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  controller: HdsTabsController = new HdsTabsController();
  @BuilderParam content: () => void;

  build() {
    HdsTabs({
      barPosition: BarPosition.End,
      index: this.currentIndex,
      controller: this.controller
    }) {
      this.content();
    }
    .id('p1_hds_tabs')
    .barMode(BarMode.Fixed)
    .barOverlap(true)
    .animationDuration(250)
    .scrollable(false)
    .width('100%')
    .height('100%')
    .clip(false)
    .divider({ mode: DividerMode.NONE })
    .onChange((index: number): void => {
      if (index >= 0 && index <= 4) {
        this.currentIndex = index;
      }
    })
    .barFloatingStyle({
      barSideMargin: 16,
      barBottomMargin: this.bottomRectHeight,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      gradientMask: {
        maskColor: $r('app.color.page_background'),
        maskHeight: 42
      },
      lightColor: $r('app.color.brand_primary'),
      adaptToHandedness: false,
      thermoCtrl: true
    });
  }
}

/**
 * 详情页底部操作区的 HDS 玻璃容器。
 * HdsTabs 在这里仅作为浮动材质承载层，操作内容保持在其上方，
 * 与 LiJiWatermark 的 HdsGlassCard 叠层方式一致。
 */
@Component
export struct ZhihuHdsActionBar {
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @BuilderParam content: () => void = this.emptyContent;
  @Prop barHeight: number = 76;
  @State private measuredWidth: number = 0;

  @Builder
  private emptyContent(): void {
  }

  private horizontalInset(): number {
    return 16;
  }

  private materialWidth(): number {
    return this.measuredWidth > this.horizontalInset() * 2
      ? this.measuredWidth - this.horizontalInset() * 2
      : 300;
  }

  private containerHeight(): number {
    return this.barHeight + this.bottomRectHeight + 8;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Center }) {
        HdsTabs({ barPosition: BarPosition.End }) {
        }
        .width(this.materialWidth())
        .height(this.barHeight)
        .barWidth(this.materialWidth())
        .barHeight(this.barHeight)
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .clip(false)
        .backgroundColor(Color.Transparent)
        .shadow(undefined)
        .vertical(false)
        .monopolizeEvents(false)
        .divider({ mode: DividerMode.NONE })
        .hitTestBehavior(HitTestMode.None)
        .barFloatingStyle({
          barWidth: {
            smallWidth: this.materialWidth(),
            mediumWidth: this.materialWidth(),
            largeWidth: this.materialWidth()
          },
          gradientMask: {
            maskColor: Color.Transparent
          },
          barBottomMargin: 0,
          barSideMargin: 0,
          lightColor: Color.White,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          thermoCtrl: true
        })

        Column() {
          this.content();
        }
        .width(this.materialWidth())
        .height(this.barHeight)
        .borderRadius(this.barHeight / 2)
        .clip(true)
      }
      .width(this.materialWidth())
      .height(this.barHeight)
      .borderRadius(this.barHeight / 2)
      .clip(true)
      .margin({ bottom: this.bottomRectHeight + 8 })
    }
    .width('100%')
    .height(this.containerHeight())
    .onAreaChange((_: Area, newValue: Area): void => {
      const width: number = new Number(newValue.width).valueOf();
      if (width > 0 && Math.abs(width - this.measuredWidth) > 1) {
        this.measuredWidth = width;
      }
    })
  }
}
