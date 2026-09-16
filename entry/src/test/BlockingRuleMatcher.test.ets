import { describe, expect, it } from '@ohos/hypium';
import {
  BlockableContentSummary,
  BlockingPreferences,
  BlockingPreferencesGateway,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlockingRuleMatcher,
  ContentBlockingStrategy,
  ContentFilterOutcome,
  ContentFilterRuntimeGateway,
  ContentFilterRuntimeSnapshot,
  ContentFilterStats,
  BlockingRuleSnapshot,
  defaultBlockingPreferences,
  defaultRecommendationFilterPreferences,
  isSafeBlockingRegex,
  matchBlockingRules,
  normalizeBlockingPreferences,
  validateBlockingIdentifier,
  RecommendationFilterPreferences,
  RecommendationFilterPreferencesGateway,
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

class CountingRecommendationGateway implements RecommendationFilterPreferencesGateway {
  loadCount: number = 0;

  loadRecommendationFilterPreferences(): Promise<RecommendationFilterPreferences> {
    this.loadCount += 1;
    return Promise.resolve(defaultRecommendationFilterPreferences());
  }

  saveRecommendationFilterPreferences(_value: RecommendationFilterPreferences): Promise<void> {
    return Promise.resolve();
  }
}

class CountingRuntimeGateway implements ContentFilterRuntimeGateway {
  loadCount: number = 0;
  recordCount: number = 0;

  loadSnapshot(): Promise<ContentFilterRuntimeSnapshot> {
    this.loadCount += 1;
    const viewCounts: Record<string, number> = {};
    const snapshot: ContentFilterRuntimeSnapshot = { viewCounts: viewCounts, openedKeys: [] };
    return Promise.resolve(snapshot);
  }

  recordOutcomes(outcomes: Array<ContentFilterOutcome>): Promise<void> {
    this.recordCount += outcomes.length;
    return Promise.resolve();
  }

  loadStats(): Promise<ContentFilterStats> {
    const stats: ContentFilterStats = { totalSeen: 0, totalFiltered: 0, filterRate: 0, lastFilteredAt: 0 };
    return Promise.resolve(stats);
  }

  cleanupOldData(_cutoff: number): Promise<void> {
    return Promise.resolve();
  }

  clearAllData(): Promise<void> {
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
      const matcher = new BlockingRuleMatcher(rules, preferences, ContentBlockingStrategy.RULES_ONLY);
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

    it('matchesBodyWithoutJoiningAcrossFieldBoundaries', 0, () => {
      const rules = emptyRules();
      rules.keywords = [{ id: 2, keyword: '正文命中', caseSensitive: false, isRegex: false, createdAt: 1 }];
      const value = content();
      value.content = '<p>这里是正文命中位置</p>';
      expect(matchBlockingRules(value, rules, defaultBlockingPreferences())?.kind)
        .assertEqual(BlockingRuleKind.KEYWORD);
      rules.keywords[0].keyword = '课程HarmonyOS';
      expect(matchBlockingRules(value, rules, defaultBlockingPreferences())).assertUndefined();
    });

    it('matchesQuestionAuthorAfterContentAuthor', 0, () => {
      const rules = emptyRules();
      rules.users = [
        { userId: 'author-1', userName: '回答者', createdAt: 2 },
        { userId: 'asker-1', userName: '提问者', createdAt: 1 }
      ];
      const value = content();
      value.questionAuthorId = 'asker-1';
      expect(matchBlockingRules(value, rules, defaultBlockingPreferences())?.reason).assertEqual('屏蔽用户：回答者');
      value.authorId = 'other';
      expect(matchBlockingRules(value, rules, defaultBlockingPreferences())?.reason).assertEqual('屏蔽提问者：提问者');
    });

    it('rulesOnlyDoesNotApplyRecommendationDefaults', 0, async () => {
      const rules = new CountingRuleGateway();
      const preferences = new CountingPreferencesGateway();
      const matcher = new BlockingRuleMatcher(rules, preferences, ContentBlockingStrategy.RULES_ONLY);
      const session = await matcher.createSession();
      const paid = content();
      paid.isPaid = defaultRecommendationFilterPreferences().blockPaidContent;
      expect(session.match(paid)).assertUndefined();
      paid.authorId = 'author-1';
      rules.snapshot.users = [{ userId: 'author-1', userName: '用户', createdAt: 1 }];
      const refreshed = await matcher.createSession();
      expect(refreshed.match(paid)?.kind).assertEqual(BlockingRuleKind.USER);
    });

    it('homeFullLoadsEachSnapshotOnceAndFlushesOnce', 0, async () => {
      const rules = new CountingRuleGateway();
      const preferences = new CountingPreferencesGateway();
      const recommendation = new CountingRecommendationGateway();
      const runtime = new CountingRuntimeGateway();
      const matcher = new BlockingRuleMatcher(rules, preferences, ContentBlockingStrategy.HOME_FULL,
        recommendation, runtime);
      const session = await matcher.createSession();
      session.match(content());
      await session.flush?.();
      await session.flush?.();
      expect(rules.loadCount).assertEqual(1);
      expect(preferences.loadCount).assertEqual(1);
      expect(recommendation.loadCount).assertEqual(1);
      expect(runtime.loadCount).assertEqual(1);
      expect(runtime.recordCount).assertEqual(1);
    });
  });
}
