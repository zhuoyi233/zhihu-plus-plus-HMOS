/**
 * 设置页搜索定位执行器：布局等待 → 坐标测量 → 动画滚动 → 落定确认 → 发布高亮。
 *
 * 每个嵌入详情页持有一个实例；页面只提供钩子（Scroller、组件 ID、就绪条件），
 * 并转发 onScrollStop / 用户滚动事件。阶段推进全程校验 requestId，
 * 新请求、用户拖动、离页都会取消旧任务并清理定时器。
 */
import {
  computeScrollPlan,
  ComponentRectVp,
  LOCATE_POLL_INTERVAL_MS,
  LOCATE_TOTAL_TIMEOUT_MS,
  readComponentRectVp,
  scrollDurationMs,
  SCROLL_SETTLE_MS
} from './SettingsSearchLocationState';
import {
  publishHighlightSignal,
  SettingsSearchHighlightSignal,
  SettingsSearchLocationKeys,
  SettingsSearchLocationRequest
} from './SettingsSearchTarget';

import { ComponentUtils } from '@ohos.arkui.UIContext';

export interface SettingsLocatorHooks {
  getUIContext: () => UIContext;
  /** 嵌入设置实例才允许消费请求；独立根路由实例必须返回 false。 */
  isEmbedded: () => boolean;
  /** 页面业务就绪（如异步 loaded）；未就绪期间轮询等待。 */
  isReady: () => boolean;
  getScroller: () => Scroller;
  /** 滚动容器组件 id（Scroll 的 .id()）。 */
  scrollId: string;
  /** 内容根容器组件 id，用于取内容总高。 */
  contentId: string;
  /** 希望的锚点视口位置（顶栏下沿再留余量），vp。 */
  desiredTop: () => number;
  /** 总超时/测量失败后的用户提示。 */
  onFailed: () => void;
  /** 条件隐藏项回退到前置开关落点时的提示（如“需先开启……”）。 */
  onFallback: () => void;
}

function readRectangle(utils: ComponentUtils, id: string): ComponentRectVp | undefined {
  return readComponentRectVp(utils, id);
}

export class SettingsSearchLocationRunner {
  private request: SettingsSearchLocationRequest | undefined = undefined;
  private readonly hooks: SettingsLocatorHooks;
  private timerId: number = -1;
  private programmaticScroll: boolean = false;
  private correctionUsed: boolean = false;
  private startedAt: number = 0;
  private lastPlanTarget: number = 0;
  /** 实际生效的锚点：条件隐藏时切换到 fallbackAnchorId。 */
  private activeAnchorId: string = '';

  constructor(hooks: SettingsLocatorHooks) {
    this.hooks = hooks;
  }

  isActive(): boolean {
    return this.request !== undefined;
  }

  /**
   * 消费定位请求：嵌入实例、pane 匹配与陈旧请求（已被消费过）三重校验后
   * 进入轮询；在此之前静默取消旧任务。
   */
  consume(request: SettingsSearchLocationRequest | undefined): boolean {
    this.cancel(false);
    if (request === undefined || !this.hooks.isEmbedded()) {
      return false;
    }
    const consumed: number = AppStorage.get<number>(SettingsSearchLocationKeys.CONSUMED_REQUEST_ID) ?? 0;
    if (request.requestId <= consumed) {
      return false;
    }
    AppStorage.setOrCreate(SettingsSearchLocationKeys.CONSUMED_REQUEST_ID, request.requestId);
    this.request = request;
    this.activeAnchorId = request.anchorId;
    this.startedAt = Date.now();
    this.correctionUsed = false;
    this.schedulePoll();
    return true;
  }

  /** 用户主动滚动或离页：发布取消信号并清理。 */
  cancel(publishCancel: boolean = true): void {
    this.clearTimer();
    const request = this.request;
    this.request = undefined;
    this.programmaticScroll = false;
    if (publishCancel && request !== undefined) {
      publishHighlightSignal({
        requestId: request.requestId,
        highlightGroupId: '',
        cancelled: true
      } as SettingsSearchHighlightSignal);
    }
  }

  /** 页面 onScrollStart 转发：非程序化滚动视为用户接管。 */
  onScrollStarted(): void {
    if (this.request !== undefined && !this.programmaticScroll) {
      this.cancel(true);
    }
  }

  /** 页面 onScrollStop 转发：程序化滚动结束后确认落点。 */
  onScrollStopped(): void {
    if (this.request === undefined || !this.programmaticScroll) {
      return;
    }
    this.programmaticScroll = false;
    this.clearTimer();
    this.verifyAfterScroll();
  }

  private schedulePoll(): void {
    this.clearTimer();
    this.timerId = setTimeout((): void => this.waitForLayout(), LOCATE_POLL_INTERVAL_MS);
  }

  private waitForLayout(): void {
    const request = this.request;
    if (request === undefined) {
      return;
    }
    if (Date.now() - this.startedAt > LOCATE_TOTAL_TIMEOUT_MS) {
      this.fail();
      return;
    }
    if (!this.hooks.isReady()) {
      this.schedulePoll();
      return;
    }
    let anchor = this.measureAnchor(this.activeAnchorId);
    if (anchor === undefined) {
      // 条件隐藏项：主锚点不存在时回退到声明的前置开关，并提示需先开启。
      const request = this.request;
      if (request !== undefined && request.fallbackAnchorId.length > 0 &&
        this.activeAnchorId !== request.fallbackAnchorId) {
        const fallback = this.measureAnchor(request.fallbackAnchorId);
        if (fallback !== undefined) {
          this.activeAnchorId = request.fallbackAnchorId;
          this.hooks.onFallback();
          anchor = fallback;
        }
      }
    }
    if (anchor === undefined) {
      this.schedulePoll();
      return;
    }
    this.startScroll(anchor.windowY);
  }

  private measureAnchor(anchorId: string): ComponentRectVp | undefined {
    if (anchorId.length === 0) {
      return undefined;
    }
    const utils: ComponentUtils = this.hooks.getUIContext().getComponentUtils();
    return readRectangle(utils, anchorId);
  }

  private startScroll(anchorWindowY: number): void {
    const request = this.request;
    if (request === undefined) {
      return;
    }
    const ui: UIContext = this.hooks.getUIContext();
    const utils: ComponentUtils = ui.getComponentUtils();
    const scrollRect = readRectangle(utils, this.hooks.scrollId);
    const contentRect = readRectangle(utils, this.hooks.contentId);
    if (scrollRect === undefined || contentRect === undefined) {
      this.schedulePoll();
      return;
    }
    const scroller: Scroller = this.hooks.getScroller();
    const offset = scroller.currentOffset();
    // Scroller 未绑定到 Scroll（页面装配遗漏）时 currentOffset 返回 undefined：
    // 按零偏移降级处理，避免空指针直接崩溃。
    const current: number = offset === undefined ? 0 : Number(offset.yOffset) || 0;
    const anchorContentY: number = (anchorWindowY - scrollRect.windowY) + current;
    const plan = computeScrollPlan(anchorContentY, current, scrollRect.height, contentRect.height,
      this.hooks.desiredTop());
    this.lastPlanTarget = plan.targetOffset;
    if (plan.skip) {
      this.finishScroll();
      return;
    }
    this.programmaticScroll = true;
    const duration: number = scrollDurationMs(plan.distance);
    this.hooks.getScroller().scrollTo({
      xOffset: 0,
      yOffset: plan.targetOffset,
      animation: { duration: duration, curve: Curve.EaseOut }
    });
    // 滚动结束优先信任 onScrollStop；此定时器只是兜底确认（个别场景回调缺失）。
    this.clearTimer();
    this.timerId = setTimeout((): void => {
      if (this.request !== undefined && this.programmaticScroll) {
        this.programmaticScroll = false;
        this.verifyAfterScroll();
      }
    }, duration + SCROLL_SETTLE_MS);
  }

  /** 落点复核：仍被顶栏遮挡且未纠偏过时做一次有限纠偏，然后进入高亮。 */
  private verifyAfterScroll(): void {
    const request = this.request;
    if (request === undefined) {
      return;
    }
    if (this.activeAnchorId.length > 0 && !this.correctionUsed) {
      const utils: ComponentUtils = this.hooks.getUIContext().getComponentUtils();
      const anchor = readRectangle(utils, this.activeAnchorId);
      const scrollRect = readRectangle(utils, this.hooks.scrollId);
      if (anchor !== undefined && scrollRect !== undefined) {
        const offset = this.hooks.getScroller().currentOffset();
        const current: number = offset === undefined ? 0 : Number(offset.yOffset) || 0;
        const anchorViewportY: number = anchor.windowY - scrollRect.windowY;
        const desired: number = this.hooks.desiredTop();
        const drift: number = anchorViewportY - desired;
        // 只纠偏明显的偏差（>8vp），且必须仍有滚动空间，避免边界处反复回弹。
        const maxOffset: number = Math.max(0, readRectangle(utils, this.hooks.contentId)?.height ?? 0) - scrollRect.height;
        if (Math.abs(drift) > 8 && ((drift > 0 && current < maxOffset - 1) || (drift < 0 && current > 1))) {
          this.correctionUsed = true;
          this.lastPlanTarget = Math.min(maxOffset, Math.max(0, current + drift));
          this.startScrollFrom(current + drift);
          return;
        }
      }
    }
    this.finishScroll();
  }

  private startScrollFrom(currentOffset: number): void {
    const request = this.request;
    if (request === undefined) {
      return;
    }
    const distance: number = Math.abs(this.lastPlanTarget - currentOffset);
    if (distance < 1) {
      this.finishScroll();
      return;
    }
    this.programmaticScroll = true;
    const duration: number = scrollDurationMs(distance);
    this.hooks.getScroller().scrollTo({
      xOffset: 0,
      yOffset: this.lastPlanTarget,
      animation: { duration: duration, curve: Curve.EaseOut }
    });
    this.clearTimer();
    this.timerId = setTimeout((): void => {
      if (this.request !== undefined && this.programmaticScroll) {
        this.programmaticScroll = false;
        this.finishScroll();
      }
    }, duration + SCROLL_SETTLE_MS);
  }

  private finishScroll(): void {
    const request = this.request;
    if (request === undefined) {
      return;
    }
    this.clearTimer();
    this.request = undefined;
    this.programmaticScroll = false;
    if (request.highlightGroupId.length > 0) {
      publishHighlightSignal({
        requestId: request.requestId,
        highlightGroupId: request.highlightGroupId,
        cancelled: false
      } as SettingsSearchHighlightSignal);
    }
  }

  private fail(): void {
    this.clearTimer();
    this.request = undefined;
    this.hooks.onFailed();
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}
