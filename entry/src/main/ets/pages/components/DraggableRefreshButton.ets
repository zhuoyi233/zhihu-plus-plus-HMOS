import { AppPreferencesStore, DEFAULT_THEME_COLOR, FabPosition, onThemeColor } from 'data';
import { floatingTitleBarOffset } from '../AppPageChrome';
import { getAbilityContext } from '../../entryability/AbilityContextHolder';
import { performConfirmHaptic } from '../../platform/HapticFeedback';

const REFRESH_FAB_SIZE: number = 48;
/** 悬浮底栏（HdsTabs 页签栏）高度；系统底部手势区另经 bottomRectHeight 累加。 */
const REFRESH_FAB_BOTTOM_BAR_HEIGHT: number = 64;

/**
 * 与上游 DraggableRefreshButton 对齐的刷新 FAB：
 * - 默认右缘贴屏、底边位于悬浮底栏上沿；
 * - 拖动范围仅受“不与顶栏/底栏重叠”约束（顶栏下沿至底栏上沿减按钮高度），其余高度自由；
 * - 松手后吸附到左右边缘；旋转等尺寸变化后按原贴边方向重新贴边并持久化；
 * - 位置使用 `<preferenceName>-x/y` 持久化（x 保存贴边后的 0 或当时的 maxX，读取按方向恢复）。
 */
@Component
export struct DraggableRefreshButton {
  preferenceName: string = 'fabRefresh';
  elementId: string = 'draggable_refresh_fab';
  accessibilityLabel: string = '刷新';
  initiallyOnLeft: boolean = false;
  @Prop fabOpacity: number = 100;
  @Prop loading: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  // 系统底部手势区高度（EntryAbility 广播），与页签栏高度相加构成底栏总避让。
  @StorageProp('bottomRectHeight') @Watch('onBottomInsetChange') private bottomRectHeightVp: number = 0;
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
    // 保存的 x 恒为贴边值（0 或当时的 maxX）：0 恢复到左侧，其余按右侧恢复到当前 maxX，
    // 屏幕尺寸变化后不会因按旧屏宽钳制而悬在中间。
    const saved = this.savedPosition;
    this.offsetX = saved === undefined
      ? (this.initiallyOnLeft ? 0 : this.maximumX())
      : (saved.x <= 0 ? 0 : this.maximumX());
    this.offsetY = saved === undefined ? this.maximumY() : this.clamp(saved.y, this.minimumY(), this.maximumY());
    this.positionReady = true;
  }

  private updateOverlaySize(newArea: Area): void {
    const width = Number(newArea.width);
    const height = Number(newArea.height);
    if (width <= 0 || height <= 0) {
      return;
    }
    const changed = Math.abs(width - this.overlayWidth) > 1 || Math.abs(height - this.overlayHeight) > 1;
    if (!this.positionReady) {
      this.overlayWidth = width;
      this.overlayHeight = height;
      this.initializePosition();
      return;
    }
    if (!changed) {
      return;
    }
    // 旋转/窗口尺寸变化：按当前贴边方向（按钮中心在左/右半屏）重新贴到对应边缘，
    // y 钳入新的合法区间并持久化，避免旋转后悬在屏中间或压到顶栏/底栏。
    const wasOnLeft = this.offsetX + REFRESH_FAB_SIZE / 2 <= this.overlayWidth / 2;
    this.overlayWidth = width;
    this.overlayHeight = height;
    this.offsetX = wasOnLeft ? 0 : this.maximumX();
    this.offsetY = this.clamp(this.offsetY, this.minimumY(), this.maximumY());
    this.persistPosition();
  }

  /** 系统手势区高度晚到或变化时，把 y 重新钳入合法区间。 */
  private onBottomInsetChange(): void {
    if (this.positionReady) {
      this.offsetY = this.clamp(this.offsetY, this.minimumY(), this.maximumY());
    }
  }

  private onPanUpdate(event: GestureEvent): void {
    const deltaX = event.offsetX - this.previousPanX;
    const deltaY = event.offsetY - this.previousPanY;
    this.previousPanX = event.offsetX;
    this.previousPanY = event.offsetY;
    this.offsetX = this.clamp(this.offsetX + deltaX, 0, this.maximumX());
    this.offsetY = this.clamp(this.offsetY + deltaY, this.minimumY(), this.maximumY());
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
    this.persistPosition();
  }

  private persistPosition(): void {
    const position: FabPosition = { x: this.offsetX, y: this.offsetY };
    void this.preferences?.saveFabPosition(this.preferenceName, position).catch((_error: Object): void => {});
  }

  private maximumX(): number {
    return Math.max(0, this.overlayWidth - REFRESH_FAB_SIZE);
  }

  /** 顶栏下沿（状态栏 + 顶栏 56vp）：按钮顶边不得进入悬浮标题栏区域。 */
  private minimumY(): number {
    return floatingTitleBarOffset();
  }

  /** 底栏上沿（页签栏 64 + 系统手势区）再让出按钮高度；仅约束不与底栏重叠，其余高度自由。 */
  private maximumY(): number {
    const bottomBar = REFRESH_FAB_BOTTOM_BAR_HEIGHT + Math.max(0, this.bottomRectHeightVp);
    return Math.max(this.minimumY(), this.overlayHeight - bottomBar - REFRESH_FAB_SIZE);
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
        .position({ x: this.offsetX, y: this.offsetY })
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
