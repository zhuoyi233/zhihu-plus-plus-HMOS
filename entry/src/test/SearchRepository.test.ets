import { describe, expect, it } from '@ohos/hypium';
import {
  buildInitialSearchUrl,
  buildSearchRequestUrl,
  canonicalSearchCursorKey,
  decodeSearchHotList,
  decodeSearchResultPage,
  DefaultSearchRepository,
  BlockableContentSummary,
  BlockingMatch,
  BlockingRuleKind,
  ContentBlockingMatcher,
  ContentBlockingSession,
  defaultSearchFilters,
  SearchFilters,
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind,
  isSearchCursorUrl,
  PreparedZhihuHttpRequest,
  SearchDecodeError,
  SearchDecodeFailureKind,
  SearchEntityKind,
  SearchRepositoryFailure,
  SearchRepositoryFailureKind,
  SearchSortOption,
  SearchTab,
  SearchTimeRange,
  SearchEntity,
  SearchResultItem,
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
  index: number = 0;
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
const FILTERS: SearchFilters = defaultSearchFilters();
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
      expect(initial.includes('offset=0&limit=20&search_source=Normal&show_all_topics=0')).assertTrue();
      expect(initial.includes('include=data%5B%2A%5D.highlight%2Cobject%2Ctype%2Cobject.author%2C' +
        'object.topics%2Cobject.bound_topic_ids%2Cobject.question.topics%2Cobject.question.bound_topic_ids'))
        .assertTrue();
      expect(buildSearchRequestUrl(QUERY, FILTERS, SearchTab.GENERAL,
        'https://www.zhihu.com/api/v4/search_v3?include=stale&t=general&q=HarmonyOS%20ArkTS&offset=20'
      )).assertEqual(
        'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20&' +
          'include=data%5B%2A%5D.highlight%2Cobject%2Ctype%2Cobject.author%2Cobject.topics%2C' +
            'object.bound_topic_ids%2Cobject.question.topics%2Cobject.question.bound_topic_ids'
      );
      expect(canonicalSearchCursorKey(QUERY, FILTERS, SearchTab.GENERAL,
        'https://www.zhihu.com/api/v4/search_v3?offset=20&t=general&q=HarmonyOS+ArkTS'
      )).assertEqual(canonicalSearchCursorKey(QUERY, FILTERS, SearchTab.GENERAL,
        'https://www.zhihu.com/api/v4/search_v3?q=HarmonyOS%20ArkTS&t=general&offset=20'
      ));
      expect(buildSearchRequestUrl(QUERY, FILTERS, SearchTab.GENERAL,
        'https://api.zhihu.com/search_v3?offset=20&t=general&q=HarmonyOS+ArkTS'
      ).startsWith('https://www.zhihu.com/api/v4/search_v3?')).assertTrue();
    });

    it('buildsTabScopedAndFilteredSearchUrlsLikeUpstream', 0, () => {
      const sortedFilters: SearchFilters = {
        sort: SearchSortOption.MOST_VOTED,
        timeRange: SearchTimeRange.WEEK
      };
      // 用户/话题 tab 忽略排序与时间筛选（对齐上游 activeFilters 重置行为）。
      const people = buildInitialSearchUrl(QUERY, sortedFilters, SearchTab.PEOPLE);
      expect(people.includes('t=people')).assertTrue();
      expect(people.includes('show_all_topics=0')).assertTrue();
      expect(people.includes('sort=')).assertFalse();
      expect(people.includes('time_interval=')).assertFalse();

      const topic = buildInitialSearchUrl(QUERY, sortedFilters, SearchTab.TOPIC);
      expect(topic.includes('t=topic')).assertTrue();
      expect(topic.includes('show_all_topics=1')).assertTrue();
      expect(topic.includes('sort=')).assertFalse();

      const answers = buildInitialSearchUrl(QUERY, FILTERS, SearchTab.ANSWER);
      expect(answers.includes('t=general')).assertTrue();
      expect(answers.includes('vertical=answer&vertical_info=0,0,0,0,0,0,0,0,0,0,0,0'))
        .assertTrue();
      expect(answers.includes('search_source=Filter')).assertTrue();

      const sorted = buildInitialSearchUrl(QUERY, {
        sort: SearchSortOption.MOST_VOTED,
        timeRange: SearchTimeRange.WEEK
      }, SearchTab.GENERAL);
      expect(sorted.includes('sort=upvoted_count')).assertTrue();
      expect(sorted.includes('time_interval=a_week')).assertTrue();
      expect(sorted.includes('search_source=Filter')).assertTrue();

      // 游标校验：t 必须与当前 tab 的请求参数一致，否则拒绝重放。
      let failure: SearchRepositoryFailure | undefined = undefined;
      try {
        buildSearchRequestUrl(QUERY, FILTERS, SearchTab.PEOPLE,
          'https://www.zhihu.com/api/v4/search_v3?t=general&q=HarmonyOS+ArkTS&offset=20');
      } catch (error) {
        if (error instanceof SearchRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(SearchRepositoryFailureKind.INVALID_CURSOR);
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
          buildSearchRequestUrl(QUERY, FILTERS, SearchTab.GENERAL, cursor);
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
      expect(page.entities.length).assertEqual(3);
      const first = contentItemOf(page.entities[0]);
      expect(first.kind).assertEqual(FeedTargetKind.QUESTION);
      expect(first.contentId).assertEqual('question-1');
      const second = contentItemOf(page.entities[1]);
      expect(second.kind).assertEqual(FeedTargetKind.ANSWER);
      expect(second.title).assertEqual('ArkTS 回答问题');
      const third = contentItemOf(page.entities[2]);
      expect(third.kind).assertEqual(FeedTargetKind.ARTICLE);
      expect(third.contentId).assertEqual('article-2');
      expect(page.cursor.isEnd).assertTrue();
    });

    it('decodesPeopleAndTopicEntitiesWithResponseIndexOrdering', 0, () => {
      const page = decodeSearchResultPage('{"data":[' +
        '{"type":"search_result","id":"w2","index":"2","object":{"type":"topic","id":"99",' +
        '"name":"<em>鸿蒙</em>话题","excerpt":"讨论","visit_count":12000,"top_answer_count":34,' +
        '"is_following":true,"avatar_url":"https://pic.example/t.png"}},' +
        '{"type":"search_result","id":"w1","index":"1","object":{"type":"people","id":"zhang-san",' +
        '"name":"张三","url_token":"zhang-san","headline":"开发者","follower_count":1000,' +
        '"answer_count":20,"avatar_url":"https://pic.example/p.png"}},' +
        '{"type":"search_result","id":"w0","index":"0","object":{"type":"article","id":"77",' +
        '"title":"<em>鸿蒙</em>指南"}}],"paging":{"is_end":true}}');
      expect(page.entities.length).assertEqual(3);
      expect(page.entities[0].kind).assertEqual(SearchEntityKind.CONTENT);
      expect(page.entities[1].kind).assertEqual(SearchEntityKind.PERSON);
      const person = page.entities[1].person;
      expect(person?.id).assertEqual('zhang-san');
      expect(person?.name).assertEqual('张三');
      expect(person?.urlToken).assertEqual('zhang-san');
      expect(person?.followerCount).assertEqual(1000);
      expect(person?.answerCount).assertEqual(20);
      expect(page.entities[2].kind).assertEqual(SearchEntityKind.TOPIC);
      const topic = page.entities[2].topic;
      expect(topic?.id).assertEqual('99');
      expect(topic?.name).assertEqual('<em>鸿蒙</em>话题');
      expect(topic?.visitCount).assertEqual(12000);
      expect(topic?.discussCount).assertEqual(34);
      expect(topic?.isFollowing).assertTrue();
    });

    it('fallsBackToObjectIdWhenWrapperIdMissing', 0, () => {
      // 服务端新版 search_v3 的 search_result 包裹层可能不返回 id（上游对缺失 id 容忍）。
      const page = decodeSearchResultPage('{"data":[' +
        '{"type":"search_result","object":{"type":"answer","id":"answer-9",' +
        '"question":{"title":"无包裹 id 的回答"}}},' +
        '{"type":"search_result","id":"wrapper-10","object":{"type":"article","id":"article-10",' +
        '"title":"有包裹 id 的文章"}}],' +
        '"paging":{"is_end":true,"is_start":true}}');
      expect(page.entities.length).assertEqual(2);
      const first = contentItemOf(page.entities[0]);
      expect(first.contentId).assertEqual('answer-9');
      expect(first.wrapperId).assertEqual('answer-9');
      expect(contentItemOf(page.entities[1]).wrapperId).assertEqual('wrapper-10');
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

    it('decodesHotSearchQueries', 0, () => {
      const items = decodeSearchHotList('{"hot_search_queries":[' +
        '{"query":"鸿蒙 next","hot_show":"456万","label":"热"},{"query":"ArkTS","hot_show":""}]}');
      expect(items.length).assertEqual(2);
      expect(items[0].query).assertEqual('鸿蒙 next');
      expect(items[0].hotShow).assertEqual('456万');
      expect(items[1].label).assertEqual('');
      expect(decodeSearchHotList('{}').length).assertEqual(0);
      let malformed = false;
      try {
        decodeSearchHotList('{"hot_search_queries":[{"hot_show":"缺 query"}]}');
      } catch (error) {
        malformed = error instanceof SearchDecodeError;
      }
      expect(malformed).assertTrue();
    });

    it('sendsSignedSessionRequestAndDeduplicatesByContentIdentity', 0, async () => {
      const factory = new SearchTransportFactory([
        { statusCode: 200, body: FIRST_PAGE },
        { statusCode: 200, body: SECOND_PAGE }
      ]);
      const client = new ZhihuHttpClient(new SearchCookieProvider(), factory);
      const repository = new DefaultSearchRepository(client);
      const first = await repository.search(QUERY);
      const second = await repository.search(QUERY, FILTERS, SearchTab.GENERAL, first.cursor.next);

      expect(first.entities.length).assertEqual(1);
      expect(second.entities.length).assertEqual(1);
      expect(contentItemOf(second.entities[0]).contentId).assertEqual('article-1');
      expect(second.cursor.isEnd).assertTrue();
      expect(factory.requests[0].headers.Cookie).assertEqual('z_c0=search-login; d_c0=search-device');
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
      expect(factory.requests[1].url.includes('offset=20')).assertTrue();
    });

    it('filtersEachPageWithOneSnapshotAndSkipsPeopleEntities', 0, async () => {
      const factory = new SearchTransportFactory([{ statusCode: 200, body: '{"data":[' +
        '{"type":"search_result","id":"w1","object":{"type":"article","id":"1",' +
        '"title":"保留","author":{"id":"member-1","name":"作者"},"topics":[{"id":19551275}]}},' +
        '{"type":"search_result","id":"w2","object":{"type":"article","id":"2",' +
        '"title":"屏蔽内容","bound_topic_ids":[19551276]}},' +
        '{"type":"search_result","id":"w3","object":{"type":"people","id":"someone","name":"路人"}}],' +
        '"paging":{"is_end":true}}' }]);
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
      expect(page.entities.length).assertEqual(2);
      expect(contentItemOf(page.entities[0]).contentId).assertEqual('1');
      expect(page.entities[1].kind).assertEqual(SearchEntityKind.PERSON);
    });

    it('fetchesHotSearchWithSessionSigning', 0, async () => {
      const factory = new SearchTransportFactory([
        { statusCode: 200, body: '{"hot_search_queries":[{"query":"鸿蒙","hot_show":"12万"}]}' }
      ]);
      const repository = new DefaultSearchRepository(
        new ZhihuHttpClient(new SearchCookieProvider(), factory)
      );
      const items = await repository.hotSearch();
      expect(items.length).assertEqual(1);
      expect(items[0].query).assertEqual('鸿蒙');
      expect(factory.requests[0].url).assertEqual('https://www.zhihu.com/api/v4/search/hot_search');
      expect(JSON.stringify(factory.requests[0].headers).includes('x-zse-96')).assertTrue();
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
      expect(retry.entities.length).assertEqual(1);
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

function contentItemOf(entity: SearchEntity): SearchResultItem {
  const item = entity.content;
  if (item === undefined) {
    throw new Error('expected content entity');
  }
  return item;
}
