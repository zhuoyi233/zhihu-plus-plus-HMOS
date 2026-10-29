import { Answer, ContentRepository } from 'data';

/** 预取缓存上限：当前答不入缓存，保留相邻最多 3 份全文（计划 §5.4）。 */
export const ANSWER_PREFETCH_CAPACITY: number = 3;

interface PrefetchQueueItem {
  readonly answerId: string;
  foreground: boolean;
  readonly resolve: (answer: Answer | undefined) => void;
}

/**
 * 单篇回答切换的前后答全文预取（docs/issue-21-answer-switch-flicker-fix-plan.md §5.4）。
 *
 * 约束：
 * - 只调用详情获取能力，不写阅读记录、不上传历史、不保存阅读位置——副作用仍由提交后的
 *   ContentDetailController.commitPreparedAnswer 负责。
 * - 必须使用调用方注入的独立 ContentRepository（独立 ZhihuHttpClient）：共享仓库是单实例单飞，
 *   预取会占住槽位并与前台详情互相 cancel。
 * - 并发 1；前台请求（手势/按钮触发的切换）插队到后台预取之前；缓存按 LRU 淘汰到容量上限。
 * - 账号、问题、排序变化时调用 reset()，迟到回包不再落入缓存。
 */
export class AnswerDetailPrefetcher {
  private readonly repository: ContentRepository;
  private readonly cache: Map<string, Answer> = new Map();
  private readonly inFlight: Map<string, Promise<Answer | undefined>> = new Map();
  private readonly queue: PrefetchQueueItem[] = [];
  private busy: boolean = false;
  private runningItem?: PrefetchQueueItem;
  private generation: number = 0;
  private disposed: boolean = false;
  private requestCount: number = 0;

  constructor(repository: ContentRepository) {
    this.repository = repository;
  }

  /** 已发出的实际请求数（测试与预算核对用；命中缓存不计）。 */
  requests(): number { return this.requestCount; }

  cacheSize(): number { return this.cache.size; }

  /** 同步命中：不发起请求，命中后提升为最近使用。 */
  peek(answerId: string): Answer | undefined {
    if (answerId.length === 0) { return undefined; }
    const cached = this.cache.get(answerId);
    if (cached === undefined) { return undefined; }
    this.cache.delete(answerId);
    this.cache.set(answerId, cached);
    return cached;
  }

  /** 请求全文：命中缓存直接返回；同一回答的重复请求复用同一在途任务。 */
  request(answerId: string, foreground: boolean): Promise<Answer | undefined> {
    if (this.disposed || answerId.length === 0) { return Promise.resolve(undefined); }
    const cached = this.peek(answerId);
    if (cached !== undefined) { return Promise.resolve(cached); }
    const running = this.inFlight.get(answerId);
    if (running !== undefined) {
      // 后台排队任务被前台需要时提升优先级，同时继续复用同一 promise。
      const index = this.queue.findIndex((item: PrefetchQueueItem): boolean => item.answerId === answerId);
      if (foreground && index >= 0) {
        const item = this.queue.splice(index, 1)[0];
        item.foreground = true;
        this.queue.unshift(item);
      }
      return running;
    }
    const promise: Promise<Answer | undefined> = new Promise<Answer | undefined>(
      (resolve: (answer: Answer | undefined) => void): void => {
        const item: PrefetchQueueItem = { answerId: answerId, foreground: foreground, resolve: resolve };
        if (foreground) {
          let index = -1;
          for (let i = 0; i < this.queue.length; i++) {
            if (!this.queue[i].foreground) { index = i; break; }
          }
          if (index < 0) { this.queue.push(item); } else { this.queue.splice(index, 0, item); }
        } else {
          this.queue.push(item);
        }
      });
    this.inFlight.set(answerId, promise);
    this.pump();
    const clear = (): void => {
      if (this.inFlight.get(answerId) === promise) { this.inFlight.delete(answerId); }
    };
    promise.then(clear, clear);
    return promise;
  }

  /** 提交后当前答不再需要预取副本。 */
  forget(answerId: string): void {
    this.cache.delete(answerId);
  }

  /** 账号/问题/排序变化：作废缓存与在途结果，取消已发出的预取请求。 */
  reset(): void {
    this.generation += 1;
    this.cache.clear();
    this.inFlight.clear();
    this.runningItem?.resolve(undefined);
    const queued = this.queue.splice(0, this.queue.length);
    for (let index = 0; index < queued.length; index++) {
      queued[index].resolve(undefined);
    }
    this.repository.cancel();
  }

  dispose(): void {
    if (this.disposed) { return; }
    this.reset();
    this.disposed = true;
  }

  private pump(): void {
    if (this.busy || this.disposed) { return; }
    const item = this.queue.shift();
    if (item === undefined) { return; }
    this.busy = true;
    this.runningItem = item;
    this.requestCount += 1;
    const generation = this.generation;
    Promise.resolve().then((): Promise<Answer> => {
      if (this.disposed || generation !== this.generation) { return Promise.reject(new Error('prefetch reset')); }
      return this.repository.getAnswer(item.answerId);
    })
      .then((answer: Answer): void => {
        if (this.disposed || generation !== this.generation) {
          item.resolve(undefined);
          return;
        }
        if (answer.id !== item.answerId) { item.resolve(undefined); return; }
        this.store(answer);
        item.resolve(answer);
      })
      .catch((_error: Object): void => {
        item.resolve(undefined);
      })
      .then((): void => {
        this.runningItem = undefined;
        this.busy = false;
        this.pump();
      });
  }

  private store(answer: Answer): void {
    if (answer.id.length === 0) { return; }
    this.cache.delete(answer.id);
    this.cache.set(answer.id, answer);
    while (this.cache.size > ANSWER_PREFETCH_CAPACITY) {
      const keys: string[] = Array.from(this.cache.keys());
      if (keys.length === 0) { break; }
      this.cache.delete(keys[0]);
    }
  }
}
