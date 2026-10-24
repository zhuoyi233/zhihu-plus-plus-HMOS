import { Answer } from 'data';
import { contentDetailErrorMessage, contentDetailRequiresLogin } from './ContentDetailState';

/**
 * 连续阅读逐答全文状态（docs/continuous-answer-reading-plan.md §4.2）：
 * pending 未请求 / loading 在途 / ready 正文就绪 / error 失败（就地重试）/
 * evicted 远处淘汰（保留实测高度占位，回看 restore 重新拉取）。
 */
export type ContinuousFullTextPhase = 'pending' | 'loading' | 'ready' | 'error' | 'evicted';

export interface ContinuousFullTextRecord {
  readonly answerId: string;
  readonly phase: ContinuousFullTextPhase;
  readonly answer?: Answer;
  readonly errorMessage?: string;
  readonly requiresLogin?: boolean;
  /** evicted 状态保留的实测正文高度（vp）；其他状态为 0。 */
  readonly measuredHeightVp: number;
}

/** 逐答正文来源抽象：生产由 ContentRepository 实现，单测注入桩。 */
export interface ContinuousFullTextSource {
  getAnswer(answerId: string): Promise<Answer>;
}

export type ContinuousFullTextObserver = (snapshot: Array<ContinuousFullTextRecord>) => void;

/**
 * 全文调度器：窗口请求、并发上限（每个槽位独立的来源实例，规避
 * ZhihuHttpClient 单实例单飞互斥）、在途去重、淘汰即丢弃。
 * 状态迁移以「记录当前 phase」为准绳：loading 中被淘汰的回包直接丢弃
 * （淘汰是内存边界的权威语义，回看经 restore 重新拉取）。
 */
export class ContinuousFullTextScheduler {
  private readonly sources: Array<ContinuousFullTextSource>;
  private readonly concurrency: number;
  private readonly records: Map<string, ContinuousFullTextRecord> = new Map();
  private readonly inFlight: Set<string> = new Set();
  private readonly queue: Array<string> = [];
  private observer?: ContinuousFullTextObserver;
  private active: boolean = false;
  private nextSlot: number = 0;

  constructor(sourceFactory: () => ContinuousFullTextSource, concurrency: number,
    observer: ContinuousFullTextObserver) {
    this.concurrency = Math.max(1, concurrency);
    this.sources = [];
    for (let i = 0; i < this.concurrency; i++) {
      this.sources.push(sourceFactory());
    }
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.pump();
  }

  /** 离页停止派发新请求；在途回包若未被淘汰仍会落账（页面销毁经 dispose 断开观察）。 */
  deactivate(): void {
    this.active = false;
    this.queue.splice(0, this.queue.length);
  }

  /** 页面销毁：断开观察者，此后任何状态变化都不再回调。 */
  dispose(): void {
    this.deactivate();
    this.observer = undefined;
  }

  /** 窗口请求：缺失的建 pending、已 pending 的入队；ready/error/evicted 不动。 */
  ensure(answerIds: Array<string>): void {
    answerIds.forEach((answerId: string): void => {
      const existing = this.records.get(answerId);
      if (existing === undefined) {
        this.records.set(answerId, {
          answerId: answerId,
          phase: 'pending',
          measuredHeightVp: 0
        });
      }
      const record = this.records.get(answerId);
      if (record !== undefined && record.phase === 'pending' && !this.queue.includes(answerId) &&
        !this.inFlight.has(answerId)) {
        this.queue.push(answerId);
      }
    });
    this.pump();
  }

  /** 淘汰：正文数据立即释放，只保留实测高度占位。 */
  evict(answerId: string, measuredHeightVp: number): void {
    const existing = this.records.get(answerId);
    if (existing === undefined || existing.phase === 'evicted') {
      return;
    }
    this.records.set(answerId, {
      answerId: answerId,
      phase: 'evicted',
      measuredHeightVp: Math.max(0, Math.round(measuredHeightVp))
    });
    this.notify();
  }

  /** 回看恢复：evicted → pending 并重新排队。 */
  restore(answerId: string): void {
    const existing = this.records.get(answerId);
    if (existing === undefined || existing.phase !== 'evicted') {
      return;
    }
    this.records.set(answerId, {
      answerId: answerId,
      phase: 'pending',
      measuredHeightVp: 0
    });
    this.ensure([answerId]);
  }

  /** 错误就地重试：error → pending 并重新排队。 */
  retry(answerId: string): void {
    const existing = this.records.get(answerId);
    if (existing === undefined || existing.phase !== 'error') {
      return;
    }
    this.records.set(answerId, {
      answerId: answerId,
      phase: 'pending',
      measuredHeightVp: 0
    });
    this.ensure([answerId]);
  }

  /**
   * 彻底移除（屏蔽重过滤用）：清记录并退出排队；在途回包因记录缺失在 fetch
   * 落账守卫处自然丢弃（与淘汰同款语义）。inFlight 保留到回包 settle 自清，
   * 避免 settle 前重复 ensure 同一回答时出现并发双请求。
   */
  drop(answerId: string): void {
    const queueIndex = this.queue.indexOf(answerId);
    if (queueIndex >= 0) {
      this.queue.splice(queueIndex, 1);
    }
    if (this.records.delete(answerId)) {
      this.notify();
    }
  }

  record(answerId: string): ContinuousFullTextRecord | undefined {
    return this.records.get(answerId);
  }

  snapshot(): Array<ContinuousFullTextRecord> {
    const values: Array<ContinuousFullTextRecord> = [];
    this.records.forEach((record: ContinuousFullTextRecord): void => {
      values.push(record);
    });
    return values;
  }

  private pump(): void {
    while (this.active && this.inFlight.size < this.concurrency && this.queue.length > 0) {
      const answerId = this.queue.shift();
      if (answerId === undefined) {
        return;
      }
      const record = this.records.get(answerId);
      if (record === undefined || record.phase !== 'pending' || this.inFlight.has(answerId)) {
        continue;
      }
      this.inFlight.add(answerId);
      this.records.set(answerId, {
        answerId: answerId,
        phase: 'loading',
        measuredHeightVp: 0
      });
      const source = this.sources[this.nextSlot % this.sources.length];
      this.nextSlot += 1;
      void this.fetch(source, answerId);
    }
    this.notify();
  }

  private async fetch(source: ContinuousFullTextSource, answerId: string): Promise<void> {
    try {
      const answer = await source.getAnswer(answerId);
      const record = this.records.get(answerId);
      // 淘汰是权威语义：在途回包到达前被淘汰的回答直接丢弃结果。
      if (record === undefined || record.phase !== 'loading') {
        return;
      }
      this.records.set(answerId, {
        answerId: answerId,
        phase: 'ready',
        answer: answer,
        measuredHeightVp: 0
      });
    } catch (error) {
      const record = this.records.get(answerId);
      if (record === undefined || record.phase !== 'loading') {
        return;
      }
      this.records.set(answerId, {
        answerId: answerId,
        phase: 'error',
        errorMessage: contentDetailErrorMessage(error),
        requiresLogin: contentDetailRequiresLogin(error),
        measuredHeightVp: 0
      });
    } finally {
      this.inFlight.delete(answerId);
      this.pump();
    }
  }

  private notify(): void {
    const observer = this.observer;
    if (observer === undefined) {
      return;
    }
    observer(this.snapshot());
  }
}
