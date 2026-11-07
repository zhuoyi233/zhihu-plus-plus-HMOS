import { describe, expect, it } from '@ohos/hypium';
import {
  CollectionContentItem,
  CollectionContentKind,
  FeedItem,
  FeedTargetKind,
  FeedTargetSummary
} from 'data';
import {
  collectionFeedCardPresentation,
  feedCardExcerptMaxLines,
  homeFeedCardPresentation,
  readHistoryCardPresentation
} from '../main/ets/pages/FeedCardPresentation';
import { ReadHistoryContentKind, ReadHistoryItem, readHistoryTimeLabel } from '../main/ets/pages/ReadHistoryState';

function feedTarget(kind: FeedTargetKind, id: string, title: string): FeedTargetSummary {
  return {
    kind: kind,
    id: id,
    title: title,
    excerpt: '回答摘要正文',
    url: `https://www.zhihu.com/question/1/answer/${id}`,
    topicIds: []
  };
}

function feedItem(kind: FeedTargetKind, id: string, title: string): FeedItem {
  return {
    id: `feed_${id}`,
    verb: 'ANSWER_CREATE_FEED',
    createdAt: 1700000000,
    updatedAt: 1700000000,
    target: feedTarget(kind, id, title)
  };
}

function collectionItem(kind: CollectionContentKind, id: string, details: string,
  authorAvatarUrl?: string, thumbnailUrl?: string): CollectionContentItem {
  return {
    kind: kind,
    id: id,
    title: '收藏条目标题',
    excerpt: '收藏条目摘要',
    details: details,
    voteupCount: 27,
    commentCount: 3,
    authorName: '张三',
    authorAvatarUrl: authorAvatarUrl,
    thumbnailUrl: thumbnailUrl,
    createdAt: 1700000000
  };
}

function historyItem(kind: ReadHistoryContentKind, title: string, thumbnailUrl?: string): ReadHistoryItem {
  return {
    contentKey: `${kind}:901`,
    kind: kind,
    id: '901',
    openedAt: 1762400000000,
    title: title,
    summary: '历史条目摘要',
    authorName: '张三',
    thumbnailUrl: thumbnailUrl
  };
}

export default function feedCardPresentationTest(): void {
  describe('feedCardPresentationTest', () => {
    it('adaptsHomeWebCardWithDetailsAndAccessibility', 0, () => {
      const item = feedItem(FeedTargetKind.ANSWER, '123', '为什么');
      item.target.voteupCount = 5;
      item.target.commentCount = 2;
      const presentation = homeFeedCardPresentation(item);
      expect(presentation.title).assertEqual('为什么');
      expect(presentation.excerpt).assertEqual('回答摘要正文');
      expect(presentation.detailsText).assertEqual('回答 · 5 赞同 · 2 评论');
      expect(presentation.accessibilityLabel).assertEqual('打开回答：为什么');
      expect(presentation.isBlocked).assertFalse();
      expect(presentation.supplementaryText).assertEqual(undefined);
      expect(presentation.thumbnailUrl).assertEqual(undefined);
      expect(presentation.authorName).assertEqual(undefined);
    });

    it('keepsHomeMobileFooterAndRecommendationSource', 0, () => {
      const mobile = feedItem(FeedTargetKind.ANSWER, '201', '移动卡');
      mobile.target.mobileFooterText = '1.9 万赞同 · 3069 评论';
      const mobilePresentation = homeFeedCardPresentation(mobile);
      expect(mobilePresentation.detailsText).assertEqual('1.9 万赞同 · 3069 评论 · 手机版推荐');
      // 移动卡来源标注已在页脚原文里，摘要下不再重复一行。
      expect(mobilePresentation.supplementaryText).assertEqual(undefined);

      const local = feedItem(FeedTargetKind.ANSWER, '202', '本地推荐');
      local.recommendationReason = '热门推荐';
      expect(homeFeedCardPresentation(local).supplementaryText).assertEqual('热门推荐');

      const web = feedItem(FeedTargetKind.ANSWER, '203', '来源标注');
      web.actionText = '赞同了回答';
      expect(homeFeedCardPresentation(web).supplementaryText).assertEqual('赞同了回答');
    });

    it('stripsBlockedCardFromTitleAuthorExcerptAndImage', 0, () => {
      const item = feedItem(FeedTargetKind.ANSWER, '301', '被屏蔽的内容');
      item.target.qualityFilterReason = '命中屏蔽规则';
      item.target.thumbnailUrl = 'https://picx.zhimg.com/v2-cover.jpg';
      item.target.author = {
        id: 'u1', name: '张三', headline: '', followerCount: 0, isFollowing: false, isOrganization: false,
        avatarUrl: 'https://pic1.zhimg.com/v2-a.jpg'
      };
      const presentation = homeFeedCardPresentation(item);
      expect(presentation.isBlocked).assertTrue();
      expect(presentation.blockedReason).assertEqual('命中屏蔽规则');
      expect(presentation.title).assertEqual('');
      expect(presentation.excerpt).assertEqual('');
      expect(presentation.authorName).assertEqual(undefined);
      expect(presentation.authorAvatarUrl).assertEqual(undefined);
      expect(presentation.thumbnailUrl).assertEqual(undefined);
      expect(presentation.supplementaryText).assertEqual(undefined);
      expect(presentation.accessibilityLabel).assertEqual('已屏蔽：命中屏蔽规则');
      // 页脚与菜单行保留。
      expect(presentation.detailsText).assertEqual('回答 · — 赞同 · — 评论');
    });

    it('keepsCollectionDetailsSemanticsWithoutFabricatedSource', 0, () => {
      const answer = collectionItem(CollectionContentKind.ANSWER, '901', '回答 · 27 赞同 · 3 评论');
      const answerPresentation = collectionFeedCardPresentation(answer);
      expect(answerPresentation.detailsText).assertEqual('回答 · 27 赞同 · 3 评论');
      expect(answerPresentation.supplementaryText).assertEqual(undefined);
      expect(answerPresentation.accessibilityLabel).assertEqual('打开回答：收藏条目标题');

      // 问题的 voteupCount 字段承载回答数、想法承载赞：detailsText 原样透传，不做赞同改写。
      const question = collectionItem(CollectionContentKind.QUESTION, '902', '问题 · 5 回答 · 6 评论');
      expect(collectionFeedCardPresentation(question).detailsText).assertEqual('问题 · 5 回答 · 6 评论');
      expect(collectionFeedCardPresentation(question).accessibilityLabel).assertEqual('打开问题：收藏条目标题');

      const pin = collectionItem(CollectionContentKind.PIN, '903', '想法 · 8 赞 · 1 评论');
      expect(collectionFeedCardPresentation(pin).detailsText).assertEqual('想法 · 8 赞 · 1 评论');
      expect(collectionFeedCardPresentation(pin).accessibilityLabel).assertEqual('打开想法：收藏条目标题');

      const article = collectionItem(CollectionContentKind.ARTICLE, '904', '文章 · 10 赞同 · 2 评论');
      expect(collectionFeedCardPresentation(article).accessibilityLabel).assertEqual('打开文章：收藏条目标题');
    });

    it('passesThroughCollectionImageFieldsAndDegradesWhenMissing', 0, () => {
      const withImages = collectionItem(CollectionContentKind.ANSWER, '911', '回答 · 1 赞同 · 0 评论',
        'https://pic1.zhimg.com/v2-avatar_l.jpg', 'https://picx.zhimg.com/v2-cover.jpg');
      const withImagesPresentation = collectionFeedCardPresentation(withImages);
      expect(withImagesPresentation.authorAvatarUrl).assertEqual('https://pic1.zhimg.com/v2-avatar_l.jpg');
      expect(withImagesPresentation.thumbnailUrl).assertEqual('https://picx.zhimg.com/v2-cover.jpg');

      const withoutImages = collectionItem(CollectionContentKind.ARTICLE, '912', '文章 · 1 赞同 · 0 评论');
      const withoutImagesPresentation = collectionFeedCardPresentation(withoutImages);
      expect(withoutImagesPresentation.authorAvatarUrl).assertEqual(undefined);
      expect(withoutImagesPresentation.thumbnailUrl).assertEqual(undefined);
      expect(withoutImagesPresentation.authorName).assertEqual('张三');
    });

    it('computesExcerptMaxLinesByThumbnailAndColumns', 0, () => {
      // 无图：单列三行、多列两行。
      expect(feedCardExcerptMaxLines(false, 1)).assertEqual(3);
      expect(feedCardExcerptMaxLines(false, 2)).assertEqual(2);
      expect(feedCardExcerptMaxLines(false, 3)).assertEqual(2);
      expect(feedCardExcerptMaxLines(false, 4)).assertEqual(2);
      // 带图：1~2 列六行、3~4 列四行。
      expect(feedCardExcerptMaxLines(true, 1)).assertEqual(6);
      expect(feedCardExcerptMaxLines(true, 2)).assertEqual(6);
      expect(feedCardExcerptMaxLines(true, 3)).assertEqual(4);
      expect(feedCardExcerptMaxLines(true, 4)).assertEqual(4);
    });

    it('movesHistoryMetaIntoFooterWithoutFabricatingFields', 0, () => {
      const item = historyItem(ReadHistoryContentKind.ANSWER, '历史标题');
      const presentation = readHistoryCardPresentation(item);
      // 原顶栏“类型 · 时间”元信息整体成为页脚，语义不变。
      expect(presentation.detailsText).assertEqual(`回答 · ${readHistoryTimeLabel(item.openedAt)}`);
      expect(presentation.title).assertEqual('历史标题');
      expect(presentation.excerpt).assertEqual('历史条目摘要');
      expect(presentation.authorName).assertEqual('张三');
      expect(presentation.supplementaryText).assertEqual(undefined);
      // 未提供封面时不补造；header.icon 实测为固定类型图标，头像恒空。
      expect(presentation.authorAvatarUrl).assertEqual(undefined);
      expect(presentation.thumbnailUrl).assertEqual(undefined);
      expect(presentation.isBlocked).assertFalse();
      expect(presentation.accessibilityLabel).assertEqual('打开回答：历史标题');
    });

    it('passesThroughHistoryCoverWhenOnlineResponseProvidesIt', 0, () => {
      const withCover = historyItem(ReadHistoryContentKind.ARTICLE, '带图历史',
        'https://picx.zhimg.com/v2-history-cover_r.jpg');
      const presentation = readHistoryCardPresentation(withCover);
      expect(presentation.thumbnailUrl).assertEqual('https://picx.zhimg.com/v2-history-cover_r.jpg');
      expect(presentation.authorAvatarUrl).assertEqual(undefined);
      expect(presentation.detailsText).assertEqual(`文章 · ${readHistoryTimeLabel(withCover.openedAt)}`);
    });

    it('fallsBackHistoryTitleAndDegradesEmptyFields', 0, () => {
      const blank = historyItem(ReadHistoryContentKind.PIN, '   ');
      blank.summary = '   ';
      blank.authorName = undefined;
      const presentation = readHistoryCardPresentation(blank);
      expect(presentation.title).assertEqual('想法 #901');
      expect(presentation.excerpt).assertEqual('   ');
      expect(presentation.authorName).assertEqual(undefined);
      expect(presentation.detailsText).assertEqual(`想法 · ${readHistoryTimeLabel(blank.openedAt)}`);
      expect(presentation.accessibilityLabel).assertEqual('打开想法：想法 #901');
    });
  });
}
