import { describe, expect, it } from '@ohos/hypium';
import {
  BlockedFeedHistoryGateway,
  BlockedFeedRecord,
  BlockedFeedRecordInput,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlockingRuleSnapshot,
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule
} from 'data';
import {
  BlockingActionController,
  BlockingActionContext,
  BlockingActionPhase
} from '../main/ets/pages/BlockingActionState';

const CONTEXT: BlockingActionContext = {
  contentTitle: '测试内容',
  contentKind: 'answer',
  contentId: '123'
};

class FakeBlockingRules implements BlockingRuleGateway {
  keywords: Array<BlockedKeywordRule> = [];
  users: Array<BlockedUserRule> = [];
  topics: Array<BlockedTopicRule> = [];

  loadSnapshot(): Promise<BlockingRuleSnapshot> {
    const snapshot: BlockingRuleSnapshot = {
      keywords: this.keywords.slice(),
      users: this.users.slice(),
      topics: this.topics.slice()
    };
    return Promise.resolve(snapshot);
  }

  addKeyword(keyword: string, caseSensitive: boolean, isRegex: boolean): Promise<void> {
    this.keywords.unshift({ id: this.keywords.length + 1, keyword: keyword,
      caseSensitive: caseSensitive, isRegex: isRegex, createdAt: 1 });
    return Promise.resolve();
  }

  addUser(userId: string, userName: string): Promise<void> {
    this.users.unshift({ userId: userId, userName: userName, createdAt: 1 });
    return Promise.resolve();
  }

  addTopic(topicId: string, topicName: string): Promise<void> {
    this.topics.unshift({ topicId: topicId, topicName: topicName, createdAt: 1 });
    return Promise.resolve();
  }

  deleteKeyword(id: number): Promise<void> {
    this.keywords = this.keywords.filter((rule): boolean => rule.id !== id);
    return Promise.resolve();
  }

  deleteUser(userId: string): Promise<void> {
    this.users = this.users.filter((rule): boolean => rule.userId !== userId);
    return Promise.resolve();
  }

  deleteTopic(topicId: string): Promise<void> {
    this.topics = this.topics.filter((rule): boolean => rule.topicId !== topicId);
    return Promise.resolve();
  }

  clear(kind: BlockingRuleKind): Promise<void> {
    if (kind === BlockingRuleKind.KEYWORD) {
      this.keywords = [];
    } else if (kind === BlockingRuleKind.USER) {
      this.users = [];
    } else {
      this.topics = [];
    }
    return Promise.resolve();
  }
}

class FakeHistory implements BlockedFeedHistoryGateway {
  records: Array<BlockedFeedRecord> = [];

  queryRecent(_limit?: number): Promise<Array<BlockedFeedRecord>> {
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

class SlowBlockingRules extends FakeBlockingRules {
  releaseAddUser: (() => void) | undefined = undefined;

  addUser(userId: string, userName: string): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.releaseAddUser = resolve;
    }).then((): void => {
      this.users.unshift({ userId: userId, userName: userName, createdAt: 1 });
    });
  }
}

export default function blockingActionStateTest(): void {
  describe('blockingActionStateTest', () => {
    it('blocksUserWritesRuleAndHistory', 0, async () => {
      const rules = new FakeBlockingRules();
      const history = new FakeHistory();
      const controller = new BlockingActionController(rules, history);
      await controller.blockUser('user-1', '用户一', CONTEXT);
      expect(rules.users.length).assertEqual(1);
      expect(rules.users[0].userId).assertEqual('user-1');
      expect(history.records.length).assertEqual(1);
      expect(history.records[0].kind).assertEqual(BlockingRuleKind.USER);
      expect(history.records[0].ruleName).assertEqual('用户一');
      expect(history.records[0].contentTitle).assertEqual('测试内容');
      expect(controller.snapshot().phase).assertEqual(BlockingActionPhase.SUCCESS);
      expect(controller.snapshot().message.includes('用户一')).assertTrue();
    });

    it('blocksKeywordWithValidation', 0, async () => {
      const rules = new FakeBlockingRules();
      const history = new FakeHistory();
      const controller = new BlockingActionController(rules, history);
      await controller.blockKeyword('  广告  ', CONTEXT);
      expect(rules.keywords.length).assertEqual(1);
      expect(rules.keywords[0].keyword).assertEqual('广告');
      expect(history.records[0].kind).assertEqual(BlockingRuleKind.KEYWORD);
      expect(history.records[0].ruleId).assertEqual('广告');
    });

    it('rejectsInvalidKeywordWithoutWrites', 0, async () => {
      const rules = new FakeBlockingRules();
      const history = new FakeHistory();
      const controller = new BlockingActionController(rules, history);
      await controller.blockKeyword('   ', CONTEXT);
      expect(rules.keywords.length).assertEqual(0);
      expect(history.records.length).assertEqual(0);
      expect(controller.snapshot().phase).assertEqual(BlockingActionPhase.ERROR);
      expect(controller.snapshot().message).assertEqual('屏蔽失败，请重试');
    });

    it('blocksTopicWritesRuleAndHistory', 0, async () => {
      const rules = new FakeBlockingRules();
      const history = new FakeHistory();
      const controller = new BlockingActionController(rules, history);
      await controller.blockTopic('topic-1', '话题一', CONTEXT);
      expect(rules.topics.length).assertEqual(1);
      expect(history.records.length).assertEqual(1);
      expect(history.records[0].kind).assertEqual(BlockingRuleKind.TOPIC);
      expect(history.records[0].ruleId).assertEqual('topic-1');
    });

    it('ignoresActionWhileBusy', 0, async () => {
      const rules = new SlowBlockingRules();
      const controller = new BlockingActionController(rules, new FakeHistory());
      const first = controller.blockUser('user-1', '用户一', CONTEXT);
      expect(controller.snapshot().busy).assertTrue();
      await controller.blockUser('user-2', '用户二', CONTEXT);
      expect(rules.users.length).assertEqual(0);
      rules.releaseAddUser?.();
      await first;
      expect(rules.users.length).assertEqual(1);
      expect(rules.users[0].userId).assertEqual('user-1');
    });

    it('resetsToIdle', 0, async () => {
      const controller = new BlockingActionController(new FakeBlockingRules(), new FakeHistory());
      await controller.blockTopic('topic-1', '话题一', CONTEXT);
      expect(controller.snapshot().phase).assertEqual(BlockingActionPhase.SUCCESS);
      controller.reset();
      expect(controller.snapshot().phase).assertEqual(BlockingActionPhase.IDLE);
      expect(controller.snapshot().message).assertEqual('');
    });
  });
}
