import { describe, expect, it } from '@ohos/hypium';
import {
  buildInitialSearchUrl,
  buildSearchRequestUrl,
  canonicalSearchCursorKey,
  decodeSearchResultPage,
  DefaultSearchRepository,
  BlockableContentSummary,
  BlockingMatch,
  BlockingRuleKind,
  ContentBlockingMatcher,
  ContentBlockingSession,
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

class RecordingSearchBlockingSession implements ContentBlockingSession {
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

class RecordingSearchBlockingMatcher implements ContentBlockingMatcher {
  readonly session: RecordingSearchBlockingSession = new RecordingSearchBlockingSession();
  createCount: number = 0;

  createSession(): Promise<ContentBlockingSession> {
    this.createCount += 1;
    return Promise.resolve(this.session);
  }
}

const QUERY = 'HarmonyOS ArkTS';
const NEXT_CURSOR = 'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20&limit=20';
const FIRST_PAGE = '{"data":[{"type":"search_result","id":"wrapper-answer-1","object":{' +
  '"type":"answer","id":"answer-1","excerpt":"回答摘要","voteup_count":12,' +
  '"comment_count":3,"question":{"title":"ArkTS 如何开发？","bound_topic_ids":[19551275]},' +
  '"author":{"id":"member-1","name":"开发者"}}},' +
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
      expect(initial.includes('include=data%5B%2A%5D.highlight%2Cobject%2Ctype%2Cobject.author%2C' +
        'object.topics%2Cobject.bound_topic_ids%2Cobject.question.topics%2Cobject.question.bound_topic_ids'))
        .assertTrue();
      expect(buildSearchRequestUrl(QUERY,
        'https://www.zhihu.com/api/v4/search_v3?include=stale&t=general&q=HarmonyOS%20ArkTS&offset=20'
      )).assertEqual(
        'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20&' +
          'include=data%5B%2A%5D.highlight%2Cobject%2Ctype%2Cobject.author%2Cobject.topics%2C' +
            'object.bound_topic_ids%2Cobject.question.topics%2Cobject.question.bound_topic_ids'
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
          if (error instanceof SearchRepositoryFailure) {
            failure = error;
          }
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
          if (cause instanceof SearchDecodeError) {
            error = cause;
          }
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

    it('filtersEachPageWithOneSnapshotAndDecodedAuthorTopics', 0, async () => {
      const factory = new SearchTransportFactory([{ statusCode: 200, body: '{"data":[' +
        '{"type":"search_result","id":"w1","object":{"type":"article","id":"1",' +
        '"title":"保留","author":{"id":"member-1","name":"作者"},"topics":[{"id":19551275}]}},' +
        '{"type":"search_result","id":"w2","object":{"type":"article","id":"2",' +
        '"title":"屏蔽内容","bound_topic_ids":[19551276]}}],"paging":{"is_end":true}}' }]);
      const matcher = new RecordingSearchBlockingMatcher();
      const repository = new DefaultSearchRepository(
        new ZhihuHttpClient(new SearchCookieProvider(), factory),
        matcher
      );
      const page = await repository.search('test');

      expect(matcher.createCount).assertEqual(1);
      expect(matcher.session.summaries.length).assertEqual(2);
      expect(matcher.session.summaries[0].authorId).assertEqual('member-1');
      expect(matcher.session.summaries[0].topicIds[0]).assertEqual('19551275');
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].contentId).assertEqual('1');
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
