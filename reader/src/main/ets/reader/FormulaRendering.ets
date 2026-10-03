const DEFAULT_FORMULA_COLOR = '#111111';
const DEFAULT_BLOCK_FORMULA_ASPECT_RATIO = 4;
/**
 * 兜底解码采样精度（px/ex）：未指定目标采样密度时按此值把 ex 尺寸换成 px。
 * 知乎公式 SVG 根节点自带 `style="font-size: 15px"`，15px/ex 是其原生锚点。
 * 正常路径由调用方按"显示字号 × 0.5em/ex × 屏幕密度"传入目标密度，见
 * formulaDecodePixelsPerEx。
 */
export const FORMULA_FALLBACK_PIXELS_PER_EX = 15;
/** 公式以约 0.5em/ex 换算显示字号（对齐浏览器渲染独立 SVG 图片时对 ex 的解析）。 */
export const FORMULA_EM_PER_EX = 0.5;
/** 解码采样密度下限（px/ex）：超宽公式按容器宽换算会低于此值，保底可辨认的笔画精度。 */
export const FORMULA_MIN_DECODE_PIXELS_PER_EX = 4;
/** 解码采样密度上限（px/ex）：防止极小公式在大密度屏上解码出离谱大栅格。 */
export const FORMULA_MAX_DECODE_PIXELS_PER_EX = 96;
/** 公式栅格单边上限（px）：ImageKit 解码与内存开销的硬约束，超出前按比例降采样密度。 */
export const FORMULA_MAX_RASTER_DIMENSION_PX = 4096;

export interface FormulaDisplaySize {
  width: number;
  height: number;
}

/**
 * 按公式 SVG 的 ex 固有尺寸与正文字号计算显示尺寸（vp）：
 * 高度 = ex 高 × 字号 × 0.5em/ex；宽度超过容器时等比缩小。
 * 积分上下限、多行公式的高度天然包含在 ex 尺寸里，无需特判。
 */
export function formulaDisplaySize(widthEx: number, heightEx: number,
  fontSize: number = 18, availableWidth: number = 320): FormulaDisplaySize {
  if (!Number.isFinite(widthEx) || !Number.isFinite(heightEx) ||
    widthEx <= 0 || heightEx <= 0) {
    return { width: 20, height: 20 };
  }
  const size = Number.isFinite(fontSize) && fontSize > 0 ? fontSize : 18;
  const limit = Number.isFinite(availableWidth) && availableWidth > 0 ? availableWidth : 320;
  const naturalWidth = widthEx * size * FORMULA_EM_PER_EX;
  const scale = Math.min(1, limit / naturalWidth);
  return { width: naturalWidth * scale, height: heightEx * size * FORMULA_EM_PER_EX * scale };
}

/** 从公式 SVG 根节点解析 ex 固有尺寸；缺 width/height 声明时返回 undefined。 */
export function formulaSvgExSize(svg: string): FormulaDisplaySize | undefined {
  const width = /\bwidth="([0-9.]+)ex"/i.exec(svg);
  const height = /\bheight="([0-9.]+)ex"/i.exec(svg);
  if (width === null || height === null) {
    return undefined;
  }
  const widthEx = Number(width[1]);
  const heightEx = Number(height[1]);
  if (!Number.isFinite(widthEx) || !Number.isFinite(heightEx) || widthEx <= 0 || heightEx <= 0) {
    return undefined;
  }
  return { width: widthEx, height: heightEx };
}

/**
 * 识别知乎公式服务的 MathJax 错误 SVG：LaTeX 无法解析时端点仍返回 200，但内容是
 * 红底红字（rgb(247, 86, 89)）的错误提示框（如 "Misplaced &"）加浅红边线。
 * 正常公式只用 currentColor + path/use，不会出现该签名色；命中即视为公式渲染失败，
 * 由组件退回 TeX 替代文本，避免展示一个突兀的红色错误框。
 */
export function isMathJaxErrorSvg(svg: string): boolean {
  return svg.includes('247, 86, 89');
}

/**
 * 计算解码采样密度（px/ex）：目标为"显示字号 × 0.5em/ex × 屏幕密度"（栅格与显示
 * 物理像素 1:1，规避上采样模糊）；再钳制到 [4, 96]，且保证栅格单边不超上限——
 * 超长公式（如 400ex 宽）按目标密度解码会超出 ImageKit 尺寸限制导致整条公式
 * 识别失败（issue #51），此处按比例压低采样密度而不是放弃解码。
 */
export function formulaDecodePixelsPerEx(widthEx: number, heightEx: number,
  targetPixelsPerEx: number,
  maxRasterDimensionPx: number = FORMULA_MAX_RASTER_DIMENSION_PX): number {
  if (!Number.isFinite(widthEx) || !Number.isFinite(heightEx) ||
    widthEx <= 0 || heightEx <= 0 || maxRasterDimensionPx <= 0) {
    return FORMULA_FALLBACK_PIXELS_PER_EX;
  }
  const target = Number.isFinite(targetPixelsPerEx) && targetPixelsPerEx > 0
    ? targetPixelsPerEx
    : FORMULA_FALLBACK_PIXELS_PER_EX;
  // 先按 [下限, 上限] 与尺寸上限取小（超宽公式让位给 4096 硬约束），再对"下限
  // 本身也超出尺寸上限"的极端式子取尺寸上限——宁可低精度解码，不可整条失败。
  // 上限预留 1px：normalizeFormulaSvgText 用 ceil 换算 px，浮点尘埃可能多出 1px
  // 触发 ImageKit 尺寸检查（如 ceil(423.75 × 4096/423.75) 得 4097）。
  const dimensionCap = Math.min((maxRasterDimensionPx - 1) / widthEx, (maxRasterDimensionPx - 1) / heightEx);
  return Math.max(
    Math.min(FORMULA_MAX_DECODE_PIXELS_PER_EX, target, dimensionCap),
    Math.min(FORMULA_MIN_DECODE_PIXELS_PER_EX, dimensionCap));
}

/**
 * 知乎公式 SVG 使用 ex 声明固有尺寸，并以 currentColor 表示公式前景色。
 * ImageKit 解码前将尺寸换成 px（采样密度由 pixelsPerEx 决定），同时把前景色
 * 固化为当前主题正文色。
 */
export function normalizeFormulaSvgText(svg: string, foregroundColor: string,
  pixelsPerEx: number = FORMULA_FALLBACK_PIXELS_PER_EX): string {
  const safePixelsPerEx = Number.isFinite(pixelsPerEx) && pixelsPerEx > 0
    ? pixelsPerEx
    : FORMULA_FALLBACK_PIXELS_PER_EX;
  const width = /\bwidth="([0-9.]+)ex"/i.exec(svg);
  const height = /\bheight="([0-9.]+)ex"/i.exec(svg);
  let normalized = svg;
  if (width !== null) {
    const pixels = Math.max(1, Math.ceil(Number(width[1]) * safePixelsPerEx));
    normalized = normalized.replace(width[0], `width="${pixels}px"`);
  }
  if (height !== null) {
    const pixels = Math.max(1, Math.ceil(Number(height[1]) * safePixelsPerEx));
    normalized = normalized.replace(height[0], `height="${pixels}px"`);
  }
  const color = /^#[0-9A-F]{6}$/i.test(foregroundColor) ? foregroundColor : DEFAULT_FORMULA_COLOR;
  return normalized.replace(/currentColor/g, color);
}

/** 块级公式按解码后的固有宽高比自适应高度，加载前保持原有 4:1 占位。 */
export function blockFormulaDisplayAspectRatio(imageWidth: number, imageHeight: number): number {
  if (!Number.isFinite(imageWidth) || !Number.isFinite(imageHeight) || imageWidth <= 0 || imageHeight <= 0) {
    return DEFAULT_BLOCK_FORMULA_ASPECT_RATIO;
  }
  return imageWidth / imageHeight;
}
