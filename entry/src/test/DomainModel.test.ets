import { describe, expect, it } from '@ohos/hypium';
import {
  decodeAnswer,
  decodeArticle,
  decodeFeedPage,
  decodeQuestion,
  decodeUser,
  DomainDecodeError,
  DomainDecodeFailureKind,
  FeedTargetKind
} from 'data';

export default function domainModelTest(): void {
  describe('domainModelTest', () => {
    it('mapsSnakeCaseUserFieldsAtDecoderBoundary', 0, () => {
      const user = decodeUser('{"id":"user-1","name":"用户","url_token":"token-1",' +
        '"avatar_url":"avatar","follower_count":42,"is_following":true,"is_org":false}');

      expect(user.id).assertEqual('user-1');
      expect(user.urlToken).assertEqual('token-1');
      expect(user.avatarUrl).assertEqual('avatar');
      expect(user.followerCount).assertEqual(42);
      expect(user.isFollowing).assertTrue();
    });

    it('keepsQuestionAndNestedAnswerIdsAsStrings', 0, () => {
      const question = decodeQuestion('{"id":123456789,"title":"问题","answer_count":3,"updated_time":9}');
      const answer = decodeAnswer('{"id":987654321,"question":{"id":123456789},' +
        '"content":"<p>正文</p>","voteup_count":7,"author":{"id":5,"name":"作者"}}');

      expect(question.id).assertEqual('123456789');
      expect(question.answerCount).assertEqual(3);
      expect(question.updatedAt).assertEqual(9);
      expect(answer.id).assertEqual('987654321');
      expect(answer.questionId).assertEqual('123456789');
      expect(answer.author?.id).assertEqual('5');
    });

    it('rejectsUnsafeNumericIdsButKeepsTheirStringForm', 0, () => {
      const question = decodeQuestion('{"id":"9007199254740993","title":"问题"}');
      let failureKind: DomainDecodeFailureKind | undefined = undefined;
      try {
        decodeQuestion('{"id":9007199254740993,"title":"问题"}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failureKind = error.kind;
        }
      }

      expect(question.id).assertEqual('9007199254740993');
      expect(failureKind).assertEqual(DomainDecodeFailureKind.MISSING_FIELD);
    });

    it('mapsArticleFieldsAndDefaultsMissingOptionalValues', 0, () => {
      const article = decodeArticle('{"id":"article-1","title":"文章","content":"<p>正文</p>",' +
        '"voteup_count":8,"created":10,"updated":20,"author":{"id":"user-2","name":"作者"}}');

      expect(article.id).assertEqual('article-1');
      expect(article.voteupCount).assertEqual(8);
      expect(article.commentCount).assertEqual(0);
      expect(article.author?.headline).assertEqual('');
    });

    it('decodesFeedTargetsAndPagingCursor', 0, () => {
      const page = decodeFeedPage('{"data":[{"id":"feed-1","action_text":"赞同了回答",' +
        '"target":{"type":"answer","id":456,"question":{"id":123,"title":"问题"},' +
        '"excerpt":"摘要","voteup_count":10,"comment_count":2}}],"paging":{"is_end":false,' +
        '"is_start":true,"page":1,"totals":25,"next":"https://api.zhihu.com/next","previous":""}}');

      expect(page.items.length).assertEqual(1);
      expect(page.items[0].target.kind).assertEqual(FeedTargetKind.ANSWER);
      expect(page.items[0].target.id).assertEqual('456');
      expect(page.items[0].target.title).assertEqual('问题');
      expect(page.cursor.isEnd).assertFalse();
      expect(page.cursor.next).assertEqual('https://api.zhihu.com/next');
      expect(page.cursor.previous).assertUndefined();
      expect(page.cursor.total).assertEqual(25);
    });

    it('acceptsEmptyFeedFixtureWithTerminalCursor', 0, () => {
      const page = decodeFeedPage('{"data":[],"paging":{"is_end":true,"is_start":true,"next":""}}');

      expect(page.items.length).assertEqual(0);
      expect(page.cursor.isEnd).assertTrue();
      expect(page.cursor.next).assertUndefined();
    });

    it('reportsMalformedJsonWithoutLeakingPayload', 0, () => {
      let failureKind: DomainDecodeFailureKind | undefined = undefined;
      try {
        decodeUser('{invalid');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failureKind = error.kind;
        }
      }

      expect(failureKind).assertEqual(DomainDecodeFailureKind.INVALID_JSON);
    });

    it('keepsUpstreamErrorEnvelopeOutOfBusinessData', 0, () => {
      let failureKind: DomainDecodeFailureKind | undefined = undefined;
      try {
        decodeFeedPage('{"error":{"code":10001,"message":"敏感上游文案不应进入异常"}}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failureKind = error.kind;
          expect(error.message.includes('敏感上游文案')).assertFalse();
        }
      }

      expect(failureKind).assertEqual(DomainDecodeFailureKind.UPSTREAM_ERROR);
    });

    it('rejectsMissingRequiredFieldsAndSkipsUnsupportedFeedTargets', 0, () => {
      let missingKind: DomainDecodeFailureKind | undefined = undefined;
      try {
        decodeUser('{"id":"","name":""}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          missingKind = error.kind;
        }
      }
      const page = decodeFeedPage('{"data":[{"type":"tab_list"},{"id":"feed-2",' +
        '"target":{"type":"zvideo","id":"video-1"}},{"id":"feed-3",' +
        '"target":{"type":"article","id":"article-1","title":"可支持文章"}}]}');

      expect(missingKind).assertEqual(DomainDecodeFailureKind.MISSING_FIELD);
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].id).assertEqual('feed-3');
    });

    it('mapsMalformedFeedStructuresToDomainErrors', 0, () => {
      const malformed: Array<string> = [
        'null',
        '{"data":{}}',
        '{"data":[null]}',
        '{"data":[],"paging":"next"}',
        '{"data":[{"id":"feed","target":{}}]}',
        '{"data":[{"id":"feed","target":{"type":"article","id":"article","title":"标题",' +
          '"excerpt":7}}]}',
        '{"data":[],"paging":{"is_end":"false"}}'
      ];
      malformed.forEach((payload: string): void => {
        let failure: DomainDecodeError | undefined = undefined;
        try {
          decodeFeedPage(payload);
        } catch (error) {
          if (error instanceof DomainDecodeError) {
            failure = error;
          }
        }
        expect(failure instanceof DomainDecodeError).assertTrue();
        expect(failure?.kind).assertEqual(DomainDecodeFailureKind.MISSING_FIELD);
      });
    });
  });
}
