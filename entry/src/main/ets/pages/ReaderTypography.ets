/**
 * 正文排版百分比（字号/行高/段间距）到像素值的映射。
 *
 * 换算口径对齐上游 `RenderMarkdown.kt`（字号、段间距与上游公式一致，默认值即现状），
 * 行高按本项目基线归一：上游语义是"line-height / font-size"（默认 160%），
 * 而本项目改造前正文是 16fp/30（比 1.875）。若照搬上游公式，默认视觉会从 30 变 25.6，
 * 属全量用户可感的回归，故取 `lineHeight = 字号 × 1.875 × (行高% / 160)`：
 * 100%/160% 档与改造前逐像素一致，滑块范围/步进仍与上游相同。
 *
 * 单位（与改造前完全同义，故默认档零视觉变化）：
 * - 字号/行高返回值交给 `Text.fontSize` / `Text.lineHeight`，number 单位是 **fp**
 *   （旧值 `$r('app.float.p1_body_font_size')` = 16fp、`.lineHeight(30)` = 30fp）；
 * - 段间距返回值交给 `List({ space })` / `Column({ space })`，number 单位是 **vp**
 *   （旧值 `space: 12`）。
 *
 * 抽成独立模块便于单测（NativeContentDocument 与行内公式子组件共用同一套换算）。
 */

/** 正文字号基线（fp）：改造前 `app.float.p1_body_font_size` = 16fp。 */
export const BODY_FONT_SIZE_BASE_FP = 16;
/** 标题字号基线（fp）：改造前 `app.float.p1_heading_font_size` = 20fp。 */
export const HEADING_FONT_SIZE_BASE_FP = 20;
/** 段间距基线（vp）：改造前 `List({ space: 12 })`。 */
export const BLOCK_SPACING_BASE_VP = 12;
/** 行高归一锚点百分比（100%/160% 档与改造前逐像素一致）。 */
export const LINE_HEIGHT_ANCHOR_PERCENT = 160;
/** 改造前正文行高比：16fp 字号配 30 行高 = 1.875。 */
export const BODY_LINE_HEIGHT_BASE_RATIO = 1.875;

export function readerBodyFontSize(fontSizePercent: number): number {
  return BODY_FONT_SIZE_BASE_FP * fontSizePercent / 100;
}

export function readerBodyLineHeight(fontSizePercent: number, lineHeightPercent: number): number {
  return readerBodyFontSize(fontSizePercent) * BODY_LINE_HEIGHT_BASE_RATIO *
    (lineHeightPercent / LINE_HEIGHT_ANCHOR_PERCENT);
}

export function readerBlockSpacing(blockSpacingPercent: number): number {
  return BLOCK_SPACING_BASE_VP * blockSpacingPercent / 100;
}

export function readerHeadingFontSize(fontSizePercent: number): number {
  return HEADING_FONT_SIZE_BASE_FP * fontSizePercent / 100;
}
