import { describe, expect, it } from '@ohos/hypium';
import {
  OpenedContent,
  ReadHistoryGateway
} from 'data';
import {
  decodeReadHistoryItem,
  ReadHistoryContentKind,
  ReadHistoryController,
  readHistoryKindLabel,
  readHistoryOpenTarget,
  ReadHistoryPhase
} from '../main/ets/pages/ReadHistoryState';

class FakeReadHistory implements ReadHistoryGateway {
  items: Array<OpenedContent> = [];
  fail: boolean = false;
  clearCount: number = 0;

  queryRecent(_limit?: number): Promise<Array<OpenedContent>> {
    if (this.fail) {
      return Promise.reject(new Error('database path and record value'));
    }
    return Promise.resolve(this.items.slice());
  }

  delete(contentKey: string): Promise<boolean> {
    const before = this.items.length;
    this.items = this.items.filter((item: OpenedContent): boolean => item.contentKey !== contentKey);
    return Promise.resolve(before !== this.items.length);
  }

  clear(): Promise<void> {
    this.clearCount += 1;
    this.items = [];
    return Promise.resolve();
  }
}

export default function readHistoryStateTest(): void {
  describe('readHistoryStateTest', () => {
    it('decodesOnlyStrictSupportedTypeAndDecimalIdPairs', 0, () => {
      const valid = decodeReadHistoryItem({ contentKey: 'answer:123', contentType: 'answer', openedAt: 1 });
      expect(valid?.kind).assertEqual(ReadHistoryContentKind.ANSWER);
      expect(valid?.id).assertEqual('123');
      expect(decodeReadHistoryItem({ contentKey: 'answer:../123', contentType: 'answer', openedAt: 1 }))
        .assertUndefined();
      expect(decodeReadHistoryItem({ contentKey: 'answer:123', contentType: 'article', openedAt: 1 }))
        .assertUndefined();
      expect(decodeReadHistoryItem({ contentKey: 'video:123', contentType: 'video', openedAt: 1 }))
        .assertUndefined();
      const pin = decodeReadHistoryItem({ contentKey: 'pin:456', contentType: 'pin', openedAt: 2 });
      expect(pin?.kind).assertEqual(ReadHistoryContentKind.PIN);
      expect(pin?.id).assertEqual('456');
      if (pin !== undefined) {
        expect(readHistoryKindLabel(pin.kind)).assertEqual('想法');
        const target = readHistoryOpenTarget(pin);
        expect(target.kind).assertEqual(ReadHistoryContentKind.PIN);
        expect(target.id).assertEqual('456');
      }
      expect(decodeReadHistoryItem({ contentKey: 'pin:0', contentType: 'pin', openedAt: 2 }))
        .assertUndefined();
    });

    it('filtersCorruptRowsAndPublishesReadyHistory', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'article:3', contentType: 'article', openedAt: 30 },
        { contentKey: 'bad', contentType: 'answer', openedAt: 20 }
      ];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().items[0].contentKey).assertEqual('article:3');
    });

    it('deletesOneRecordAndClearsAllWithReloadedState', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'question:1', contentType: 'question', openedAt: 20 },
        { contentKey: 'answer:2', contentType: 'answer', openedAt: 10 },
        { contentKey: 'pin:3', contentType: 'pin', openedAt: 5 }
      ];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      await controller.delete('pin:3');
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().items.some((item): boolean => item.kind === ReadHistoryContentKind.PIN))
        .assertFalse();
      await controller.clear();
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.EMPTY);
      expect(history.clearCount).assertEqual(1);
    });

    it('usesFixedReadErrorWithoutLeakingStoredValues', 0, async () => {
      const history = new FakeReadHistory();
      history.fail = true;
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.ERROR);
      expect(controller.snapshot().message).assertEqual('已读记录读取失败，请重试');
      expect(controller.snapshot().message.includes('record value')).assertFalse();
    });

    it('ignoresMutationsAfterDeactivation', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 1 }];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      controller.deactivate();
      await controller.clear();
      expect(history.clearCount).assertEqual(0);
      expect(history.items.length).assertEqual(1);
    });
  });
}
