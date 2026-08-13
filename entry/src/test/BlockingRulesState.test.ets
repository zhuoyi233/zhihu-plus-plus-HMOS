import { describe, expect, it } from '@ohos/hypium';
import {
  BlockingPreferences,
  BlockingPreferencesGateway,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlockingRuleSnapshot,
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule,
  defaultBlockingPreferences
} from 'data';
import {
  BlockingRulesController,
  BlockingRulesPhase
} from '../main/ets/pages/BlockingRulesState';

class FakeBlockingRules implements BlockingRuleGateway {
  snapshot: BlockingRuleSnapshot = new FakeBlockingRuleSnapshot();
  fail: boolean = false;
  clearCount: number = 0;

  loadSnapshot(): Promise<BlockingRuleSnapshot> {
    if (this.fail) {
      return Promise.reject(new Error('database path and rule secret'));
    }
    const copy = new FakeBlockingRuleSnapshot();
    copy.keywords = this.snapshot.keywords.slice();
    copy.users = this.snapshot.users.slice();
    copy.topics = this.snapshot.topics.slice();
    return Promise.resolve(copy);
  }

  addKeyword(keyword: string, caseSensitive: boolean, isRegex: boolean): Promise<void> {
    this.snapshot.keywords.unshift({ id: 1, keyword: keyword, caseSensitive: caseSensitive,
      isRegex: isRegex, createdAt: 1 });
    return Promise.resolve();
  }

  addUser(userId: string, userName: string): Promise<void> {
    this.snapshot.users.unshift({ userId: userId, userName: userName, createdAt: 1 });
    return Promise.resolve();
  }

  addTopic(topicId: string, topicName: string): Promise<void> {
    this.snapshot.topics.unshift({ topicId: topicId, topicName: topicName, createdAt: 1 });
    return Promise.resolve();
  }

  deleteKeyword(id: number): Promise<void> {
    this.snapshot.keywords = this.snapshot.keywords.filter((item): boolean => item.id !== id);
    return Promise.resolve();
  }

  deleteUser(userId: string): Promise<void> {
    this.snapshot.users = this.snapshot.users.filter((item): boolean => item.userId !== userId);
    return Promise.resolve();
  }

  deleteTopic(topicId: string): Promise<void> {
    this.snapshot.topics = this.snapshot.topics.filter((item): boolean => item.topicId !== topicId);
    return Promise.resolve();
  }

  clear(kind: BlockingRuleKind): Promise<void> {
    this.clearCount += 1;
    if (kind === BlockingRuleKind.KEYWORD) {
      this.snapshot.keywords = [];
    } else if (kind === BlockingRuleKind.USER) {
      this.snapshot.users = [];
    } else {
      this.snapshot.topics = [];
    }
    return Promise.resolve();
  }
}

class FakeBlockingRuleSnapshot implements BlockingRuleSnapshot {
  keywords: Array<BlockedKeywordRule> = [];
  users: Array<BlockedUserRule> = [];
  topics: Array<BlockedTopicRule> = [];
}

class FakeBlockingPreferences implements BlockingPreferencesGateway {
  value: BlockingPreferences = defaultBlockingPreferences();
  fail: boolean = false;

  loadBlockingPreferences(): Promise<BlockingPreferences> {
    if (this.fail) {
      return Promise.reject(new Error('preferences absolute path'));
    }
    return Promise.resolve(this.value);
  }

  saveBlockingPreferences(value: BlockingPreferences): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

export default function blockingRulesStateTest(): void {
  describe('blockingRulesStateTest', () => {
    it('loadsThreeRuleKindsAndReturnsDefensiveSnapshots', 0, async () => {
      const rules = new FakeBlockingRules();
      rules.snapshot.users = [{ userId: 'user-1', userName: '用户一', createdAt: 1 }];
      const controller = new BlockingRulesController(rules, new FakeBlockingPreferences());
      controller.activate();
      await controller.reload();
      const external = controller.snapshot();
      external.users[0].userName = 'changed';
      expect(controller.snapshot().phase).assertEqual(BlockingRulesPhase.READY);
      expect(controller.snapshot().users[0].userName).assertEqual('用户一');
    });

    it('addsAndClearsOnlySelectedRuleKind', 0, async () => {
      const rules = new FakeBlockingRules();
      const controller = new BlockingRulesController(rules, new FakeBlockingPreferences());
      controller.activate();
      await controller.reload();
      await controller.addKeyword('广告', false, false);
      expect(controller.snapshot().keywords.length).assertEqual(1);
      await controller.clearSelected();
      expect(controller.snapshot().keywords.length).assertEqual(0);
      expect(rules.clearCount).assertEqual(1);
    });

    it('persistsSwitchesAndTopicThresholdTogether', 0, async () => {
      const preferences = new FakeBlockingPreferences();
      const controller = new BlockingRulesController(new FakeBlockingRules(), preferences);
      controller.activate();
      await controller.reload();
      await controller.savePreferences({
        keywordBlockingEnabled: false,
        userBlockingEnabled: true,
        topicBlockingEnabled: true,
        topicBlockingThreshold: 3
      });
      expect(preferences.value.keywordBlockingEnabled).assertFalse();
      expect(controller.snapshot().preferences.topicBlockingThreshold).assertEqual(3);
    });

    it('publishesFixedReadFailureWithoutUnderlyingDetails', 0, async () => {
      const rules = new FakeBlockingRules();
      rules.fail = true;
      const controller = new BlockingRulesController(rules, new FakeBlockingPreferences());
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().phase).assertEqual(BlockingRulesPhase.ERROR);
      expect(controller.snapshot().message).assertEqual('屏蔽规则读取失败，请重试');
      expect(controller.snapshot().message.includes('database path')).assertFalse();
    });

    it('ignoresActionsAfterDeactivation', 0, async () => {
      const rules = new FakeBlockingRules();
      const controller = new BlockingRulesController(rules, new FakeBlockingPreferences());
      controller.activate();
      await controller.reload();
      controller.deactivate();
      await controller.addUser('user-2', '用户二');
      expect(rules.snapshot.users.length).assertEqual(0);
    });
  });
}
