import { describe, expect, it } from '@ohos/hypium';
import { LinkCardMeta, LinkCardMetaRepository, LinkCardResourceKind } from 'data';
import { LinkCardMetaLoader } from '../main/ets/pages/ReaderBlockView';

/** 脚本化假仓库：按 URL 返回预置结果/失败，并记录调用顺序（串行性断言依据）。 */
class FakeLinkCardMetaRepository implements LinkCardMetaRepository {
  readonly calls: Array<string> = [];
  private readonly responses: Map<string, LinkCardMeta | undefined> = new Map();
  private readonly failures: Set<string> = new Set();
  private readonly delays: Map<string, number> = new Map();

  respond(url: string, meta: LinkCardMeta | undefined): void {
    this.responses.set(url, meta);
  }

  fail(url: string): void {
    this.failures.add(url);
  }

  delay(url: string, milliseconds: number): void {
    this.delays.set(url, milliseconds);
  }

  getMeta(url: string): Promise<LinkCardMeta | undefined> {
    this.calls.push(url);
    const delay = this.delays.get(url) ?? 0;
    const milliseconds = Date.now() + delay;
    if (this.failures.has(url)) {
      return new Promise<LinkCardMeta | undefined>((_resolve: (value: LinkCardMeta | undefined) => void,
        reject: (error: Error) => void): void => {
        setTimeout((): void => {
          reject(new Error(`forced failure for ${url}`));
        }, Math.max(0, milliseconds - Date.now()));
      });
    }
    return new Promise<LinkCardMeta | undefined>((resolve: (value: LinkCardMeta | undefined) => void): void => {
      setTimeout((): void => {
        resolve(this.responses.get(url));
      }, Math.max(0, milliseconds - Date.now()));
    });
  }
}

function answerMeta(voteupCount: number): LinkCardMeta {
  return { kind: LinkCardResourceKind.ANSWER, voteupCount: voteupCount, commentCount: 3 };
}

async function waitUntil(condition: () => boolean, timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (condition()) {
      return true;
    }
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 10);
    });
  }
  return condition();
}

export default function linkCardMetaLoaderTest(): void {
  describe('linkCardMetaLoaderTest', () => {
    it('loadsRegisteredUrlsSequentiallyInOrder', 0, async (): Promise<void> => {
      const repository = new FakeLinkCardMetaRepository();
      repository.respond('https://www.zhihu.com/question/1/answer/1', answerMeta(10));
      repository.respond('https://www.zhihu.com/question/1/answer/2', answerMeta(20));
      repository.respond('https://www.zhihu.com/question/1/answer/3', answerMeta(30));
      const loader = new LinkCardMetaLoader(repository);
      const updates: Array<string> = [];
      loader.onUpdate = (url: string, _meta: LinkCardMeta): void => {
        updates.push(url);
      };
      loader.load(['https://www.zhihu.com/question/1/answer/1',
        'https://www.zhihu.com/question/1/answer/2', 'https://www.zhihu.com/question/1/answer/3']);
      const done = await waitUntil((): boolean => updates.length === 3, 3000);
      expect(done).assertTrue();
      // ZhihuHttpClient 单飞设计要求串行：调用顺序必须与登记顺序一致，且不并发。
      expect(repository.calls[0]).assertEqual('https://www.zhihu.com/question/1/answer/1');
      expect(repository.calls[1]).assertEqual('https://www.zhihu.com/question/1/answer/2');
      expect(repository.calls[2]).assertEqual('https://www.zhihu.com/question/1/answer/3');
      expect(repository.calls.length).assertEqual(3);
      loader.dispose();
    });

    it('deduplicatesScheduledAndLoadedUrls', 0, async (): Promise<void> => {
      const repository = new FakeLinkCardMetaRepository();
      repository.respond('https://www.zhihu.com/question/1/answer/1', answerMeta(10));
      const loader = new LinkCardMetaLoader(repository);
      const updates: Array<string> = [];
      loader.onUpdate = (url: string, _meta: LinkCardMeta): void => {
        updates.push(url);
      };
      const url = 'https://www.zhihu.com/question/1/answer/1';
      loader.load([url]);
      await waitUntil((): boolean => updates.length === 1, 3000);
      loader.load([url, url]);
      loader.load([url]);
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 50);
      });
      // 已加载 URL 不再重复请求（淘汰回看重新登记时避免重复拉取）。
      expect(repository.calls.length).assertEqual(1);
      loader.dispose();
    });

    it('keepsLoadingFollowingUrlsAfterFailure', 0, async (): Promise<void> => {
      const repository = new FakeLinkCardMetaRepository();
      repository.fail('https://www.zhihu.com/question/1/answer/1');
      repository.respond('https://www.zhihu.com/question/1/answer/2', answerMeta(20));
      const loader = new LinkCardMetaLoader(repository);
      const updates: Array<string> = [];
      loader.onUpdate = (url: string, _meta: LinkCardMeta): void => {
        updates.push(url);
      };
      loader.load(['https://www.zhihu.com/question/1/answer/1', 'https://www.zhihu.com/question/1/answer/2']);
      const done = await waitUntil((): boolean => repository.calls.length === 2 &&
        updates.length === 1, 3000);
      expect(done).assertTrue();
      // 单卡失败不阻塞后续卡片；失败卡不产生回填。
      expect(updates.length).assertEqual(1);
      expect(updates[0]).assertEqual('https://www.zhihu.com/question/1/answer/2');
      loader.dispose();
    });

    it('disposeDiscardsQueueAndLateResponses', 0, async (): Promise<void> => {
      const repository = new FakeLinkCardMetaRepository();
      repository.respond('https://www.zhihu.com/question/1/answer/1', answerMeta(10));
      repository.delay('https://www.zhihu.com/question/1/answer/1', 120);
      repository.respond('https://www.zhihu.com/question/1/answer/2', answerMeta(20));
      const loader = new LinkCardMetaLoader(repository);
      const updates: Array<string> = [];
      loader.onUpdate = (url: string, _meta: LinkCardMeta): void => {
        updates.push(url);
      };
      loader.load(['https://www.zhihu.com/question/1/answer/1', 'https://www.zhihu.com/question/1/answer/2']);
      loader.dispose();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 250);
      });
      // 销毁后迟到回包不再回填，排队 URL 不再发起请求（对齐组件销毁语义）。
      expect(updates.length).assertEqual(0);
      expect(repository.calls.length).assertEqual(1);
    });

    it('skipsUndefinedMetaWithoutBlockingQueue', 0, async (): Promise<void> => {
      const repository = new FakeLinkCardMetaRepository();
      // 非站内资源返回 undefined：静默跳过并继续后续卡片。
      repository.respond('https://example.com/external', undefined);
      repository.respond('https://www.zhihu.com/question/1/answer/2', answerMeta(20));
      const loader = new LinkCardMetaLoader(repository);
      const updates: Array<string> = [];
      loader.onUpdate = (url: string, _meta: LinkCardMeta): void => {
        updates.push(url);
      };
      loader.load(['https://example.com/external', 'https://www.zhihu.com/question/1/answer/2']);
      const done = await waitUntil((): boolean => updates.length === 1, 3000);
      expect(done).assertTrue();
      expect(updates[0]).assertEqual('https://www.zhihu.com/question/1/answer/2');
      loader.dispose();
    });
  });
}
