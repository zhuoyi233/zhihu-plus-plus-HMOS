import { describe, expect, it } from '@ohos/hypium';
import {
  BlockedFeedHistoryGateway,
  BlockedFeedRecord,
  BlockedFeedRecordInput,
  BlockingRuleKind
} from 'data';
import {
  BlockedFeedHistoryController,
  BlockedFeedHistoryPhase,
  blockedFeedHistoryItemLabel
} from '../main/ets/pages/BlockedFeedHistoryState';

class FakeHistory implements BlockedFeedHistoryGateway {
  records: Array<BlockedFeedRecord> = [];
  fail: boolean = false;

  queryRecent(_limit?: number): Promise<Array<BlockedFeedRecord>> {
    if (this.fail) {
      return Promise.reject(new Error('database path and rule secret'));
    }
    return Promise.resolve(this.records.slice());
  }

  insert(record: BlockedFeedRecordInput): Promise<void> {
    this.records.unshift({
      id: this.records.length + 1,
      kind: record.kind,
      ruleId: record.ruleId,
      ruleName: record.ruleName,
      contentTitle: record.contentTitle,
      contentKind: record.contentKind,
      contentId: record.contentId,
      blockedAt: record.blockedAt
    });
    return Promise.resolve();
  }

  delete(id: number): Promise<void> {
    this.records = this.records.filter((record): boolean => record.id !== id);
    return Promise.resolve();
  }

  clear(): Promise<void> {
    this.records = [];
    return Promise.resolve();
  }
}

function sampleRecord(id: number): BlockedFeedRecord {
  return {
    id: id,
    kind: BlockingRuleKind.USER,
    ruleId: 'user-1',
    ruleName: '用户一',
    contentTitle: '某篇内容',
    contentKind: 'answer',
    contentId: '123',
    blockedAt: 1000
  };
}

export default function blockedFeedHistoryStateTest(): void {
  describe('blockedFeedHistoryStateTest', () => {
    it('loadsRecordsAndReturnsDefensiveSnapshots', 0, async () => {
      const history = new FakeHistory();
      history.records = [sampleRecord(1)];
      const controller = new BlockedFeedHistoryController(history);
      controller.activate();
      await controller.reload();
      const external = controller.snapshot();
      external.records[0].ruleName = 'changed';
      expect(controller.snapshot().phase).assertEqual(BlockedFeedHistoryPhase.READY);
      expect(controller.snapshot().records[0].ruleName).assertEqual('用户一');
    });

    it('deletesSingleRecordAndReloads', 0, async () => {
      const history = new FakeHistory();
      history.records = [sampleRecord(1), sampleRecord(2)];
      const controller = new BlockedFeedHistoryController(history);
      controller.activate();
      await controller.reload();
      await controller.delete(1);
      expect(controller.snapshot().records.length).assertEqual(1);
      expect(controller.snapshot().records[0].id).assertEqual(2);
    });

    it('clearsRecordsAndEntersEmptyPhase', 0, async () => {
      const history = new FakeHistory();
      history.records = [sampleRecord(1)];
      const controller = new BlockedFeedHistoryController(history);
      controller.activate();
      await controller.reload();
      await controller.clear();
      expect(history.records.length).assertEqual(0);
      expect(controller.snapshot().phase).assertEqual(BlockedFeedHistoryPhase.EMPTY);
      expect(controller.snapshot().message).assertEqual('暂无屏蔽记录');
    });

    it('publishesFixedReadFailureWithoutUnderlyingDetails', 0, async () => {
      const history = new FakeHistory();
      history.fail = true;
      const controller = new BlockedFeedHistoryController(history);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().phase).assertEqual(BlockedFeedHistoryPhase.ERROR);
      expect(controller.snapshot().message).assertEqual('屏蔽记录读取失败，请重试');
      expect(controller.snapshot().message.includes('database path')).assertFalse();
    });

    it('ignoresActionsAfterDeactivation', 0, async () => {
      const history = new FakeHistory();
      history.records = [sampleRecord(1)];
      const controller = new BlockedFeedHistoryController(history);
      controller.activate();
      await controller.reload();
      controller.deactivate();
      await controller.delete(1);
      expect(history.records.length).assertEqual(1);
    });

    it('labelsBlockingKinds', 0, () => {
      expect(blockedFeedHistoryItemLabel(BlockingRuleKind.USER)).assertEqual('屏蔽用户');
      expect(blockedFeedHistoryItemLabel(BlockingRuleKind.KEYWORD)).assertEqual('屏蔽关键词');
      expect(blockedFeedHistoryItemLabel(BlockingRuleKind.TOPIC)).assertEqual('屏蔽话题');
    });
  });
}
