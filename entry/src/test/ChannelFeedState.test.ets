import { describe, expect, it } from '@ohos/hypium';
import {
  ChannelContentItem,
  ChannelDailyStoryItem,
  ChannelFeedItem,
  ChannelFeedItemKind,
  ChannelFeedPage,
  ChannelFeedRepository,
  ChannelFeedSource,
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind
} from 'data';
import { AppDestinationName } from 'core';
import { channelFeedDestination } from '../main/ets/pages/ChannelFeedPage';
import { dailyFeedDateAtIndex, dailyDateCursor, dailyPickerDate } from '../main/ets/pages/DailyFeedDates';
import {
  ChannelFeedController,
  ChannelFeedPhase,
  mergeChannelFeedItems
} from '../main/ets/pages/ChannelFeedState';

interface PendingChannelRequest {
  resolve: (page: ChannelFeedPage) => void;
  reject: (error: HttpFailure) => void;
}

class ControlledChannelRepository implements ChannelFeedRepository {
  readonly sources: Array<ChannelFeedSource> = [];
  readonly cursors: Array<string | undefined> = [];
  readonly resetFlags: Array<boolean> = [];
  private readonly pending: Array<PendingChannelRequest> = [];
  cancelCount: number = 0;

  loadPage(source: ChannelFeedSource, cursor?: string, reset: boolean = false): Promise<ChannelFeedPage> {
    this.sources.push(source);
    this.cursors.push(cursor);
    this.resetFlags.push(reset);
    return new Promise<ChannelFeedPage>((resolve: (page: ChannelFeedPage) => void,
      reject: (error: HttpFailure) => void): void => {
      this.pending.push({ resolve: resolve, reject: reject });
    });
  }

  cancel(): void {
    this.cancelCount += 1;
  }

  succeed(index: number, value: ChannelFeedPage): void {
    const request = this.pending.find((_request: PendingChannelRequest, currentIndex: number): boolean =>
      currentIndex === index);
    request?.resolve(value);
  }

  fail(index: number, error: HttpFailure = new HttpFailure(HttpFailureKind.NETWORK)): void {
    const request = this.pending.find((_request: PendingChannelRequest, currentIndex: number): boolean =>
      currentIndex === index);
    request?.reject(error);
  }
}

export default function channelFeedStateTest(): void {
  describe('channelFeedStateTest', () => {
    it('ordersFollowingActivitiesNewestFirstAcrossPagesAndRefresh', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.FOLLOWING, repository);
      controller.setFollowingTimeOrder(true);
      controller.activate();
      const initial = controller.loadInitial();
      const initialItems: Array<ChannelFeedItem> = [activity('1', 100), activity('2', 300), activity('3', 200)];
      repository.succeed(0, page(initialItems, 'older'));
      await initial;
      expect(contentIds(controller.snapshot().items)).assertEqual('2,3,1');
      expect(contentIds(initialItems)).assertEqual('1,2,3');

      const more = controller.loadMore();
      expect(repository.cursors[1]).assertEqual('older');
      repository.succeed(1, page([activity('4', 250), activity('1', 100), activity('5', 50)], undefined, true));
      await more;
      expect(contentIds(controller.snapshot().items)).assertEqual('2,4,3,1,5');
      expect(controller.snapshot().canLoadMore).assertFalse();

      const refresh = controller.refresh();
      expect(repository.cursors[2]).assertUndefined();
      repository.succeed(2, page([activity('6', 400), activity('7', 500)], undefined, true));
      await refresh;
      expect(contentIds(controller.snapshot().items)).assertEqual('7,6');
    });

    it('switchesDynamicSortingWithoutReloadingOrLosingServerOrderAndPagination', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.FOLLOWING, repository);
      controller.activate();
      const initial = controller.loadInitial();
      repository.succeed(0, page([activity('1', 100), activity('2', 300)], 'next'));
      await initial;
      expect(contentIds(controller.snapshot().items)).assertEqual('1,2');
      controller.setFollowingTimeOrder(true);
      expect(contentIds(controller.snapshot().items)).assertEqual('2,1');

      const more = controller.loadMore();
      controller.setFollowingTimeOrder(false);
      expect(contentIds(controller.snapshot().items)).assertEqual('1,2');
      expect(controller.snapshot().loadingMore).assertTrue();
      expect(repository.cursors[1]).assertEqual('next');
      repository.succeed(1, page([activity('3', 200)], undefined, true));
      await more;
      expect(contentIds(controller.snapshot().items)).assertEqual('1,2,3');
      controller.setFollowingTimeOrder(true);
      expect(contentIds(controller.snapshot().items)).assertEqual('2,3,1');
      expect(repository.cancelCount).assertEqual(0);
      expect(controller.snapshot().canLoadMore).assertFalse();

      controller.deactivate();
      controller.setFollowingTimeOrder(false);
      controller.activate();
      expect(contentIds(controller.snapshot().items)).assertEqual('1,2,3');
      expect(repository.sources.length).assertEqual(2);
    });

    it('keepsRecommendationAndHotRankingWhenActivityTimesDiffer', 0, async () => {
      const sources: Array<ChannelFeedSource> = [ChannelFeedSource.FOLLOWING_RECOMMEND, ChannelFeedSource.HOT];
      for (let index = 0; index < sources.length; index += 1) {
        const repository = new ControlledChannelRepository();
        const controller = new ChannelFeedController(sources[index], repository);
        controller.setFollowingTimeOrder(true);
        controller.activate();
        const initial = controller.loadInitial();
        repository.succeed(0, page([activity('1', 100), activity('2', 300)], 'next'));
        await initial;
        const more = controller.loadMore();
        repository.succeed(1, page([activity('3', 400)], undefined, true));
        await more;
        expect(contentIds(controller.snapshot().items)).assertEqual('1,2,3');
      }
    });

    it('stablyOrdersEqualAndMissingActivityTimesWithUpdatedTimeFallback', 0, () => {
      const first = [activity('1', 0, 0), activity('2', 100), activity('3', 0, 200),
        activity('4', 100, 900), activity('5', Number.NaN, -1)];
      const ordered = mergeChannelFeedItems(first, [activity('6', 100), activity('7', -1, Number.NaN)],
        ChannelFeedSource.FOLLOWING);
      expect(contentIds(ordered)).assertEqual('3,2,4,6,1,5,7');
      expect(contentIds(first)).assertEqual('1,2,3,4,5');
    });

    it('loadsSelectedSourceAndDeduplicatesFirstPage', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.HOT, repository);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([content('1'), content('1'), content('2')], 'next'));
      await loading;

      expect(repository.sources[0]).assertEqual(ChannelFeedSource.HOT);
      expect(controller.snapshot().phase).assertEqual(ChannelFeedPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().canLoadMore).assertTrue();
    });

    it('keepsLoadedChannelItemsWhenReactivatedAfterTopLevelTabSwitch', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.HOT, repository);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([content('retained')], 'next'));
      await loading;

      controller.deactivate();
      controller.activate();

      expect(repository.cursors.length).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(ChannelFeedPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect((controller.snapshot().items[0] as ChannelContentItem).feedItem.target.id).assertEqual('retained');
    });

    it('serializesPaginationAndRetriesSameCursor', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.DAILY, repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([daily('1')], '20260810'));
      await first;

      const failed = controller.loadMore();
      controller.loadMore();
      expect(repository.cursors.length).assertEqual(2);
      repository.fail(1);
      await failed;
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().canLoadMore).assertFalse();

      const retried = controller.retry();
      expect(repository.cursors[2]).assertEqual('20260810');
      repository.succeed(2, page([daily('2')], undefined, true));
      await retried;
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('reloadsDailyFeedFromSelectedDateWithFreshPaginationState', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.DAILY, repository);
      controller.activate();
      const initial = controller.loadInitial();
      repository.succeed(0, page([daily('latest')], '20260810'));
      await initial;

      const selected = controller.loadDate('20260808');
      expect(repository.cursors[1]).assertEqual('20260808');
      expect(repository.resetFlags[1]).assertTrue();
      repository.succeed(1, page([daily('selected')], '20260807'));
      await selected;

      expect(controller.snapshot().phase).assertEqual(ChannelFeedPhase.READY);
      expect((controller.snapshot().items[0] as ChannelDailyStoryItem).story.id).assertEqual('selected');
    });

    it('prioritizesSelectedDailyDateOverInFlightPagination', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.DAILY, repository);
      controller.activate();
      const initial = controller.loadInitial();
      repository.succeed(0, page([daily('latest')], '20260810'));
      await initial;

      const loadingMore = controller.loadMore();
      const selected = controller.loadDate('20260808');
      expect(repository.cancelCount).assertEqual(1);
      expect(repository.cursors[2]).assertEqual('20260808');
      expect(repository.resetFlags[2]).assertTrue();

      repository.succeed(1, page([daily('stale')], undefined, true));
      await loadingMore;
      repository.succeed(2, page([daily('selected')], undefined, true));
      await selected;
      expect((controller.snapshot().items[0] as ChannelDailyStoryItem).story.id).assertEqual('selected');
    });

    it('retriesTheSelectedDailyDateAndRefreshesBackToLatest', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.DAILY, repository);
      controller.activate();
      const selected = controller.loadDate('20260808');
      repository.fail(0);
      await selected;
      const retried = controller.retry();
      expect(repository.cursors[1]).assertEqual('20260808');
      expect(repository.resetFlags[1]).assertTrue();
      repository.succeed(1, page([daily('1')], '20260808'));
      await retried;
      const refreshed = controller.refresh();
      expect(repository.cursors[2]).assertUndefined();
      repository.succeed(2, page([daily('2')], '20260904'));
      await refreshed;
    });

    it('resolvesVisibleDailyDateAcrossSectionsAndLoadingFooter', 0, () => {
      const first = daily('1') as ChannelDailyStoryItem;
      const older = daily('2', '20260810');
      const items: Array<ChannelFeedItem> = [first, first, older];
      expect(dailyFeedDateAtIndex(items, 1)).assertEqual(first.story.date);
      expect(dailyFeedDateAtIndex(items, 2)).assertEqual('20260810');
      expect(dailyFeedDateAtIndex(items, 3)).assertEqual('20260810');
      expect(dailyFeedDateAtIndex([], 0)).assertEqual('');
      expect(dailyDateCursor(dailyPickerDate('20240229'))).assertEqual('20240229');
    });

    it('continuesAfterEmptyNonTerminalPage', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.HOT, repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([], 'filtered-page'));
      await first;

      expect(controller.snapshot().phase).assertEqual(ChannelFeedPhase.EMPTY);
      const next = controller.retry();
      expect(repository.cursors[1]).assertEqual('filtered-page');
      repository.succeed(1, page([content('3')], undefined, true));
      await next;
      expect(controller.snapshot().phase).assertEqual(ChannelFeedPhase.READY);
    });

    it('offersLoginForSignedChannelsOn401OrMissingSession', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.FOLLOWING, repository);
      controller.activate();
      const missing = controller.loadInitial();
      repository.fail(0, new HttpFailure(HttpFailureKind.AUTHENTICATION));
      await missing;
      expect(controller.snapshot().requiresLogin).assertTrue();

      const retry = controller.retry();
      repository.fail(1, new HttpFailure(HttpFailureKind.AUTHENTICATION, 401));
      await retry;
      expect(controller.snapshot().requiresLogin).assertTrue();

      const hotRepository = new ControlledChannelRepository();
      const hotController = new ChannelFeedController(ChannelFeedSource.HOT, hotRepository);
      hotController.activate();
      const hotMissing = hotController.loadInitial();
      hotRepository.fail(0, new HttpFailure(HttpFailureKind.AUTHENTICATION));
      await hotMissing;
      expect(hotController.snapshot().requiresLogin).assertTrue();
      expect(hotController.snapshot().errorMessage).assertEqual('热榜需要登录，请登录后重试');
    });

    it('treats403AsRiskControlWithoutLoginCtaOnFirstOrNextPage', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.FOLLOWING, repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.fail(0, new HttpFailure(HttpFailureKind.AUTHENTICATION, 403));
      await first;
      expect(controller.snapshot().requiresLogin).assertFalse();
      expect(controller.snapshot().errorMessage).assertEqual('请求被拒绝，可能需要稍后重试或完成风控');

      const retry = controller.retry();
      repository.succeed(1, page([content('1')], 'next'));
      await retry;
      const more = controller.loadMore();
      repository.fail(2, new HttpFailure(HttpFailureKind.AUTHENTICATION, 403));
      await more;
      expect(controller.snapshot().requiresLogin).assertFalse();
      expect(controller.snapshot().errorMessage).assertEqual('请求被拒绝，可能需要稍后重试或完成风控');
    });

    it('ignoresLateResultAfterLeaveAndRestartsInterruptedInitialLoad', 0, async () => {
      const repository = new ControlledChannelRepository();
      const controller = new ChannelFeedController(ChannelFeedSource.HOT, repository);
      controller.activate();
      const stale = controller.loadInitial();
      controller.deactivate();
      repository.succeed(0, page([content('stale')], undefined, true));
      await stale;
      expect(controller.snapshot().items.length).assertEqual(0);
      expect(repository.cancelCount).assertEqual(1);

      controller.activate();
      expect(repository.cursors.length).assertEqual(2);
      repository.succeed(1, page([content('fresh')], undefined, true));
      await Promise.resolve();
      await Promise.resolve();
      expect(controller.snapshot().items.length).assertEqual(1);
    });

    it('mapsSupportedContentToStrongTypedDestination', 0, () => {
      const question = channelFeedDestination(content('101', FeedTargetKind.QUESTION));
      const answer = channelFeedDestination(content('102', FeedTargetKind.ANSWER));
      const article = channelFeedDestination(content('103', FeedTargetKind.ARTICLE));
      expect(question?.name).assertEqual(AppDestinationName.QUESTION);
      expect(answer?.name).assertEqual(AppDestinationName.ANSWER);
      expect(article?.name).assertEqual(AppDestinationName.ARTICLE);
      expect(channelFeedDestination(content('not-decimal'))).assertUndefined();
    });

    it('preservesFirstOccurrenceAcrossKinds', 0, () => {
      const merged = mergeChannelFeedItems(
        [content('1'), daily('1')],
        [content('1'), daily('1'), content('2')]
      );
      expect(merged.length).assertEqual(3);
    });
  });
}

function content(id: string, kind: FeedTargetKind = FeedTargetKind.ANSWER): ChannelContentItem {
  return {
    kind: ChannelFeedItemKind.CONTENT,
    topicIds: [],
    feedItem: {
      id: `wrapper-${id}`,
      verb: 'raw_protocol_verb',
      createdAt: 1,
      updatedAt: 1,
      target: {
        kind: kind,
        id: id,
        title: `${id} title`,
        excerpt: `${id} excerpt`,
        url: `https://www.zhihu.com/${id}`,
        voteupCount: 1,
        commentCount: 2,
        topicIds: []
      }
    }
  };
}

function activity(id: string, createdAt: number, updatedAt: number = createdAt): ChannelContentItem {
  const item = content(id);
  item.feedItem.createdAt = createdAt;
  item.feedItem.updatedAt = updatedAt;
  return item;
}

function contentIds(items: Array<ChannelFeedItem>): string {
  return items.map((item: ChannelFeedItem): string =>
    item.kind === ChannelFeedItemKind.CONTENT ? item.feedItem.target.id : item.story.id).join(',');
}

function daily(id: string, date: string = '20260811'): ChannelFeedItem {
  return {
    kind: ChannelFeedItemKind.DAILY_STORY,
    story: {
      id: id,
      title: `${id} daily`,
      hint: 'hint',
      url: `https://daily.zhihu.com/story/${id}`,
      storyType: 0,
      date: date
    }
  };
}

function page(items: Array<ChannelFeedItem>, next?: string, isEnd: boolean = false): ChannelFeedPage {
  return {
    items: items,
    cursor: {
      isEnd: isEnd,
      isStart: false,
      next: next,
      page: 0,
      total: items.length
    }
  };
}
