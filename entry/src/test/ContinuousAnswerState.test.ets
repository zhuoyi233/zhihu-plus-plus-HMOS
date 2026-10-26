import { describe, expect, it } from '@ohos/hypium';
import { Answer } from 'data';
import {
  ContinuousFullTextRecord,
  ContinuousFullTextScheduler,
  ContinuousFullTextSource
} from '../main/ets/pages/ContinuousAnswerState';

/** 可手动控制解析时机的桩来源：记录调用序并挂起 Promise 供测试驱动。 */
class DeferredSource implements ContinuousFullTextSource {
  readonly calls: Array<string> = [];
  private readonly resolvers: Map<string, Array<(answer: Answer) => void>> = new Map();
  private readonly rejecters: Map<string, Array<(error: Error) => void>> = new Map();

  getAnswer(answerId: string): Promise<Answer> {
    this.calls.push(answerId);
    return new Promise<Answer>((resolve, reject) => {
      const resolvers = this.resolvers.get(answerId) ?? [];
      resolvers.push(resolve);
      this.resolvers.set(answerId, resolvers);
      const rejecters = this.rejecters.get(answerId) ?? [];
      rejecters.push(reject);
      this.rejecters.set(answerId, rejecters);
    });
  }

  resolve(answerId: string): void {
    (this.resolvers.get(answerId) ?? []).forEach((resolve: (answer: Answer) => void): void => {
      resolve(fixtureAnswer(answerId));
    });
    this.resolvers.delete(answerId);
  }

  reject(answerId: string, message: string): void {
    (this.rejecters.get(answerId) ?? []).forEach((reject: (error: Error) => void): void => {
      reject(new Error(message));
    });
    this.rejecters.delete(answerId);
  }

  totalCalls(): number {
    return this.calls.length;
  }
}

function fixtureAnswer(answerId: string): Answer {
  return {
    id: answerId,
    questionId: '1',
    contentHtml: `<p>正文 ${answerId}</p>`,
    excerpt: `摘要 ${answerId}`,
    url: `https://www.zhihu.com/question/1/answer/${answerId}`,
    voteupCount: 10,
    commentCount: 2,
    createdAt: 1700000000,
    updatedAt: 1700000000
  };
}

/** 宏任务 flush：保证 fetch 的 await 续延与 finally pump 全部执行完。 */
function flush(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, 0);
  });
}

/** 双槽位调度器夹具：两个独立桩按槽轮转，快照记录到 lastSnapshot。 */
class SchedulerFixture {
  readonly sourceA: DeferredSource = new DeferredSource();
  readonly sourceB: DeferredSource = new DeferredSource();
  readonly scheduler: ContinuousFullTextScheduler;
  lastSnapshot: Array<ContinuousFullTextRecord> = [];

  constructor() {
    let rotate = false;
    const sourceA = this.sourceA;
    const sourceB = this.sourceB;
    const self = this;
    this.scheduler = new ContinuousFullTextScheduler((): ContinuousFullTextSource => {
      rotate = !rotate;
      return rotate ? sourceA : sourceB;
    }, 2, (snapshot: Array<ContinuousFullTextRecord>): void => {
      self.lastSnapshot = snapshot;
    });
  }

  totalCalls(): number {
    return this.sourceA.totalCalls() + this.sourceB.totalCalls();
  }

  phaseOf(answerId: string): string {
    return this.scheduler.record(answerId)?.phase ?? 'missing';
  }
}

export default function continuousAnswerStateTest(): void {
  describe('continuousAnswerStateTest', () => {
    it('ensureLaunchesUpToConcurrencyAndQueuesRest', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a', 'b', 'c']);
      expect(fixture.totalCalls()).assertEqual(2);
      expect(fixture.phaseOf('a')).assertEqual('loading');
      expect(fixture.phaseOf('b')).assertEqual('loading');
      expect(fixture.phaseOf('c')).assertEqual('pending');
      // 同 id 重复 ensure 不重复入队（在途去重）。
      fixture.scheduler.ensure(['a', 'b', 'c']);
      expect(fixture.totalCalls()).assertEqual(2);
      fixture.sourceA.resolve('a');
      await flush();
      // a 完成后 c 补位（fetch 的 finally pump 继续派发）。
      expect(fixture.totalCalls()).assertEqual(3);
      expect(fixture.phaseOf('a')).assertEqual('ready');
      expect(fixture.phaseOf('c')).assertEqual('loading');
    });

    it('evictDuringFlightDropsResult', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a']);
      fixture.scheduler.evict('a', 480);
      expect(fixture.phaseOf('a')).assertEqual('evicted');
      expect(fixture.scheduler.record('a')?.measuredHeightVp).assertEqual(480);
      fixture.sourceA.resolve('a');
      await flush();
      // 在途回包被淘汰语义丢弃：不复活为 ready。
      expect(fixture.phaseOf('a')).assertEqual('evicted');
    });

    it('retryAfterErrorAndSucceeds', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a']);
      fixture.sourceA.reject('a', '网络连接失败');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('error');
      // 失败原因经 contentDetailErrorMessage 映射为用户可读文案。
      expect((fixture.scheduler.record('a')?.errorMessage ?? '').length > 0).assertTrue();
      fixture.scheduler.retry('a');
      expect(fixture.phaseOf('a')).assertEqual('loading');
      // 槽位轮转：第二次请求可能落在另一个桩上，两桩都驱动以消除测试对轮转的依赖。
      fixture.sourceA.resolve('a');
      fixture.sourceB.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('ready');
      expect(fixture.scheduler.record('a')?.answer?.id).assertEqual('a');
    });

    it('deactivateStopsPumpButInFlightStillApplies', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a', 'b', 'c']);
      expect(fixture.totalCalls()).assertEqual(2);
      fixture.scheduler.deactivate();
      fixture.sourceA.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('ready');
      expect(fixture.totalCalls()).assertEqual(2);
      // deactivate 清空等待队列：重新激活后不自动恢复被丢弃的排队项，需重新 ensure。
      fixture.scheduler.activate();
      expect(fixture.totalCalls()).assertEqual(2);
      fixture.scheduler.ensure(['c']);
      expect(fixture.totalCalls()).assertEqual(3);
      expect(fixture.phaseOf('c')).assertEqual('loading');
    });

    it('restoreRefetchesEvictedAnswer', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a']);
      fixture.sourceA.resolve('a');
      fixture.sourceB.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('ready');
      fixture.scheduler.evict('a', 320);
      fixture.scheduler.restore('a');
      expect(fixture.phaseOf('a')).assertEqual('loading');
      expect(fixture.scheduler.record('a')?.measuredHeightVp).assertEqual(0);
      expect(fixture.totalCalls()).assertEqual(2);
      fixture.sourceA.resolve('a');
      fixture.sourceB.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('ready');
    });

    it('dropRemovesRecordAndCancelsQueue', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a', 'b', 'c']);
      expect(fixture.phaseOf('a')).assertEqual('loading');
      expect(fixture.phaseOf('b')).assertEqual('loading');
      expect(fixture.phaseOf('c')).assertEqual('pending');
      // 排队中的回答被屏蔽移除：清记录、退出排队，后续不再请求。
      fixture.scheduler.drop('c');
      expect(fixture.phaseOf('c')).assertEqual('missing');
      fixture.sourceA.resolve('a');
      fixture.sourceB.resolve('b');
      await flush();
      expect(fixture.totalCalls()).assertEqual(2);
      // 在途回包到达前被 drop：记录缺失，落账守卫直接丢弃。
      fixture.scheduler.ensure(['d']);
      expect(fixture.phaseOf('d')).assertEqual('loading');
      fixture.scheduler.drop('d');
      fixture.sourceA.resolve('d');
      fixture.sourceB.resolve('d');
      await flush();
      expect(fixture.phaseOf('d')).assertEqual('missing');
      expect(fixture.totalCalls()).assertEqual(3);
    });

    it('outOfOrderCompletionReusesOnlyTheIdleSource', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a', 'b', 'c', 'd']);
      fixture.sourceB.resolve('b');
      await flush();
      expect(fixture.sourceA.calls.join(',')).assertEqual('a');
      expect(fixture.sourceB.calls.join(',')).assertEqual('b,c');
      fixture.sourceB.resolve('c');
      await flush();
      expect(fixture.sourceA.calls.join(',')).assertEqual('a');
      expect(fixture.sourceB.calls.join(',')).assertEqual('b,c,d');
    });

    it('restoreBeforeOldRequestSettlesRefetchesWithoutAcceptingOldBody', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a']);
      fixture.scheduler.evict('a', 480);
      fixture.scheduler.restore('a');
      expect(fixture.phaseOf('a')).assertEqual('pending');
      fixture.sourceA.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('loading');
      expect(fixture.totalCalls()).assertEqual(2);
      fixture.sourceA.resolve('a');
      fixture.sourceB.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('ready');
    });

    it('dropAndRecreateDoesNotAcceptTheRemovedRequestsResult', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a']);
      fixture.scheduler.drop('a');
      fixture.scheduler.ensure(['a']);
      fixture.sourceA.reject('a', '旧会话错误');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('loading');
      expect(fixture.totalCalls()).assertEqual(2);
      fixture.sourceA.resolve('a');
      fixture.sourceB.resolve('a');
      await flush();
      expect(fixture.phaseOf('a')).assertEqual('ready');
    });

    it('visibleRequestMovesAheadOfQueuedPrefetch', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a', 'b', 'prefetch']);
      fixture.scheduler.ensure(['visible'], true);
      fixture.sourceB.resolve('b');
      await flush();
      expect(fixture.phaseOf('visible')).assertEqual('loading');
      expect(fixture.phaseOf('prefetch')).assertEqual('pending');
      expect(fixture.totalCalls()).assertEqual(3);
    });

    it('disposeDropsLateResultAndDoesNotNotifyOrStartQueuedRequests', 0, async () => {
      const fixture = new SchedulerFixture();
      fixture.scheduler.activate();
      fixture.scheduler.ensure(['a', 'b', 'c']);
      const previous = fixture.lastSnapshot;
      fixture.scheduler.dispose();
      fixture.sourceA.resolve('a');
      fixture.sourceB.reject('b', '离页后失败');
      await flush();
      expect(fixture.lastSnapshot === previous).assertTrue();
      expect(fixture.scheduler.snapshot().length).assertEqual(0);
      expect(fixture.totalCalls()).assertEqual(2);
    });
  });
}
