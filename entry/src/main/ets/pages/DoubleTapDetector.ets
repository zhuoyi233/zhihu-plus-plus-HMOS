/**
 * 基于原始 touch 事件的双击识别器。
 *
 * 为什么不用 TapGesture({ count: 2 })：开启 copyOption（长按选词）的 Text 组件由其内部
 * 触摸处理接管手势识别，组件自身与所有祖先容器上注册的手势在文段上都收不到完整双击
 * 序列（实测模拟器验证，onGestureJudgeBegin 也拦截不到——该逻辑不经过标准手势仲裁），
 * 唯有 onTouch 原始事件可达。因此正文等可选中文本区域的双击统一走本识别器。
 */
export class DoubleTapDetector {
  /** 双击判定窗口：上一次抬起到本次按下，与系统 TapGesture 多击判定口径一致。 */
  private static readonly DOUBLE_TAP_WINDOW_MS: number = 300;
  /** 两次按下的落点容差（vp）：手指双击存在自然抖动，取宽松值避免误判为两次单击。 */
  private static readonly SLOP_VP: number = 50;

  private lastUpTime: number = 0;
  private lastUpX: number = 0;
  private lastUpY: number = 0;
  /** 最近一次可点击子元素（划线片段/链接 Span）的 onClick 时刻：双击的第一击会先触发
   * 这些单击语义（打开划线面板/跳转链接），本序列的双击必须让位（对齐上游"可点区域
   * 不触发双击动作"），否则出现"面板打开又触发点赞"的双触发竞态。 */
  private lastForeignClickTime: number = 0;

  /** 可点击子元素的 onClick 回调里调用：抑制紧接着的双击上报。 */
  markForeignClick(): void {
    this.lastForeignClickTime = Date.now();
  }

  /** 喂入 touch 事件；当本次按下构成双击时返回 true（并复位，连续三击按两次双击触发）。 */
  feed(event: TouchEvent): boolean {
    const touch: TouchObject | undefined = event.touches[0];
    if (touch === undefined) {
      return false;
    }
    if (event.type === TouchType.Up) {
      this.lastUpTime = Date.now();
      this.lastUpX = touch.windowX;
      this.lastUpY = touch.windowY;
      return false;
    }
    if (event.type !== TouchType.Down) {
      return false;
    }
    const now: number = Date.now();
    const isDoubleTap: boolean = now - this.lastUpTime <= DoubleTapDetector.DOUBLE_TAP_WINDOW_MS
      && now - this.lastForeignClickTime > DoubleTapDetector.DOUBLE_TAP_WINDOW_MS
      && Math.abs(touch.windowX - this.lastUpX) <= DoubleTapDetector.SLOP_VP
      && Math.abs(touch.windowY - this.lastUpY) <= DoubleTapDetector.SLOP_VP;
    this.lastUpTime = 0;
    return isDoubleTap;
  }
}

