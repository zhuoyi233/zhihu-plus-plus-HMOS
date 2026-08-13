import { describe, expect, it } from '@ohos/hypium';
import {
  BlockableContentSummary,
  BlockingPreferences,
  BlockingPreferencesGateway,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlockingRuleMatcher,
  BlockingRuleSnapshot,
  defaultBlockingPreferences,
  isSafeBlockingRegex,
  matchBlockingRules,
  normalizeBlockingPreferences,
  validateBlockingIdentifier,
  validateBlockingKeyword
} from 'data';

function emptyRules(): BlockingRuleSnapshot {
  return { keywords: [], users: [], topics: [] };
}

function content(): BlockableContentSummary {
  return { title: 'ArkTS 广告课程', excerpt: 'HarmonyOS 阅读', authorId: 'author-1', topicIds: ['100', '200'] };
}

class CountingRuleGateway implements BlockingRuleGateway {
  snapshot: BlockingRuleSnapshot = emptyRules();
  loadCount: number = 0;

  loadSnapshot(): Promise<BlockingRuleSnapshot> {
    this.loadCount += 1;
    return Promise.resolve(this.snapshot);
  }

  addKeyword(_keyword: string, _caseSensitive: boolean, _isRegex: boolean): Promise<void> {
    return Promise.resolve();
  }

  addUser(_userId: string, _userName: string): Promise<void> {
    return Promise.resolve();
  }

  addTopic(_topicId: string, _topicName: string): Promise<void> {
    return Promise.resolve();
  }

  deleteKeyword(_id: number): Promise<void> {
    return Promise.resolve();
  }

  deleteUser(_userId: string): Promise<void> {
    return Promise.resolve();
  }

  deleteTopic(_topicId: string): Promise<void> {
    return Promise.resolve();
  }

  clear(_kind: BlockingRuleKind): Promise<void> {
    return Promise.resolve();
  }
}

class CountingPreferencesGateway implements BlockingPreferencesGateway {
  loadCount: number = 0;

  loadBlockingPreferences(): Promise<BlockingPreferences> {
    this.loadCount += 1;
    return Promise.resolve(defaultBlockingPreferences());
  }

  saveBlockingPreferences(_value: BlockingPreferences): Promise<void> {
    return Promise.resolve();
  }
}

export default function blockingRuleMatcherTest(): void {
  describe('blockingRuleMatcherTest', () => {
    it('validatesBoundedIdentifiersAndConservativeRegexSubset', 0, () => {
      expect(validateBlockingIdentifier(' user-1 ')).assertEqual('user-1');
      expect(validateBlockingKeyword(' 广告 ', false)).assertEqual('广告');
      expect(isSafeBlockingRegex('^ArkTS.*课程$')).assertTrue();
      expect(isSafeBlockingRegex('(a+)+$')).assertFalse();
      expect(isSafeBlockingRegex('(a|aa)+$')).assertFalse();
      expect(isSafeBlockingRegex('a.*b.*c')).assertFalse();
      expect(() => validateBlockingIdentifier('../escape')).assertThrowError(
        'Blocking identifier must contain 1 to 128 safe characters');
    });

    it('matchesPlainKeywordsWithAndroidLiteCaseSemantics', 0, () => {
      const rules = emptyRules();
      rules.keywords = [
        { id: 1, keyword: 'arkts', caseSensitive: false, isRegex: false, createdAt: 1 }
      ];
      expect(matchBlockingRules(content(), rules, defaultBlockingPreferences())?.kind)
        .assertEqual(BlockingRuleKind.KEYWORD);
      rules.keywords[0].caseSensitive = true;
      expect(matchBlockingRules(content(), rules, defaultBlockingPreferences())).assertUndefined();
    });

    it('matchesSafeRegexWithoutExposingKeywordInReason', 0, () => {
      const rules = emptyRules();
      rules.keywords = [
        { id: 8, keyword: '广告.*课程', caseSensitive: true, isRegex: true, createdAt: 1 }
      ];
      const match = matchBlockingRules(content(), rules, defaultBlockingPreferences());
      expect(match?.ruleId).assertEqual('8');
      expect(match?.reason).assertEqual('命中屏蔽关键词');
      expect(match?.reason.includes('广告')).assertFalse();
    });

    it('prioritizesBlockedUserAndHonorsDisabledKinds', 0, () => {
      const rules = emptyRules();
      rules.users = [{ userId: 'author-1', userName: '本地用户', createdAt: 1 }];
      rules.keywords = [{ id: 1, keyword: '广告', caseSensitive: false, isRegex: false, createdAt: 1 }];
      expect(matchBlockingRules(content(), rules, defaultBlockingPreferences())?.kind)
        .assertEqual(BlockingRuleKind.USER);
      const preferences = defaultBlockingPreferences();
      preferences.userBlockingEnabled = false;
      expect(matchBlockingRules(content(), rules, preferences)?.kind).assertEqual(BlockingRuleKind.KEYWORD);
    });

    it('appliesUniqueTopicThreshold', 0, () => {
      const rules = emptyRules();
      rules.topics = [
        { topicId: '100', topicName: '话题一', createdAt: 2 },
        { topicId: '200', topicName: '话题二', createdAt: 1 }
      ];
      const preferences = defaultBlockingPreferences();
      preferences.keywordBlockingEnabled = false;
      preferences.userBlockingEnabled = false;
      preferences.topicBlockingThreshold = 2;
      expect(matchBlockingRules(content(), rules, preferences)?.kind).assertEqual(BlockingRuleKind.TOPIC);
      preferences.topicBlockingThreshold = 3;
      expect(matchBlockingRules(content(), rules, preferences)).assertUndefined();
    });

    it('normalizesInvalidPersistedThresholdWithoutChangingSwitches', 0, () => {
      const value: BlockingPreferences = {
        keywordBlockingEnabled: false,
        userBlockingEnabled: true,
        topicBlockingEnabled: false,
        topicBlockingThreshold: 0
      };
      const normalized = normalizeBlockingPreferences(value);
      expect(normalized.topicBlockingThreshold).assertEqual(1);
      expect(normalized.keywordBlockingEnabled).assertFalse();
      expect(normalized.topicBlockingEnabled).assertFalse();
    });

    it('loadsOneImmutableSnapshotPerPageSession', 0, async () => {
      const rules = new CountingRuleGateway();
      const preferences = new CountingPreferencesGateway();
      rules.snapshot.keywords = [
        { id: 1, keyword: '广告', caseSensitive: false, isRegex: false, createdAt: 1 }
      ];
      const matcher = new BlockingRuleMatcher(rules, preferences);
      const session = await matcher.createSession();

      expect(session.match(content())?.kind).assertEqual(BlockingRuleKind.KEYWORD);
      expect(session.match(content())?.kind).assertEqual(BlockingRuleKind.KEYWORD);
      expect(rules.loadCount).assertEqual(1);
      expect(preferences.loadCount).assertEqual(1);

      rules.snapshot.keywords = [];
      expect(session.match(content())?.kind).assertEqual(BlockingRuleKind.KEYWORD);
      const refreshedSession = await matcher.createSession();
      expect(refreshedSession.match(content())).assertUndefined();
      expect(rules.loadCount).assertEqual(2);
    });
  });
}
