import { LengthMetrics } from '@kit.ArkUI';

/** 换列保位的单次恢复请求：目标 FlowItem 索引、新布局下该项应有宽度与悬浮标题栏让位。 */
export interface FeedAnchorRestoreRequest {
  flowIndex: number;
  expectedItemWidth: number;
  extraOffsetVp: number;
}

/**
 * 换列后恢复阅读位置：sections 重排是异步布局，立即 scrollToIndex 可能落在旧布局上。
 * 轮询 getItemRect 直到目标项宽度与新布局一致再恢复；超过上限仍未生效则按索引兜底。
 * 各页面各持独立实例（离屏页互不影响）；高频换列时仅保留最后一次请求目标。
 */
export class FeedAnchorRestorer {
  private static readonly TICK_MS: number = 32;
  private static readonly MAX_ATTEMPTS: number = 10;
  private request: FeedAnchorRestoreRequest | undefined = undefined;
  private attempts: number = 0;
  private timerId: number = -1;

  schedule(request: FeedAnchorRestoreRequest, scroller: Scroller): void {
    if (request.flowIndex < 0) {
      return;
    }
    this.request = request;
    this.attempts = 0;
    if (this.timerId >= 0) {
      return;
    }
    this.tick(scroller);
  }

  cancel(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.request = undefined;
  }

  private tick(scroller: Scroller): void {
    this.timerId = -1;
    const request = this.request;
    if (request === undefined) {
      return;
    }
    this.attempts += 1;
    if (this.layoutSettled(scroller, request) || this.attempts >= FeedAnchorRestorer.MAX_ATTEMPTS) {
      this.request = undefined;
      // extraOffset 取负：锚点对齐视口顶部后再下移让位，避免落进悬浮标题栏底下。
      scroller.scrollToIndex(request.flowIndex, false, ScrollAlign.START,
        { extraOffset: LengthMetrics.vp(-request.extraOffsetVp) });
      return;
    }
    this.timerId = setTimeout((): void => this.tick(scroller), FeedAnchorRestorer.TICK_MS);
  }

  private layoutSettled(scroller: Scroller, request: FeedAnchorRestoreRequest): boolean {
    try {
      const rect: RectResult = scroller.getItemRect(request.flowIndex);
      return rect.width > 0 && Math.abs(rect.width - request.expectedItemWidth) <= 1;
    } catch (_error) {
      // 索引无效或控制器未绑定：视作新布局尚未生效，继续等待。
      return false;
    }
  }
}
