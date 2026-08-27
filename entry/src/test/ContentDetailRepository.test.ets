import { describe, expect, it } from '@ohos/hypium';
import {
  Answer,
  Article,
  buildContentDetailUrl,
  ContentDetailKind,
  ContentRepositoryFailure,
  ContentRepositoryFailureKind,
  decodeAnswerDetail,
  decodeArticleDetail,
  decodeQuestionDetail,
  DefaultContentRepository,
  DomainDecodeError,
  PreparedZhihuHttpRequest,
  Question,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class ContentSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'd_c0', value: 'detail-device-cookie' },
      { name: 'z_c0', value: 'detail-session-cookie' }
    ];
  }
}

class ContentTransport implements ZhihuHttpTransport {
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

class ContentTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new ContentTransport(response, this.requests);
  }
}

export default function contentDetailRepositoryTest(): void {
  describe('contentDetailRepositoryTest', () => {
    it('buildsOnlyCanonicalDetailUrlsAndRejectsIdInjection', 0, () => {
      expect(buildContentDetailUrl(ContentDetailKind.QUESTION, '123')).assertEqual(
        'https://www.zhihu.com/api/v4/questions/123?include=' +
          'read_count%2Cvisit_count%2Canswer_count%2Cvoteup_count%2Ccomment_count%2Cfollower_count%2Cdetail%2C' +
          'excerpt%2Cauthor%2Crelationship.is_following%2Ctopics'
      );
      const rejected: Array<string> = [
        '', '0', '-1', '01', '1/answers/2', '1?include=secret', '1%2F2', '1.example',
        '1234567890123456789012345678901'
      ];
      rejected.forEach((id: string): void => {
        let failure: ContentRepositoryFailure | undefined = undefined;
        try {
          buildContentDetailUrl(ContentDetailKind.ANSWER, id);
        } catch (error) {
          if (error instanceof ContentRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(ContentRepositoryFailureKind.INVALID_ID);
        if (id.length > 0 && failure !== undefined) {
          expect(failure.message.includes(id)).assertFalse();
        }
      });
    });

    it('requestsAllKindsWithSessionZseAndNoRedirects', 0, async () => {
      const factory = new ContentTransportFactory([
        { statusCode: 200, body: QUESTION_JSON },
        { statusCode: 200, body: ANSWER_JSON },
        { statusCode: 200, body: ARTICLE_JSON }
      ]);
      const repository = new DefaultContentRepository(
        new ZhihuHttpClient(new ContentSessionProvider(), factory)
      );
      const question = await repository.getQuestion('123');
      const answer = await repository.getAnswer('9007199254740993');
      const article = await repository.getArticle('789');

      expect(question.title).assertEqual('完整问题标题');
      expect(answer.id).assertEqual('9007199254740993');
      expect(article.title).assertEqual('完整文章标题');
      expect(factory.requests.length).assertEqual(3);
      factory.requests.forEach((request: PreparedZhihuHttpRequest): void => {
        expect(request.url.startsWith('https://www.zhihu.com/api/v4/')).assertTrue();
        expect(request.maxRedirects).assertEqual(0);
        expect(request.headers.Cookie?.includes('detail-session-cookie')).assertTrue();
        expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
      });
    });

    it('decodesAuthorsStatisticsAndCanonicalPublicUrls', 0, () => {
      const question: Question = decodeQuestionDetail(QUESTION_JSON, '123');
      const answer: Answer = decodeAnswerDetail(ANSWER_JSON, '9007199254740993');
      const article: Article = decodeArticleDetail(ARTICLE_JSON, '789');

      expect(question.author?.name).assertEqual('提问者');
      expect(question.answerCount).assertEqual(8);
      expect(question.url).assertEqual('https://www.zhihu.com/question/123');
      expect(answer.author?.headline).assertEqual('回答者签名');
      expect(answer.questionTitle).assertEqual('回答所属问题');
      expect(answer.voteupCount).assertEqual(21);
      expect(answer.url).assertEqual('https://www.zhihu.com/question/456/answer/9007199254740993');
      expect(article.commentCount).assertEqual(5);
      expect(article.url).assertEqual('https://zhuanlan.zhihu.com/p/789');
    });

    it('decodesEndorsementsAndIpInfoSafely', 0, () => {
      const answer: Answer = decodeAnswerDetail(
        '{"id":"9007199254740993","question":{"id":"456"},"content":"正文","excerpt":"摘要",' +
        '"voteup_count":21,"comment_count":3,"created_time":1700000000,"updated_time":1700000001,' +
        '"endorsements":[{"elements":[{"type":"TEXT","content":"专业领域","fontColor":{"group":"GBK03A","alpha":1}},' +
        '{"type":"IMAGE","imageKey":"zhicon_icon_24_chat_bubble_hash_fill"}]},' +
        '{"elements":[{"type":"TEXT","content":"不可信","fontColor":{"group":"BAD_TOKEN","alpha":1}}]}],' +
        '"ip_info":"广东"}',
        '9007199254740993'
      );
      expect(answer.endorsements?.length).assertEqual(2);
      expect(answer.endorsements?.[0].text).assertEqual('专业领域');
      expect(answer.endorsements?.[0].textColorGroup).assertEqual('GBK03A');
      expect(answer.endorsements?.[1].text).assertEqual('不可信');
      expect(answer.endorsements?.[1].textColorGroup).assertUndefined();
      expect(answer.ipInfo).assertEqual('广东');
    });

    it('keepsRequestedLongIdWhenJsonNumberCannotBeRepresentedExactly', 0, () => {
      const answer = decodeAnswerDetail(ANSWER_JSON, '9007199254740993');
      expect(answer.id).assertEqual('9007199254740993');
    });

    it('rejectsSafeMismatchedIdsAndInvalidFieldTypes', 0, () => {
      let mismatched: DomainDecodeError | undefined = undefined;
      let invalidCount: DomainDecodeError | undefined = undefined;
      try {
        decodeQuestionDetail('{"id":124,"title":"错配"}', '123');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          mismatched = error;
        }
      }
      try {
        decodeArticleDetail('{"id":789,"title":"文章","voteup_count":-1}', '789');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          invalidCount = error;
        }
      }
      expect(mismatched instanceof DomainDecodeError).assertTrue();
      expect(invalidCount instanceof DomainDecodeError).assertTrue();

      let fractionalId: DomainDecodeError | undefined = undefined;
      try {
        decodeArticleDetail('{"id":789.5,"title":"文章"}', '789');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          fractionalId = error;
        }
      }
      expect(fractionalId instanceof DomainDecodeError).assertTrue();
    });

    it('doesNotExposeUpstreamMessageOrUrlInDecodeFailures', 0, () => {
      let failure: DomainDecodeError | undefined = undefined;
      try {
        decodeArticleDetail(
          '{"error":{"code":403,"message":"cookie=z_c0-secret https://evil.example"}}',
          '789'
        );
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failure = error;
        }
      }
      expect(failure instanceof DomainDecodeError).assertTrue();
      expect(failure?.message.includes('z_c0-secret')).assertFalse();
      expect(failure?.message.includes('evil.example')).assertFalse();
    });
  });
}

const QUESTION_JSON = '{"id":123,"title":"完整问题标题","detail":"<p>问题补充</p>",' +
  '"answer_count":8,"comment_count":3,"follower_count":13,"created":1,"updated_time":2,' +
  '"author":{"id":"author-q","name":"提问者","headline":"提问者签名"}}';
const ANSWER_JSON = '{"id":9007199254740993,"question":{"id":456,"title":"回答所属问题"},' +
  '"content":"<p>回答正文</p>","excerpt":"摘要","voteup_count":21,"comment_count":4,' +
  '"created_time":3,"updated_time":4,' +
  '"author":{"id":"author-a","name":"回答者","headline":"回答者签名"}}';
const ARTICLE_JSON = '{"id":789,"title":"完整文章标题","content":"<p>文章正文</p>",' +
  '"excerpt":"摘要","voteup_count":34,"comment_count":5,"created":5,"updated":6,' +
  '"author":{"id":"author-z","name":"作者","headline":"作者签名"}}';
