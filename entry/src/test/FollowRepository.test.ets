import { describe, expect, it } from '@ohos/hypium';
import {
  buildMemberFollowUrl,
  buildQuestionFollowUrl,
  ContentRepositoryFailure,
  ContentRepositoryFailureKind,
  DefaultFollowRepository,
  PeopleRepositoryFailure,
  PeopleRepositoryFailureKind,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class FollowCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'd_c0', value: 'follow-device-cookie' },
      { name: 'z_c0', value: 'follow-session-cookie' }
    ];
  }
}

class FollowTransport implements ZhihuHttpTransport {
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

class FollowTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new FollowTransport(response, this.requests);
  }
}

export default function followRepositoryTest(): void {
  describe('followRepositoryTest', () => {
    it('buildsCanonicalFollowUrlsAndRejectsInjection', 0, () => {
      expect(buildMemberFollowUrl('alice-token')).assertEqual(
        'https://www.zhihu.com/api/v4/members/alice-token/followers'
      );
      expect(buildMemberFollowUrl('a_b-1')).assertEqual(
        'https://www.zhihu.com/api/v4/members/a_b-1/followers'
      );
      expect(buildQuestionFollowUrl('123')).assertEqual(
        'https://www.zhihu.com/api/v4/questions/123/followers'
      );

      const badPeople: Array<string> = ['', '../alice', 'alice/answers', 'alice?include=x', 'user@host', '百分号%'];
      badPeople.forEach((identifier: string): void => {
        let failure: PeopleRepositoryFailure | undefined = undefined;
        try {
          buildMemberFollowUrl(identifier);
        } catch (error) {
          if (error instanceof PeopleRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(PeopleRepositoryFailureKind.INVALID_IDENTIFIER);
      });

      const badQuestions: Array<string> = ['', '0', '-1', '01', '1/2', '1?x=2', '1%2F2'];
      badQuestions.forEach((id: string): void => {
        let failure: ContentRepositoryFailure | undefined = undefined;
        try {
          buildQuestionFollowUrl(id);
        } catch (error) {
          if (error instanceof ContentRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(ContentRepositoryFailureKind.INVALID_ID);
      });
    });

    it('followsAndUnfollowsMemberWithParsedFollowerCount', 0, async () => {
      const factory = new FollowTransportFactory([
        { statusCode: 200, body: '{"follower_count":99,"is_following":true}' },
        { statusCode: 200, body: '{"follower_count":98,"is_following":false}' }
      ]);
      const repository = new DefaultFollowRepository(new ZhihuHttpClient(new FollowCookieProvider(), factory));
      const followed = await repository.followUser('alice-token', true);
      const unfollowed = await repository.followUser('alice-token', false);

      expect(followed.followerCount).assertEqual(99);
      expect(unfollowed.followerCount).assertEqual(98);
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.POST);
      expect(factory.requests[0].url).assertEqual(
        'https://www.zhihu.com/api/v4/members/alice-token/followers'
      );
      expect(factory.requests[1].method).assertEqual(ZhihuHttpMethod.DELETE);
      factory.requests.forEach((request: PreparedZhihuHttpRequest): void => {
        expect(request.maxRedirects).assertEqual(0);
        expect(request.headers.Cookie?.includes('follow-session-cookie')).assertTrue();
        expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
      });
    });

    it('followsAndUnfollowsQuestionWithParsedFollowerCount', 0, async () => {
      const factory = new FollowTransportFactory([
        { statusCode: 200, body: '{"follower_count":55}' },
        { statusCode: 200, body: '{"follower_count":54}' }
      ]);
      const repository = new DefaultFollowRepository(new ZhihuHttpClient(new FollowCookieProvider(), factory));
      const followed = await repository.followQuestion('123', true);
      const unfollowed = await repository.followQuestion('123', false);

      expect(followed.followerCount).assertEqual(55);
      expect(unfollowed.followerCount).assertEqual(54);
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.POST);
      expect(factory.requests[0].url).assertEqual('https://www.zhihu.com/api/v4/questions/123/followers');
      expect(factory.requests[1].method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(factory.requests[1].url).assertEqual('https://www.zhihu.com/api/v4/questions/123/followers');
    });

    it('toleratesInvalidOrMissingFollowerCountsInResponses', 0, async () => {
      const factory = new FollowTransportFactory([
        { statusCode: 200, body: 'not-json' },
        { statusCode: 200, body: '{}' }
      ]);
      const repository = new DefaultFollowRepository(new ZhihuHttpClient(new FollowCookieProvider(), factory));
      const invalid = await repository.followUser('alice-token', true);
      const missing = await repository.followQuestion('123', true);

      expect(invalid.followerCount).assertUndefined();
      expect(missing.followerCount).assertUndefined();
    });
  });
}
