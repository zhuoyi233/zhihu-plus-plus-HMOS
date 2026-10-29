/**
 * 搜索定位请求的生命周期纯逻辑：阶段、滚动坐标计算与双次闪烁编排。
 * 不依赖 UI，宿主、设置页与 Hypium 共用同一套判定。
 */
import { SettingsSearchLocationRequest, readHighlightSignal } from './SettingsSearchTarget';
import componentUtils from '@ohos.arkui.componentUtils';
import { ComponentUtils } from '@ohos.arkui.UIContext';
import { display } from '@kit.ArkUI';

/** 请求阶段：pending → waitingLayout → scrolling → highlighting → completed。 */
export enum SettingsLocatePhase {
  PENDING = 'pending',
  WAITING_LAYOUT = 'waiting_layout',
  SCROLLING = 'scrolling',
  HIGHLIGHTING = 'highlighting',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
  FAILED = 'failed'
}

/** 一次滚动的执行计划：目标偏移、距离与是否零距离跳过。 */
export interface ScrollPlan {
  readonly targetOffset: number;
  readonly distance: number;
  readonly skip: boolean;
}

/** 双次闪烁的一个阶段：目标强度与时长。 */
export interface HighlightStep {
  readonly level: number;
  readonly durationMs: number;
  /** 阶段结束后的静止间隔（第五阶段后为 0）。 */
  readonly gapAfterMs: number;
}

/** 滚动等待上限（毫秒）：布局轮询 + 滚动动画 + 纠偏共用总预算。 */
export const LOCATE_TOTAL_TIMEOUT_MS: number = 3000;
/** 布局就绪轮询间隔（毫秒）。 */
export const LOCATE_POLL_INTERVAL_MS: number = 120;
/** 滚动动画结束后的确认余量（毫秒）。 */
export const SCROLL_SETTLE_MS: number = 200;

/**
 * 计算滚动计划：目标偏移 = 锚点在内容坐标系中的 Y − 希望的视口位置，
 * 钳制到 [0, 内容高 − 视口高]。距离小于 1vp 视为零距离，跳过滚动。
 */
export function computeScrollPlan(anchorContentY: number, currentOffset: number,
  viewportHeight: number, contentHeight: number, desiredTop: number): ScrollPlan {
  const viewport: number = Number.isFinite(viewportHeight) && viewportHeight > 0 ? viewportHeight : 0;
  const content: number = Number.isFinite(contentHeight) && contentHeight > 0 ? contentHeight : 0;
  const maxOffset: number = Math.max(0, content - viewport);
  const desired: number = Number.isFinite(desiredTop) ? desiredTop : 0;
  const rawTarget: number = Number.isFinite(anchorContentY) ? anchorContentY - desired : 0;
  const targetOffset: number = Math.min(maxOffset, Math.max(0, rawTarget));
  const distance: number = Math.abs(targetOffset - currentOffset);
  return { targetOffset: targetOffset, distance: distance, skip: distance < 1 };
}

/** 滚动时长：280–400ms 常规，较长距离上限 500ms，缓出由调用方指定曲线。 */
export function scrollDurationMs(distance: number): number {
  if (!Number.isFinite(distance) || distance <= 0) {
    return 0;
  }
  if (distance > 1600) {
    return 500;
  }
  return Math.round(280 + (distance / 1600) * 120);
}

/**
 * 双次闪烁编排：亮 160ms → 灭 200ms → 静止 100ms → 亮 160ms → 灭 200ms。
 * 严格两个完整周期，总计约 820ms；调用方以有限阶段链驱动，不用无限动画。
 */
export function highlightPlan(): Array<HighlightStep> {
  return [
    { level: 1, durationMs: 160, gapAfterMs: 0 },
    { level: 0, durationMs: 200, gapAfterMs: 100 },
    { level: 1, durationMs: 160, gapAfterMs: 0 },
    { level: 0, durationMs: 200, gapAfterMs: 0 }
  ];
}

/**
 * 请求是否仍然有效：requestId 与最新请求一致且未被取消信号覆盖。
 * 动画完成回调、布局回调和超时都必须先经过这里，避免旧回调修改新页面。
 */
export function isRequestCurrent(request: SettingsSearchLocationRequest): boolean {
  const latest: SettingsSearchLocationRequest | undefined =
    AppStorage.get<SettingsSearchLocationRequest>('settingsSearchLocationRequest');
  if (latest === undefined || latest.requestId !== request.requestId) {
    return false;
  }
  const signal = readHighlightSignal();
  if (signal !== undefined && signal.cancelled && signal.requestId === request.requestId) {
    return false;
  }
  return true;
}

/** 主题色 hex 附加 alpha 通道；输入非 #RRGGBB/#AARRGGBB 时原样返回。 */
export function withAlpha(color: string, alphaHex: string): string {
  if (color.startsWith('#') && (color.length === 7 || color.length === 9)) {
    return `#${alphaHex}${color.substring(color.length - 6)}`;
  }
  return color;
}

/** 组件矩形（已换算为 vp）。windowX/windowY 为窗口坐标，width/height 为尺寸。 */
export interface ComponentRectVp {
  readonly windowX: number;
  readonly windowY: number;
  readonly width: number;
  readonly height: number;
}

function displayDensity(): number {
  try {
    const density: number = display.getDefaultDisplaySync().densityPixels;
    return Number.isFinite(density) && density > 0 ? density : 1;
  } catch (_error) {
    return 1;
  }
}

/**
 * 读取组件矩形并统一换算为 vp：getRectangleById 返回 px，
 * 而 Scroller.currentOffset/scrollTo 均为 vp，必须除以屏幕密度后参与计算。
 * 组件未挂载或尺寸非法时返回 undefined。
 */
export function readComponentRectVp(utils: ComponentUtils, id: string): ComponentRectVp | undefined {
  try {
    const rect: componentUtils.ComponentInfo = utils.getRectangleById(id);
    const scale: number = displayDensity();
    const width: number = Number(rect.size.width) / scale;
    const height: number = Number(rect.size.height) / scale;
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return undefined;
    }
    return {
      windowX: Number(rect.windowOffset.x) / scale,
      windowY: Number(rect.windowOffset.y) / scale,
      width: width,
      height: height
    };
  } catch (_error) {
    return undefined;
  }
}
