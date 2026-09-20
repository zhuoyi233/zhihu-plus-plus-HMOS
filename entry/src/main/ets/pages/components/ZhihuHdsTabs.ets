import { DividerMode, hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { DEFAULT_THEME_COLOR } from 'data';

@Component
export struct ZhihuHdsTabs {
  @Link currentIndex: number;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('autoHideBottomBar') private autoHideBottomBar: boolean = false;
  @StorageProp('bottomBarHiddenByScroll') private bottomBarHiddenByScroll: boolean = false;
  controller: HdsTabsController = new HdsTabsController();
  @BuilderParam content: () => void;
  /** 双击页签回调（350ms 内同页签连点两次），供宿主实现双击刷新。 */
  onTabDoubleTap: (index: number) => void = (_index: number): void => {
  };
  /** 单击当前页签时回到顶部/刷新。 */
  onCurrentTabTap: (index: number) => void = (_index: number): void => {
  };
  private lastTapIndex: number = -1;
  private lastTapTime: number = 0;

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
    .barHeight(this.autoHideBottomBar && this.bottomBarHiddenByScroll ? 0 : 64)
    .barOverlap(true)
    .animationDuration(250)
    .scrollable(true)
    .width('100%')
    .height('100%')
    .clip(false)
    .divider({ mode: DividerMode.NONE })
    .onChange((index: number): void => {
      if (index >= 0 && index <= 4) {
        AppStorage.setOrCreate('bottomBarHiddenByScroll', false);
        this.currentIndex = index;
      }
    })
    .onTabBarClick((index: number): void => {
      const now = Date.now();
      if (this.lastTapIndex === index && now - this.lastTapTime <= 350) {
        this.lastTapIndex = -1;
        this.lastTapTime = 0;
        this.onTabDoubleTap(index);
        return;
      }
      if (index === this.currentIndex) {
        this.onCurrentTabTap(index);
      }
      this.lastTapIndex = index;
      this.lastTapTime = now;
    })
    .barFloatingStyle({
      barSideMargin: 16,
      barBottomMargin: this.bottomRectHeight,
      systemMaterialEffect: {
        // ADAPTIVE 跟随系统材质策略（自 6.1.0(23) 起可用）：系统按设备能力自选材质类型与档位，
        // 支持材质的设备自动选用沉浸材质，未来新增材质类型无需应用侧跟进
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      gradientMask: {
        maskColor: $r('app.color.page_background'),
        maskHeight: 42
      },
      lightColor: this.resolvedThemeColor,
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
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
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
