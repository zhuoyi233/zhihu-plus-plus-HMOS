import { describe, expect, it } from '@ohos/hypium';
import {
  DailyStoryPayload,
  DailyStoryRepository,
  DailyStoryRepositoryFailure,
  DailyStoryRepositoryFailureKind,
  HttpFailure,
  HttpFailureKind
} from 'data';
import { AppDestination } from 'core';
import {
  DailyStoryDetailController,
  DailyStoryDetailPhase,
  DailyStoryViewState
} from '../main/ets/pages/DailyStoryDetailState';
import { ReaderBlock, ReaderBlockKind } from 'reader';

interface PendingDailyStoryRequest {
  resolve: (payload: DailyStoryPayload) => void;
  reject: (error: Object) => void;
}

class ControlledDailyStoryRepository implements DailyStoryRepository {
  readonly pending: Array<PendingDailyStoryRequest> = [];
  cancelCount: number = 0;
  storyRequestCount: number = 0;
  destinationRequestCount: number = 0;
  failure?: Error | HttpFailure | DailyStoryRepositoryFailure;

  getStory(_storyId: string): Promise<DailyStoryPayload> {
    this.storyRequestCount += 1;
    if (this.failure !== undefined) {
      const failure = this.failure;
      return Promise.reject(failure);
    }
    return new Promise<DailyStoryPayload>((resolve: (payload: DailyStoryPayload) => void,
      reject: (error: Object) => void): void => {
      this.pending.push({ resolve: resolve, reject: reject });
    });
  }

  getDestination(_storyId: string): Promise<AppDestination | undefined> {
    this.destinationRequestCount += 1;
    return Promise.resolve(undefined);
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

function payload(bodyHtml: string, storyId: string = '1'): DailyStoryPayload {
  return {
    id: storyId,
    title: '日报标题',
    bodyHtml: bodyHtml,
    imageUrl: 'https://pic1.zhimg.com/v2-head.jpg',
    imageUrls: ['https://pic1.zhimg.com/v2-head.jpg'],
    rawType: 0,
    shareUrl: `https://daily.zhihu.com/story/${storyId}`,
    responseUrl: 'https://daily.zhihu.com/story/1',
    publishTimeSeconds: 0
  };
}

const ANSWER_BODY = '<div class="content-inner"><div class="question">' +
  '<h2 class="question-title">问题</h2><div class="answer">' +
  '<div class="meta"><img class="avatar" src="https://picx.zhimg.com/a.jpg"><span class="author">作者</span></div>' +
  '<div class="content"><p>回答正文</p></div></div></div></div>';

export default function dailyStoryDetailStateTest(): void {
  describe('dailyStoryDetailStateTest', () => {
    it('loadsPayloadOnceAndEmitsReadyWithBlocks', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const states: Array<DailyStoryViewState> = [];
      const controller = new DailyStoryDetailController(repository,
        (state: DailyStoryViewState): void => {
          states.push(state);
        });
      controller.activate();
      const pending = controller.load('1');
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.LOADING);
      repository.pending[0].resolve(payload(ANSWER_BODY));
      await pending;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.READY);
      expect(controller.snapshot().payload?.title).assertEqual('日报标题');
      expect(states[states.length - 1].phase).assertEqual(DailyStoryDetailPhase.READY);
      // 一次打开只发一次正文请求：不额外调用旧 getDestination 契约。
      expect(repository.storyRequestCount).assertEqual(1);
      expect(repository.destinationRequestCount).assertEqual(0);
      const blocks: Array<ReaderBlock> = controller.snapshot().blocks;
      expect(blocks.some((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.PARAGRAPH &&
        block.text === '回答正文')).assertTrue();
      // 作者头像不进正文图集。
      expect(blocks.some((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.IMAGE)).assertFalse();
    });

    it('reportsUnsupportedForEmptyBodyWithoutFabricatingContent', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const controller = new DailyStoryDetailController(repository);
      controller.activate();
      const pending = controller.load('1');
      repository.pending[0].resolve(payload(''));
      await pending;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.UNSUPPORTED);
      expect(controller.snapshot().blocks.length).assertEqual(0);
      expect(controller.snapshot().webUrl).assertEqual('https://daily.zhihu.com/story/1');
    });

    it('reportsPartialForUnsupportedElementsButKeepsReadableContent', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const controller = new DailyStoryDetailController(repository);
      controller.activate();
      const pending = controller.load('1');
      repository.pending[0].resolve(payload(
        '<div class="content"><table><tr><td>表格</td></tr></table><p>仍可读</p></div>'));
      await pending;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.PARTIAL);
      expect(controller.snapshot().blocks.some((block: ReaderBlock): boolean => block.text === '仍可读'))
        .assertTrue();
      expect(controller.snapshot().errorMessage === undefined).assertTrue();
    });

    it('mapsNetworkAndInvalidIdErrorsToSafeMessages', 0, async () => {
      const networkRepository = new ControlledDailyStoryRepository();
      networkRepository.failure = new HttpFailure(HttpFailureKind.NETWORK);
      const networkController = new DailyStoryDetailController(networkRepository);
      networkController.activate();
      await networkController.load('1');
      expect(networkController.snapshot().phase).assertEqual(DailyStoryDetailPhase.ERROR);
      expect(networkController.snapshot().errorMessage).assertEqual('网络连接失败，请检查网络后重试');

      const idRepository = new ControlledDailyStoryRepository();
      idRepository.failure = new DailyStoryRepositoryFailure(DailyStoryRepositoryFailureKind.INVALID_ID);
      const idController = new DailyStoryDetailController(idRepository);
      idController.activate();
      await idController.load('../1');
      expect(idController.snapshot().errorMessage).assertEqual('日报 ID 无效，无法加载正文');
    });

    it('cancelsAndDiscardsSupersededResults', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const controller = new DailyStoryDetailController(repository);
      controller.activate();
      const first = controller.load('1');
      const second = controller.load('2');
      expect(repository.cancelCount).assertEqual(1);
      // 旧请求后到（A/B 乱序）：必须被丢弃，不能覆盖新正文。
      repository.pending[1].resolve(payload('<div class="content"><p>第二个</p></div>', '2'));
      repository.pending[0].resolve(payload('<div class="content"><p>第一个</p></div>', '1'));
      await first;
      await second;
      expect(controller.snapshot().storyId).assertEqual('2');
      expect(controller.snapshot().blocks[0].text).assertEqual('第二个');
    });

    it('deactivatesWithoutPublishingLateResults', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      let emissions: number = 0;
      const controller = new DailyStoryDetailController(repository, (_state: DailyStoryViewState): void => {
        emissions += 1;
      });
      controller.activate();
      const pending = controller.load('1');
      controller.deactivate();
      repository.pending[0].resolve(payload(ANSWER_BODY));
      await pending;
      expect(repository.cancelCount).assertEqual(1);
      // activate + LOADING 两次；离页后的结果不再发回调。
      expect(emissions).assertEqual(2);
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.LOADING);
    });

    it('retriesWithFreshGenerationAfterError', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const controller = new DailyStoryDetailController(repository);
      controller.activate();
      const first = controller.load('1');
      repository.pending[0].reject(new HttpFailure(HttpFailureKind.SERVER));
      await first;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.ERROR);
      const second = controller.load('1');
      repository.pending[1].resolve(payload(ANSWER_BODY));
      await second;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.READY);
      expect(repository.storyRequestCount).assertEqual(2);
    });

    it('keepsCanonicalWebUrlEvenWhenPayloadUrlDiffers', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const controller = new DailyStoryDetailController(repository);
      controller.activate();
      const pending = controller.load('9793572');
      const hostile: DailyStoryPayload = {
        id: '9793572',
        title: '标题',
        bodyHtml: '<div class="content"><p>正文</p></div>',
        imageUrl: '',
        imageUrls: [],
        rawType: 0,
        // 响应里的 url 不可信：分享/回退只能使用规范地址。
        shareUrl: 'https://daily.zhihu.com/story/9793572',
        responseUrl: 'https://evil.example/story/9793572',
        publishTimeSeconds: 0
      };
      repository.pending[0].resolve(hostile);
      await pending;
      expect(controller.snapshot().webUrl).assertEqual('https://daily.zhihu.com/story/9793572');
      expect(controller.snapshot().webUrl.includes('evil.example')).assertFalse();
    });
  });
}
