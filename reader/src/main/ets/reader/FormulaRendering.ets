const DEFAULT_FORMULA_COLOR = '#111111';
const INLINE_FORMULA_MIN_WIDTH_VP = 4;
const INLINE_FORMULA_MAX_WIDTH_VP = 220;
const DEFAULT_BLOCK_FORMULA_ASPECT_RATIO = 4;

/**
 * 知乎公式 SVG 使用 ex 声明固有尺寸，并以 currentColor 表示公式前景色。
 * ImageKit 解码前将尺寸换成 px，同时把前景色固化为当前主题正文色。
 */
export function normalizeFormulaSvgText(svg: string, foregroundColor: string): string {
  const width = /\bwidth="([0-9.]+)ex"/i.exec(svg);
  const height = /\bheight="([0-9.]+)ex"/i.exec(svg);
  let normalized = svg;
  if (width !== null) {
    const pixels = Math.max(1, Math.ceil(Number(width[1]) * 15));
    normalized = normalized.replace(width[0], `width="${pixels}px"`);
  }
  if (height !== null) {
    const pixels = Math.max(1, Math.ceil(Number(height[1]) * 15));
    normalized = normalized.replace(height[0], `height="${pixels}px"`);
  }
  const color = /^#[0-9A-F]{6}$/i.test(foregroundColor) ? foregroundColor : DEFAULT_FORMULA_COLOR;
  return normalized.replace(/currentColor/g, color);
}

/** 按解码后的真实宽高比计算行内占位，避免用 TeX 源码长度造成大段空白。 */
export function inlineFormulaDisplayWidth(imageWidth: number, imageHeight: number,
  displayHeight: number = 24): number {
  if (!Number.isFinite(imageWidth) || !Number.isFinite(imageHeight) ||
    imageWidth <= 0 || imageHeight <= 0 || displayHeight <= 0) {
    return 20;
  }
  return Math.min(INLINE_FORMULA_MAX_WIDTH_VP,
    Math.max(INLINE_FORMULA_MIN_WIDTH_VP, displayHeight * imageWidth / imageHeight));
}

/** 块级公式按解码后的固有宽高比自适应高度，加载前保持原有 4:1 占位。 */
export function blockFormulaDisplayAspectRatio(imageWidth: number, imageHeight: number): number {
  if (!Number.isFinite(imageWidth) || !Number.isFinite(imageHeight) || imageWidth <= 0 || imageHeight <= 0) {
    return DEFAULT_BLOCK_FORMULA_ASPECT_RATIO;
  }
  return imageWidth / imageHeight;
}
