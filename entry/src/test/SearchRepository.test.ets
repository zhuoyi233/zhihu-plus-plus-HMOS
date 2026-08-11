import { describe, expect, it } from '@ohos/hypium';
import {
  buildInitialSearchUrl,
  buildSearchRequestUrl,
  canonicalSearchCursorKey,
  decodeSearchResultPage,
  DefaultSearchRepository,
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind,
  isSearchCursorUrl,
  PreparedZhihuHttpRequest,
  SearchDecodeError,
  SearchDecodeFailureKind,
  SearchRepositoryFailure,
  SearchRepositoryFailureKind,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class SearchCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'search-login' },
      { name: 'd_c0', value: 'search-device' }
    ];
  }
}

class SearchTransport implements ZhihuHttpTransport {
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

class SearchTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new SearchTransport(response, this.requests);
  }
}

class PendingSearchTransport implements ZhihuHttpTransport {
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

class PendingSearchTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingSearchTransport = new PendingSearchTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

const QUERY = 'HarmonyOS ArkTS';
const NEXT_CURSOR = 'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20&limit=20';
const FIRST_PAGE = '{"data":[{"type":"search_result","id":"wrapper-answer-1","object":{' +
  '"type":"answer","id":"answer-1","excerpt":"回答摘要","voteup_count":12,' +
  '"comment_count":3,"question":{"title":"ArkTS 如何开发？"},"author":{"name":"开发者"}}},' +
  '{"type":"knowledge_ad","id":"ad-1","object":{"type":"article"}}],"paging":{' +
  '"is_end":false,"is_start":true,"next":"' + NEXT_CURSOR + '"}}';
const SECOND_PAGE = '{"data":[{"type":"search_result","id":"another-wrapper","object":{' +
  '"type":"answer","id":"answer-1","question":{"title":"重复回答"}}},{"type":"search_result",' +
  '"id":"wrapper-article-1","object":{"type":"article","id":"article-1","title":"ArkTS 文章"}}],' +
  '"paging":{"is_end":false,"is_start":false,"next":"' + NEXT_CURSOR + '"}}';
const SUPPORTED_RESULT_PAGE = '{"data":[{"type":"search_result","id":"question-wrapper","object":{' +
  '"type":"question","id":"question-1","title":"ArkTS 问题"}},{"type":"search_result",' +
  '"id":"answer-wrapper","object":{"type":"answer","id":"answer-2","question":{' +
  '"title":"ArkTS 回答问题"}}},{"type":"search_result","id":"article-wrapper","object":{' +
  '"type":"article","id":"article-2","title":"ArkTS 文章"}},{"type":"search_result",' +
  '"id":"video-wrapper","object":{"type":"zvideo"}},{"type":"knowledge_ad","id":"ad"}],' +
  '"paging":{"is_end":true}}';

export default function searchRepositoryTest(): void {
  describe('searchRepositoryTest', () => {
    it('buildsAndroidCompatibleSearchUrlAndNormalizesCursor', 0, () => {
      const initial = buildInitialSearchUrl('  HarmonyOS ArkTS  ');
      expect(initial.includes('t=general&q=HarmonyOS+ArkTS')).assertTrue();
      expect(initial.includes('offset=0&limit=20&search_source=Normal')).assertTrue();
      expect(initial.includes('include=data%5B%2A%5D.highlight%2Cobject%2Ctype')).assertTrue();
      expect(buildSearchRequestUrl(QUERY,
        'https://www.zhihu.com/api/v4/search_v3?include=stale&t=general&q=HarmonyOS%20ArkTS&offset=20'
      )).assertEqual(
        'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20&' +
          'include=data%5B%2A%5D.highlight%2Cobject%2Ctype'
      );
      expect(canonicalSearchCursorKey(QUERY,
        'https://www.zhihu.com/api/v4/search_v3?offset=20&t=general&q=HarmonyOS+ArkTS'
      )).assertEqual(canonicalSearchCursorKey(QUERY,
        'https://www.zhihu.com/api/v4/search_v3?q=HarmonyOS%20ArkTS&t=general&offset=20'
      ));
      expect(buildSearchRequestUrl(QUERY,
        'https://api.zhihu.com/search_v3?offset=20&t=general&q=HarmonyOS+ArkTS'
      ).startsWith('https://www.zhihu.com/api/v4/search_v3?')).assertTrue();
    });

    it('rejectsCrossOriginPathFragmentAndQuerySwitchingCursors', 0, () => {
      expect(isSearchCursorUrl(NEXT_CURSOR)).assertTrue();
      expect(isSearchCursorUrl(
        'https://api.zhihu.com/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20'
      )).assertTrue();
      expect(isSearchCursorUrl('https://www.zhihu.com.evil.example/api/v4/search_v3?t=general&q=x')).assertFalse();
      expect(isSearchCursorUrl('https://user@www.zhihu.com/api/v4/search_v3?t=general&q=x')).assertFalse();
      expect(isSearchCursorUrl('https://www.zhihu.com:443/api/v4/search_v3?t=general&q=x')).assertFalse();
      expect(isSearchCursorUrl('https://www.zhihu.com/api/v4/search/hot_search?t=general&q=x')).assertFalse();
      expect(isSearchCursorUrl(`${NEXT_CURSOR}#redirect`)).assertFalse();
      const invalidCursors: Array<string> = [
        'https://www.zhihu.com/api/v4/search_v3?t=general&q=other&offset=20',
        'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&q=duplicate',
        'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&bad%0Aname=value'
      ];
      invalidCursors.forEach((cursor: string): void => {
        let failure: SearchRepositoryFailure | undefined = undefined;
        try {
          buildSearchRequestUrl(QUERY, cursor);
        } catch (error) {
          failure = error as SearchRepositoryFailure;
        }
        expect(failure?.kind).assertEqual(SearchRepositoryFailureKind.INVALID_CURSOR);
      });
    });

    it('decodesQuestionAnswerArticleAndSkipsExplicitUnsupportedCards', 0, () => {
      const page = decodeSearchResultPage(SUPPORTED_RESULT_PAGE);
      expect(page.items.length).assertEqual(3);
      expect(page.items[0].kind).assertEqual(FeedTargetKind.QUESTION);
      expect(page.items[0].contentId).assertEqual('question-1');
      expect(page.items[1].kind).assertEqual(FeedTargetKind.ANSWER);
      expect(page.items[1].title).assertEqual('ArkTS 回答问题');
      expect(page.items[2].kind).assertEqual(FeedTargetKind.ARTICLE);
      expect(page.items[2].contentId).assertEqual('article-2');
      expect(page.cursor.isEnd).assertTrue();
    });

    it('mapsMalformedSearchFieldsToStructuredErrors', 0, () => {
      const payloads: Array<string> = [
        'null',
        '{"data":{}}',
        '{"data":[{"type":7}]}',
        '{"data":[{"type":"search_result","id":"x","object":{}}]}',
        '{"data":[{"type":"search_result","id":"x","object":{' +
          '"type":"article","id":"a","title":"标题","excerpt":7}}]}',
        '{"data":[],"paging":{"is_end":"false"}}'
      ];
      payloads.forEach((payload: string): void => {
        let error: SearchDecodeError | undefined = undefined;
        try {
          decodeSearchResultPage(payload);
        } catch (cause) {
          error = cause as SearchDecodeError;
        }
        expect(error instanceof SearchDecodeError).assertTrue();
        expect(error?.kind).assertEqual(SearchDecodeFailureKind.MALFORMED_RESPONSE);
      });
    });

    it('sendsSignedSessionRequestAndDeduplicatesByContentIdentity', 0, async () => {
      const factory = new SearchTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const client = new ZhihuHttpClient(new SearchCookieProvider(), factory);
      const repository = new DefaultSearchRepository(client);
      const first = await repository.search(QUERY);
      const second = await repository.search(QUERY, first.cursor.next);

      expect(first.items.length).assertEqual(1);
      expect(second.items.length).assertEqual(1);
      expect(second.items[0].contentId).assertEqual('article-1');
      expect(second.cursor.isEnd).assertTrue();
      expect(factory.requests[0].headers.Cookie).assertEqual('z_c0=search-login; d_c0=search-device');
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
      expect(factory.requests[1].url.includes('offset=20')).assertTrue();
    });

    it('doesNotCommitCursorAfterRejectedResponse', 0, async () => {
      const factory = new SearchTransportFactory([
        { statusCode: 503, body: 'sensitive upstream body' },
        { statusCode: 200, body: FIRST_PAGE }
      ]);
      const repository = new DefaultSearchRepository(
        new ZhihuHttpClient(new SearchCookieProvider(), factory)
      );
      let failed: boolean = false;
      try {
        await repository.search(QUERY);
      } catch (_error) {
        failed = true;
      }
      const retry = await repository.search(QUERY);
      expect(failed).assertTrue();
      expect(retry.items.length).assertEqual(1);
      expect(factory.requests.length).assertEqual(2);
    });

    it('cancelsPendingTransportWithoutWaitingForItToSettle', 0, async () => {
      const factory = new PendingSearchTransportFactory();
      const repository = new DefaultSearchRepository(
        new ZhihuHttpClient(new SearchCookieProvider(), factory)
      );
      const pending = repository.search(QUERY);
      repository.cancel();
      let failure: HttpFailure | undefined = undefined;
      try {
        await pending;
      } catch (error) {
        failure = error as HttpFailure;
      }
      expect(failure?.kind).assertEqual(HttpFailureKind.CANCELLED);
      expect(factory.transport.requests.length).assertEqual(1);
      expect(factory.transport.destroyCount).assertEqual(1);
    });
  });
}
