import { describe, expect, it } from '@ohos/hypium';
import {
  buildHomeFeedRequestUrl,
  canonicalHomeFeedCursorKey,
  DefaultFeedRepository,
  FeedRepositoryFailure,
  FeedRepositoryFailureKind,
  BlockableContentSummary,
  BlockingMatch,
  BlockingRuleKind,
  ContentBlockingMatcher,
  ContentBlockingSession,
  HOME_FEED_URL,
  HomeFeedStartupCacheGateway,
  HttpFailure,
  isHomeFeedCursorUrl,
  PreparedZhihuHttpRequest,
  RecommendationFilterPreferences,
  RecommendationFilterPreferencesGateway,
  RecommendationMode,
  defaultRecommendationFilterPreferences,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory,
  ZhihuMobileHttpClient
} from 'data';

class FixedRecommendationPreferences implements RecommendationFilterPreferencesGateway {
  value: RecommendationFilterPreferences = defaultRecommendationFilterPreferences();

  loadRecommendationFilterPreferences(): Promise<RecommendationFilterPreferences> {
    return Promise.resolve(this.value);
  }

  saveRecommendationFilterPreferences(value: RecommendationFilterPreferences): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

class MemoryHomeFeedCache implements HomeFeedStartupCacheGateway {
  web?: string;
  android?: string;

  loadHomeFeedStartupResponse(mode: RecommendationMode): Promise<string | undefined> {
    return Promise.resolve(mode === RecommendationMode.ANDROID ? this.android : this.web);
  }

  saveHomeFeedStartupResponse(mode: RecommendationMode, response: string): Promise<void> {
    if (mode === RecommendationMode.ANDROID) this.android = response;
    else this.web = response;
    return Promise.resolve();
  }
}

class CountingSessionProvider implements SessionCookieProvider {
  readCount: number = 0;

  getCookies(): Array<SessionCookie> {
    this.readCount += 1;
    return [
      { name: 'z_c0', value: 'test-session-cookie' },
      { name: 'd_c0', value: 'test-device-cookie' }
    ];
  }
}

class FeedTransport implements ZhihuHttpTransport {
  private readonly response: ZhihuHttpResponse;
  readonly requests: Array<PreparedZhihuHttpRequest>;

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

class SequenceFeedTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private responseIndex: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.responseIndex];
    this.responseIndex += 1;
    return new FeedTransport(response, this.requests);
  }
}

class PendingFeedTransport implements ZhihuHttpTransport {
  private resolveRequest?: (response: ZhihuHttpResponse) => void;
  destroyed: boolean = false;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((resolve: (response: ZhihuHttpResponse) => void): void => {
      this.resolveRequest = resolve;
    });
  }

  resolve(response: ZhihuHttpResponse): void {
    this.resolveRequest?.(response);
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class CancellationFeedTransportFactory implements ZhihuHttpTransportFactory {
  readonly pending = new PendingFeedTransport();
  private createCount: number = 0;

  create(): ZhihuHttpTransport {
    this.createCount += 1;
    if (this.createCount === 1) {
      return new FeedTransport({ statusCode: 200, body: FIRST_PAGE }, []);
    }
    if (this.createCount === 2) {
      return this.pending;
    }
    return new FeedTransport({
      statusCode: 200,
      body: '{"data":[{"id":"fresh-wrapper","target":{"type":"article",' +
        '"id":"fresh-article","title":"刷新结果"}}],"paging":{"is_end":true}}'
    }, []);
  }
}

class RecordingFeedBlockingSession implements ContentBlockingSession {
  readonly summaries: Array<BlockableContentSummary> = [];

  match(content: BlockableContentSummary): BlockingMatch | undefined {
    this.summaries.push(content);
    return content.title.includes('屏蔽') ? {
      kind: BlockingRuleKind.KEYWORD,
      ruleId: '1',
      reason: 'test'
    } : undefined;
  }
}

class RecordingFeedBlockingMatcher implements ContentBlockingMatcher {
  readonly session: RecordingFeedBlockingSession = new RecordingFeedBlockingSession();
  createCount: number = 0;

  createSession(): Promise<ContentBlockingSession> {
    this.createCount += 1;
    return Promise.resolve(this.session);
  }
}

const FIRST_PAGE = '{"data":[{"id":"feed-1","target":{"type":"article",' +
  '"id":"article-1","title":"第一�?","author":{"id":"author-1","name":"作�?"},' +
  '"bound_topic_ids":[19551275]}}],"paging":{"is_end":false,"is_start":true,' +
  '"next":"https://www.zhihu.com/api/v3/feed/topstory/recommend?include=stale&%6fffset=2"}}';
const SECOND_PAGE = '{"data":[{"id":"feed-1","target":{"type":"article",' +
  '"id":"article-1","title":"重复�?"}},{"id":"feed-2","target":{"type":"question",' +
  '"id":"question-2","title":"第二�?"}},{"id":"feed-1","target":{"type":"question",' +
  '"id":"question-cross-kind","title":"�? Feed ID 的另一内容"}}],"paging":{"is_end":false,"is_start":false,' +
  '"next":"https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=2"}}';
const MOBILE_PAGE = '{"data":[{"id":"mobile-card-1","type":"ComponentCard",' +
  '"action":{"parameter":"route_url=https%3A%2F%2Fwww.zhihu.com%2Fquestion%2F100%2Fanswer%2F200"},' +
  '"children":[{"id":"Text","text":"移动推荐回答"},' +
  '{"id":"text_pin_summary","text":"移动摘要"},' +
  '{"type":"Line","elements":[{"reaction":"Vote","count":88},{"reaction":"Comment","count":7}]},' +
  '{"style":"RecommendAuthorLine_default","follower_count":200,"is_following":false,' +
  '"elements":[{"type":"Text","text":"移动作�?"},' +
  '{"style":"Avatar_default","image":{"url":"https://pic.zhimg.com/avatar.jpg"}}]}]}],' +
  '"paging":{"is_end":true,"is_start":true}}';
const LOCAL_FOLLOWING_PAGE = '{"data":[{"id":"local-following","target":{"type":"article",' +
  '"id":"31","title":"followed-item","author":{"id":"author-9","name":"followed-author","is_following":true}}},' +
  '{"id":"local-trending","target":{"type":"article","id":"32","title":"trending-item"}}],' +
  '"paging":{"is_end":true}}';
const EXPECTED_HOME_FEED_INCLUDE_QUERY =
  'include=data%5B%2A%5D.content%2Cexcerpt%2Cheadline%2Ctarget.voteup_count%2Ctarget.vote_count%2C' +
    'target.comment_count%2Ctarget.answer_count%2Ctarget.follower_count%2Ctarget.author.badge_v2%2C' +
    'target.author.is_following%2Ctarget.author.follower_count%2Ctarget.bound_topic_ids%2C' +
    'target.question.bound_topic_ids%2Ctarget.question.author';

export default function homeFeedRepositoryTest(): void {
  describe('homeFeedRepositoryTest', () => {
    it('buildsExactInitialAndPagingRequestUrls', 0, () => {
      expect(buildHomeFeedRequestUrl()).assertEqual(HOME_FEED_URL);
      expect(buildHomeFeedRequestUrl('https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=2')).assertEqual(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=2&' + EXPECTED_HOME_FEED_INCLUDE_QUERY
      );
      expect(buildHomeFeedRequestUrl(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?include=stale&offset=3'
      )).assertEqual(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=3&' + EXPECTED_HOME_FEED_INCLUDE_QUERY
      );
      expect(buildHomeFeedRequestUrl(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?%69nclude=stale&%6fffset=3'
      )).assertEqual(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=3&' + EXPECTED_HOME_FEED_INCLUDE_QUERY
      );
      expect(canonicalHomeFeedCursorKey(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=3&limit=10'
      )).assertEqual(canonicalHomeFeedCursorKey(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?limit=10&%6fffset=3'
      ));
    });

    it('acceptsOnlyExactHttpsHomeFeedCursors', 0, () => {
      expect(isHomeFeedCursorUrl('https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=2')).assertTrue();
      expect(isHomeFeedCursorUrl('https://www.zhihu.com.evil.example/api/v3/feed/topstory/recommend')).assertFalse();
      expect(isHomeFeedCursorUrl('https://www.zhihu.com/notifications/v3/message/v3')).assertFalse();
      expect(isHomeFeedCursorUrl('http://www.zhihu.com/api/v3/feed/topstory/recommend')).assertFalse();
      expect(isHomeFeedCursorUrl('https://www.zhihu.com/api/v3/feed/topstory/recommend#redirect')).assertFalse();
    });

    it('signsHomeRequestWithValidatedWebSession', 0, async () => {
      const provider = new CountingSessionProvider();
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: '{"data":[],"paging":{"is_end":false,"is_start":true}}' }
      ]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(provider, factory));
      const page = await repository.loadHomePage();

      expect(page.items.length).assertEqual(0);
      expect(page.cursor.isEnd).assertTrue();
      expect(factory.requests[0].url).assertEqual(HOME_FEED_URL);
      expect(factory.requests[0].headers.Cookie?.includes('test-session-cookie')).assertTrue();
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
      expect(provider.readCount).assertEqual(1);
    });

    it('honorsGuestRecommendationAndSkipsWebCredentials', 0, async () => {
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: '{"data":[],"paging":{"is_end":true}}' }
      ]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.WEB;
      preferences.value.loginForRecommendation = false;
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), undefined,
        preferences, new MemoryHomeFeedCache());
      await repository.loadHomePage();

      expect(factory.requests[0].headers.Cookie).assertUndefined();
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertFalse();
    });

    it('requiresAnAuthenticatedSessionWhenRecommendationLoginIsEnabled', 0, async () => {
      const factory = new SequenceFeedTransportFactory([]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.WEB;
      let failure: HttpFailure | undefined;
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), undefined,
        preferences, new MemoryHomeFeedCache());
      try {
        await repository.loadHomePage();
      } catch (error) {
        if (error instanceof HttpFailure) failure = error;
      }
      expect(failure?.kind).assertEqual('authentication');
      expect(factory.requests.length).assertEqual(0);
    });

    it('mergesWebAndAndroidRecommendationSources', 0, async () => {
      const webFactory = new SequenceFeedTransportFactory([{ statusCode: 200, body: FIRST_PAGE }]);
      const mobileFactory = new SequenceFeedTransportFactory([{ statusCode: 200, body: MOBILE_PAGE }]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.MIXED;
      preferences.value.loginForRecommendation = false;
      const mobile = new ZhihuMobileHttpClient(undefined, mobileFactory);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, webFactory), undefined,
        preferences, new MemoryHomeFeedCache(), mobile);
      const page = await repository.loadHomePage();

      expect(page.items.length).assertEqual(2);
      expect(page.items[0].target.title).assertEqual('第一�?');
      expect(page.items[1].target.title).assertEqual('移动推荐回答');
      expect(page.items[1].actionText).assertEqual('\u624b\u673a\u7248\u63a8\u8350');
      expect(mobileFactory.requests[0].headers.Cookie).assertUndefined();
    });

    it('restoresStartupSnapshotWhenAutomaticRefreshIsDisabled', 0, async () => {
      const factory = new SequenceFeedTransportFactory([]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.WEB;
      preferences.value.loginForRecommendation = false;
      preferences.value.autoRefreshHomeOnStartup = false;
      const cache = new MemoryHomeFeedCache();
      cache.web = FIRST_PAGE;
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), undefined,
        preferences, cache);
      const page = await repository.loadHomePage();

      expect(page.items[0].target.title).assertEqual('第一�?');
      expect(page.cursor.isEnd).assertTrue();
      expect(factory.requests.length).assertEqual(0);
    });

    it('decodesAndroidRecommendationCardsAndUsesMobileEndpoint', 0, async () => {
      const factory = new SequenceFeedTransportFactory([{ statusCode: 200, body: MOBILE_PAGE }]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.ANDROID;
      preferences.value.loginForRecommendation = false;
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), undefined,
        preferences, new MemoryHomeFeedCache());
      const page = await repository.loadHomePage();

      expect(factory.requests[0].url).assertEqual('https://api.zhihu.com/topstory/recommend');
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].target.id).assertEqual('200');
      expect(page.items[0].target.voteupCount).assertEqual(88);
      expect(page.items[0].actionText).assertEqual('\u624b\u673a\u7248\u63a8\u8350');
      expect(page.items[0].target.author?.name).assertEqual('移动作�?');
      expect(page.items[0].target.authorFollowerCount).assertEqual(200);
      expect(page.items[0].target.authorIsFollowing).assertFalse();
    });

    it('ranksCachedCandidatesLocallyWithoutNetworkRequests', 0, async () => {
      const low = '{"data":[{"id":"low","target":{"type":"article","id":"1","title":"低分",' +
        '"voteup_count":1}},{"id":"high","target":{"type":"article","id":"2","title":"高分",' +
        '"voteup_count":100}}],"paging":{"is_end":true}}';
      const factory = new SequenceFeedTransportFactory([]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.LOCAL;
      preferences.value.loginForRecommendation = false;
      const cache = new MemoryHomeFeedCache();
      cache.web = low;
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), undefined,
        preferences, cache);
      const page = await repository.loadHomePage();

      expect(page.items[0].target.title).assertEqual('高分');
      expect(page.cursor.isEnd).assertTrue();
      expect(factory.requests.length).assertEqual(0);
    });

    it('annotatesLocalRankingWithRecommendationReasons', 0, async () => {
      const factory = new SequenceFeedTransportFactory([]);
      const preferences = new FixedRecommendationPreferences();
      preferences.value.recommendationMode = RecommendationMode.LOCAL;
      preferences.value.loginForRecommendation = false;
      const cache = new MemoryHomeFeedCache();
      cache.web = LOCAL_FOLLOWING_PAGE;
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), undefined,
        preferences, cache);
      const page = await repository.loadHomePage();

      expect(page.items.length).assertEqual(2);
      expect(page.items[0].recommendationReason).assertEqual('\u5173\u6ce8\u7528\u6237\u7684\u6700\u65b0\u52a8\u6001');
      expect(page.items[1].recommendationReason).assertEqual('\u70ed\u95e8\u63a8\u8350');
      expect(factory.requests.length).assertEqual(0);
    });

    it('filtersEachPageWithOneSnapshotAndRealAuthorTopicFields', 0, async () => {
      const factory = new SequenceFeedTransportFactory([{ statusCode: 200, body: '{"data":[' +
        '{"id":"feed-1","target":{"type":"article","id":"1","title":"保留",' +
        '"voteup_count":2374,"comment_count":424,' +
        '"author":{"id":"author-1","name":"作�?","follower_count":5000,"is_following":false},' +
        '"bound_topic_ids":[19551275]}},' +
        '{"id":"feed-2","target":{"type":"article","id":"2","title":"屏蔽内容",' +
        '"bound_topic_ids":[19551276]}}],"paging":{"is_end":true}}' }]);
      const matcher = new RecordingFeedBlockingMatcher();
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(new CountingSessionProvider(), factory), matcher);
      const page = await repository.loadHomePage();

      expect(matcher.createCount).assertEqual(1);
      expect(matcher.session.summaries.length).assertEqual(2);
      expect(matcher.session.summaries[0].authorId).assertEqual('author-1');
      expect(matcher.session.summaries[0].topicIds[0]).assertEqual('19551275');
      expect(matcher.session.summaries[0].voteupCount).assertEqual(2374);
      expect(matcher.session.summaries[0].authorFollowerCount).assertEqual(5000);
      expect(matcher.session.summaries[0].authorIsFollowing).assertFalse();
      expect(matcher.session.summaries[1].voteupCount).assertUndefined();
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].target.id).assertEqual('1');
    });

    it('deduplicatesItemsAcrossPagesAndStopsLoopingCursor', 0, async () => {
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(new CountingSessionProvider(), factory));
      const first = await repository.loadHomePage();
      const second = await repository.loadHomePage(first.cursor.next);

      expect(first.items.length).assertEqual(1);
      expect(second.items.length).assertEqual(2);
      expect(second.items[0].target.id).assertEqual('question-2');
      expect(second.items[1].target.id).assertEqual('question-cross-kind');
      expect(second.cursor.isEnd).assertTrue();
      expect(second.cursor.next).assertUndefined();
      expect(factory.requests[1].url).assertEqual(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend?offset=2&' + EXPECTED_HOME_FEED_INCLUDE_QUERY
      );
    });

    it('allowsRetryAfterTransientPagingFailure', 0, async () => {
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 503, body: 'upstream detail must not escape' },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(new CountingSessionProvider(), factory));
      const first = await repository.loadHomePage();
      let failure: HttpFailure | undefined = undefined;
      try {
        await repository.loadHomePage(first.cursor.next);
      } catch (error) {
        if (error instanceof HttpFailure) {
          failure = error;
        }
      }
      const retried = await repository.loadHomePage(first.cursor.next);

      expect(failure?.status).assertEqual(503);
      expect(failure?.message.includes('upstream detail')).assertFalse();
      expect(retried.items.length).assertEqual(2);
      expect(factory.requests.length).assertEqual(3);
    });

    it('cancelsOldPaginationBeforeStartingFreshSequence', 0, async () => {
      const factory = new CancellationFeedTransportFactory();
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(new CountingSessionProvider(), factory));
      const first = await repository.loadHomePage();
      const stalePaging = repository.loadHomePage(first.cursor.next);
      repository.cancel();
      let cancelled: boolean = false;
      try {
        await stalePaging;
      } catch (_error) {
        cancelled = true;
      }
      const fresh = await repository.loadHomePage();
      factory.pending.resolve({ statusCode: 200, body: SECOND_PAGE });

      expect(cancelled).assertTrue();
      expect(factory.pending.destroyed).assertTrue();
      expect(fresh.items.length).assertEqual(1);
      expect(fresh.items[0].target.id).assertEqual('fresh-article');
    });

    it('rejectsUntrustedResponseCursorWithoutLeakingIt', 0, async () => {
      const factory = new SequenceFeedTransportFactory([{
        statusCode: 200,
        body: '{"data":[],"paging":{"is_end":false,' +
          '"next":"https://www.zhihu.com.evil.example/secret?token=sensitive"}}'
      }]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(new CountingSessionProvider(), factory));
      let failure: FeedRepositoryFailure | undefined = undefined;
      try {
        await repository.loadHomePage();
      } catch (error) {
        if (error instanceof FeedRepositoryFailure) {
          failure = error;
        }
      }

      expect(failure?.kind).assertEqual(FeedRepositoryFailureKind.INVALID_CURSOR);
      expect(failure?.message.includes('sensitive')).assertFalse();
    });
  });
}
