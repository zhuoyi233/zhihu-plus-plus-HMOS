/** Shared width breakpoints and sizing targets for adaptive overlays (vp). */
export const ADAPTIVE_OVERLAY_WIDE_WIDTH_VP: number = 600;
export const ADAPTIVE_OVERLAY_EDGE_GUTTER_VP: number = 24;
export const ADAPTIVE_OVERLAY_TASK_MAX_WIDTH_VP: number = 480;
export const ADAPTIVE_OVERLAY_MENU_WIDTH_VP: number = 352;
export const ADAPTIVE_OVERLAY_CONFIRM_MAX_WIDTH_VP: number = 400;
export const ADAPTIVE_OVERLAY_READING_MAX_WIDTH_VP: number = 640;

export function adaptiveOverlayWidth(availableWidthVp: number, maxWidthVp: number): number {
  const gutterWidthVp = ADAPTIVE_OVERLAY_EDGE_GUTTER_VP * 2;
  const usableWidthVp = Math.max(0, availableWidthVp - gutterWidthVp);
  return Math.min(maxWidthVp, usableWidthVp);
}

export function isWideOverlayContainer(availableWidthVp: number): boolean {
  return availableWidthVp >= ADAPTIVE_OVERLAY_WIDE_WIDTH_VP;
}
