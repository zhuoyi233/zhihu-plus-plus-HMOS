/**
 * 详情页图片显示尺寸策略（纯计算，无 UI 依赖）。
 *
 * 以图片原始像素按屏幕密度折算出的 vp 尺寸为"原大小"，记 naturalW / naturalH；
 * 屏幕可视区为 screenWidth / screenHeight（同单位）。
 *
 * 占比取图片相对屏幕两个方向占比中的主导维度：
 * 1. 图片宽高比 ≤ 屏幕宽高比（高度为主导维度，如竖图放在横屏上）：
 *    - 占比 ≤ 30%：按原比例放大至 30% 显示；
 *    - 占比在 30% ~ 80% 之间：保持原比例、原大小；
 *    - 占比 ≥ 80%：按原比例缩小至 80% 显示。
 * 2. 图片宽高比 ＞ 屏幕宽高比（宽度为主导维度，如横图放在窄屏上）：
 *    - 占比 ≤ 30%：按原比例放大至 30% 显示；
 *    - 占比在 30% ~ 100% 之间：保持原比例、原大小；
 *    - 占比 ≥ 100%：按原比例缩小至 100% 显示。
 *
 * 数学上"图片宽高比 ≤ 屏幕宽高比"等价于"高度占比 ≥ 宽度占比"，因此两种情形
 * 合并起来即：主导维度占比钳制到 [30%, 80%]（竖向主导）或 [30%, 100%]（横向主导），
 * 非主导维度按源图宽高比跟随缩放。
 */

/** 显示尺寸（vp）。宽高 ≤ 0 表示无有效计算结果，由调用方回退占位样式。 */
export interface ImageDisplaySize {
  width: number;
  height: number;
}

/** 最小显示占比：不足 30% 的小图放大到 30%，避免缩略图过小。 */
export const IMAGE_MIN_DISPLAY_PROPORTION = 0.3;

/** 竖向主导（图片宽高比 ≤ 屏幕宽高比）的最大显示占比。 */
export const IMAGE_MAX_TALL_DISPLAY_PROPORTION = 0.8;

/** 横向主导（图片宽高比 ＞ 屏幕宽高比）的最大显示占比。 */
export const IMAGE_MAX_WIDE_DISPLAY_PROPORTION = 1.0;

/**
 * 按上述策略计算图片显示尺寸。
 * 任意输入非正数时返回 { width: 0, height: 0 }，交由调用方回退占位样式。
 */
export function computeImageDisplaySize(
  naturalWidth: number,
  naturalHeight: number,
  screenWidth: number,
  screenHeight: number
): ImageDisplaySize {
  if (!(naturalWidth > 0) || !(naturalHeight > 0) || !(screenWidth > 0) || !(screenHeight > 0)) {
    return { width: 0, height: 0 };
  }
  const imageRatio = naturalWidth / naturalHeight;
  const screenRatio = screenWidth / screenHeight;
  const tallDominant = imageRatio <= screenRatio;
  const dominantProportion = tallDominant
    ? naturalHeight / screenHeight
    : naturalWidth / screenWidth;
  const maxProportion = tallDominant
    ? IMAGE_MAX_TALL_DISPLAY_PROPORTION
    : IMAGE_MAX_WIDE_DISPLAY_PROPORTION;
  const proportion = Math.min(Math.max(dominantProportion, IMAGE_MIN_DISPLAY_PROPORTION), maxProportion);
  if (tallDominant) {
    const height = proportion * screenHeight;
    return { width: height * imageRatio, height: height };
  }
  const width = proportion * screenWidth;
  return { width: width, height: width / imageRatio };
}
