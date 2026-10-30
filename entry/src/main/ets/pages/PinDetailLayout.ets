/**
 * 想法详情页的布局口径（#119）。
 *
 * 只放"想法页需要单独判定、且能脱离界面验证"的三个量：首屏让位、底栏紧凑判定、底栏测宽。
 * 具体公式复用共享阅读实现（AppPageChrome / ReaderViewportLayout），不在这里另立一套。
 */
import { FLOATING_TITLE_BAR_OFFSET, ROOT_TITLE_BAR_CONTENT_HEIGHT } from './AppPageChrome';
import { readerBottomInsetVp, readerCompactActions, readerHorizontalPaddingVp } from './ReaderViewportLayout';

/**
 * 首屏内容起点：`max(94vp, 状态栏高度 + 56vp)`。
 *
 * 顶栏由 AppShell 的 HDS 标题栏承担，内容视口延伸到顶栏之后，只有首屏起点让位；
 * 顶栏模糊扩展区不计入（避免滚动后正文被二次推低）。状态栏高度缺失或异常（负数、
 * NaN、Infinity）按 0 处理，仍退到 94vp 下限，不会把内容整块推出屏幕。
 */
export function pinTopContentInsetVp(statusBarHeightVp: number): number {
  const statusBar = Number.isFinite(statusBarHeightVp) ? Math.max(0, statusBarHeightVp) : 0;
  return Math.max(FLOATING_TITLE_BAR_OFFSET, statusBar + ROOT_TITLE_BAR_CONTENT_HEIGHT);
}

/**
 * 文末让位：底栏实测高度 + 16vp，最低 80vp。
 *
 * 实测高度已包含系统手势区（底栏底部按 bottomRectHeight 避让），这里只额外补一段
 * 呼吸空间，安全区只算一次，避免正文尾部悬空过高。高度未测得（0 或异常）时沿用
 * 共享实现的 100vp 兜底。
 */
export function pinBottomContentInsetVp(actionBarHeightVp: number): number {
  return readerBottomInsetVp(actionBarHeightVp, false);
}

/**
 * 底栏左右边距：与正文同口径（窄窗 16／常规 20／宽窗按 720vp 阅读列居中）。
 *
 * 宽屏下两块胶囊因此围绕阅读列摆放，而不是各自贴到屏幕两端；窄窗下与正文左缘对齐。
 */
export function pinBottomBarSideInsetVp(containerWidthVp: number): number {
  return readerHorizontalPaddingVp(containerWidthVp);
}

/**
 * 底栏是否收起可见数字：窄窗（<340vp）或系统大字体（>1.2 倍）。
 *
 * 收起后完整计数仍保留在按钮的可访问名称里，读数不丢失。
 */
export function pinCompactBottomActions(containerWidthVp: number, fontScale: number): boolean {
  return readerCompactActions(containerWidthVp, fontScale);
}
