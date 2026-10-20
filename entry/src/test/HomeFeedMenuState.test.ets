import { describe, expect, it } from '@ohos/hypium';
import { Answer, Article, ContentRepository, decodeFeedPage, FeedItem, FeedTargetKind, Question, UserProfile } from 'data';
import { homeFeedMenuItems, resolveHomeFeedBlockUser, resolveHomeFeedTopics } from '../main/ets/pages/HomeFeedMenuState';

class MenuContentRepository implements ContentRepository {
  calls: Array<string> = [];
  questionAuthor?: UserProfile = user('question-author');
  fail: boolean = false;

  async getQuestion(id: string): Promise<Question> {
    this.calls.push(`question:${id}`);
    if (this.fail) {
      throw new Error('unavailable');
    }
    return { id: id, title: '问题', detailHtml: '', url: '', answerCount: 0, commentCount: 0,
      followerCount: 0, createdAt: 0, updatedAt: 0, author: this.questionAuthor, topics: [{ id: '11', name: '一个很长的话题名称，用于检查完整屏蔽项' }] };
  }

  async getAnswer(id: string): Promise<Answer> {
    this.calls.push(`answer:${id}`);
    return { id: id, questionId: '42', contentHtml: '', excerpt: '', url: '', voteupCount: 0,
      commentCount: 0, createdAt: 0, updatedAt: 0, author: user('answer-author') };
  }

  async getArticle(id: string): Promise<Article> {
    this.calls.push(`article:${id}`);
    return { id: id, title: '文章', contentHtml: '', excerpt: '', url: '', voteupCount: 0,
      commentCount: 0, createdAt: 0, updatedAt: 0, author: user('article-author'), topics: [{ id: '12', name: '文章话题' }] };
  }

  cancel(): void {}
}

export default function homeFeedMenuStateTest(): void {
  describe('homeFeedMenuStateTest', () => {
    it('alignsLiteMenuOrderAndKeepsSettingsOnQualityFilteredCards', 0, () => {
      const item = feed(FeedTargetKind.ANSWER);
      item.target.qualityFilterReason = '规则：回答；赞数 < 10，未关注作者';
      item.target.topics = [{ id: '1', name: '鸿蒙' }];
      expect(homeFeedMenuItems(item).map((entry): string => entry.label).join('|'))
        .assertEqual('屏蔽用户|屏蔽提问者|屏蔽「鸿蒙」|外观设置|调整质量屏蔽');
    });

    it('omitsQuestionAuthorAndQualitySettingsOnNormalArticleAndVideo', 0, () => {
      [FeedTargetKind.ARTICLE, FeedTargetKind.VIDEO].forEach((kind: FeedTargetKind): void => {
        expect(homeFeedMenuItems(feed(kind)).map((entry): string => entry.label).join('|'))
          .assertEqual('屏蔽用户|外观设置');
      });
    });

    it('usesKnownQuestionAuthorWithoutRequestingDetail', 0, async () => {
      const item = feed(FeedTargetKind.ANSWER);
      item.target.author = user('answer-author');
      item.target.questionAuthor = user('question-author');
      const repository = new MenuContentRepository();
      expect((await resolveHomeFeedBlockUser(item, repository, true))?.userId).assertEqual('question-author');
      expect((await resolveHomeFeedBlockUser(item, repository, false))?.userId).assertEqual('answer-author');
      expect(repository.calls.length).assertEqual(0);
    });

    it('resolvesMobileCardQuestionThroughAnswerDetail', 0, async () => {
      const repository = new MenuContentRepository();
      const candidate = await resolveHomeFeedBlockUser(feed(FeedTargetKind.ANSWER), repository, true);
      expect(candidate?.userId).assertEqual('question-author');
      expect(repository.calls.join('|')).assertEqual('answer:7|question:42');
    });

    it('usesFeedQuestionIdAndDoesNotConfuseItWithAnswerId', 0, async () => {
      const repository = new MenuContentRepository();
      const item = feed(FeedTargetKind.ANSWER);
      item.target.questionId = '99';
      expect((await resolveHomeFeedBlockUser(item, repository, true))?.userId).assertEqual('question-author');
      expect(repository.calls.join('|')).assertEqual('question:99');
    });

    it('resolvesQuestionCardAndMissingArticleAuthorFromTheirOwnDetails', 0, async () => {
      const repository = new MenuContentRepository();
      expect((await resolveHomeFeedBlockUser(feed(FeedTargetKind.QUESTION), repository, true))?.userId)
        .assertEqual('question-author');
      expect((await resolveHomeFeedBlockUser(feed(FeedTargetKind.ARTICLE), repository, false))?.userId)
        .assertEqual('article-author');
      expect(repository.calls.join('|')).assertEqual('question:7|article:7');
    });

    it('doesNotUseAnswerAuthorWhenQuestionAuthorIsUnavailable', 0, async () => {
      const repository = new MenuContentRepository();
      repository.questionAuthor = undefined;
      const item = feed(FeedTargetKind.ANSWER);
      item.target.author = user('answer-author');
      expect(await resolveHomeFeedBlockUser(item, repository, true)).assertUndefined();
      expect(await resolveHomeFeedBlockUser(item, undefined, true)).assertUndefined();
      expect(await resolveHomeFeedBlockUser(feed(FeedTargetKind.VIDEO), repository, true)).assertUndefined();
    });

    it('propagatesDetailFailureForThePageToShowAnError', 0, async () => {
      const repository = new MenuContentRepository();
      repository.fail = true;
      let rejected = false;
      try {
        await resolveHomeFeedBlockUser(feed(FeedTargetKind.QUESTION), repository, true);
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('loadsMobileAnswerTopicsFromItsQuestionAndPreservesLongLabels', 0, async () => {
      const repository = new MenuContentRepository();
      const item = feed(FeedTargetKind.ANSWER);
      item.target.questionId = '100';
      const topics = await resolveHomeFeedTopics(item, repository);
      expect(repository.calls.join('|')).assertEqual('question:100');
      expect(topics[0].id).assertEqual('11');
      expect(homeFeedMenuItems(item, topics)[2].label).assertEqual('屏蔽「一个很长的话题名称，用于检查完整屏蔽项」');
    });

    it('resolvesQuestionIdWhenOlderCardsOnlyHaveAnswerId', 0, async () => {
      const repository = new MenuContentRepository();
      expect((await resolveHomeFeedTopics(feed(FeedTargetKind.ANSWER), repository))[0].id).assertEqual('11');
      expect(repository.calls.join('|')).assertEqual('answer:7|question:42');
    });

    it('loadsTopicsForQuestionAndArticleCards', 0, async () => {
      const repository = new MenuContentRepository();
      expect((await resolveHomeFeedTopics(feed(FeedTargetKind.QUESTION), repository))[0].id).assertEqual('11');
      expect((await resolveHomeFeedTopics(feed(FeedTargetKind.ARTICLE), repository))[0].id).assertEqual('12');
      expect(repository.calls.join('|')).assertEqual('question:7|article:7');
    });

    it('reusesKnownTopicsAndDoesNotInventTopicsForUnsupportedCards', 0, async () => {
      const repository = new MenuContentRepository();
      const item = feed(FeedTargetKind.ANSWER);
      item.target.topics = [{ id: '13', name: '已有话题' }];
      expect((await resolveHomeFeedTopics(item, repository))[0].id).assertEqual('13');
      expect((await resolveHomeFeedTopics(feed(FeedTargetKind.VIDEO), repository)).length).assertEqual(0);
      expect((await resolveHomeFeedTopics(feed(FeedTargetKind.ANSWER), undefined)).length).assertEqual(0);
      expect(repository.calls.length).assertEqual(0);
    });

    it('keepsTopicLookupFailureVisibleToTheMenu', 0, async () => {
      const repository = new MenuContentRepository();
      repository.fail = true;
      let failed = false;
      try {
        await resolveHomeFeedTopics(feed(FeedTargetKind.QUESTION), repository);
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });

    it('preservesRealTopicNamesAndLosslessQuestionIdForMenuAndFiltering', 0, () => {
      const page = decodeFeedPage('{"data":[{"id":"f","target":{"type":"answer","id":"7",' +
        '"question":{"id":9223372036854775807,"title":"问题","topics":[' +
        '{"id":"11","name":"鸿蒙"},{"id":11,"name":"重复"},{"id":12},{"name":"无ID"},null]},' +
        '"bound_topic_ids":[13]}}]}');
      const item = page.items[0];
      expect(item.target.questionId).assertEqual('9223372036854775807');
      expect(item.target.topics?.length).assertEqual(1);
      expect(item.target.topics?.[0].name).assertEqual('鸿蒙');
      expect(item.target.topicIds.join('|')).assertEqual('11|13');
      expect(homeFeedMenuItems(item)[2].topic?.id).assertEqual('11');
    });
  });
}

function feed(kind: FeedTargetKind): FeedItem {
  return { id: 'f', verb: '', createdAt: 0, updatedAt: 0,
    target: { kind: kind, id: '7', title: '标题', excerpt: '', url: '', topicIds: [] } };
}

function user(id: string): UserProfile {
  return { id: id, name: id, headline: '', followerCount: 0, isFollowing: false, isOrganization: false };
}
