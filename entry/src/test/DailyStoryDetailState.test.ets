import { describe, expect, it } from '@ohos/hypium';
import {
  DailyStoryRepository,
  DailyStoryRepositoryFailure,
  DailyStoryRepositoryFailureKind,
  HttpFailure,
  HttpFailureKind
} from 'data';
import { P1Destination, P1DestinationName } from 'core';
import {
  DailyStoryDetailController,
  DailyStoryDetailPhase,
  DailyStoryDetailViewState
} from '../main/ets/pages/DailyStoryDetailState';

interface PendingDailyStoryRequest {
  resolve: (destination: P1Destination | undefined) => void;
}

class ControlledDailyStoryRepository implements DailyStoryRepository {
  readonly pending: Array<PendingDailyStoryRequest> = [];
  cancelCount: number = 0;
  failure?: Error;

  getDestination(_storyId: string): Promise<P1Destination | undefined> {
    if (this.failure !== undefined) {
      return Promise.reject(this.failure);
    }
    return new Promise<P1Destination | undefined>((resolve: (destination: P1Destination | undefined) => void): void => {
      this.pending.push({ resolve: resolve });
    });
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

export default function dailyStoryDetailStateTest(): void {
  describe('dailyStoryDetailStateTest', () => {
    it('loadsNativeDestinationAndEmitsReady', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const states: Array<DailyStoryDetailViewState> = [];
      const controller = new DailyStoryDetailController(repository,
        (state: DailyStoryDetailViewState): void => states.push(state));
      controller.activate();
      const pending = controller.load('1');
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.LOADING);
      repository.pending[0].resolve({ name: P1DestinationName.ARTICLE, id: '2' });
      await pending;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.READY);
      expect(controller.snapshot().destination?.name).assertEqual(P1DestinationName.ARTICLE);
      expect(states[states.length - 1].phase).assertEqual(DailyStoryDetailPhase.READY);
    });

    it('reportsUnsupportedDailyContentWithoutExternalFallback', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      const controller = new DailyStoryDetailController(repository);
      controller.activate();
      const pending = controller.load('1');
      repository.pending[0].resolve(undefined);
      await pending;
      expect(controller.snapshot().phase).assertEqual(DailyStoryDetailPhase.ERROR);
      expect(controller.snapshot().errorMessage).assertEqual('该日报暂不支持原生阅读');
    });

    it('mapsNetworkAndInvalidIdErrorsToSafeMessages', 0, async () => {
      const networkRepository = new ControlledDailyStoryRepository();
      networkRepository.failure = new HttpFailure(HttpFailureKind.NETWORK);
      const networkController = new DailyStoryDetailController(networkRepository);
      networkController.activate();
      await networkController.load('1');
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
      repository.pending[0].resolve({ name: P1DestinationName.QUESTION, id: '1' });
      repository.pending[1].resolve({ name: P1DestinationName.ANSWER, id: '2' });
      await first;
      await second;
      expect(controller.snapshot().destination?.name).assertEqual(P1DestinationName.ANSWER);
    });

    it('deactivatesWithoutPublishingLateResults', 0, async () => {
      const repository = new ControlledDailyStoryRepository();
      let emissions: number = 0;
      const controller = new DailyStoryDetailController(repository, (_state: DailyStoryDetailViewState): void => {
        emissions += 1;
      });
      controller.activate();
      const pending = controller.load('1');
      controller.deactivate();
      repository.pending[0].resolve({ name: P1DestinationName.QUESTION, id: '1' });
      await pending;
      expect(repository.cancelCount).assertEqual(1);
      expect(emissions).assertEqual(2);
    });
  });
}
