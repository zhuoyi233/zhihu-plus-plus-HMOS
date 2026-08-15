import { describe, expect, it } from '@ohos/hypium';
import {
  buildPeopleDetailUrl,
  buildPeopleContentUrl,
  buildPinDetailUrl,
  decodePeopleDetail,
  decodePinDetail,
  DefaultPeopleRepository,
  DefaultPeopleContentRepository,
  DefaultPinRepository,
  DomainDecodeError,
  HttpFailure,
  HttpFailureKind,
  isPeopleContentCursorUrl,
  PeopleRepositoryFailure,
  PeopleRepositoryFailureKind,
  PeopleContentRepositoryFailure,
  PeopleContentRepositoryFailureKind,
  PeopleContentSection,
  PinRepositoryFailure,
  PinRepositoryFailureKind,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class DetailCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'people-pin-session' },
      { name: 'd_c0', value: 'people-pin-device' }
    ];
  }
}

class DetailTransport implements ZhihuHttpTransport {
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

class DetailTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new DetailTransport(response, this.requests);
  }
}

class PendingDetailTransport implements ZhihuHttpTransport {
  requestCount: number = 0;
  destroyCount: number = 0;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requestCount += 1;
    return new Promise<ZhihuHttpResponse>((_resolve: (response: ZhihuHttpResponse) => void): void => {
    });
  }

  destroy(): void {
    this.destroyCount += 1;
  }
}

class PendingDetailTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingDetailTransport = new PendingDetailTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

export default function peoplePinDetailRepositoryTest(): void {
  describe('peoplePinDetailRepositoryTest', () => {
    it('buildsFixedEndpointsAndRejectsPathInjection', 0, () => {
      expect(buildPeopleDetailUrl('alice-token')).assertEqual(
        'https://www.zhihu.com/api/v4/members/alice-token?include=allow_message%2Cis_followed%2Cis_following%2Cis_org%2C' +
          'is_blocking%2Cbadge_v2%2Canswer_count%2Cfollower_count%2Cfollowing_count%2Carticles_count%2C' +
          'question_count%2Cpins_count'
      );
      expect(buildPinDetailUrl('9007199254740993')).assertEqual(
        'https://www.zhihu.com/api/v4/pins/9007199254740993?include=topics'
      );
      const badPeople: Array<string> = ['', '../alice', 'alice/answers', 'alice?include=x', 'user@host', '百分号%'];
      badPeople.forEach((identifier: string): void => {
        let failure: PeopleRepositoryFailure | undefined = undefined;
        try {
          buildPeopleDetailUrl(identifier);
        } catch (error) {
          if (error instanceof PeopleRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(PeopleRepositoryFailureKind.INVALID_IDENTIFIER);
      });
      const badPins: Array<string> = ['', '0', '-1', '01', '1/2', '1?x=2', '1%2F2'];
      badPins.forEach((id: string): void => {
        let failure: PinRepositoryFailure | undefined = undefined;
        try {
          buildPinDetailUrl(id);
        } catch (error) {
          if (error instanceof PinRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(PinRepositoryFailureKind.INVALID_ID);
      });
    });

    it('signsPeopleAndPinThroughSessionCookieProvider', 0, async () => {
      const peopleFactory = new DetailTransportFactory([{ statusCode: 200, body: PEOPLE_JSON }]);
      const pinFactory = new DetailTransportFactory([{ statusCode: 200, body: PIN_JSON }]);
      const cookies = new DetailCookieProvider();
      const people = await new DefaultPeopleRepository(
        new ZhihuHttpClient(cookies, peopleFactory)
      ).getUser('alice-token');
      const pin = await new DefaultPinRepository(
        new ZhihuHttpClient(cookies, pinFactory)
      ).getPin('9007199254740993');

      expect(people.name).assertEqual('Alice');
      expect(pin.author.name).assertEqual('Pin Author');
      expect(peopleFactory.requests[0].headers.Cookie?.includes('people-pin-session')).assertTrue();
      expect(JSON.stringify(peopleFactory.requests[0].headers).includes('x-zse-96')).assertTrue();
      expect(peopleFactory.requests[0].maxRedirects).assertEqual(0);
      expect(pinFactory.requests[0].headers.Cookie?.includes('people-pin-session')).assertTrue();
      expect(JSON.stringify(pinFactory.requests[0].headers).includes('x-zse-96')).assertTrue();
      expect(pinFactory.requests[0].maxRedirects).assertEqual(0);
    });

    it('decodesProfilePinAuthorTopicsStatisticsAndCanonicalUrls', 0, () => {
      const people = decodePeopleDetail(PEOPLE_JSON, 'alice-token');
      const pin = decodePinDetail(PIN_JSON, '9007199254740993');
      expect(people.id).assertEqual('member-hash');
      expect(people.followingCount).assertEqual(12);
      expect(people.answerCount).assertEqual(34);
      expect(people.canonicalUrl).assertEqual('https://www.zhihu.com/people/alice-token');
      expect(pin.id).assertEqual('9007199254740993');
      expect(pin.likeCount).assertEqual(56);
      expect(pin.topics.length).assertEqual(1);
      expect(pin.topics[0].name).assertEqual('HarmonyOS');
      expect(pin.url).assertEqual('https://www.zhihu.com/pin/9007199254740993');
    });

    it('rejectsMismatchedIdentityAndMalformedStatistics', 0, () => {
      let peopleFailure: DomainDecodeError | undefined = undefined;
      let pinFailure: DomainDecodeError | undefined = undefined;
      try {
        decodePeopleDetail(PEOPLE_JSON, 'other-user');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          peopleFailure = error;
        }
      }
      try {
        decodePinDetail('{"id":101,"author":{"id":"a","name":"A"},"like_count":-1}', '101');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          pinFailure = error;
        }
      }
      expect(peopleFailure instanceof DomainDecodeError).assertTrue();
      expect(pinFailure instanceof DomainDecodeError).assertTrue();
    });

    it('dropsUnsafeAvatarAndDoesNotExposeUpstreamSecrets', 0, () => {
      const unsafeAvatar = decodePeopleDetail(
        '{"id":"a","url_token":"a","name":"A","avatar_url":"https://evil.example/a.png"}',
        'a'
      );
      expect(unsafeAvatar.avatarUrl).assertUndefined();
      let failure: DomainDecodeError | undefined = undefined;
      try {
        decodePinDetail(
          '{"error":{"code":403,"message":"Cookie z_c0=secret https://evil.example"}}',
          '1'
        );
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          failure = error;
        }
      }
      expect(failure instanceof DomainDecodeError).assertTrue();
      expect(failure?.message.includes('secret')).assertFalse();
      expect(failure?.message.includes('evil.example')).assertFalse();
    });

    it('cancelsPendingRequestWithoutWaitingForTransport', 0, async () => {
      const factory = new PendingDetailTransportFactory();
      // people 请求已走会话签名，需要提供含 d_c0 的 cookie provider 才能正常发起。
      const repository = new DefaultPeopleRepository(
        new ZhihuHttpClient(new DetailCookieProvider(), factory)
      );
      const pending = repository.getUser('alice-token');
      repository.cancel();
      let failure: HttpFailure | undefined = undefined;
      try {
        await pending;
      } catch (error) {
        if (error instanceof HttpFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(HttpFailureKind.CANCELLED);
      expect(factory.transport.requestCount).assertEqual(1);
      expect(factory.transport.destroyCount).assertEqual(1);
    });

    it('buildsSignedPeopleContentEndpointsAndRejectsForeignCursors', 0, () => {
      expect(buildPeopleContentUrl('alice-token', PeopleContentSection.ANSWERS)).assertEqual(
        'https://www.zhihu.com/api/v4/members/alice-token/answers?sort_by=voteups&limit=20&' +
          'include=data%5B%2A%5D.question%2Cexcerpt%2Cvoteup_count%2Ccomment_count%2Ccreated_time'
      );
      expect(buildPeopleContentUrl('alice-token', PeopleContentSection.ARTICLES)).assertEqual(
        'https://www.zhihu.com/api/v4/members/alice-token/articles?sort_by=created&limit=20&' +
          'include=data%5B%2A%5D.title%2Cexcerpt%2Cvoteup_count%2Ccomment_count%2Ccreated%2Cupdated'
      );
      let failure: PeopleContentRepositoryFailure | undefined = undefined;
      try {
        buildPeopleContentUrl('alice-token', PeopleContentSection.ANSWERS,
          'https://www.zhihu.com/api/v4/members/other/answers?offset=20');
      } catch (error) {
        if (error instanceof PeopleContentRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(PeopleContentRepositoryFailureKind.INVALID_CURSOR);
    });

    it('acceptsHttpSchemePeopleContentCursorFromZhihu', 0, () => {
      // 知乎分页 next 可能返回 http://（与通知分页同源），应归一化后接受，
      // 否则整个用户内容首屏加载报 INVALID_CURSOR 失败。
      const next = 'http://www.zhihu.com/api/v4/members/alice-token/answers?offset=20&limit=20';
      expect(isPeopleContentCursorUrl('alice-token', PeopleContentSection.ANSWERS, next)).assertTrue();
      const rebuilt = buildPeopleContentUrl('alice-token', PeopleContentSection.ANSWERS, next);
      expect(rebuilt.startsWith('https://www.zhihu.com/api/v4/members/alice-token/answers?')).assertTrue();
      expect(rebuilt.includes('offset=20')).assertTrue();
      expect(rebuilt.includes('include=')).assertTrue();
    });

    it('decodesAndDeduplicatesPeopleContentPages', 0, async () => {
      const next = 'https://www.zhihu.com/api/v4/members/alice-token/answers?offset=20&limit=20';
      const factory = new DetailTransportFactory([
        { statusCode: 200, body: PEOPLE_ANSWERS_JSON },
        { statusCode: 200, body: PEOPLE_ANSWERS_NEXT_JSON }
      ]);
      const repository = new DefaultPeopleContentRepository(new ZhihuHttpClient(new DetailCookieProvider(), factory));
      const first = await repository.getContentPage('alice-token', PeopleContentSection.ANSWERS);
      const second = await repository.getContentPage('alice-token', PeopleContentSection.ANSWERS, next);
      expect(first.items.length).assertEqual(1);
      expect(first.items[0].title).assertEqual('用户回答的问题');
      expect(second.items.length).assertEqual(1);
      expect(second.items[0].id).assertEqual('103');
      expect(factory.requests[0].headers.Cookie?.includes('people-pin-session')).assertTrue();
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
    });
  });
}

const PEOPLE_JSON = '{"id":"member-hash","url_token":"alice-token","name":"Alice",' +
  '"headline":"HarmonyOS developer","avatar_url":"https://picx.zhimg.com/avatar.png",' +
  '"follower_count":78,"following_count":12,"answer_count":34,"articles_count":5,' +
  '"is_following":true,"is_org":false}';
const PIN_JSON = '{"id":9007199254740993,"content_html":"<p>想法正文</p>",' +
  '"like_count":56,"comment_count":7,"created":1,"updated":2,' +
  '"author":{"id":"pin-author","url_token":"pin-author-token","name":"Pin Author",' +
  '"headline":"作者签名","avatar_url":"https://pic1.zhimg.com/author.png"},' +
  '"topics":[{"id":19551275,"name":"HarmonyOS"}]}';
const PEOPLE_ANSWERS_JSON = '{"data":[{"id":101,"question":{"id":1,"title":"用户回答的问题"},' +
  '"excerpt":"回答摘要","voteup_count":3,"comment_count":2,"created_time":1},' +
  '{"id":101,"question":{"id":1,"title":"重复回答"},"excerpt":"重复","voteup_count":3,' +
  '"comment_count":2,"created_time":1}],"paging":{"is_end":false,' +
  '"next":"https://www.zhihu.com/api/v4/members/alice-token/answers?offset=20&limit=20"}}';
const PEOPLE_ANSWERS_NEXT_JSON = '{"data":[{"id":101,"question":{"id":1,"title":"重复回答"},' +
  '"excerpt":"重复","voteup_count":3,"comment_count":2,"created_time":1},' +
  '{"id":103,"question":{"id":2,"title":"第二个问题"},"excerpt":"第二条",' +
  '"voteup_count":4,"comment_count":1,"created_time":2}],"paging":{"is_end":true}}';
