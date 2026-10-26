/**
 * 基于原始 touch 事件的双击识别器。
 *
 * 为什么不用 TapGesture({ count: 2 })：开启 copyOption（长按选词）的 Text 组件由其内部
 * 触摸处理接管手势识别，组件自身与所有祖先容器上注册的手势在文段上都收不到完整双击
 * 序列（实测模拟器验证，onGestureJudgeBegin 也拦截不到——该逻辑不经过标准手势仲裁），
 * 唯有 onTouch 原始事件可达。因此正文等可选中文本区域的双击统一走本识别器。
 *
 * 因为绕开了手势系统，识别器必须自己区分「轻点」和「滑动」：只记抬手时间/坐标会把
 * 「滑动抬手 → 下一次滑动按下」误判成双击（连续下滑正文时几乎必触发）。这里的口径：
 * 每个手势按下后记录起点与时刻，位移超容差或按住超时即判为拖动，只有两击都是轻点
 * 才算双击；列表滚动期间（拖动或惯性）直接不判定。
 */
export class DoubleTapDetector {
  /** 双击判定窗口：上一次轻点抬起到本次按下。 */
  private static readonly DOUBLE_TAP_WINDOW_MS: number = 300;
  /** 两次轻点落点容差（vp）：双击时手指几乎不动，取小值避免把两次独立点击当双击。 */
  private static readonly DOUBLE_TAP_SLOP_VP: number = 30;
  /** 单次轻点的最长按住时长（ms）：超过即视为长按（选词等），不参与双击。 */
  private static readonly TAP_MAX_DURATION_MS: number = 250;
  /** 单次轻点的最大位移（vp）：滑动/拖动必然超出此值。 */
  private static readonly TAP_SLOP_VP: number = 12;
  /** 滚动静默窗口（ms）：最近一次位移发生后这段时间内不判定双击（含惯性滚动）。 */
  private static readonly SCROLL_QUIET_MS: number = 200;

  private lastUpTime: number = 0;
  private lastUpX: number = 0;
  private lastUpY: number = 0;
  /** 上一次抬起是否构成一次轻点（双击的第一击必须是轻点）。 */
  private lastUpWasTap: boolean = false;
  private downTime: number = 0;
  private downX: number = 0;
  private downY: number = 0;
  /** 当前手势是否已判为拖动（位移超容差或收到 Cancel）。 */
  private gestureIsDrag: boolean = true;
  /** 最近一次滚动位移时刻：用时间戳而非开关，程序化滚动没有配对的停止事件也不会卡死判定。 */
  private lastScrollTime: number = 0;
  /** 最近一次可点击子元素（划线片段/链接 Span）的 onClick 时刻：双击的第一击会先触发
   * 这些单击语义（打开划线面板/跳转链接），本序列的双击必须让位（对齐上游"可点区域
   * 不触发双击动作"），否则出现"面板打开又触发点赞"的双触发竞态。 */
  private lastForeignClickTime: number = 0;

  /** 可点击子元素的 onClick 回调里调用：抑制紧接着的双击上报。 */
  markForeignClick(): void {
    this.lastForeignClickTime = Date.now();
  }

  /** 列表发生滚动位移时调用：刷新滚动静默时刻并作废待定的第一击。 */
  markScrollActive(): void {
    this.lastScrollTime = Date.now();
    this.resetPendingTap();
  }

  /** 距最近一次滚动位移是否已超过静默窗口（窗口内不判定轻点/双击）。 */
  private scrollQuiet(now: number): boolean {
    return now - this.lastScrollTime > DoubleTapDetector.SCROLL_QUIET_MS;
  }

  /** 喂入 touch 事件；当本次按下构成双击时返回 true（并复位，连续三击按两次双击触发）。 */
  feed(event: TouchEvent): boolean {
    const touch: TouchObject | undefined = event.touches[0];
    if (touch === undefined) {
      return false;
    }
    if (event.type === TouchType.Down) {
      const now: number = Date.now();
      const isDoubleTap: boolean = this.scrollQuiet(now) && this.lastUpWasTap
        && now - this.lastUpTime <= DoubleTapDetector.DOUBLE_TAP_WINDOW_MS
        && now - this.lastForeignClickTime > DoubleTapDetector.DOUBLE_TAP_WINDOW_MS
        && Math.abs(touch.windowX - this.lastUpX) <= DoubleTapDetector.DOUBLE_TAP_SLOP_VP
        && Math.abs(touch.windowY - this.lastUpY) <= DoubleTapDetector.DOUBLE_TAP_SLOP_VP;
      this.downTime = now;
      this.downX = touch.windowX;
      this.downY = touch.windowY;
      this.gestureIsDrag = false;
      this.resetPendingTap();
      return isDoubleTap;
    }
    if (event.type === TouchType.Move) {
      if (!this.gestureIsDrag &&
        (Math.abs(touch.windowX - this.downX) > DoubleTapDetector.TAP_SLOP_VP ||
          Math.abs(touch.windowY - this.downY) > DoubleTapDetector.TAP_SLOP_VP)) {
        this.gestureIsDrag = true;
      }
      return false;
    }
    if (event.type === TouchType.Up) {
      const now: number = Date.now();
      const isTap: boolean = this.scrollQuiet(now) && !this.gestureIsDrag &&
        now - this.downTime <= DoubleTapDetector.TAP_MAX_DURATION_MS;
      this.lastUpWasTap = isTap;
      this.lastUpTime = isTap ? now : 0;
      this.lastUpX = touch.windowX;
      this.lastUpY = touch.windowY;
      this.gestureIsDrag = true;
      return false;
    }
    if (event.type === TouchType.Cancel) {
      this.gestureIsDrag = true;
      this.resetPendingTap();
    }
    return false;
  }

  private resetPendingTap(): void {
    this.lastUpWasTap = false;
    this.lastUpTime = 0;
  }
}
