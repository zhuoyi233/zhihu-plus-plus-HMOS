/**
 * 设置分组卡片的搜索定位提醒容器：包住既有分组 Column，
 * 搜索定位滚动落定后对目标分组播放“亮起—恢复—亮起—恢复”两个完整周期。
 *
 * 提醒层只改变主题色淡背景/描边强度（opacity 0→1→0），不改卡片尺寸、边距、
 * 文本透明度或控件值；overlay 关闭命中测试，不阻断控件交互。
 * 动画经有限阶段链驱动，每个阶段前校验高亮信号仍指向当前请求，
 * 新请求/取消都会立即复位，不使用无限循环动画。
 */
import { DEFAULT_THEME_COLOR, FeedCardStyle } from 'data';
import { settingsGroupRadius } from '../pages/AccountSettingsLayout';
import { highlightPlan, readComponentRectVp, withAlpha } from '../pages/SettingsSearchLocationState';
import {
  readHighlightSignal,
  readLocationRequest,
  SettingsSearchLocationKeys
} from '../pages/SettingsSearchTarget';

@Component
export struct SettingsHighlightGroup {
  @BuilderParam content: () => void = this.emptyGroup;
  /** 分组标识：与定位请求的 highlightGroupId 匹配才播放。 */
  groupId: string = '';
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp(SettingsSearchLocationKeys.HIGHLIGHT_TICK) @Watch('onHighlightTick')
  private highlightTick: number = 0;
  @State private level: number = 0;
  /** 分组实测尺寸（vp）：overlay 用数值绘制，百分比尺寸在 overlay 语境会取页面约束。 */
  @State private groupWidth: number = 0;
  @State private groupHeight: number = 0;
  /** 行级高亮：目标行相对分组顶部的偏移与高度；rowTop < 0 表示回退整组。 */
  @State private rowTop: number = -1;
  @State private rowHeight: number = 0;
  private activeRequestId: number = -1;
  private timerId: number = -1;

  @Builder
  private emptyGroup() {
  }

  aboutToDisappear(): void {
    this.clearTimer();
    this.activeRequestId = -1;
    this.level = 0;
  }

  private onHighlightTick(): void {
    const signal = readHighlightSignal();
    if (signal === undefined) {
      return;
    }
    // 更新的请求已发布：立即复位正在进行的旧动画（连点 A→B 只完成最新 B）。
    if (this.activeRequestId >= 0 && signal.requestId !== this.activeRequestId) {
      this.stopBlinking();
    }
    if (signal.cancelled || signal.highlightGroupId !== this.groupId) {
      return;
    }
    this.stopBlinking();
    this.measureRowRect(signal.requestId);
    this.activeRequestId = signal.requestId;
    this.runBlinkSteps(0);
  }

  private stackId(): string {
    return `hl_group_${this.groupId}`;
  }

  /**
   * 测量目标行在分组内的位置：读取当前请求的锚点（条件隐藏时用回退锚点），
   * 以“锚点控件垂直范围上下各扩 14vp”作为行高亮矩形——锚点控件（开关/滑杆）
   * 垂直居中于所在行，扩展后与整行基本对齐。测量失败回退整组。
   */
  private measureRowRect(requestId: number): void {
    const request = readLocationRequest();
    if (request === undefined || request.requestId !== requestId) {
      return;
    }
    try {
      const utils = this.getUIContext().getComponentUtils();
      const groupRect = readComponentRectVp(utils, this.stackId());
      const anchor = readComponentRectVp(utils, request.anchorId) ??
        readComponentRectVp(utils, request.fallbackAnchorId);
      if (groupRect === undefined || anchor === undefined) {
        this.rowTop = -1;
        return;
      }
      const rawTop: number = anchor.windowY - groupRect.windowY - 14;
      const rawHeight: number = anchor.height + 28;
      // 钳制到分组范围，避免超高行或越界行画出分组。
      const top: number = Math.min(Math.max(0, rawTop), Math.max(0, this.groupHeight - 8));
      const bottom: number = Math.min(this.groupHeight, rawTop + rawHeight);
      this.rowTop = top;
      this.rowHeight = Math.max(8, bottom - top);
    } catch (_error) {
      this.rowTop = -1;
    }
  }

  private stopBlinking(): void {
    this.clearTimer();
    this.activeRequestId = -1;
    this.level = 0;
  }

  private runBlinkSteps(stepIndex: number): void {
    const plan = highlightPlan();
    if (stepIndex >= plan.length) {
      this.stopBlinking();
      return;
    }
    const step = plan[stepIndex];
    const currentRequestId: number = this.activeRequestId;
    // 阶段前校验：请求已被替换/取消时立即复位，不继续后续周期。
    if (currentRequestId < 0) {
      this.stopBlinking();
      return;
    }
    const signal = readHighlightSignal();
    if (signal !== undefined && signal.cancelled && signal.requestId === currentRequestId) {
      this.stopBlinking();
      return;
    }
    this.getUIContext().animateTo({
      duration: step.durationMs,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (this.activeRequestId !== currentRequestId) {
          return;
        }
        if (step.gapAfterMs > 0) {
          this.clearTimer();
          this.timerId = setTimeout((): void => {
            this.timerId = -1;
            this.runBlinkSteps(stepIndex + 1);
          }, step.gapAfterMs);
        } else {
          this.runBlinkSteps(stepIndex + 1);
        }
      }
    }, (): void => {
      this.level = step.level;
    });
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private strokeColor(): ResourceColor {
    return withAlpha(this.resolvedThemeColor, 'CC');
  }

  private fillColor(): ResourceColor {
    return withAlpha(this.resolvedThemeColor, '26');
  }

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  @Builder
  private highlightLayer() {
    // 以 .overlay() 挂在 Stack 上，不参与布局。尺寸必须用 onAreaChange 实测的
    // 数值 vp：height('100%') 在 Stack 子项语境会把分组撑高约一屏（布局被撑大），
    // 在 overlay 语境则会画到约一屏高（高亮层越界覆盖下方分组）。
    // 行级优先：测量到请求锚点行时只亮那一小行，测量失败回退整组。
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.rowTop >= 0) {
        Column()
          .width(this.groupWidth)
          .height(this.rowHeight)
          .position({ x: 0, y: this.rowTop })
          .borderRadius(8)
          .border({ width: 2, color: this.strokeColor() })
          .backgroundColor(this.fillColor())
      } else {
        Column()
          .width(this.groupWidth)
          .height(this.groupHeight)
          .borderRadius(settingsGroupRadius(this.feedCardStyle))
          .border({
            width: this.isCardStyle() ? 2 : 0,
            color: this.strokeColor()
          })
          .backgroundColor(this.fillColor())
      }
    }
    .width(this.groupWidth)
    .height(this.groupHeight)
    .hitTestBehavior(HitTestMode.None)
    .opacity(this.level)
  }

  private onGroupAreaChange(_oldArea: Area, newArea: Area): void {
    const width: number = Number(newArea.width);
    const height: number = Number(newArea.height);
    if (Number.isFinite(width) && width > 0) {
      this.groupWidth = width;
    }
    if (Number.isFinite(height) && height > 0) {
      this.groupHeight = height;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.content()
      }
      .width('100%')
    }
    .width('100%')
    .id(this.stackId())
    .onAreaChange((oldArea: Area, newArea: Area): void => this.onGroupAreaChange(oldArea, newArea))
    .overlay(this.highlightLayer(), { align: Alignment.TopStart })
  }
}
