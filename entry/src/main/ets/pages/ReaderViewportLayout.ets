/** 手机留边 16/20vp，宽窗口把正文限制在 720vp，避免横屏出现超长行。 */
export function readerHorizontalPaddingVp(widthVp: number): number {
  if (!(widthVp > 0) || !Number.isFinite(widthVp)) {
    return 20;
  }
  const edge = widthVp < 360 ? 16 : 20;
  return Math.max(edge, (widthVp - 720) / 2);
}

/** 操作栏测量值包含系统底部避让；只在其上额外保留 16vp，不重复加安全区。 */
export function readerBottomInsetVp(actionBarHeightVp: number, immersive: boolean): number {
  if (immersive) {
    return 24;
  }
  return actionBarHeightVp > 0 && Number.isFinite(actionBarHeightVp)
    ? Math.max(80, actionBarHeightVp + 16) : 100;
}

/** 窄窗口或系统大字体时收起数字，把可用空间留给各个操作。 */
export function readerCompactActions(widthVp: number, fontScale: number): boolean {
  return (widthVp > 0 && widthVp < 340) || fontScale > 1.2;
}

/** 极小行高偏好下，图注仍保留足够行高，避免多行文字相互覆盖。 */
export function readerCaptionLineHeightFp(bodyFontSizeFp: number, bodyLineHeightFp: number): number {
  return Math.max(bodyFontSizeFp * 1.125, bodyLineHeightFp * 2 / 3);
}
