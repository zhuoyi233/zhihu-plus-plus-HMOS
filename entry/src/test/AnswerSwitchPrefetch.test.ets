import { describe, expect, it } from '@ohos/hypium';
import { Answer, Article, ContentRepository, Question } from 'data';
import { ANSWER_PREFETCH_CAPACITY, AnswerDetailPrefetcher } from '../main/ets/pages/AnswerSwitchPrefetch';

interface PendingAnswerRequest {
  readonly answerId: string;
  readonly resolve: (answer: Answer) => void;
  readonly reject: (error: Error) => void;
}

/** 手动控制完成时机的详情仓库：用于核对并发、去重与优先级。 */
class ControlledAnswerRepository implements ContentRepository {
  readonly pending: PendingAnswerRequest[] = [];
  readonly requested: string[] = [];
  inFlight: number = 0;
  maxInFlight: number = 0;
  cancelCount: number = 0;

  getQuestion(_id: string): Promise<Question> {
    return Promise.reject(new Error('unused'));
  }

  getArticle(_id: string): Promise<Article> {
    return Promise.reject(new Error('unused'));
  }

  getAnswer(id: string): Promise<Answer> {
    this.requested.push(id);
    this.inFlight += 1;
    this.maxInFlight = Math.max(this.maxInFlight, this.inFlight);
    return new Promise<Answer>((resolve: (answer: Answer) => void,
      reject: (error: Error) => void): void => {
      this.pending.push({ answerId: id, resolve: resolve, reject: reject });
    });
  }

  cancel(): void {
    this.cancelCount += 1;
  }

  resolveNext(): void {
    const item = this.pending.shift();
    if (item === undefined) { return; }
    this.inFlight -= 1;
    item.resolve(answerFixture(item.answerId));
  }

  rejectNext(): void {
    const item = this.pending.shift();
    if (item === undefined) { return; }
    this.inFlight -= 1;
    item.reject(new Error('network'));
  }
}

function answerFixture(id: string): Answer {
  return {
    id: id,
    questionId: 'q1',
    questionTitle: '问题',
    contentHtml: `<p>${id}</p>`,
    excerpt: '摘要',
    url: '',
    voteupCount: 1,
    commentCount: 2,
    createdAt: 1,
    updatedAt: 2
  };
}

function tick(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 0);
  });
}

export default function answerSwitchPrefetchTest(): void {
  describe('answerSwitchPrefetchTest', () => {
    it('reusesInFlightAndServesLaterRequestsFromCache', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const first = prefetcher.request('2', false);
      const second = prefetcher.request('2', false);
      await tick();
      // 同一回答的重复请求复用同一在途任务，不重复占用单飞槽位。
      expect(repository.requested.length).assertEqual(1);
      repository.resolveNext();
      await tick();
      const firstAnswer = await first;
      const secondAnswer = await second;
      expect(firstAnswer?.id).assertEqual('2');
      expect(secondAnswer?.id).assertEqual('2');
      // 缓存命中不再发请求。
      const cached = await prefetcher.request('2', true);
      expect(cached?.id).assertEqual('2');
      expect(repository.requested.length).assertEqual(1);
      prefetcher.dispose();
    });

    it('keepsSingleRequestInFlightAndEvictsBeyondCapacity', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const ids: string[] = ['2', '3', '4', '5'];
      const requests: Array<Promise<Answer | undefined>> = ids.map(
        (id: string): Promise<Answer | undefined> => prefetcher.request(id, false));
      await tick();
      // 并发 1：先发首条，其余排队。
      expect(repository.requested.length).assertEqual(1);
      for (let index = 0; index < ids.length; index++) {
        repository.resolveNext();
        await tick();
      }
      for (let index = 0; index < requests.length; index++) {
        expect((await requests[index])?.id).assertEqual(ids[index]);
      }
      expect(repository.maxInFlight).assertEqual(1);
      expect(prefetcher.cacheSize()).assertEqual(ANSWER_PREFETCH_CAPACITY);
      // 最早的条目已被淘汰，最后一份仍在。
      expect(prefetcher.peek('2')).assertUndefined();
      expect(prefetcher.peek('5')?.id).assertEqual('5');
      prefetcher.dispose();
    });

    it('servesForegroundBeforeQueuedBackgroundPrefetch', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const backgroundAhead = prefetcher.request('2', false);
      const backgroundBehind = prefetcher.request('3', false);
      await tick();
      const foreground = prefetcher.request('4', true);
      await tick();
      expect(repository.requested[0]).assertEqual('2');
      repository.resolveNext();
      await tick();
      // 前台请求插队到仍在排队的后台预取之前。
      expect(repository.requested[1]).assertEqual('4');
      repository.resolveNext();
      await tick();
      repository.resolveNext();
      await tick();
      expect((await backgroundAhead)?.id).assertEqual('2');
      expect((await foreground)?.id).assertEqual('4');
      expect((await backgroundBehind)?.id).assertEqual('3');
      prefetcher.dispose();
    });

    it('resolvesFailuresAsUndefinedWithoutCaching', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const failed = prefetcher.request('2', false);
      await tick();
      repository.rejectNext();
      expect(await failed === undefined).assertTrue();
      expect(prefetcher.peek('2')).assertUndefined();
      const retried = prefetcher.request('2', false);
      await tick();
      expect(repository.requested.length).assertEqual(2);
      repository.resolveNext();
      expect((await retried)?.id).assertEqual('2');
      prefetcher.dispose();
    });

    it('resetDropsCacheAndLateResults', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const pending = prefetcher.request('2', false);
      await tick();
      prefetcher.reset();
      expect(repository.cancelCount).assertEqual(1);
      repository.resolveNext();
      // 账号/问题变化后迟到的结果既不入缓存也不返回给调用方。
      expect(await pending === undefined).assertTrue();
      expect(prefetcher.peek('2')).assertUndefined();
      expect(prefetcher.cacheSize()).assertEqual(0);
      prefetcher.dispose();
    });

    it('promotesQueuedDuplicateWithoutStartingAnotherRequest', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const first = prefetcher.request('2', false);
      const background = prefetcher.request('3', false);
      const target = prefetcher.request('4', false);
      const foreground = prefetcher.request('4', true);
      expect(target === foreground).assertTrue();
      await tick();
      repository.resolveNext(); await tick();
      expect(repository.requested[1]).assertEqual('4');
      repository.resolveNext(); await tick();
      expect(repository.requested[2]).assertEqual('3');
      repository.resolveNext();
      await Promise.all([first, background, target, foreground]);
      expect(repository.maxInFlight).assertEqual(1);
      prefetcher.dispose();
    });

    it('resetDoesNotLetOldCompletionEraseSameIdNewTask', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const old = prefetcher.request('2', false); await tick();
      prefetcher.reset();
      expect(await old === undefined).assertTrue();
      const fresh = prefetcher.request('2', true);
      repository.resolveNext(); await tick();
      expect(prefetcher.request('2', true) === fresh).assertTrue();
      expect(repository.requested.length).assertEqual(2);
      expect(prefetcher.peek('2')).assertUndefined();
      repository.resolveNext();
      expect((await fresh)?.id).assertEqual('2');
      expect(repository.maxInFlight).assertEqual(1);
      prefetcher.dispose();
    });

    it('resetBeforeDispatchDoesNotSendObsoleteRequest', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      const old = prefetcher.request('2', false);
      const queued = prefetcher.request('3', false);
      prefetcher.reset();
      expect(await old === undefined).assertTrue();
      expect(await queued === undefined).assertTrue();
      await tick();
      expect(repository.requested.length).assertEqual(0);
      const fresh = prefetcher.request('4', true); await tick();
      repository.resolveNext();
      expect((await fresh)?.id).assertEqual('4');
      prefetcher.dispose();
    });

    it('disposeIsIdempotentAndRejectsFurtherRequests', 0, async () => {
      const repository = new ControlledAnswerRepository();
      const prefetcher = new AnswerDetailPrefetcher(repository);
      prefetcher.dispose();
      prefetcher.dispose();
      expect(await prefetcher.request('2', true) === undefined).assertTrue();
      expect(repository.requested.length).assertEqual(0);
    });
  });
}
