import { AppPreferencesStore, DEFAULT_THEME_COLOR, FabPosition, onThemeColor } from 'data';
import { getAbilityContext } from '../../entryability/AbilityContextHolder';
import { performConfirmHaptic } from '../../platform/HapticFeedback';

const REFRESH_FAB_SIZE: number = 48;
const REFRESH_FAB_BOTTOM_BASELINE: number = 250;

/**
 * 与上游 DraggableRefreshButton 对齐的刷新 FAB：
 * - 默认右缘贴屏，顶边位于可视域底部上方 250vp；
 * - 可在可视域内自由拖动，松手后吸附到左右边缘；
 * - 位置使用 `<preferenceName>-x/y` 持久化。
 */
@Component
export struct DraggableRefreshButton {
  preferenceName: string = 'fabRefresh';
  elementId: string = 'draggable_refresh_fab';
  accessibilityLabel: string = '刷新';
  initiallyOnLeft: boolean = false;
  bottomAvoidance: number = 0;
  @Prop fabOpacity: number = 100;
  @Prop loading: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  onRefresh: () => void = (): void => {};

  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private positionReady: boolean = false;
  private overlayWidth: number = 0;
  private overlayHeight: number = 0;
  private previousPanX: number = 0;
  private previousPanY: number = 0;
  private dragging: boolean = false;
  private positionLoaded: boolean = false;
  private savedPosition?: FabPosition = undefined;
  private preferences?: AppPreferencesStore = undefined;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.positionLoaded = true;
      this.initializePosition();
      return;
    }
    this.preferences = new AppPreferencesStore(context);
    void this.loadPosition();
  }

  private async loadPosition(): Promise<void> {
    try {
      this.savedPosition = await this.preferences?.loadFabPosition(this.preferenceName);
    } catch (_error) {
      this.savedPosition = undefined;
    }
    this.positionLoaded = true;
    this.initializePosition();
  }

  private initializePosition(): void {
    if (!this.positionLoaded || this.overlayWidth <= 0 || this.overlayHeight <= 0) {
      return;
    }
    const maxX = this.maximumX();
    const maxY = this.maximumStoredY();
    const saved = this.savedPosition;
    this.offsetX = saved === undefined ? (this.initiallyOnLeft ? 0 : maxX) : this.clamp(saved.x, 0, maxX);
    this.offsetY = saved === undefined ? maxY : this.clamp(saved.y, 0, maxY);
    this.positionReady = true;
  }

  private updateOverlaySize(newArea: Area): void {
    const width = Number(newArea.width);
    const height = Number(newArea.height);
    if (width <= 0 || height <= 0) {
      return;
    }
    const changed = Math.abs(width - this.overlayWidth) > 1 || Math.abs(height - this.overlayHeight) > 1;
    this.overlayWidth = width;
    this.overlayHeight = height;
    if (!this.positionReady) {
      this.initializePosition();
    } else if (changed) {
      this.offsetX = this.clamp(this.offsetX, 0, this.maximumX());
      this.offsetY = this.clamp(this.offsetY, 0, this.maximumStoredY());
    }
  }

  private onPanUpdate(event: GestureEvent): void {
    const deltaX = event.offsetX - this.previousPanX;
    const deltaY = event.offsetY - this.previousPanY;
    this.previousPanX = event.offsetX;
    this.previousPanY = event.offsetY;
    this.offsetX = this.clamp(this.offsetX + deltaX, 0, this.maximumX());
    this.offsetY = this.clamp(this.offsetY + deltaY, 0, this.maximumStoredY());
  }

  private finishDragging(): void {
    if (!this.dragging) {
      return;
    }
    this.dragging = false;
    this.previousPanX = 0;
    this.previousPanY = 0;
    const targetX = this.offsetX < this.overlayWidth / 2 ? 0 : this.maximumX();
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
      this.offsetX = targetX;
    });
    const position: FabPosition = { x: targetX, y: this.offsetY };
    void this.preferences?.saveFabPosition(this.preferenceName, position).catch((_error: Object): void => {});
  }

  private maximumX(): number {
    return Math.max(0, this.overlayWidth - REFRESH_FAB_SIZE);
  }

  private maximumStoredY(): number {
    return Math.max(0, this.overlayHeight - REFRESH_FAB_BOTTOM_BASELINE);
  }

  private visibleY(): number {
    return Math.min(this.offsetY, Math.max(0, this.maximumStoredY() - Math.max(0, this.bottomAvoidance)));
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.min(maximum, Math.max(minimum, value));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.positionReady) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          if (this.loading) {
            LoadingProgress()
              .width(26)
              .height(26)
              .color(onThemeColor(this.resolvedThemeColor))
          } else {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20)
              .fontColor([onThemeColor(this.resolvedThemeColor)])
          }
        }
        .id(this.elementId)
        .width(REFRESH_FAB_SIZE)
        .height(REFRESH_FAB_SIZE)
        .padding(0)
        .position({ x: this.offsetX, y: this.visibleY() })
        .backgroundColor(this.resolvedThemeColor)
        .opacity(this.clamp(this.fabOpacity, 10, 100) / 100)
        .accessibilityText(this.accessibilityLabel)
        .gesture(
          PanGesture({ fingers: 1 })
            .onActionStart((event: GestureEvent): void => {
              this.previousPanX = event.offsetX;
              this.previousPanY = event.offsetY;
              this.dragging = true;
              performConfirmHaptic();
            })
            .onActionUpdate((event: GestureEvent): void => this.onPanUpdate(event))
            .onActionEnd((): void => this.finishDragging())
            .onActionCancel((): void => this.finishDragging())
        )
        .onClick((): void => this.onRefresh())
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((_oldArea: Area, newArea: Area): void => this.updateOverlaySize(newArea))
  }
}
