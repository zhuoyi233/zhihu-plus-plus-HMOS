import { describe, expect, it } from '@ohos/hypium';
import {
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind,
  SearchRepository,
  SearchResultItem,
  SearchResultPage
} from 'data';
import {
  filterSearchResults,
  searchResultDestination,
  SearchResultFilter
} from '../main/ets/pages/SearchPage';
import { mergeSearchResults, SearchController, SearchPhase } from '../main/ets/pages/SearchState';

interface PendingSearch {
  readonly query: string;
  readonly cursor?: string;
  readonly resolve: (page: SearchResultPage) => void;
  readonly reject: (error: Error) => void;
}

class ControlledSearchRepository implements SearchRepository {
  readonly pending: Array<PendingSearch> = [];
  cancelCount: number = 0;

  search(query: string, cursor?: string): Promise<SearchResultPage> {
    return new Promise<SearchResultPage>((resolve: (page: SearchResultPage) => void,
      reject: (error: Error) => void): void => {
      this.pending.push({ query: query, cursor: cursor, resolve: resolve, reject: reject });
    });
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

  async search(_query: string, cursor?: string): Promise<SearchResultPage> {
    if (cursor === undefined && this.firstPage !== undefined) {
      return this.firstPage;
    }
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION, this.status);
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
      repository.pending[0].resolve(page([result('answer-1')], 'next'));
      await loading;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
    });

    it('cancelsPreviousQueryAndIgnoresItsLateResult', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const oldSearch = controller.submit('old');
      const newSearch = controller.submit('new');
      repository.pending[1].resolve(page([result('new')], undefined, true));
      await newSearch;
      repository.pending[0].resolve(page([result('old')], undefined, true));
      await oldSearch;

      expect(controller.snapshot().query).assertEqual('new');
      expect(controller.snapshot().items[0].contentId).assertEqual('new');
      expect(repository.cancelCount).assertEqual(2);
    });

    it('retriesFailedPaginationWithSameCursorAndKeepsItems', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const first = controller.submit('query');
      repository.pending[0].resolve(page([result('first')], 'next'));
      await first;
      const failed = controller.loadMore();
      repository.pending[1].reject(new Error('network detail'));
      await failed;
      expect(controller.snapshot().canLoadMore).assertFalse();

      const retry = controller.retry();
      expect(repository.pending[2].cursor).assertEqual('next');
      repository.pending[2].resolve(page([result('second')], undefined, true));
      await retry;
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('continuesAfterEmptyNonTerminalPage', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const first = controller.submit('query');
      repository.pending[0].resolve(page([], 'next-empty'));
      await first;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.EMPTY);
      const next = controller.retry();
      expect(repository.pending[1].cursor).assertEqual('next-empty');
      repository.pending[1].resolve(page([result('visible')], undefined, true));
      await next;
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
    });

    it('cancelsOnDeactivateAndDoesNotPublishLateResponse', 0, async () => {
      const repository = new ControlledSearchRepository();
      const controller = new SearchController(repository);
      controller.activate();
      const initial = controller.submit('query');
      repository.pending[0].resolve(page([result('visible')], 'next'));
      await initial;
      const loading = controller.loadMore();
      controller.deactivate();
      repository.pending[1].resolve(page([result('late')], undefined, true));
      await loading;
      expect(repository.cancelCount).assertEqual(2);
      expect(controller.snapshot().items.length).assertEqual(1);
      controller.activate();
      expect(controller.snapshot().items[0].contentId).assertEqual('visible');

      const initialRepository = new ControlledSearchRepository();
      const initialController = new SearchController(initialRepository);
      initialController.activate();
      const interrupted = initialController.submit('resume');
      initialController.deactivate();
      initialController.activate();
      expect(initialRepository.pending.length).assertEqual(2);
      initialRepository.pending[1].resolve(page([result('resumed')], undefined, true));
      await Promise.resolve();
      initialRepository.pending[0].resolve(page([result('stale')], undefined, true));
      await interrupted;
      expect(initialController.snapshot().items[0].contentId).assertEqual('resumed');
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
      const firstPage = page([result('visible')], 'next');
      const controller = new SearchController(new AuthenticationSearchRepository(403, firstPage));
      controller.activate();
      await controller.submit('query');
      await controller.loadMore();
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().requiresLogin).assertFalse();
      expect(controller.snapshot().errorMessage)
        .assertEqual('请求被拒绝，可能需要稍后重试或完成风控');
    });

    it('deduplicatesStableTargetsAndMapsTypedDestinations', 0, () => {
      const merged = mergeSearchResults(
        [result('same', FeedTargetKind.ANSWER, 'wrapper-1')],
        [result('same', FeedTargetKind.ANSWER, 'wrapper-2'), result('same', FeedTargetKind.ARTICLE, 'wrapper-3')]
      );
      expect(merged.length).assertEqual(2);
      expect(searchResultDestination(merged[0]).name).assertEqual('Answer');
      expect(searchResultDestination(merged[1]).name).assertEqual('Article');
      expect(searchResultDestination(result('question', FeedTargetKind.QUESTION)).name).assertEqual('Question');
    });

    it('filtersLoadedGeneralResultsByVisibleResultTab', 0, () => {
      const results: Array<SearchResultItem> = [
        result('question', FeedTargetKind.QUESTION),
        result('answer', FeedTargetKind.ANSWER),
        result('article', FeedTargetKind.ARTICLE)
      ];
      expect(filterSearchResults(results, SearchResultFilter.ALL).length).assertEqual(3);
      expect(filterSearchResults(results, SearchResultFilter.QUESTION)[0].contentId).assertEqual('question');
      expect(filterSearchResults(results, SearchResultFilter.ANSWER)[0].contentId).assertEqual('answer');
      expect(filterSearchResults(results, SearchResultFilter.ARTICLE)[0].contentId).assertEqual('article');
    });
  });
}

function result(contentId: string, kind: FeedTargetKind = FeedTargetKind.ANSWER,
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

function page(items: Array<SearchResultItem>, next?: string, isEnd: boolean = false): SearchResultPage {
  return {
    items: items,
    cursor: {
      isEnd: isEnd,
      isStart: true,
      next: next,
      page: 0,
      total: items.length
    }
  };
}
