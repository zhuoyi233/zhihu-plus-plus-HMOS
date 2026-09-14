/**
 * 阅读进度条的几何换算（纯函数，单位统一 vp），逐条对齐上游
 * `shared/src/commonMain/kotlin/.../ui/components/VerticalReadingProgressBar.kt`：
 *
 * - 上游 `viewportHeightPx` 取的是 `BoxWithConstraints` 的 `maxHeight`。上游调用点写的是
 *   `modifier.padding(top, bottom, end).width(12.dp).fillMaxHeight()`，`padding` 在
 *   `fillMaxHeight` 之前，因此 `maxHeight` = **可用高 − 上下留白**，即"轨道高度"，
 *   而不是正文列表的视口高。此处对应 `scrollbarTrackHeightVp`。
 * - 上游 `contentHeightPx = viewportHeightPx + maxScrollPx`，`maxScrollPx` 才是真实
 *   可滚动量（本侧 = 内容总高 − 正文视口高）。
 *
 * 抽成独立纯函数模块的原因：拇指高度与拇指行程若用了不同的"视口"（例如高度按列表视口、
 * 行程按轨道），拇指行程会比轨道长 `上留白 + 下留白`，滑到底时拇指冲出轨道并贴到屏幕
 * 物理底边（2026-09-14 实机复现），故把两者锁在同一函数族里并用单测固定。
 */

/** 拇指高度下限（vp，对齐上游 `minThumbHeight = 24.dp`）。 */
export const MIN_THUMB_HEIGHT_VP = 24;

/** 低于该可滚动量视为无滚动，避免亚像素抖动把进度条闪出来。 */
export const MIN_SCROLLABLE_VP = 1;

/**
 * 轨道高度（vp）= 进度条盒的可用高 − 上下留白，
 * 即上游 `BoxWithConstraints` 的 `maxHeight`（padding 先于 fillMaxHeight 生效）。
 * 轨道条与拇指都在这个高度内活动。
 */
export function scrollbarTrackHeightVp(
  availableHeightVp: number,
  topInsetVp: number,
  bottomInsetVp: number
): number {
  return Math.max(0, availableHeightVp - Math.max(0, topInsetVp) - Math.max(0, bottomInsetVp));
}

/**
 * 拇指高度（vp）对齐上游 `calculateScrollbarThumbHeightPx`：
 * `轨道高 × (轨道高 / (轨道高 + 可滚动量))`，clamp 到 `[24, 轨道高]`。
 * 轨道高或用例参数非法（可滚动量 < 0、轨道高 ≤ 0）时返回 0，表示不渲染。
 */
export function scrollbarThumbHeightVp(
  trackHeightVp: number,
  maxScrollVp: number,
  minThumbHeightVp: number = MIN_THUMB_HEIGHT_VP
): number {
  if (!(trackHeightVp > 0) || maxScrollVp < 0) {
    return 0;
  }
  const contentHeightVp = trackHeightVp + maxScrollVp;
  if (!(contentHeightVp > 0)) {
    return 0;
  }
  const raw = trackHeightVp * (trackHeightVp / contentHeightVp);
  // 上游用 `coerceIn(minThumbHeight, viewportHeight)`，两者反序时会抛异常；
  // 这里取等价语义但不抛（轨道比下限还短时按轨道高收口）。
  return Math.min(trackHeightVp, Math.max(minThumbHeightVp, raw));
}

/**
 * 拇指可移动行程（vp，对齐上游 `trackRangePx`）：`轨道高 − 拇指高`。
 * 这是拇指偏移的分母，保证 100% 时拇指底边正好落在轨道底边（不会越出轨道）。
 */
export function scrollbarThumbTravelVp(trackHeightVp: number, thumbHeightVp: number): number {
  return Math.max(0, trackHeightVp - thumbHeightVp);
}

/** 拇指位移（vp，对齐上游 `calculateScrollbarThumbOffsetPx`）：行程 × 进度（clamp 0..1）。 */
export function scrollbarThumbOffsetVp(
  progress: number,
  trackHeightVp: number,
  thumbHeightVp: number
): number {
  const travel = scrollbarThumbTravelVp(trackHeightVp, thumbHeightVp);
  const bounded = Math.min(1, Math.max(0, progress));
  return Math.min(travel, Math.max(0, travel * bounded));
}

/**
 * 阅读进度（对齐上游 `calculateReadingProgress`）：`滚动量 / 可滚动量`，clamp 0..1；
 * 无可滚动量时返回 0。
 */
export function readingProgress(scrollYVp: number, maxScrollVp: number): number {
  if (!(maxScrollVp > 0)) {
    return 0;
  }
  return Math.min(1, Math.max(0, scrollYVp / maxScrollVp));
}
