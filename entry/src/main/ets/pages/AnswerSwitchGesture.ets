/**
 * 累计回答切换手势的原始拖动量。
 *
 * 横向切换是整页分页手势，不依赖正文的纵向滚动边界；纵向切换仍只允许在正文
 * 顶部/底部继续过滑。反向拖动只回收已经产生的偏移，不会越过零点误触另一方向。
 */
export function accumulateAnswerSwitchDrag(mode: string, rawDrag: number, visualOffset: number,
  delta: number, atTop: boolean, atBottom: boolean, hasPrevious: boolean, hasNext: boolean): number {
  if (delta < 0) {
    if (hasNext && (mode === 'horizontal' || atBottom)) {
      return rawDrag + delta;
    }
    if (visualOffset > 0) {
      return Math.max(0, rawDrag + delta);
    }
  } else if (delta > 0) {
    if (hasPrevious && (mode === 'horizontal' || atTop)) {
      return rawDrag + delta;
    }
    if (visualOffset < 0) {
      return Math.min(0, rawDrag + delta);
    }
  }
  return rawDrag;
}
