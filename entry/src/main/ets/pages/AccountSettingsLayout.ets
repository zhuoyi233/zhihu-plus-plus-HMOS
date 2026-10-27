/**
 * “我的”与设置页共用的响应式布局判定与列表样式解析。
 *
 * 断点以页面实际分配的容器宽度（vp）为准，不读取设备物理尺寸；字体放大时同步抬高
 * 最小列宽/栏宽要求，空间不足自动回退单列或逐级导航。页面不应各自维护一套断点。
 */
import { FeedCardStyle } from 'data';

/** “我的”：低于该宽度单列，达到后且满足最小列宽才使用两列。 */
export const ACCOUNT_TWO_COLUMN_BREAKPOINT_VP: number = 720;
/** “我的”整体内容最大宽度。 */
export const ACCOUNT_MAX_CONTENT_WIDTH_VP: number = 1120;
/** “我的”两列时每列最小宽度（默认字号）。 */
export const ACCOUNT_MIN_COLUMN_WIDTH_VP: number = 320;

/** 设置：低于该宽度整页逐级导航，达到后且满足最小栏宽才使用目录/详情双栏。 */
export const SETTINGS_SPLIT_BREAKPOINT_VP: number = 900;
/** 设置目录最小宽度（默认字号）。 */
export const SETTINGS_MASTER_MIN_WIDTH_VP: number = 280;
/** 设置详情最小宽度（默认字号）。 */
export const SETTINGS_DETAIL_MIN_WIDTH_VP: number = 480;
/** 设置详情内容最大宽度。 */
export const SETTINGS_DETAIL_MAX_CONTENT_WIDTH_VP: number = 720;

/** 页面左右边距，沿用 page_padding。 */
export const LAYOUT_HORIZONTAL_PADDING_VP: number = 12;
/** 列/栏间距。 */
export const LAYOUT_COLUMN_GAP_VP: number = 24;

export enum AccountLayoutMode {
  SINGLE_COLUMN = 'single_column',
  TWO_COLUMN = 'two_column'
}

export interface AccountLayoutSpec {
  readonly mode: AccountLayoutMode;
  readonly columns: number;
  readonly columnGap: number;
  readonly horizontalPadding: number;
  readonly maxContentWidth: number;
}

export enum SettingsLayoutMode {
  STACKED = 'stacked',
  SPLIT = 'split'
}

export interface SettingsLayoutSpec {
  readonly mode: SettingsLayoutMode;
  readonly masterWidth: number;
  readonly detailWidth: number;
  readonly columnGap: number;
  readonly horizontalPadding: number;
  readonly detailMaxContentWidth: number;
}

/** 字体缩放限制在 1~2 倍内，避免异常配置把页面永久压成单列或无限放大最小宽度。 */
export function normalizedFontScale(fontScale: number): number {
  if (!Number.isFinite(fontScale) || fontScale < 1) {
    return 1;
  }
  return Math.min(2, fontScale);
}

function safeContainerWidth(containerWidth: number): number {
  return Number.isFinite(containerWidth) && containerWidth > 0 ? containerWidth : 0;
}

/**
 * “我的”布局：W < 720 单列；W >= 720 且两列各自达到 320 × 字体缩放才双列。
 * 资料区与快捷区始终跨列，功能分组按完整分组并排，因此这里只决定列数。
 */
export function resolveAccountLayout(containerWidth: number, fontScale: number): AccountLayoutSpec {
  const scale: number = normalizedFontScale(fontScale);
  const width: number = safeContainerWidth(containerWidth);
  const single: AccountLayoutSpec = {
    mode: AccountLayoutMode.SINGLE_COLUMN,
    columns: 1,
    columnGap: LAYOUT_COLUMN_GAP_VP,
    horizontalPadding: LAYOUT_HORIZONTAL_PADDING_VP,
    maxContentWidth: ACCOUNT_MAX_CONTENT_WIDTH_VP
  };
  if (width < ACCOUNT_TWO_COLUMN_BREAKPOINT_VP) {
    return single;
  }
  const usable: number = width - LAYOUT_HORIZONTAL_PADDING_VP * 2 - LAYOUT_COLUMN_GAP_VP;
  if (usable < ACCOUNT_MIN_COLUMN_WIDTH_VP * 2 * scale) {
    return single;
  }
  const two: AccountLayoutSpec = {
    mode: AccountLayoutMode.TWO_COLUMN,
    columns: 2,
    columnGap: LAYOUT_COLUMN_GAP_VP,
    horizontalPadding: LAYOUT_HORIZONTAL_PADDING_VP,
    maxContentWidth: ACCOUNT_MAX_CONTENT_WIDTH_VP
  };
  return two;
}

/**
 * 设置布局：W < 900 整页逐级导航；W >= 900 且目录至少 280、详情至少 480（均乘字体缩放）
 * 才分栏。左栏宽度在 280~360 × 缩放之间取值，剩余空间留给详情。
 */
export function resolveSettingsLayout(containerWidth: number, fontScale: number): SettingsLayoutSpec {
  const scale: number = normalizedFontScale(fontScale);
  const width: number = safeContainerWidth(containerWidth);
  const stacked: SettingsLayoutSpec = {
    mode: SettingsLayoutMode.STACKED,
    masterWidth: 0,
    detailWidth: 0,
    columnGap: LAYOUT_COLUMN_GAP_VP,
    horizontalPadding: LAYOUT_HORIZONTAL_PADDING_VP,
    detailMaxContentWidth: SETTINGS_DETAIL_MAX_CONTENT_WIDTH_VP
  };
  if (width < SETTINGS_SPLIT_BREAKPOINT_VP) {
    return stacked;
  }
  const usable: number = width - LAYOUT_HORIZONTAL_PADDING_VP * 2 - LAYOUT_COLUMN_GAP_VP;
  const minimum: number = (SETTINGS_MASTER_MIN_WIDTH_VP + SETTINGS_DETAIL_MIN_WIDTH_VP) * scale;
  if (usable < minimum) {
    return stacked;
  }
  const masterFloor: number = SETTINGS_MASTER_MIN_WIDTH_VP * scale;
  const masterCeiling: number = Math.min(360 * scale, usable - SETTINGS_DETAIL_MIN_WIDTH_VP * scale);
  const preferred: number = usable * 0.36;
  const masterWidth: number = Math.round(Math.max(masterFloor, Math.min(masterCeiling, preferred)));
  const split: SettingsLayoutSpec = {
    mode: SettingsLayoutMode.SPLIT,
    masterWidth: masterWidth,
    detailWidth: usable - masterWidth,
    columnGap: LAYOUT_COLUMN_GAP_VP,
    horizontalPadding: LAYOUT_HORIZONTAL_PADDING_VP,
    detailMaxContentWidth: SETTINGS_DETAIL_MAX_CONTENT_WIDTH_VP
  };
  return split;
}

/** 卡片样式的分组表面；分割线样式与页面同底，只保留组标题与行间细线。 */
export function settingsGroupBackground(cardStyle: string): ResourceColor {
  return cardStyle === FeedCardStyle.CARD ? $r('app.color.surface_background') : Color.Transparent;
}

/** 卡片样式的分组圆角；分割线样式不绘制圆角表面。 */
export function settingsGroupRadius(cardStyle: string): Length {
  return cardStyle === FeedCardStyle.CARD ? $r('app.float.card_radius') : 0;
}
