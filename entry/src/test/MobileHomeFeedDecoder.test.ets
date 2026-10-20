import { describe, expect, it } from '@ohos/hypium';
import { decodeMobileHomeFeedPage, FeedTargetSummary } from 'data';

const USER_INFO = '{"business_ext_map":{"userInfo":{"memberHashId":"author-stable-id",' +
  '"userName":"测试作者","avatarUrl":"https://pic.zhimg.com/avatar.jpg","followState":"none"}}}';

function card(footerElements: string, extra: string = USER_INFO, authorFields: string = ''): string {
  return '{"data":[{"id":"mobile-card","type":"ComponentCard",' +
    '"action":{"parameter":"route_url=https%3A%2F%2Fwww.zhihu.com%2Fquestion%2F100%2Fanswer%2F200"},' +
    '"children":[{"type":"Text","id":"Text","text":"测试标题"},' +
    '{"type":"Text","id":"text_pin_summary","text":"正文里的 0 赞同 · 0 评论不是卡片统计"},' +
    '{"type":"Line","style":"LineAuthor_default",' + authorFields +
    '"elements":[{"type":"Text","text":"测试作者"}]},' +
    '{"type":"Line","id":"feed_footer","style":"lineFooterDescription_default","elements":' +
    footerElements + '}],"extra":' + extra + '}],"paging":{"is_end":true}}';
}

function footer(text: string, extra: string = USER_INFO): FeedTargetSummary {
  return decodeMobileHomeFeedPage(card('[{"type":"Text","text":' + JSON.stringify(text) + '}]', extra))
    .items[0].target;
}

export default function mobileHomeFeedDecoderTest(): void {
  describe('mobileHomeFeedDecoderTest', () => {
    it('decodesObservedDescriptionFooterAndBusinessAuthorMetadata', 0, () => {
      const target = footer('20 赞同 · 17 评论');
      expect(target.questionId).assertEqual('100');
      expect(target.voteupCount).assertEqual(20);
      expect(target.commentCount).assertEqual(17);
      expect(target.author?.id).assertEqual('author-stable-id');
      expect(target.authorIsFollowing).assertFalse();
      expect(target.authorFollowerCount).assertUndefined();
    });

    it('readsZeroAndCommaSeparatedCountsWithoutInventingOmittedComments', 0, () => {
      const zero = footer('0 赞同 · 0 评论');
      expect(zero.voteupCount).assertEqual(0);
      expect(zero.commentCount).assertEqual(0);
      const collected = footer('1,234 赞同 · 126 收藏');
      expect(collected.voteupCount).assertEqual(1234);
      expect(collected.commentCount).assertUndefined();
      expect(collected.mobileFooterText).assertEqual('1,234 赞同 · 126 收藏');
    });

    it('preservesConservativeBoundsForAbbreviatedCounts', 0, () => {
      const tenThousands = footer('1.9 万赞同 · 3069 评论');
      expect(tenThousands.voteupCount).assertEqual(19000);
      expect(tenThousands.voteupCountUpperBound).assertEqual(19999);
      expect(tenThousands.commentCount).assertEqual(3069);
      expect(tenThousands.mobileFooterText).assertEqual('1.9 万赞同 · 3069 评论');
      const hundredMillions = footer('1.2亿赞同 · 1万评论');
      expect(hundredMillions.voteupCount).assertEqual(120000000);
      expect(hundredMillions.voteupCountUpperBound).assertEqual(129999999);
      expect(hundredMillions.commentCount).assertEqual(10000);
    });

    it('prefersStructuredZeroCountsOverDescriptionFallback', 0, () => {
      const target = decodeMobileHomeFeedPage(card('[{"reaction":"Vote","count":0},' +
        '{"reaction":"Comment","count":2},{"type":"Text","text":"1万赞同 · 99 评论"}]')).items[0].target;
      expect(target.voteupCount).assertEqual(0);
      expect(target.voteupCountUpperBound).assertUndefined();
      expect(target.commentCount).assertEqual(2);
    });

    it('rejectsMalformedCountsAndIgnoresNumbersOutsideTheFooter', 0, () => {
      const invalid = footer('-1 赞同 · 1.5 评论');
      expect(invalid.voteupCount).assertUndefined();
      expect(invalid.commentCount).assertUndefined();
      const missing = decodeMobileHomeFeedPage(card('[]')).items[0].target;
      expect(missing.voteupCount).assertUndefined();
      expect(missing.commentCount).assertUndefined();
      expect(missing.mobileFooterText).assertEqual('');
      const placeholders = footer('赞同 · 暂无评论');
      expect(placeholders.voteupCount).assertUndefined();
      expect(placeholders.commentCount).assertUndefined();
    });

    it('formatsCompleteStructuredFooterAndRetainsIncompleteFooterDescription', 0, () => {
      const complete = decodeMobileHomeFeedPage(card('[{"reaction":"Vote","count":0},' +
        '{"reaction":"Comment","count":2},{"reaction":"Collect","count":3},' +
        '{"type":"Text","text":"旧文字"}]')).items[0].target;
      expect(complete.mobileFooterText).assertEqual('0 赞同 · 2 评论 · 3 收藏');
      const incomplete = decodeMobileHomeFeedPage(card('[{"reaction":"Vote","count":7},' +
        '{"reaction":"Collect","count":9},{"type":"Text","text":"7 赞同 · 9 收藏"}]')).items[0].target;
      expect(incomplete.mobileFooterText).assertEqual('7 赞同 · 9 收藏');
      expect(incomplete.commentCount).assertUndefined();
      const legacy = decodeMobileHomeFeedPage(card('[{"reaction":"Vote","count":7},' +
        '{"reaction":"Comment","count":2}]')).items[0].target;
      expect(legacy.mobileFooterText).assertEqual('7 赞同 · 2 评论');
    });

    it('preservesUnknownFollowStatesAndPrefersExplicitFollowBooleans', 0, () => {
      const unknown = footer('0 赞同', '{"business_ext_map":{"userInfo":{"followState":"new-state"}}}');
      expect(unknown.authorIsFollowing).assertUndefined();
      const followed = footer('0 赞同', '{"passthrough_info":{"author":{' +
        '"id":"followed-author","is_following":true,"follower_count":700}},' +
        '"business_ext_map":{"userInfo":{"followState":"none"}}}');
      expect(followed.author?.id).assertEqual('followed-author');
      expect(followed.authorIsFollowing).assertTrue();
      expect(followed.authorFollowerCount).assertEqual(700);
      const legacy = decodeMobileHomeFeedPage(card('[]', USER_INFO,
        '"author_id":"legacy-author","is_following":true,"follower_count":42,')).items[0].target;
      expect(legacy.author?.id).assertEqual('legacy-author');
      expect(legacy.authorIsFollowing).assertTrue();
      expect(legacy.authorFollowerCount).assertEqual(42);
    });

    it('usesBusinessMetadataWhenTheAuthorLineIsAbsent', 0, () => {
      const source = card('[]').replace('LineAuthor_default', 'UnrelatedLine');
      const target = decodeMobileHomeFeedPage(source).items[0].target;
      expect(target.author?.id).assertEqual('author-stable-id');
      expect(target.author?.name).assertEqual('测试作者');
      expect(target.authorIsFollowing).assertFalse();
    });
  });
}
