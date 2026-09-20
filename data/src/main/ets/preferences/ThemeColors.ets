/**
 * 主题色（品牌主色）工具：seed 色校验、HSV 转换、深色模式解析与派生色计算。
 * 颜色字符串统一为不透明度前缀可省的大写 hex（#RRGGBB / #AARRGGBB），可直接作为
 * ArkUI ResourceColor 使用。
 */

/** 默认主题色：知乎蓝。未设置或解析失败时的兜底值。 */
export const DEFAULT_THEME_COLOR = '#0066FF';

export interface RgbColor {
  r: number;
  g: number;
  b: number;
}

/** h ∈ [0, 360)，s / v ∈ [0, 1]。 */
export interface HsvColor {
  h: number;
  s: number;
  v: number;
}

const THEME_COLOR_PATTERN: RegExp = /^#[0-9a-fA-F]{6}$/;

export function isValidThemeColorHex(value: string | undefined): boolean {
  return typeof value === 'string' && THEME_COLOR_PATTERN.test(value.trim());
}

/** 规范化为大写 #RRGGBB；非法输入回退默认主题色。 */
export function normalizeThemeColor(value: string | undefined): string {
  if (!isValidThemeColorHex(value)) {
    return DEFAULT_THEME_COLOR;
  }
  return (value as string).trim().toUpperCase();
}

function clampChannel(value: number): number {
  return Math.min(255, Math.max(0, Math.round(value)));
}

export function hexToRgb(hex: string): RgbColor {
  const normalized = normalizeThemeColor(hex);
  const result: RgbColor = {
    r: parseInt(normalized.substring(1, 3), 16),
    g: parseInt(normalized.substring(3, 5), 16),
    b: parseInt(normalized.substring(5, 7), 16)
  };
  return result;
}

export function rgbToHex(rgb: RgbColor): string {
  const r = clampChannel(rgb.r).toString(16).padStart(2, '0');
  const g = clampChannel(rgb.g).toString(16).padStart(2, '0');
  const b = clampChannel(rgb.b).toString(16).padStart(2, '0');
  return `#${r}${g}${b}`.toUpperCase();
}

export function rgbToHsv(rgb: RgbColor): HsvColor {
  const r = clampChannel(rgb.r) / 255;
  const g = clampChannel(rgb.g) / 255;
  const b = clampChannel(rgb.b) / 255;
  const max = Math.max(r, Math.max(g, b));
  const min = Math.min(r, Math.min(g, b));
  const delta = max - min;
  let h = 0;
  if (delta > 0) {
    if (max === r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max === g) {
      h = 60 * ((b - r) / delta + 2);
    } else {
      h = 60 * ((r - g) / delta + 4);
    }
  }
  if (h < 0) {
    h += 360;
  }
  const s = max === 0 ? 0 : delta / max;
  const result: HsvColor = { h: h, s: s, v: max };
  return result;
}

export function hsvToRgb(hsv: HsvColor): RgbColor {
  const h = ((hsv.h % 360) + 360) % 360;
  const s = Math.min(1, Math.max(0, hsv.s));
  const v = Math.min(1, Math.max(0, hsv.v));
  const c = v * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = v - c;
  let r = 0;
  let g = 0;
  let b = 0;
  if (h < 60) {
    r = c; g = x;
  } else if (h < 120) {
    r = x; g = c;
  } else if (h < 180) {
    g = c; b = x;
  } else if (h < 240) {
    g = x; b = c;
  } else if (h < 300) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  const result: RgbColor = {
    r: clampChannel((r + m) * 255),
    g: clampChannel((g + m) * 255),
    b: clampChannel((b + m) * 255)
  };
  return result;
}

/**
 * 深色模式下的生效主色：向白色线性提亮（对齐原深色资源 #5B9DFF 相对浅色
 * #0066FF 的观感）。seed 已是亮色时变化很小。
 */
export function resolveThemeColorForDark(seedHex: string): string {
  const rgb = hexToRgb(seedHex);
  const lighten = (channel: number): number => clampChannel(channel + (255 - channel) * 0.35);
  const result: RgbColor = { r: lighten(rgb.r), g: lighten(rgb.g), b: lighten(rgb.b) };
  return rgbToHex(result);
}

/** 由生效主色派生的容器底色（约 12% 不透明度叠加，深浅色模式均协调）。 */
export function themeColorContainerColor(resolvedHex: string): string {
  const normalized = normalizeThemeColor(resolvedHex);
  return `#1F${normalized.substring(1)}`;
}

/** 主色之上的前景色：按 YIQ 亮度在白/深之间切换，保证可读对比度。 */
export function onThemeColor(resolvedHex: string): string {
  const rgb = hexToRgb(resolvedHex);
  const yiq = (rgb.r * 299 + rgb.g * 587 + rgb.b * 114) / 1000;
  return yiq >= 150 ? '#14181F' : '#FFFFFF';
}
