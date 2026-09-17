import { describe, expect, it } from '@ohos/hypium';
import {
  BlockableContentSummary,
  BlockingRuleKind,
  decodeQualityFilterMode,
  decodeRecommendationMode,
  defaultRecommendationFilterPreferences,
  matchRecommendationFilters,
  normalizeRecommendationFilterPreferences,
  QualityFilterMode,
  qualityFilterReason,
  RecommendationFilterPreferences,
  RecommendationMode
} from 'data';

function content(kind: string = 'answer'): BlockableContentSummary {
  return {
    contentId: '123',
    contentKind: kind,
    title: '测试内容',
    excerpt: '测试摘要',
    authorId: 'author-1',
    authorIsFollowing: false,
    topicIds: [],
    voteupCount: 100,
    answerCount: 100,
    followerCount: 100,
    authorFollowerCount: 100
  };
}

export default function recommendationFilterPolicyTest(): void {
  describe('recommendationFilterPolicyTest', () => {
    it('keepsUpstreamDefaultsAndPersistedModeKeys', 0, () => {
      const defaults = defaultRecommendationFilterPreferences();
      expect(defaults.recommendationMode).assertEqual(RecommendationMode.MIXED);
      expect(defaults.qualityFilterMode).assertEqual(QualityFilterMode.RULES);
      expect(defaults.enableContentFilter).assertTrue();
      expect(defaults.filterFollowedUserContent).assertFalse();
      expect(decodeRecommendationMode('server')).assertEqual(RecommendationMode.WEB);
      expect(decodeRecommendationMode('android')).assertEqual(RecommendationMode.ANDROID);
      expect(decodeRecommendationMode('local')).assertEqual(RecommendationMode.LOCAL);
      expect(decodeRecommendationMode('unexpected')).assertEqual(RecommendationMode.MIXED);
      expect(decodeQualityFilterMode('HIDE')).assertEqual(QualityFilterMode.HIDE);
      expect(decodeQualityFilterMode('unexpected')).assertEqual(QualityFilterMode.RULES);
    });

    it('normalizesInvalidQualityThresholds', 0, () => {
      const value = defaultRecommendationFilterPreferences();
      value.answerVoteupThreshold = -1;
      value.articleVoteupThreshold = 100000001;
      value.questionAnswerThreshold = 3;
      const normalized = normalizeRecommendationFilterPreferences(value);
      expect(normalized.answerVoteupThreshold).assertEqual(10);
      expect(normalized.articleVoteupThreshold).assertEqual(20);
      expect(normalized.questionAnswerThreshold).assertEqual(3);
    });

    it('appliesEveryUpstreamQualityThresholdByContentKind', 0, () => {
      const preferences = defaultRecommendationFilterPreferences();
      const answer = content('answer');
      answer.voteupCount = 9;
      expect(qualityFilterReason(answer, preferences)).assertEqual('回答赞同数低于 10');
      const article = content('article');
      article.authorFollowerCount = 49;
      expect(qualityFilterReason(article, preferences)).assertEqual('文章赞同数或作者粉丝数低于阈值');
      const video = content('video');
      video.voteupCount = 19;
      video.authorFollowerCount = 49;
      expect(qualityFilterReason(video, preferences)).assertEqual('视频赞同数或作者粉丝数低于阈值');
      const question = content('question');
      preferences.questionAnswerThreshold = 1;
      question.answerCount = 0;
      question.followerCount = 49;
      expect(qualityFilterReason(question, preferences)).assertEqual('问题回答数或关注数低于阈值');
      preferences.qualityFilterMode = QualityFilterMode.OFF;
      expect(qualityFilterReason(answer, preferences)).assertUndefined();
    });

    it('distinguishesQualityRuleAnnotationFromHiddenContent', 0, () => {
      const preferences = defaultRecommendationFilterPreferences();
      const answer = content();
      answer.voteupCount = 0;
      expect(matchRecommendationFilters(answer, preferences)).assertUndefined();
      preferences.qualityFilterMode = QualityFilterMode.HIDE;
      expect(matchRecommendationFilters(answer, preferences)?.kind).assertEqual(BlockingRuleKind.QUALITY);
    });

    it('doesNotTreatMissingQualitySignalsAsZero', 0, () => {
      const preferences = defaultRecommendationFilterPreferences();
      const answer = content('answer');
      answer.voteupCount = undefined;
      expect(qualityFilterReason(answer, preferences)).assertUndefined();
      const article = content('article');
      article.voteupCount = undefined;
      article.authorFollowerCount = undefined;
      expect(qualityFilterReason(article, preferences)).assertUndefined();
      const video = content('video');
      video.voteupCount = undefined;
      video.authorFollowerCount = 0;
      expect(qualityFilterReason(video, preferences)).assertUndefined();
      const question = content('question');
      question.answerCount = undefined;
      question.followerCount = 0;
      expect(qualityFilterReason(question, preferences)).assertUndefined();
    });

    it('blocksAllConfiguredPromotionAndPaidContentTypes', 0, () => {
      const preferences = defaultRecommendationFilterPreferences();
      const paid = content();
      paid.isPaid = true;
      expect(matchRecommendationFilters(paid, preferences)?.kind).assertEqual(BlockingRuleKind.PAID);
      const advertisement = content();
      advertisement.url = 'https://xg.zhihu.com/ad';
      expect(matchRecommendationFilters(advertisement, preferences)?.kind)
        .assertEqual(BlockingRuleKind.ADVERTISEMENT);
      const school = content();
      school.content = '<div data-edu-card-id="course"></div>';
      expect(matchRecommendationFilters(school, preferences)?.ruleId).assertEqual('zhihu-school');
      const weChat = content();
      weChat.excerpt = 'https://mp.weixin.qq.com/s/article';
      expect(matchRecommendationFilters(weChat, preferences)?.ruleId).assertEqual('mp.weixin.qq.com');
    });

    it('honorsFollowedAuthorBypassAndItsOverride', 0, () => {
      const preferences = defaultRecommendationFilterPreferences();
      preferences.qualityFilterMode = QualityFilterMode.HIDE;
      const followed = content();
      followed.voteupCount = 0;
      followed.isPaid = true;
      followed.authorIsFollowing = true;
      expect(matchRecommendationFilters(followed, preferences)).assertUndefined();
      preferences.filterFollowedUserContent = true;
      expect(matchRecommendationFilters(followed, preferences)?.kind).assertEqual(BlockingRuleKind.PAID);
    });

    it('filtersRepeatedUnopenedContentAndSupportsReverseBlocking', 0, () => {
      const preferences: RecommendationFilterPreferences = defaultRecommendationFilterPreferences();
      const repeated = content();
      repeated.viewCount = 2;
      expect(matchRecommendationFilters(repeated, preferences)?.kind).assertEqual(BlockingRuleKind.SMART);
      repeated.opened = true;
      expect(matchRecommendationFilters(repeated, preferences)).assertUndefined();
      preferences.reverseBlock = true;
      expect(matchRecommendationFilters(repeated, preferences)?.kind).assertEqual(BlockingRuleKind.REVERSE);
      repeated.isPaid = true;
      expect(matchRecommendationFilters(repeated, preferences)).assertUndefined();
    });
  });
}
