import { describe, expect, it } from '@ohos/hypium';
import {
  buildDailyStoryDetailUrl,
  DAILY_STORY_MAX_BODY_UTF8_BYTES,
  DailyStoryRepositoryFailure,
  DailyStoryRepositoryFailureKind,
  DailyStoryPayload,
  decodeDailyStoryDestination,
  decodeDailyStoryPayload,
  dailyStoryUtf8ByteLength,
  DefaultDailyStoryRepository,
  DomainDecodeError,
  PreparedZhihuHttpRequest,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';
import { AppDestination, AppDestinationName } from 'core';

class DailyStoryTransport implements ZhihuHttpTransport {
  private readonly response: ZhihuHttpResponse;
  private readonly requests: Array<PreparedZhihuHttpRequest>;

  constructor(response: ZhihuHttpResponse, requests: Array<PreparedZhihuHttpRequest>) {
    this.response = response;
    this.requests = requests;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    return Promise.resolve(this.response);
  }

  destroy(): void {
  }
}

class DailyStoryTransportFactory implements ZhihuHttpTransportFactory {
  readonly requests: Array<PreparedZhihuHttpRequest> = [];
  private readonly response: ZhihuHttpResponse;

  constructor(response: ZhihuHttpResponse) {
    this.response = response;
  }

  create(): ZhihuHttpTransport {
    return new DailyStoryTransport(this.response, this.requests);
  }
}

export default function dailyStoryRepositoryTest(): void {
  describe('dailyStoryRepositoryTest', () => {
    it('buildsFixedDailyDetailEndpointAndRejectsUnsafeStoryIds', 0, () => {
      expect(buildDailyStoryDetailUrl('9007199254740993')).assertEqual(
        'https://daily.zhihu.com/api/7/story/9007199254740993'
      );
      const invalidIds: Array<string> = ['', '0', '01', '-1', '../1', '1?next=2', '1'.repeat(31)];
      invalidIds.forEach((id: string): void => {
        let failure: DailyStoryRepositoryFailure | undefined = undefined;
        try {
          buildDailyStoryDetailUrl(id);
        } catch (error) {
          if (error instanceof DailyStoryRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(DailyStoryRepositoryFailureKind.INVALID_ID);
      });
    });

    it('decodesOriginUrlToNativeArticleAnswerAndQuestionOnly', 0, () => {
      const article: AppDestination | undefined = decodeDailyStoryDestination(bodyWith('<a class="originUrl" href="https://zhuanlan.zhihu.com/p/12">原文</a>'));
      const answer: AppDestination | undefined = decodeDailyStoryDestination(bodyWith('<a class="originUrl" href="https://www.zhihu.com/question/2/answer/3">原文</a>'));
      const question: AppDestination | undefined = decodeDailyStoryDestination(bodyWith('<a class="originUrl" href="zhihu://questions/4">原文</a>'));
      expect(article?.name).assertEqual(AppDestinationName.ARTICLE);
      expect(answer?.name).assertEqual(AppDestinationName.ANSWER);
      expect(question?.name).assertEqual(AppDestinationName.QUESTION);
      if (article?.name === AppDestinationName.ARTICLE) {
        expect(article.id).assertEqual('12');
      }
      if (answer?.name === AppDestinationName.ANSWER) {
        expect(answer.id).assertEqual('3');
      }
      if (question?.name === AppDestinationName.QUESTION) {
        expect(question.id).assertEqual('4');
      }
    });

    it('usesViewMoreWhenOriginUrlDoesNotResolveToSupportedNativeContent', 0, () => {
      const destination: AppDestination | undefined = decodeDailyStoryDestination(bodyWith(
        '<a class="originUrl" href="https://www.zhihu.com/people/alice">原文</a>' +
          '<div class="view-more"><a href="https://www.zhihu.com/question/99">查看原文</a></div>'
      ));
      expect(destination?.name).assertEqual(AppDestinationName.QUESTION);
      if (destination?.name === AppDestinationName.QUESTION) {
        expect(destination.id).assertEqual('99');
      }
    });

    it('fallsBackToFirstQuestionLinkWhenOriginLinksArePlaceholders', 0, () => {
      // 主样本的真实形态：originUrl 是 `/question/None/answer/None`，只有正文问答链接可用。
      // 「查看知乎讨论」要落在讨论所在的问题页，而不是某一条回答。
      const destination: AppDestination | undefined = decodeDailyStoryDestination(bodyWith(
        '<a class="originUrl" href="https://www.zhihu.com/question/None/answer/None">查看知乎原文</a>' +
          '<p>Q：<a class="internal" href="https://www.zhihu.com/question/5021648507/answer/1920481259353772209">问题</a></p>'
      ));
      expect(destination?.name).assertEqual(AppDestinationName.QUESTION);
      if (destination?.name === AppDestinationName.QUESTION) {
        expect(destination.id).assertEqual('5021648507');
      }
    });

    it('prefersViewMoreOverOriginUrlForDiscussionTarget', 0, () => {
      const destination: AppDestination | undefined = decodeDailyStoryDestination(bodyWith(
        '<a class="originUrl" href="https://www.zhihu.com/question/2/answer/3">原文</a>' +
          '<div class="view-more"><a href="https://www.zhihu.com/question/99">查看知乎讨论</a></div>'
      ));
      expect(destination?.name).assertEqual(AppDestinationName.QUESTION);
      if (destination?.name === AppDestinationName.QUESTION) {
        expect(destination.id).assertEqual('99');
      }
    });

    it('ignoresNonQuestionLinksWhenScanningForDiscussionTarget', 0, () => {
      expect(decodeDailyStoryDestination(bodyWith(
        '<a class="UserLink-link" href="https://www.zhihu.com/people/alice">@alice</a>' +
          '<a href="https://www.zhihu.com/ring/123">圈子</a>'
      ))).assertUndefined();
    });

    it('rejectsMalformedBodiesAndReturnsUndefinedForExternalLinks', 0, () => {
      let failure: DomainDecodeError | undefined = undefined;
      try {
        decodeDailyStoryDestination('{"body": 3}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failure = error;
        }
      }
      expect(failure instanceof DomainDecodeError).assertTrue();
      expect(decodeDailyStoryDestination(bodyWith('<a class="originUrl" href="https://example.com/x">原文</a>')))
        .assertUndefined();
    });

    it('keepsDailyStoryRequestAnonymousAndWithoutRedirects', 0, async () => {
      const factory = new DailyStoryTransportFactory({
        statusCode: 200,
        body: bodyWith('<a class="originUrl" href="https://www.zhihu.com/question/5">原文</a>')
      });
      const destination: AppDestination | undefined = await new DefaultDailyStoryRepository(
        new ZhihuHttpClient(undefined, factory)
      ).getDestination('5');
      expect(destination?.name).assertEqual(AppDestinationName.QUESTION);
      expect(factory.requests.length).assertEqual(1);
      expect(factory.requests[0].url).assertEqual('https://daily.zhihu.com/api/7/story/5');
      expect(factory.requests[0].headers.Cookie).assertUndefined();
      expect(factory.requests[0].maxRedirects).assertEqual(0);
    });

    it('decodesPayloadWithCanonicalShareUrlAndSection', 0, () => {
      // 直接拼 JSON 文本：ArkTS 禁止无类型对象字面量，嵌套 section 也不便声明中间类型。
      const raw = '{"id":9793572,"title":"瞎扯 · 如何正确地吐槽",' +
        '"body":"\\u003cdiv class=\\"content\\"\\u003e\\u003cp\\u003e正文\\u003c/p\\u003e\\u003c/div\\u003e",' +
        '"image":"https://pica.zhimg.com/v2-head.jpg?source=1",' +
        '"images":["https://pic1.zhimg.com/v2-thumb.jpg"],"type":0,' +
        '"url":"https://evil.example/story/9793572",' +
        '"share_url":"http://daily.zhihu.com/story/9793572","publish_time":1793141998,' +
        '"section":{"id":2,"name":"瞎扯","thumbnail":"https://pic1.zhimg.com/v2-s.jpg"}}';
      const payload = decodeDailyStoryPayload(raw, '9793572');
      // 长 ID 不经 Number 中转；分享地址始终由本应用构造。
      expect(payload.id).assertEqual('9793572');
      expect(payload.shareUrl).assertEqual('https://daily.zhihu.com/story/9793572');
      expect(payload.responseUrl).assertEqual('https://evil.example/story/9793572');
      expect(payload.section?.name).assertEqual('瞎扯');
      expect(payload.section?.id).assertEqual(2);
      expect(payload.imageUrl.startsWith('https://pica.zhimg.com/')).assertTrue();
      expect(payload.imageUrls.includes('https://pic1.zhimg.com/v2-thumb.jpg')).assertTrue();
      expect(payload.rawType).assertEqual(0);
      expect(payload.publishTimeSeconds).assertEqual(1793141998);
    });

    it('rejectsMismatchedResponseIdsAndOversizedBodies', 0, () => {
      let mismatch: DomainDecodeError | undefined = undefined;
      try {
        decodeDailyStoryPayload(JSON.stringify({ id: 2, body: 'x' }), '1');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          mismatch = error;
        }
      }
      expect(mismatch instanceof DomainDecodeError).assertTrue();

      let oversized: DomainDecodeError | undefined = undefined;
      try {
        decodeDailyStoryPayload(JSON.stringify({ id: 3, body: 'x'.repeat(DAILY_STORY_MAX_BODY_UTF8_BYTES + 1) }));
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          oversized = error;
        }
      }
      expect(oversized instanceof DomainDecodeError).assertTrue();
    });

    it('countsUtf8BytesForMultiByteBody', 0, () => {
      // string.length 与 UTF-8 字节数不同：中文 3 字节、emoji 4 字节。
      expect(dailyStoryUtf8ByteLength('abc')).assertEqual(3);
      expect(dailyStoryUtf8ByteLength('中文')).assertEqual(6);
      expect(dailyStoryUtf8ByteLength('😀')).assertEqual(4);
      expect(dailyStoryUtf8ByteLength('a中文😀')).assertEqual(1 + 6 + 4);
    });

    it('fetchesPayloadOnceAndValidatesResponseId', 0, async () => {
      const factory = new DailyStoryTransportFactory({
        statusCode: 200,
        body: JSON.stringify({
          id: 7,
          title: '标题',
          body: '<div class="content"><p>正文</p></div>'
        })
      });
      const payload = await new DefaultDailyStoryRepository(new ZhihuHttpClient(undefined, factory)).getStory('7');
      expect(payload.id).assertEqual('7');
      expect(factory.requests.length).assertEqual(1);
      expect(factory.requests[0].url).assertEqual('https://daily.zhihu.com/api/7/story/7');
      expect(factory.requests[0].headers.Cookie).assertUndefined();
      expect(factory.requests[0].maxRedirects).assertEqual(0);

      const mismatched = new DailyStoryTransportFactory({
        statusCode: 200,
        body: JSON.stringify({ id: 8, body: 'x' })
      });
      let failure: DomainDecodeError | undefined = undefined;
      try {
        await new DefaultDailyStoryRepository(new ZhihuHttpClient(undefined, mismatched)).getStory('7');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failure = error;
        }
      }
      expect(failure instanceof DomainDecodeError).assertTrue();
    });

    it('rejectsUnsafeStoryIdsBeforeRequesting', 0, async () => {
      const factory = new DailyStoryTransportFactory({ statusCode: 200, body: '{"id":1,"body":""}' });
      const repository = new DefaultDailyStoryRepository(new ZhihuHttpClient(undefined, factory));
      const invalid: Array<string> = ['', '0', '01', '-1', '../1', '1?next=2', '1'.repeat(31)];
      for (let index = 0; index < invalid.length; index += 1) {
        let failure: DailyStoryRepositoryFailure | undefined = undefined;
        try {
          await repository.getStory(invalid[index]);
        } catch (error) {
          if (error instanceof DailyStoryRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(DailyStoryRepositoryFailureKind.INVALID_ID);
      }
      expect(factory.requests.length).assertEqual(0);
    });

    it('dropsLateResultsAfterCancel', 0, async () => {
      const factory = new DailyStoryTransportFactory({
        statusCode: 200,
        body: JSON.stringify({ id: 9, body: '<p>x</p>' })
      });
      const repository = new DefaultDailyStoryRepository(new ZhihuHttpClient(undefined, factory));
      const pending = repository.getStory('9');
      repository.cancel();
      let failure: DailyStoryRepositoryFailure | undefined = undefined;
      try {
        await pending;
      } catch (error) {
        if (error instanceof DailyStoryRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(DailyStoryRepositoryFailureKind.CANCELLED);
    });
  });
}

function bodyWith(html: string): string {
  return `{"body":${JSON.stringify(html)}}`;
}
