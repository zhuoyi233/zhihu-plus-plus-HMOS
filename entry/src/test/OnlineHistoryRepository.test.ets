import { describe, expect, it } from '@ohos/hypium';
import {
  buildOnlineHistoryUrl,
  canonicalOnlineHistoryCursorKey,
  decodeOnlineHistoryPage,
  DefaultOnlineHistoryRepository,
  HttpFailure,
  HttpFailureKind,
  isOnlineHistoryCursorUrl,
  OnlineHistoryDecodeError,
  OnlineHistoryDecodeFailureKind,
  OnlineHistoryKind,
  OnlineHistoryRepositoryFailure,
  OnlineHistoryRepositoryFailureKind,
  onlineHistoryOffsetOf,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

const ONLINE_BASE = 'https://www.zhihu.com/api/v4/unify-consumption/read_history';
const NEXT_CURSOR = `${ONLINE_BASE}?offset=10&limit=10`;

const FIRST_PAGE = '{"data":[' +
  '{"card_type":"read_history","data":{"header":{"icon":"i","title":"ArkTS 如何入门？"},' +
  '"content":{"author_name":"作者甲","summary":"问题摘要"},' +
  '"action":{"type":"open_url","url":"https://www.zhihu.com/question/100001"},' +
  '"extra":{"content_token":"100001","content_type":"question","read_time":1716120000,' +
  '"question_token":"100001"}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"回答标题"},' +
  '"action":{"type":"open_url","url":"zhihu://answers/200001"},' +
  '"extra":{"content_token":"200001","content_type":"answer","read_time":1716120100,' +
  '"question_token":"100001"}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"专栏文章标题"},' +
  '"content":{"summary":"文章摘要"},"action":{"type":"open_url","url":"https://zhuanlan.zhihu.com/p/300001"},' +
  '"extra":{"content_token":"300001","content_type":"article","read_time":1716120200,' +
  '"question_token":""}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"一条想法"},' +
  '"action":{"type":"open_url","url":"https://www.zhihu.com/pin/400001"},' +
  '"extra":{"content_token":"400001","content_type":"pin","read_time":1716120300,' +
  '"question_token":""}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"用户主页"},' +
  '"action":{"type":"open_url","url":"https://www.zhihu.com/people/xiaoming"}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"无法解析"}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"视频内容"},' +
  '"action":{"type":"open_url","url":"https://www.zhihu.com/video/500001"}}}],' +
  '"paging":{"is_end":false,"is_start":true,"page":1,"totals":100}}';

const SECOND_PAGE = '{"data":[' +
  '{"card_type":"read_history","data":{"header":{"title":"第二页文章"},' +
  '"action":{"type":"open_url","url":"https://zhuanlan.zhihu.com/p/600001"},' +
  '"extra":{"content_token":"600001","content_type":"article","read_time":1716120400,' +
  '"question_token":""}}},' +
  '{"card_type":"read_history","data":{"header":{"title":"重复的问题"},' +
  '"action":{"type":"open_url","url":"https://www.zhihu.com/question/100001"},' +
  '"extra":{"content_token":"100001","content_type":"question","read_time":1716120500,' +
  '"question_token":"100001"}}}],' +
  '"paging":{"is_end":true,"is_start":false,"page":2,"totals":100}}';

class OnlineCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'online-login' },
      { name: 'd_c0', value: 'online-device' }
    ];
  }
}

class OnlineTransport implements ZhihuHttpTransport {
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

class OnlineTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new OnlineTransport(response, this.requests);
  }
}

class PendingOnlineTransport implements ZhihuHttpTransport {
  readonly requests: Array<PreparedZhihuHttpRequest> = [];
  destroyCount: number = 0;

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    return new Promise<ZhihuHttpResponse>((_resolve: (response: ZhihuHttpResponse) => void): void => {
    });
  }

  destroy(): void {
    this.destroyCount += 1;
  }
}

class PendingOnlineTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingOnlineTransport = new PendingOnlineTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

export default function onlineHistoryRepositoryTest(): void {
  describe('onlineHistoryRepositoryTest', () => {
    it('buildsOnlineHistoryUrlsAndValidatesCursorBoundaries', 0, () => {
      expect(buildOnlineHistoryUrl(0)).assertEqual(`${ONLINE_BASE}?offset=0&limit=10`);
      expect(buildOnlineHistoryUrl(10).includes('offset=10')).assertTrue();
      expect(isOnlineHistoryCursorUrl(`${ONLINE_BASE}?offset=0&limit=10`)).assertTrue();
      expect(onlineHistoryOffsetOf(`${ONLINE_BASE}?offset=10&limit=10`)).assertEqual(10);
      expect(canonicalOnlineHistoryCursorKey(`${ONLINE_BASE}?limit=10&offset=0`))
        .assertEqual(`${ONLINE_BASE}?limit=10&offset=0`);
      const invalidOffsets: Array<number> = [-1, 100001];
      invalidOffsets.forEach((offset: number): void => {
        let failure: OnlineHistoryRepositoryFailure | undefined = undefined;
        try {
          buildOnlineHistoryUrl(offset);
        } catch (error) {
          if (error instanceof OnlineHistoryRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(OnlineHistoryRepositoryFailureKind.INVALID_CURSOR);
      });
      const invalidCursors: Array<string> = [
        'https://www.zhihu.com.evil.example/api/v4/unify-consumption/read_history?offset=0&limit=10',
        'https://www.zhihu.com:443/api/v4/unify-consumption/read_history?offset=0&limit=10',
        `${ONLINE_BASE}?offset=0&limit=10#fragment`,
        `${ONLINE_BASE}?offset=0`,
        `${ONLINE_BASE}?offset=abc&limit=10`,
        `${ONLINE_BASE}?offset=-1&limit=10`,
        `${ONLINE_BASE}?offset=0&limit=10&extra=1`,
        `${ONLINE_BASE}?offset=0&limit=20`,
        `${ONLINE_BASE}?offset=0&limit=10%0A`,
        'https://api.zhihu.com/unify-consumption/read_history?offset=0&limit=10'
      ];
      invalidCursors.forEach((cursor: string): void => {
        expect(isOnlineHistoryCursorUrl(cursor)).assertFalse();
      });
      let invalidOffsetFailure: OnlineHistoryRepositoryFailure | undefined = undefined;
      try {
        onlineHistoryOffsetOf('https://evil.example/read_history?offset=0&limit=10');
      } catch (error) {
        if (error instanceof OnlineHistoryRepositoryFailure) {
          invalidOffsetFailure = error;
        }
      }
      expect(invalidOffsetFailure?.kind).assertEqual(OnlineHistoryRepositoryFailureKind.INVALID_CURSOR);
    });

    it('decodesSupportedCardsAndSkipsUnsupportedAndUnresolvableOnes', 0, () => {
      const page = decodeOnlineHistoryPage(FIRST_PAGE);
      expect(page.items.length).assertEqual(4);
      expect(page.items[0].contentKey).assertEqual('question:100001');
      expect(page.items[0].kind).assertEqual(OnlineHistoryKind.QUESTION);
      expect(page.items[0].title).assertEqual('ArkTS 如何入门？');
      expect(page.items[0].summary).assertEqual('问题摘要');
      expect(page.items[0].authorName).assertEqual('作者甲');
      expect(page.items[0].readTime).assertEqual(1716120000000);
      expect(page.items[1].kind).assertEqual(OnlineHistoryKind.ANSWER);
      expect(page.items[1].id).assertEqual('200001');
      expect(page.items[1].readTime).assertEqual(1716120100000);
      expect(page.items[2].kind).assertEqual(OnlineHistoryKind.ARTICLE);
      expect(page.items[2].id).assertEqual('300001');
      expect(page.items[3].kind).assertEqual(OnlineHistoryKind.PIN);
      expect(page.items[3].id).assertEqual('400001');
      expect(page.cursor.isEnd).assertFalse();
      expect(page.cursor.isStart).assertTrue();
      expect(page.cursor.page).assertEqual(1);
      expect(page.cursor.total).assertEqual(100);
      expect(page.cursor.next).assertUndefined();
    });

    it('rejectsMalformedEnvelopesWithStructuredErrors', 0, () => {
      const malformedPayloads: Array<string> = [
        'null',
        '{"data":{}}',
        '{"data":[],"paging":7}'
      ];
      malformedPayloads.forEach((payload: string): void => {
        let error: OnlineHistoryDecodeError | undefined = undefined;
        try {
          decodeOnlineHistoryPage(payload);
        } catch (cause) {
          if (cause instanceof OnlineHistoryDecodeError) {
            error = cause;
          }
        }
        expect(error?.kind).assertEqual(OnlineHistoryDecodeFailureKind.MALFORMED_RESPONSE);
      });
      let invalidJsonError: OnlineHistoryDecodeError | undefined = undefined;
      try {
        decodeOnlineHistoryPage('not-json');
      } catch (cause) {
        if (cause instanceof OnlineHistoryDecodeError) {
          invalidJsonError = cause;
        }
      }
      expect(invalidJsonError?.kind).assertEqual(OnlineHistoryDecodeFailureKind.INVALID_JSON);
      let upstreamError: OnlineHistoryDecodeError | undefined = undefined;
      try {
        decodeOnlineHistoryPage('{"error":{"code":100}}');
      } catch (cause) {
        if (cause instanceof OnlineHistoryDecodeError) {
          upstreamError = cause;
        }
      }
      expect(upstreamError?.kind).assertEqual(OnlineHistoryDecodeFailureKind.UPSTREAM_ERROR);
      const empty = decodeOnlineHistoryPage('{"data":[]}');
      expect(empty.items.length).assertEqual(0);
      expect(empty.cursor.isEnd).assertTrue();
    });

    it('sendsSignedSessionRequestAndPaginatesWithDeduplication', 0, async () => {
      const factory = new OnlineTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const client = new ZhihuHttpClient(new OnlineCookieProvider(), factory);
      const repository = new DefaultOnlineHistoryRepository(client);
      const first = await repository.loadPage();
      const second = await repository.loadPage(first.cursor.next);

      expect(first.items.length).assertEqual(4);
      expect(first.cursor.next).assertEqual(NEXT_CURSOR);
      expect(second.items.length).assertEqual(1);
      expect(second.items[0].contentKey).assertEqual('article:600001');
      expect(second.cursor.isEnd).assertTrue();
      expect(factory.requests[0].url).assertEqual(`${ONLINE_BASE}?offset=0&limit=10`);
      expect(factory.requests[1].url).assertEqual(NEXT_CURSOR);
      expect(factory.requests[0].headers.Cookie).assertEqual('z_c0=online-login; d_c0=online-device');
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
    });

    it('doesNotCommitCursorAfterRejectedResponse', 0, async () => {
      const factory = new OnlineTransportFactory([
        { statusCode: 503, body: 'sensitive upstream body' },
        { statusCode: 200, body: FIRST_PAGE }
      ]);
      const repository = new DefaultOnlineHistoryRepository(
        new ZhihuHttpClient(new OnlineCookieProvider(), factory)
      );
      let failed: boolean = false;
      try {
        await repository.loadPage();
      } catch (_error) {
        failed = true;
      }
      const retry = await repository.loadPage();
      expect(failed).assertTrue();
      expect(retry.items.length).assertEqual(4);
      expect(factory.requests.length).assertEqual(2);
    });

    it('rejectsRepeatedCursorRequests', 0, async () => {
      const factory = new OnlineTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const repository = new DefaultOnlineHistoryRepository(
        new ZhihuHttpClient(new OnlineCookieProvider(), factory)
      );
      const first = await repository.loadPage();
      const second = await repository.loadPage(first.cursor.next);
      expect(second.cursor.isEnd).assertTrue();
      let failure: OnlineHistoryRepositoryFailure | undefined = undefined;
      try {
        await repository.loadPage(first.cursor.next);
      } catch (error) {
        if (error instanceof OnlineHistoryRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(OnlineHistoryRepositoryFailureKind.REPEATED_CURSOR);
      expect(factory.requests.length).assertEqual(2);
    });

    it('stopsPaginationWhenPageReturnsNoNewItems', 0, async () => {
      const factory = new OnlineTransportFactory([
        { statusCode: 200, body: '{"data":[],"paging":{"is_end":false,"is_start":true}}' }
      ]);
      const repository = new DefaultOnlineHistoryRepository(
        new ZhihuHttpClient(new OnlineCookieProvider(), factory)
      );
      const page = await repository.loadPage();
      expect(page.items.length).assertEqual(0);
      expect(page.cursor.isEnd).assertTrue();
      expect(page.cursor.next).assertUndefined();
    });

    it('cancelsPendingTransportWithoutWaitingForItToSettle', 0, async () => {
      const factory = new PendingOnlineTransportFactory();
      const repository = new DefaultOnlineHistoryRepository(
        new ZhihuHttpClient(new OnlineCookieProvider(), factory)
      );
      const pending = repository.loadPage();
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
      expect(factory.transport.requests.length).assertEqual(1);
      expect(factory.transport.destroyCount).assertEqual(1);
    });
  });
}
