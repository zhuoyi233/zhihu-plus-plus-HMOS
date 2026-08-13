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
  HttpFailure,
  isHomeFeedCursorUrl,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class CountingSessionProvider implements SessionCookieProvider {
  readCount: number = 0;

  getCookies(): Array<SessionCookie> {
    this.readCount += 1;
    return [{ name: 'z_c0', value: 'must-not-leave-provider' }];
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
  '"id":"article-1","title":"第一页","author":{"id":"author-1","name":"作者"},' +
  '"bound_topic_ids":[19551275]}}],"paging":{"is_end":false,"is_start":true,' +
  '"next":"https://api.zhihu.com/topstory/recommend?include=stale&%6fffset=2"}}';
const SECOND_PAGE = '{"data":[{"id":"feed-1","target":{"type":"article",' +
  '"id":"article-1","title":"重复项"}},{"id":"feed-2","target":{"type":"question",' +
  '"id":"question-2","title":"第二页"}},{"id":"feed-1","target":{"type":"question",' +
  '"id":"question-cross-kind","title":"同 Feed ID 的另一内容"}}],"paging":{"is_end":false,"is_start":false,' +
  '"next":"https://api.zhihu.com/topstory/recommend?offset=2"}}';

export default function homeFeedRepositoryTest(): void {
  describe('homeFeedRepositoryTest', () => {
    it('buildsExactInitialAndPagingRequestUrls', 0, () => {
      expect(buildHomeFeedRequestUrl()).assertEqual(HOME_FEED_URL);
      expect(buildHomeFeedRequestUrl('https://api.zhihu.com/topstory/recommend?offset=2')).assertEqual(
        'https://api.zhihu.com/topstory/recommend?offset=2&' +
          'include=data%5B%2A%5D.content%2Cexcerpt%2Cheadline%2Ctarget.author.badge_v2%2C' +
            'target.bound_topic_ids%2Ctarget.question.bound_topic_ids'
      );
      expect(buildHomeFeedRequestUrl(
        'https://api.zhihu.com/topstory/recommend?include=stale&offset=3'
      )).assertEqual(
        'https://api.zhihu.com/topstory/recommend?offset=3&' +
          'include=data%5B%2A%5D.content%2Cexcerpt%2Cheadline%2Ctarget.author.badge_v2%2C' +
            'target.bound_topic_ids%2Ctarget.question.bound_topic_ids'
      );
      expect(buildHomeFeedRequestUrl(
        'https://api.zhihu.com/topstory/recommend?%69nclude=stale&%6fffset=3'
      )).assertEqual(
        'https://api.zhihu.com/topstory/recommend?offset=3&' +
          'include=data%5B%2A%5D.content%2Cexcerpt%2Cheadline%2Ctarget.author.badge_v2%2C' +
            'target.bound_topic_ids%2Ctarget.question.bound_topic_ids'
      );
      expect(canonicalHomeFeedCursorKey(
        'https://api.zhihu.com/topstory/recommend?offset=3&limit=10'
      )).assertEqual(canonicalHomeFeedCursorKey(
        'https://api.zhihu.com/topstory/recommend?limit=10&%6fffset=3'
      ));
    });

    it('acceptsOnlyExactHttpsHomeFeedCursors', 0, () => {
      expect(isHomeFeedCursorUrl('https://api.zhihu.com/topstory/recommend?offset=2')).assertTrue();
      expect(isHomeFeedCursorUrl('https://api.zhihu.com.evil.example/topstory/recommend')).assertFalse();
      expect(isHomeFeedCursorUrl('https://api.zhihu.com/notifications/v3/message/v3')).assertFalse();
      expect(isHomeFeedCursorUrl('http://api.zhihu.com/topstory/recommend')).assertFalse();
      expect(isHomeFeedCursorUrl('https://api.zhihu.com/topstory/recommend#redirect')).assertFalse();
    });

    it('keepsGuestFeedRequestFreeOfCookiesAndZseHeaders', 0, async () => {
      const provider = new CountingSessionProvider();
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: '{"data":[],"paging":{"is_end":false,"is_start":true}}' }
      ]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(provider, factory));
      const page = await repository.loadHomePage();

      expect(page.items.length).assertEqual(0);
      expect(page.cursor.isEnd).assertTrue();
      expect(factory.requests[0].url).assertEqual(HOME_FEED_URL);
      expect(factory.requests[0].headers.Cookie).assertUndefined();
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-')).assertFalse();
      expect(provider.readCount).assertEqual(0);
    });

    it('filtersEachPageWithOneSnapshotAndRealAuthorTopicFields', 0, async () => {
      const factory = new SequenceFeedTransportFactory([{ statusCode: 200, body: '{"data":[' +
        '{"id":"feed-1","target":{"type":"article","id":"1","title":"保留",' +
        '"author":{"id":"author-1","name":"作者"},"bound_topic_ids":[19551275]}},' +
        '{"id":"feed-2","target":{"type":"article","id":"2","title":"屏蔽内容",' +
        '"bound_topic_ids":[19551276]}}],"paging":{"is_end":true}}' }]);
      const matcher = new RecordingFeedBlockingMatcher();
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory), matcher);
      const page = await repository.loadHomePage();

      expect(matcher.createCount).assertEqual(1);
      expect(matcher.session.summaries.length).assertEqual(2);
      expect(matcher.session.summaries[0].authorId).assertEqual('author-1');
      expect(matcher.session.summaries[0].topicIds[0]).assertEqual('19551275');
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].target.id).assertEqual('1');
    });

    it('deduplicatesItemsAcrossPagesAndStopsLoopingCursor', 0, async () => {
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory));
      const first = await repository.loadHomePage();
      const second = await repository.loadHomePage(first.cursor.next);

      expect(first.items.length).assertEqual(1);
      expect(second.items.length).assertEqual(2);
      expect(second.items[0].target.id).assertEqual('question-2');
      expect(second.items[1].target.id).assertEqual('question-cross-kind');
      expect(second.cursor.isEnd).assertTrue();
      expect(second.cursor.next).assertUndefined();
      expect(factory.requests[1].url).assertEqual(
        'https://api.zhihu.com/topstory/recommend?offset=2&' +
          'include=data%5B%2A%5D.content%2Cexcerpt%2Cheadline%2Ctarget.author.badge_v2%2C' +
            'target.bound_topic_ids%2Ctarget.question.bound_topic_ids'
      );
    });

    it('allowsRetryAfterTransientPagingFailure', 0, async () => {
      const factory = new SequenceFeedTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 503, body: 'upstream detail must not escape' },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory));
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
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory));
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
          '"next":"https://api.zhihu.com.evil.example/secret?token=sensitive"}}'
      }]);
      const repository = new DefaultFeedRepository(new ZhihuHttpClient(undefined, factory));
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
