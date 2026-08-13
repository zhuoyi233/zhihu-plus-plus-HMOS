import { describe, expect, it } from '@ohos/hypium';
import {
  buildChannelFeedRequestUrl,
  BlockableContentSummary,
  BlockingMatch,
  BlockingRuleKind,
  canonicalChannelFeedCursorKey,
  ChannelFeedItemKind,
  ChannelFeedRepositoryFailure,
  ChannelFeedRepositoryFailureKind,
  ChannelFeedSource,
  ContentBlockingMatcher,
  ContentBlockingSession,
  DAILY_FALLBACK_BASE_URL,
  DefaultChannelFeedRepository,
  decodeChannelContentPage,
  decodeDailyFeedPage,
  DomainDecodeError,
  DomainDecodeFailureKind,
  FOLLOWING_FEED_BASE_URL,
  HOT_FEED_BASE_URL,
  HttpFailure,
  HttpFailureKind,
  isChannelFeedCursorUrl,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class ChannelCookieProvider implements SessionCookieProvider {
  readCount: number = 0;

  getCookies(): Array<SessionCookie> {
    this.readCount += 1;
    return [
      { name: 'z_c0', value: 'session-token' },
      { name: 'd_c0', value: 'device-token' }
    ];
  }
}

class TransportBusinessError extends Error {
  readonly code: number;

  constructor(code: number) {
    super('transport details must not escape');
    this.code = code;
  }
}

class ChannelOutcome {
  readonly response?: ZhihuHttpResponse;
  readonly error?: Error;

  constructor(response?: ZhihuHttpResponse, error?: Error) {
    this.response = response;
    this.error = error;
  }
}

class ChannelTransport implements ZhihuHttpTransport {
  private readonly outcome: ChannelOutcome;
  private readonly requests: Array<PreparedZhihuHttpRequest>;
  destroyed: boolean = false;

  constructor(outcome: ChannelOutcome, requests: Array<PreparedZhihuHttpRequest>) {
    this.outcome = outcome;
    this.requests = requests;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    if (this.outcome.error !== undefined) {
      return Promise.reject(this.outcome.error);
    }
    if (this.outcome.response !== undefined) {
      return Promise.resolve(this.outcome.response);
    }
    return Promise.reject(new Error('missing test outcome'));
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class SequenceChannelTransportFactory implements ZhihuHttpTransportFactory {
  private readonly outcomes: Array<ChannelOutcome>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(outcomes: Array<ChannelOutcome>) {
    this.outcomes = outcomes;
  }

  create(): ZhihuHttpTransport {
    const outcome = this.outcomes[this.index];
    this.index += 1;
    return new ChannelTransport(outcome, this.requests);
  }
}

class PendingChannelTransport implements ZhihuHttpTransport {
  destroyed: boolean = false;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, _reject) => {
    });
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class PendingChannelTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingChannelTransport = new PendingChannelTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

class TitleBlockingSession implements ContentBlockingSession {
  private readonly summaries: Array<BlockableContentSummary>;

  constructor(summaries: Array<BlockableContentSummary>) {
    this.summaries = summaries;
  }

  match(content: BlockableContentSummary): BlockingMatch | undefined {
    this.summaries.push(content);
    if (content.title.includes('热榜')) {
      return {
        kind: BlockingRuleKind.KEYWORD,
        ruleId: '1',
        reason: '命中屏蔽关键词'
      };
    }
    return undefined;
  }
}

class TitleBlockingMatcher implements ContentBlockingMatcher {
  readonly summaries: Array<BlockableContentSummary> = [];
  createSessionCount: number = 0;

  createSession(): Promise<ContentBlockingSession> {
    this.createSessionCount += 1;
    return Promise.resolve(new TitleBlockingSession(this.summaries));
  }
}

const FOLLOW_PAGE = '{"data":[{"type":"moments_feed","id":"follow-wrapper","moment_desc":"张三赞同了回答",' +
  '"target":{"type":"answer","id":"101","excerpt":"摘要","question":{"title":"关注问题"},' +
  '"author":{"id":"author-1","name":"张三"}}}],"paging":{"is_end":false,' +
  '"next":"https://www.zhihu.com/api/v3/moments?desktop=true&limit=10&offset=10"}}';
const HOT_PAGE = '{"data":[{"type":"hot_list_feed","id":"hot-wrapper","detail_text":"1234 万热度",' +
  '"target":{"type":"question","id":"202","title":"热榜问题","bound_topic_ids":[1,"2",1]}}],' +
  '"paging":{"is_end":true}}';
const FILTER_PAGE = '{"data":[{"id":"blocked","target":{"type":"question","id":"202",' +
  '"title":"热榜问题","bound_topic_ids":[1,"2",1]}},{"id":"visible",' +
  '"target":{"type":"article","id":"203","title":"普通文章"}}],"paging":{"is_end":true}}';
const DAILY_PAGE = '{"date":"20260811","stories":[{"id":303,"title":"日报标题",' +
  '"hint":"作者 · 栏目","url":"https://daily.zhihu.com/story/303",' +
  '"images":["https://pic.example/303.jpg"],"type":0}]}';

export default function channelFeedRepositoryTest(): void {
  describe('channelFeedRepositoryTest', () => {
    it('buildsExactInitialUrlsAndCanonicalContentCursors', 0, () => {
      expect(buildChannelFeedRequestUrl(ChannelFeedSource.FOLLOWING).startsWith(FOLLOWING_FEED_BASE_URL)).assertTrue();
      expect(buildChannelFeedRequestUrl(ChannelFeedSource.HOT).startsWith(HOT_FEED_BASE_URL)).assertTrue();
      expect(buildChannelFeedRequestUrl(ChannelFeedSource.DAILY)).assertEqual(
        'https://news-at.zhihu.com/api/4/stories/latest'
      );
      expect(buildChannelFeedRequestUrl(ChannelFeedSource.DAILY, '20260810')).assertEqual(
        'https://news-at.zhihu.com/api/4/stories/before/20260810'
      );
      expect(canonicalChannelFeedCursorKey(
        ChannelFeedSource.FOLLOWING,
        'https://www.zhihu.com/api/v3/moments?offset=10&limit=10'
      )).assertEqual(canonicalChannelFeedCursorKey(
        ChannelFeedSource.FOLLOWING,
        'https://www.zhihu.com/api/v3/moments?limit=10&offset=10'
      ));
    });

    it('rejectsCrossEndpointAndMalformedCursors', 0, () => {
      expect(isChannelFeedCursorUrl(
        ChannelFeedSource.FOLLOWING,
        'https://www.zhihu.com/api/v3/moments?offset=10'
      )).assertTrue();
      expect(isChannelFeedCursorUrl(
        ChannelFeedSource.FOLLOWING,
        'https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total?offset=10'
      )).assertFalse();
      expect(isChannelFeedCursorUrl(
        ChannelFeedSource.HOT,
        'https://www.zhihu.com.evil.example/api/v3/feed/topstory/hot-lists/total'
      )).assertFalse();
      let failure: ChannelFeedRepositoryFailure | undefined = undefined;
      try {
        buildChannelFeedRequestUrl(ChannelFeedSource.DAILY, '../latest');
      } catch (error) {
        if (error instanceof ChannelFeedRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(ChannelFeedRepositoryFailureKind.INVALID_CURSOR);
      expect(() => buildChannelFeedRequestUrl(ChannelFeedSource.DAILY, '20261340')).assertThrowError(
        '频道返回了不受信任的分页游标'
      );
    });

    it('usesSignedSessionOnlyForFollowing', 0, async () => {
      const provider = new ChannelCookieProvider();
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome({ statusCode: 200, body: FOLLOW_PAGE }),
        new ChannelOutcome({ statusCode: 200, body: HOT_PAGE })
      ]);
      const client = new ZhihuHttpClient(provider, factory);
      const following = await new DefaultChannelFeedRepository(client).loadPage(ChannelFeedSource.FOLLOWING);
      const hot = await new DefaultChannelFeedRepository(client).loadPage(ChannelFeedSource.HOT);

      expect(following.items[0].kind).assertEqual(ChannelFeedItemKind.CONTENT);
      expect(factory.requests[0].headers.Cookie).assertEqual('z_c0=session-token; d_c0=device-token');
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
      expect(factory.requests[1].headers.Cookie).assertUndefined();
      expect(JSON.stringify(factory.requests[1].headers).includes('x-zse-')).assertFalse();
      expect(provider.readCount).assertEqual(1);
    });

    it('preservesFollowingAndHotDisplayLabelsAndTopicIds', 0, async () => {
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome({ statusCode: 200, body: FOLLOW_PAGE }),
        new ChannelOutcome({ statusCode: 200, body: HOT_PAGE })
      ]);
      const following = await new DefaultChannelFeedRepository(
        new ZhihuHttpClient(new ChannelCookieProvider(), factory)
      ).loadPage(ChannelFeedSource.FOLLOWING);
      const hot = await new DefaultChannelFeedRepository(
        new ZhihuHttpClient(undefined, factory)
      ).loadPage(ChannelFeedSource.HOT);

      if (following.items[0].kind === ChannelFeedItemKind.CONTENT &&
        hot.items[0].kind === ChannelFeedItemKind.CONTENT) {
        expect(following.items[0].feedItem.actionText).assertEqual('张三赞同了回答');
        expect(hot.items[0].feedItem.actionText).assertEqual('1234 万热度');
        expect(hot.items[0].topicIds.join(',')).assertEqual('1,2');
      } else {
        expect(false).assertTrue();
      }
    });

    it('filtersContentThroughInjectedBlockingContract', 0, async () => {
      const matcher = new TitleBlockingMatcher();
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome({ statusCode: 200, body: FILTER_PAGE })
      ]);
      const page = await new DefaultChannelFeedRepository(
        new ZhihuHttpClient(undefined, factory),
        matcher
      ).loadPage(ChannelFeedSource.HOT);

      expect(page.items.length).assertEqual(1);
      expect(matcher.createSessionCount).assertEqual(1);
      expect(matcher.summaries.length).assertEqual(2);
      expect(matcher.summaries[0].topicIds.join(',')).assertEqual('1,2');
    });

    it('skipsExplicitUnsupportedTargetsButRejectsMalformedSupportedData', 0, () => {
      const unsupported = decodeChannelContentPage('{"data":[{"id":"skip","action_text":7,' +
        '"target":{"type":"zvideo","id":"1"}}],"paging":{"is_end":true}}');
      expect(unsupported.items.length).assertEqual(0);

      let malformed: DomainDecodeError | undefined = undefined;
      try {
        decodeChannelContentPage('{"data":[{"id":"bad","action_text":7,' +
          '"target":{"type":"question","id":"1","title":"标题"}}],"paging":{"is_end":true}}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          malformed = error;
        }
      }
      expect(malformed?.kind).assertEqual(DomainDecodeFailureKind.MISSING_FIELD);
      expect(() => decodeDailyFeedPage('{"date":"20260230","stories":[]}')).assertThrowError(
        'daily.date 格式无效'
      );
    });

    it('decodesDailyAndStopsRepeatedDateCursor', 0, async () => {
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome({ statusCode: 200, body: DAILY_PAGE }),
        new ChannelOutcome({ statusCode: 200, body: DAILY_PAGE })
      ]);
      const repository = new DefaultChannelFeedRepository(new ZhihuHttpClient(undefined, factory));
      const latest = await repository.loadPage(ChannelFeedSource.DAILY);
      const older = await repository.loadPage(ChannelFeedSource.DAILY, latest.cursor.next);

      expect(latest.items[0].kind).assertEqual(ChannelFeedItemKind.DAILY_STORY);
      expect(latest.cursor.next).assertEqual('20260811');
      expect(older.items.length).assertEqual(0);
      expect(older.cursor.isEnd).assertTrue();
      expect(older.cursor.next).assertUndefined();
    });

    it('fallsBackOnlyWhenPrimaryHostResolutionFails', 0, async () => {
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome(undefined, new TransportBusinessError(2300006)),
        new ChannelOutcome({ statusCode: 200, body: DAILY_PAGE })
      ]);
      const page = await new DefaultChannelFeedRepository(
        new ZhihuHttpClient(undefined, factory)
      ).loadPage(ChannelFeedSource.DAILY);

      expect(page.items.length).assertEqual(1);
      expect(factory.requests.length).assertEqual(2);
      expect(factory.requests[1].url.startsWith(DAILY_FALLBACK_BASE_URL)).assertTrue();
    });

    it('doesNotFallbackForTimeoutOrCancellation', 0, async () => {
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome(undefined, new TransportBusinessError(2300028))
      ]);
      let failure: HttpFailure | undefined = undefined;
      try {
        await new DefaultChannelFeedRepository(
          new ZhihuHttpClient(undefined, factory)
        ).loadPage(ChannelFeedSource.DAILY);
      } catch (error) {
        if (error instanceof HttpFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(HttpFailureKind.TIMEOUT);
      expect(factory.requests.length).assertEqual(1);

      const pendingFactory = new PendingChannelTransportFactory();
      const repository = new DefaultChannelFeedRepository(new ZhihuHttpClient(undefined, pendingFactory));
      const pending = repository.loadPage(ChannelFeedSource.DAILY);
      repository.cancel();
      let cancelled: boolean = false;
      try {
        await pending;
      } catch (_error) {
        cancelled = true;
      }
      expect(cancelled).assertTrue();
      expect(pendingFactory.transport.destroyed).assertTrue();
    });

    it('allowsRetryAfterFailureAndDeduplicatesAcrossPages', 0, async () => {
      const second = '{"data":[{"id":"duplicate","target":{"type":"answer","id":"101",' +
        '"question":{"title":"重复"}}},{"id":"new","target":{"type":"article","id":"404",' +
        '"title":"新文章"}}],' +
        '"paging":{"is_end":true}}';
      const factory = new SequenceChannelTransportFactory([
        new ChannelOutcome({ statusCode: 200, body: FOLLOW_PAGE }),
        new ChannelOutcome({ statusCode: 503, body: 'secret' }),
        new ChannelOutcome({ statusCode: 200, body: second })
      ]);
      const repository = new DefaultChannelFeedRepository(new ZhihuHttpClient(new ChannelCookieProvider(), factory));
      const first = await repository.loadPage(ChannelFeedSource.FOLLOWING);
      try {
        await repository.loadPage(ChannelFeedSource.FOLLOWING, first.cursor.next);
      } catch (_error) {
      }
      const retried = await repository.loadPage(ChannelFeedSource.FOLLOWING, first.cursor.next);
      expect(retried.items.length).assertEqual(1);
      expect(factory.requests.length).assertEqual(3);
    });
  });
}
