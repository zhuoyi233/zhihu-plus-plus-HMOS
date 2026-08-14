import { describe, expect, it } from '@ohos/hypium';
import {
  buildAnswerThankUrl,
  buildAnswerVoteBody,
  buildAnswerVoteUrl,
  buildArticleVoteBody,
  buildArticleVoteUrl,
  ContentRepositoryFailure,
  ContentRepositoryFailureKind,
  ContentVoteState,
  DefaultVoteRepository,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class VoteCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'd_c0', value: 'vote-device-cookie' },
      { name: 'z_c0', value: 'vote-session-cookie' }
    ];
  }
}

class VoteTransport implements ZhihuHttpTransport {
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

class VoteTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new VoteTransport(response, this.requests);
  }
}

export default function voteRepositoryTest(): void {
  describe('voteRepositoryTest', () => {
    it('buildsCanonicalVoteAndThankUrlsAndRejectsIdInjection', 0, () => {
      expect(buildAnswerVoteUrl('123')).assertEqual('https://www.zhihu.com/api/v4/answers/123/voters');
      expect(buildArticleVoteUrl('456')).assertEqual('https://www.zhihu.com/api/v4/articles/456/voters');
      expect(buildAnswerThankUrl('789')).assertEqual('https://www.zhihu.com/api/v4/answers/789/thank');
      expect(buildAnswerVoteBody(ContentVoteState.UP)).assertEqual('{"type":"up"}');
      expect(buildAnswerVoteBody(ContentVoteState.DOWN)).assertEqual('{"type":"down"}');
      expect(buildAnswerVoteBody(ContentVoteState.NEUTRAL)).assertEqual('{"type":"neutral"}');
      expect(buildArticleVoteBody(ContentVoteState.UP)).assertEqual('{"voting":1}');
      expect(buildArticleVoteBody(ContentVoteState.DOWN)).assertEqual('{"voting":0}');
      expect(buildArticleVoteBody(ContentVoteState.NEUTRAL)).assertEqual('{"voting":0}');

      const rejected: Array<string> = ['', '0', '-1', '01', '1/2', '1?include=secret', '1%2F2'];
      rejected.forEach((id: string): void => {
        let failure: ContentRepositoryFailure | undefined = undefined;
        try {
          buildAnswerVoteUrl(id);
        } catch (error) {
          if (error instanceof ContentRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(ContentRepositoryFailureKind.INVALID_ID);
      });
    });

    it('postsAnswerVoteWithTypeBodyAndParsesServerVoteupCount', 0, async () => {
      const factory = new VoteTransportFactory([
        { statusCode: 200, body: '{"voteup_count":42,"voting":1}' }
      ]);
      const repository = new DefaultVoteRepository(new ZhihuHttpClient(new VoteCookieProvider(), factory));
      const result = await repository.voteAnswer('123', ContentVoteState.UP);

      expect(result.voteupCount).assertEqual(42);
      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.method).assertEqual(ZhihuHttpMethod.POST);
      expect(request.url).assertEqual('https://www.zhihu.com/api/v4/answers/123/voters');
      expect(request.body).assertEqual('{"type":"up"}');
      expect(request.maxRedirects).assertEqual(0);
      expect(request.headers.Cookie?.includes('vote-session-cookie')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
    });

    it('postsArticleVoteWithVotingBodyForEveryState', 0, async () => {
      const factory = new VoteTransportFactory([
        { statusCode: 200, body: '{"voteup_count":10}' },
        { statusCode: 200, body: '{"voteup_count":9}' },
        { statusCode: 200, body: '{"voteup_count":9}' }
      ]);
      const repository = new DefaultVoteRepository(new ZhihuHttpClient(new VoteCookieProvider(), factory));
      const up = await repository.voteArticle('456', ContentVoteState.UP);
      const down = await repository.voteArticle('456', ContentVoteState.DOWN);
      const neutral = await repository.voteArticle('456', ContentVoteState.NEUTRAL);

      expect(up.voteupCount).assertEqual(10);
      expect(down.voteupCount).assertEqual(9);
      expect(neutral.voteupCount).assertEqual(9);
      expect(factory.requests[0].body).assertEqual('{"voting":1}');
      expect(factory.requests[1].body).assertEqual('{"voting":0}');
      expect(factory.requests[2].body).assertEqual('{"voting":0}');
      factory.requests.forEach((request: PreparedZhihuHttpRequest): void => {
        expect(request.url).assertEqual('https://www.zhihu.com/api/v4/articles/456/voters');
        expect(request.method).assertEqual(ZhihuHttpMethod.POST);
      });
    });

    it('thanksAnswerViaPostAndDeleteAndParsesCounts', 0, async () => {
      const factory = new VoteTransportFactory([
        { statusCode: 200, body: '{"thanks_count":7,"is_thanked":true}' },
        { statusCode: 200, body: '{"thanks_count":6,"is_thanked":false}' }
      ]);
      const repository = new DefaultVoteRepository(new ZhihuHttpClient(new VoteCookieProvider(), factory));
      const thanked = await repository.thankAnswer('789', true);
      const unthanked = await repository.thankAnswer('789', false);

      expect(thanked.thanksCount).assertEqual(7);
      expect(thanked.thanked).assertTrue();
      expect(unthanked.thanksCount).assertEqual(6);
      expect(unthanked.thanked).assertFalse();
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.POST);
      expect(factory.requests[0].url).assertEqual('https://www.zhihu.com/api/v4/answers/789/thank');
      expect(factory.requests[0].body).assertEqual('{}');
      expect(factory.requests[1].method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(factory.requests[1].url).assertEqual('https://www.zhihu.com/api/v4/answers/789/thank');
    });

    it('toleratesInvalidOrMissingCountsInResponses', 0, async () => {
      const factory = new VoteTransportFactory([
        { statusCode: 200, body: 'not-json' },
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{"voteup_count":-1}' }
      ]);
      const repository = new DefaultVoteRepository(new ZhihuHttpClient(new VoteCookieProvider(), factory));
      const invalid = await repository.voteAnswer('123', ContentVoteState.UP);
      const missing = await repository.voteArticle('456', ContentVoteState.UP);
      const negative = await repository.thankAnswer('789', true);

      expect(invalid.voteupCount).assertUndefined();
      expect(missing.voteupCount).assertUndefined();
      expect(negative.thanksCount).assertUndefined();
      expect(negative.thanked).assertUndefined();
    });
  });
}
