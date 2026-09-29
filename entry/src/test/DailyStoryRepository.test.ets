import { describe, expect, it } from '@ohos/hypium';
import {
  buildDailyStoryDetailUrl,
  DailyStoryRepositoryFailure,
  DailyStoryRepositoryFailureKind,
  decodeDailyStoryDestination,
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
  });
}

function bodyWith(html: string): string {
  return `{"body":${JSON.stringify(html)}}`;
}
