import { describe, expect, it } from '@ohos/hypium';
import {
  defaultSearchFilters,
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind,
  SearchEntity,
  searchEntityOfContent,
  SearchFilters,
  SearchHotItem,
  SearchRepository,
  SearchResultItem,
  SearchResultPage,
  SearchSortOption,
  SearchTab,
  SearchTimeRange
} from 'data';
import { searchResultDestination, searchTabLabel } from '../main/ets/pages/SearchPage';
import { mergeSearchEntities, SearchController, SearchPhase } from '../main/ets/pages/SearchState';

interface PendingSearch {
  readonly query: string;
  readonly filters: SearchFilters | undefined;
  readonly tab: SearchTab | undefined;
  readonly cursor?: string;
  readonly resolve: (page: SearchResultPage) => void;
  readonly reject: (error: Error) => void;
}

class ControlledSearchRepository implements SearchRepository {
  readonly pending: Array<PendingSearch> = [];
  cancelCount: number = 0;
  hotSearchCount: number = 0;

  search(query: string, filters?: SearchFilters, tab?: SearchTab, cursor?: string): Promise<SearchResultPage> {
    return new Promise<SearchResultPage>((resolve: (page: SearchResultPage) => void,
      reject: (error: Error) => void): void => {
      this.pending.push({
        query: query,
        filters: filters,
        tab: tab,
        cursor: cursor,
        resolve: resolve,
        reject: reject
      });
    });
  }

  async hotSearch(): Promise<Array<SearchHotItem>> {
    this.hotSearchCount += 1;
    return [];
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class AuthenticationSearchRepository implements SearchRepository {
  private readonly status?: number;
  private readonly firstPage?: SearchResultPage;

  constructor(status?: number, firstPage?: SearchResultPage) {
    this.status = status;
    this.firstPage = firstPage;
  }

  async search(_query: string, _filters?: SearchFilters, _tab?: SearchTab, cursor?: string):
    Promise<SearchResultPage> {
    if (cursor === undefined && this.firstPage !== undefined) {
      return this.firstPage;
    }
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION, this.status);
  }

  async hotSearch(): Promise<Array<SearchHotItem>> {
    return [];
  }

  cancel(): void {
  }
}

export default function searchStateTest(): void {
  describe('searchStateTest', () => {
    it('keepsEmptyQueryIdleAndLoadsTrimmedQuery', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      await controller.submit('   ');
      expect(controller.snapshot().phase).assertEqual(SearchPhase.IDLE);
      expect(repository.pending.length).assertEqual(0);

      const loading = controller.submit('  arkts  ');
      expect(repository.pending[0].query).assertEqual('arkts');
      repository.pending[0].resolve(pageOf([content('answer-1')], 'next'));
      await loading;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
      expect(controller.snapshot().entities.length).assertEqual(1);
    });

    it('cancelsPreviousQueryAndIgnoresItsLateResult', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const oldSearch = controller.submit('old');
      const newSearch = controller.submit('new');
      repository.pending[1].resolve(pageOf([content('new')], undefined, true));
      await newSearch;
      repository.pending[0].resolve(pageOf([content('old')], undefined, true));
      await oldSearch;

      expect(controller.snapshot().query).assertEqual('new');
      expect(controller.snapshot().entities[0].content?.contentId).assertEqual('new');
      expect(repository.cancelCount).assertEqual(2);
    });

    it('retriesFailedPaginationWithSameCursorAndKeepsItems', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const first = controller.submit('query');
      repository.pending[0].resolve(pageOf([content('first')], 'next'));
      await first;
      const failed = controller.loadMore();
      repository.pending[1].reject(new Error('network detail'));
      await failed;
      expect(controller.snapshot().canLoadMore).assertFalse();

      const retry = controller.retry();
      expect(repository.pending[2].cursor).assertEqual('next');
      repository.pending[2].resolve(pageOf([content('second')], undefined, true));
      await retry;
      expect(controller.snapshot().entities.length).assertEqual(2);
    });

    it('continuesAfterEmptyNonTerminalPage', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const first = controller.submit('query');
      repository.pending[0].resolve(pageOf([], 'next-empty'));
      await first;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.EMPTY);
      const next = controller.retry();
      expect(repository.pending[1].cursor).assertEqual('next-empty');
      repository.pending[1].resolve(pageOf([content('visible')], undefined, true));
      await next;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
    });

    it('cancelsOnDeactivateAndDoesNotPublishLateResponse', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const initial = controller.submit('query');
      repository.pending[0].resolve(pageOf([content('visible')], 'next'));
      await initial;
      const loading = controller.loadMore();
      controller.deactivate();
      repository.pending[1].resolve(pageOf([content('late')], undefined, true));
      await loading;
      expect(repository.cancelCount).assertEqual(2);
      expect(controller.snapshot().entities.length).assertEqual(1);
      controller.activate();
      expect(controller.snapshot().entities[0].content?.contentId).assertEqual('visible');

      const initialRepository = new ControlledSearchRepository();
      const initialController = new SearchController(initialRepository);
      initialController.activate();
      const interrupted = initialController.submit('resume');
      initialController.deactivate();
      initialController.activate();
      expect(initialRepository.pending.length).assertEqual(2);
      initialRepository.pending[1].resolve(pageOf([content('resumed')], undefined, true));
      await Promise.resolve();
      initialRepository.pending[0].resolve(pageOf([content('stale')], undefined, true));
      await interrupted;
      expect(initialController.snapshot().entities[0].content?.contentId).assertEqual('resumed');
    });

    it('exposesAuthenticationFailureWithoutLeakingTransportDetails', 0, async () => {
      const controller = new SearchController(new AuthenticationSearchRepository());
      controller.activate();
      const loading = controller.submit('query');
      await loading;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(controller.snapshot().errorMessage).assertEqual('搜索需要登录，请登录后重试');

      const rejected = new SearchController(new AuthenticationSearchRepository(401));
      rejected.activate();
      await rejected.submit('query');
      expect(rejected.snapshot().requiresLogin).assertTrue();
      expect(rejected.snapshot().errorMessage).assertEqual('搜索需要登录，请登录后重试');
    });

    it('doesNotMisreportFirstPage403AsExpiredSession', 0, async () => {
      const controller = new SearchController(new AuthenticationSearchRepository(403));
      controller.activate();
      await controller.submit('query');
      expect(controller.snapshot().phase).assertEqual(SearchPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertFalse();
      expect(controller.snapshot().errorMessage)
        .assertEqual('请求被拒绝，可能需要稍后重试或完成风控');
    });

    it('doesNotMisreportPagination403AsExpiredSession', 0, async () => {
      const firstPage = pageOf([content('visible')], 'next');
      const controller = new SearchController(new AuthenticationSearchRepository(403, firstPage));
      controller.activate();
      await controller.submit('query');
      await controller.loadMore();
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
      expect(controller.snapshot().entities.length).assertEqual(1);
      expect(controller.snapshot().requiresLogin).assertFalse();
      expect(controller.snapshot().errorMessage)
        .assertEqual('请求被拒绝，可能需要稍后重试或完成风控');
    });

    it('deduplicatesStableTargetsAndMapsTypedDestinations', 0, () => {
      const merged = mergeSearchEntities(
        [contentOf('same', FeedTargetKind.ANSWER, 'wrapper-1')],
        [contentOf('same', FeedTargetKind.ANSWER, 'wrapper-2'), contentOf('same', FeedTargetKind.ARTICLE, 'wrapper-3')]
      );
      expect(merged.length).assertEqual(2);
      const first = contentItemOf(merged[0]);
      const second = contentItemOf(merged[1]);
      expect(searchResultDestination(first).name).assertEqual('Answer');
      expect(searchResultDestination(second).name).assertEqual('Article');
      expect(searchResultDestination(contentOf('question', FeedTargetKind.QUESTION).content ?? first).name)
        .assertEqual('Question');
    });

    it('reloadsFirstPageWhenSelectingTabAndKeepsFilters', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const first = controller.submit('query');
      repository.pending[0].resolve(pageOf([content('general-1')], 'next'));
      await first;

      const people = controller.selectTab(SearchTab.PEOPLE);
      expect(repository.pending[1].tab).assertEqual(SearchTab.PEOPLE);
      expect(repository.pending[1].cursor).assertEqual(undefined);
      repository.pending[1].resolve(pageOf([], undefined, true));
      await people;
      expect(controller.snapshot().activeTab).assertEqual(SearchTab.PEOPLE);
      expect(controller.snapshot().phase).assertEqual(SearchPhase.EMPTY);

      // 空结果的 tab 再次切换不触发请求；回到综合 tab 重新拉首页。
      const back = controller.selectTab(SearchTab.GENERAL);
      expect(repository.pending.length).assertEqual(3);
      expect(repository.pending[2].tab).assertEqual(SearchTab.GENERAL);
      repository.pending[2].resolve(pageOf([content('general-2')], undefined, true));
      await back;
      expect(controller.snapshot().entities.length).assertEqual(1);

      const noop = controller.selectTab(SearchTab.GENERAL);
      expect(repository.pending.length).assertEqual(3);
      await noop;
    });

    it('reloadsFirstPageWhenFiltersChangeAndSubmitResetsTab', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const first = controller.submit('query');
      repository.pending[0].resolve(pageOf([content('one')], undefined, true));
      await first;

      const filtered = controller.updateFilters(SearchSortOption.MOST_VOTED, SearchTimeRange.WEEK);
      expect(repository.pending[1].filters?.sort).assertEqual(SearchSortOption.MOST_VOTED);
      expect(repository.pending[1].filters?.timeRange).assertEqual(SearchTimeRange.WEEK);
      repository.pending[1].resolve(pageOf([content('two')], undefined, true));
      await filtered;

      const second = controller.selectTab(SearchTab.PEOPLE);
      repository.pending[2].resolve(pageOf([], undefined, true));
      await second;
      const resubmit = controller.submit('other');
      expect(repository.pending[3].tab).assertEqual(SearchTab.GENERAL);
      expect(repository.pending[3].filters?.sort).assertEqual(SearchSortOption.MOST_VOTED);
      repository.pending[3].resolve(pageOf([content('three')], undefined, true));
      await resubmit;
      expect(controller.snapshot().activeTab).assertEqual(SearchTab.GENERAL);
      expect(controller.snapshot().sort).assertEqual(SearchSortOption.MOST_VOTED);
      expect(controller.snapshot().timeRange).assertEqual(SearchTimeRange.WEEK);
    });

    it('labelsSearchTabsInUpstreamOrder', 0, () => {
      expect(searchTabLabel(SearchTab.GENERAL)).assertEqual('综合');
      expect(searchTabLabel(SearchTab.PEOPLE)).assertEqual('用户');
      expect(searchTabLabel(SearchTab.ANSWER)).assertEqual('回答');
      expect(searchTabLabel(SearchTab.ARTICLE)).assertEqual('文章');
      expect(searchTabLabel(SearchTab.TOPIC)).assertEqual('话题');
      expect(defaultSearchFilters().sort).assertEqual(SearchSortOption.DEFAULT);
    });
  });
}

function content(contentId: string, kind: FeedTargetKind = FeedTargetKind.ANSWER,
  wrapperId: string = `wrapper-${contentId}`): SearchResultItem {
  return {
    wrapperId: wrapperId,
    kind: kind,
    contentId: contentId,
    title: `${contentId} title`,
    excerpt: `${contentId} excerpt`,
    voteupCount: 1,
    commentCount: 2,
    topicIds: []
  };
}

function contentOf(contentId: string, kind: FeedTargetKind = FeedTargetKind.ANSWER,
  wrapperId: string = `wrapper-${contentId}`): SearchEntity {
  return searchEntityOfContent(content(contentId, kind, wrapperId));
}

function contentItemOf(entity: SearchEntity): SearchResultItem {
  const item = entity.content;
  if (item === undefined) {
    throw new Error('expected content entity');
  }
  return item;
}

function pageOf(items: Array<SearchResultItem>, next?: string, isEnd: boolean = false): SearchResultPage {
  return {
    entities: items.map((item: SearchResultItem): SearchEntity => searchEntityOfContent(item)),
    cursor: {
      isEnd: isEnd,
      isStart: true,
      next: next,
      page: 0,
      total: items.length
    }
  };
}
