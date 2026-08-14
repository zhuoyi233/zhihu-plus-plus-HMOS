import { describe, expect, it } from '@ohos/hypium';
import {
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlockingRuleSnapshot,
  BlocklistBackupPayload,
  decodeBlocklistBackup,
  encodeBlocklistBackup,
  importBlocklistBackup,
  importBlocklistBackupPayload
} from 'data';

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

function sampleSnapshot(): BlockingRuleSnapshot {
  return {
    keywords: [{ id: 1, keyword: '广告', caseSensitive: false, isRegex: false, createdAt: 1 }],
    users: [{ userId: 'user-1', userName: '用户一', createdAt: 1 }],
    topics: [{ topicId: 'topic-1', topicName: '话题一', createdAt: 1 }]
  };
}

export default function blocklistBackupTest(): void {
  describe('blocklistBackupTest', () => {
    it('encodesAndDecodesRoundTrip', 0, () => {
      const text = encodeBlocklistBackup(sampleSnapshot());
      const payload = decodeBlocklistBackup(text);
      expect(payload.version).assertEqual(2);
      expect(payload.keywords.length).assertEqual(1);
      expect(payload.keywords[0].keyword).assertEqual('广告');
      expect(payload.users.length).assertEqual(1);
      expect(payload.users[0].userId).assertEqual('user-1');
      expect(payload.topics.length).assertEqual(1);
      expect(payload.topics[0].topicName).assertEqual('话题一');
    });

    it('decodesBackupWithoutOptionalFields', 0, () => {
      const payload = decodeBlocklistBackup('{"version":2,"keywords":[],"users":[],"topics":[]}');
      expect(payload.keywords.length).assertEqual(0);
      expect(payload.exportTime).assertEqual(0);
    });

    it('rejectsMalformedOrOversizedBackup', 0, () => {
      let rejected = false;
      try {
        decodeBlocklistBackup('not-json');
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      rejected = false;
      try {
        decodeBlocklistBackup('[1,2,3]');
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      rejected = false;
      try {
        decodeBlocklistBackup('{"version":99,"keywords":[],"users":[],"topics":[]}');
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('importsValidEntriesAndSkipsInvalidOnes', 0, async () => {
      const rules = new FakeBlockingRules();
      const payload: BlocklistBackupPayload = {
        version: 2,
        exportTime: 1,
        keywords: [
          { keyword: '广告', caseSensitive: false, isRegex: false },
          { keyword: '  ', caseSensitive: false, isRegex: false },
          { keyword: '包含\u0000控制符', caseSensitive: false, isRegex: false }
        ],
        users: [
          { userId: 'user-1', userName: '用户一' },
          { userId: 'bad user!', userName: '非法ID' }
        ],
        topics: [
          { topicId: 'topic-1', topicName: '话题一' }
        ]
      };
      const text = JSON.stringify(payload);
      const summary = await importBlocklistBackup(text, rules);
      expect(summary.keywords).assertEqual(1);
      expect(summary.users).assertEqual(1);
      expect(summary.topics).assertEqual(1);
      expect(summary.skipped).assertEqual(3);
      expect(rules.keywords.length).assertEqual(1);
      expect(rules.keywords[0].keyword).assertEqual('广告');
      expect(rules.users.length).assertEqual(1);
      expect(rules.topics.length).assertEqual(1);
    });

    it('dedupesRepeatedKeywordsWithinImport', 0, async () => {
      const rules = new FakeBlockingRules();
      const payload: BlocklistBackupPayload = {
        version: 2,
        exportTime: 1,
        keywords: [
          { keyword: '广告', caseSensitive: false, isRegex: false },
          { keyword: '广告', caseSensitive: false, isRegex: false },
          { keyword: '广告', caseSensitive: true, isRegex: false }
        ],
        users: [],
        topics: []
      };
      const summary = await importBlocklistBackupPayload(payload, rules);
      expect(summary.keywords).assertEqual(2);
      expect(rules.keywords.length).assertEqual(2);
    });

    it('rejectsUnsupportedVersionDuringImport', 0, async () => {
      const rules = new FakeBlockingRules();
      let rejected = false;
      try {
        await importBlocklistBackup('{"version":99,"keywords":[],"users":[],"topics":[]}', rules);
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
