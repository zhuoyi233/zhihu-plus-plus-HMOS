import { describe, expect, it } from '@ohos/hypium';
import { FeedItem, FeedPage, FeedRepository, FeedTargetKind, HttpFailure, HttpFailureKind } from 'data';
import {
  HomeFeedController,
  HomeFeedPhase,
  HomeFeedViewState,
  mergeUniqueFeedItems
} from '../main/ets/pages/HomeFeedState';
import { homeFeedActionLabel, homeFeedDestination, homeFeedDetailsLabel, homeFeedFooterLabel, resolveHomeFeedDestination } from '../main/ets/pages/HomeFeedPage';

interface PendingRequest {
  resolve: (page: FeedPage) => void;
  reject: (error: Error) => void;
}

class ControlledFeedRepository implements FeedRepository {
  readonly cursors: Array<string | undefined> = [];
  private readonly pending: Array<PendingRequest> = [];
  cancelCount: number = 0;

  loadHomePage(cursor?: string): Promise<FeedPage> {
    this.cursors.push(cursor);
    return new Promise<FeedPage>((resolve: (page: FeedPage) => void, reject: (error: Error) => void): void => {
      this.pending.push({ resolve: resolve, reject: reject });
    });
  }

  cancel(): void {
    this.cancelCount += 1;
  }

  succeed(index: number, page: FeedPage): void {
    const request = this.pending.find((_request: PendingRequest, currentIndex: number): boolean => currentIndex === index);
    request?.resolve(page);
  }

  fail(index: number): void {
    this.failWith(index, new Error('network details must not reach UI'));
  }

  failWith(index: number, error: Error): void {
    const request = this.pending.find((_request: PendingRequest, currentIndex: number): boolean => currentIndex === index);
    request?.reject(error);
  }

}

class RejectedHomeFeedRepository implements FeedRepository {
  async loadHomePage(_cursor?: string): Promise<FeedPage> {
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION, 403);
  }

  cancel(): void {
  }
}

class RemoteReadFeedRepository extends ControlledFeedRepository {
  listener?: () => void;
  readonly read: Set<string> = new Set<string>();
  filterCount: number = 0;
  pendingFilter?: (items: Array<FeedItem>) => void;
  delayFilter: boolean = false;

  subscribeRemoteReads(listener: () => void): () => void {
    this.listener = listener;
    return (): void => { this.listener = undefined; };
  }

  async filterRemoteReads(items: Array<FeedItem>): Promise<Array<FeedItem>> {
    this.filterCount += 1;
    if (this.delayFilter) {
      return new Promise<Array<FeedItem>>((resolve): void => { this.pendingFilter = resolve; });
    }
    return items.filter((item: FeedItem): boolean => !this.read.has(item.id));
  }
}

async function flushRemoteFilter(): Promise<void> {
  for (let index = 0; index < 12; index += 1) await Promise.resolve();
}

class MissingSessionHomeFeedRepository implements FeedRepository {
  async loadHomePage(_cursor?: string): Promise<FeedPage> {
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
  }

  cancel(): void {
  }
}

export default function homeFeedStateTest(): void {
  describe('homeFeedStateTest', () => {
    it('fillsTheInitialViewportBeforePublishingReady', 0, async () => {
      const repository = new ControlledFeedRepository();
      const states: Array<HomeFeedPhase> = [];
      const controller = new HomeFeedController(repository, (state: HomeFeedViewState): void => {
        states.push(state.phase);
      });
      controller.activate();
      const loading = controller.loadInitial();
      // 窗口测量通常发生在首个网络请求期间。
      controller.setInitialItemTarget(3);
      repository.succeed(0, page([feed('a')], 'next'));
      await flushRemoteFilter();
      expect(repository.cursors.length).assertEqual(2);
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.INITIAL_LOADING);
      expect(controller.snapshot().items.length).assertEqual(0);
      expect(states.includes(HomeFeedPhase.READY)).assertFalse();
      repository.succeed(1, page([feed('a'), feed('b'), feed('c')], 'after'));
      await loading;
      expect(controller.snapshot().items.length).assertEqual(3);
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.READY);
      expect(controller.snapshot().loadingMore).assertFalse();
    });

    it('continuesPastFilteredEmptyPagesAndStopsAtTheEnd', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.setInitialItemTarget(12);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([], 'next'));
      await flushRemoteFilter();
      repository.succeed(1, page([feed('a')], undefined, true));
      await loading;
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().canLoadMore).assertFalse();
      expect(repository.cursors.length).assertEqual(2);
    });

    it('keepsSuccessfulInitialItemsWhenAnExtraPageFailsAndRetriesThatCursor', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.setInitialItemTarget(3);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([feed('a')], 'next'));
      await flushRemoteFilter();
      repository.fail(1);
      await loading;
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.READY);
      expect(controller.snapshot().items[0].id).assertEqual('a');
      expect(controller.snapshot().errorMessage !== undefined).assertTrue();
      expect(controller.snapshot().canLoadMore).assertFalse();
      const retry = controller.retry();
      expect(repository.cursors[2]).assertEqual('next');
      repository.succeed(2, page([feed('b')], undefined, true));
      await retry;
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('discardsTheEntireInitialBatchIfThePageBecomesInactive', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.setInitialItemTarget(3);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([feed('a')], 'next'));
      await flushRemoteFilter();
      controller.deactivate();
      repository.succeed(1, page([feed('b'), feed('c')], 'after'));
      await loading;
      expect(controller.snapshot().items.length).assertEqual(0);
    });

    it('boundsInitialRequestsEvenWhenEveryPageIsFilteredOut', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.setInitialItemTarget(12);
      controller.activate();
      const loading = controller.loadInitial();
      for (let index = 0; index < 4; index += 1) {
        repository.succeed(index, page([], `next-${index}`));
        await flushRemoteFilter();
      }
      await loading;
      expect(repository.cursors.length).assertEqual(4);
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.EMPTY);
    });

    it('stopsInitialPrefetchOnARepeatedCursor', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.setInitialItemTarget(12);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([feed('a')], 'same'));
      await flushRemoteFilter();
      repository.succeed(1, page([feed('b')], 'same'));
      await loading;
      expect(repository.cursors.length).assertEqual(2);
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('keepsTheOldFeedVisibleUntilTheRefreshBatchIsReady', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const initial = controller.loadInitial();
      repository.succeed(0, page([feed('old')], 'old-next'));
      await initial;
      controller.setInitialItemTarget(3);
      const refresh = controller.refresh();
      repository.succeed(1, page([feed('new-a')], 'new-next'));
      await flushRemoteFilter();
      expect(controller.snapshot().items[0].id).assertEqual('old');
      expect(controller.snapshot().refreshing).assertTrue();
      repository.succeed(2, page([feed('new-b'), feed('new-c')], undefined, true));
      await refresh;
      expect(controller.snapshot().items.length).assertEqual(3);
      expect(controller.snapshot().items[0].id).assertEqual('new-a');
      expect(controller.snapshot().refreshing).assertFalse();
    });

    it('filtersLateRemoteReadsOnlyBeyondTheBrowsedPrefixWithoutReloadingRecommendations', 0, async () => {
      const repository = new RemoteReadFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([feed('first'), feed('second'), feed('third')], 'next'));
      await first;
      controller.markVisibleThrough(1);
      await flushRemoteFilter();
      repository.read.add('first');
      repository.read.add('second');
      repository.read.add('third');
      repository.listener?.();
      await flushRemoteFilter();
      expect(controller.snapshot().items.map((item: FeedItem): string => item.id).join(','))
        .assertEqual('first,second');
      expect(repository.cursors.length).assertEqual(1);
      expect(controller.snapshot().canLoadMore).assertTrue();
      expect(controller.snapshot().refreshing).assertFalse();
    });

    it('rechecksTheBrowsedPrefixWhenTheUserScrollsDuringAnAsyncReadQuery', 0, async () => {
      const repository = new RemoteReadFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([feed('first'), feed('second'), feed('third')], 'next'));
      await first;
      controller.markVisibleThrough(0);
      await flushRemoteFilter();
      repository.delayFilter = true;
      repository.listener?.();
      controller.markVisibleThrough(1);
      repository.pendingFilter?.([]);
      await flushRemoteFilter();
      expect(controller.snapshot().items.map((item: FeedItem): string => item.id).join(','))
        .assertEqual('first,second');
    });

    it('detachesRemoteReadUpdatesWhileInactiveAndChecksAgainOnReentry', 0, async () => {
      const repository = new RemoteReadFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([feed('first'), feed('second')], 'next'));
      await first;
      controller.markVisibleThrough(0);
      await flushRemoteFilter();
      controller.deactivate();
      expect(repository.listener).assertUndefined();
      repository.read.add('second');
      controller.activate();
      await flushRemoteFilter();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(repository.cursors.length).assertEqual(1);
    });

    it('loadsFirstPageAndDeduplicatesItems', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();

      const loading = controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.INITIAL_LOADING);
      repository.succeed(0, page([feed('first'), feed('first'), feed('second')], 'next'));
      await loading;

      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().canLoadMore).assertTrue();
    });

    it('keepsLoadedItemsWhenReactivatedAfterTopLevelTabSwitch', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const loading = controller.loadInitial();
      repository.succeed(0, page([feed('retained')], 'next'));
      await loading;

      controller.deactivate();
      controller.activate();

      expect(repository.cursors.length).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.READY);
      expect(controller.snapshot().items[0].id).assertEqual('retained');
    });

    it('appendsOnePaginationRequestAndUsesServerCursor', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([feed('first')], 'next'));
      await first;

      const more = controller.loadMore();
      controller.loadMore();
      expect(repository.cursors.length).assertEqual(2);
      expect(repository.cursors[1]).assertEqual('next');
      repository.succeed(1, page([feed('first'), feed('second')], undefined, true));
      await more;

      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().canLoadMore).assertFalse();
    });

    it('retriesFailedPaginationWithoutReplacingVisibleItems', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const first = controller.loadInitial();
      repository.succeed(0, page([feed('first')], 'next'));
      await first;

      const failed = controller.loadMore();
      repository.fail(1);
      await failed;
      expect(controller.snapshot().canLoadMore).assertFalse();
      const retry = controller.retry();
      expect(repository.cursors[2]).assertEqual('next');
      repository.succeed(2, page([feed('second')], undefined, true));
      await retry;

      expect(controller.snapshot().items.map((item: FeedItem): string => item.id).join(',')).assertEqual(
        'first,second'
      );
    });

    it('showsRecoverableEmptyAndErrorStates', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const failed = controller.loadInitial();
      repository.fail(0);
      await failed;
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.ERROR);
      expect(controller.snapshot().errorMessage).assertEqual('首页加载失败，请检查网络后重试');

      const retry = controller.refresh();
      repository.succeed(1, page([], 'next-empty'));
      await retry;
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.EMPTY);
      expect(controller.snapshot().canLoadMore).assertTrue();
      expect(controller.snapshot().errorMessage).assertUndefined();

      const continueAfterFilteredPage = controller.retry();
      expect(repository.cursors[2]).assertEqual('next-empty');
      repository.succeed(2, page([], undefined, true));
      await continueAfterFilteredPage;
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.EMPTY);
      expect(controller.snapshot().canLoadMore).assertFalse();
    });

    it('showsZhihuRejectionWithoutExposingResponseContent', 0, async () => {
      const repository = new RejectedHomeFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();

      await controller.loadInitial();

      expect(controller.snapshot().errorMessage).assertEqual('首页请求被知乎拒绝，可能需要完成风控验证');
      expect(controller.snapshot().requiresLogin).assertFalse();
    });

    it('marksMissingSessionAsLoginRecoverable', 0, async () => {
      const controller = new HomeFeedController(new MissingSessionHomeFeedRepository());
      controller.activate();

      await controller.loadInitial();

      expect(controller.snapshot().errorMessage).assertEqual('登录状态不可用，请重新登录后刷新');
      expect(controller.snapshot().requiresLogin).assertTrue();
    });

    it('serializesRefreshAndIgnoresResultsAcrossLeave', 0, async () => {
      const repository = new ControlledFeedRepository();
      const controller = new HomeFeedController(repository);
      controller.activate();
      const initial = controller.loadInitial();
      controller.refresh();
      expect(repository.cursors.length).assertEqual(1);
      repository.succeed(0, page([feed('initial')], undefined, true));
      await initial;

      const latest = controller.refresh();
      controller.refresh();
      expect(repository.cursors.length).assertEqual(2);
      repository.succeed(1, page([feed('latest')], undefined, true));
      await latest;
      expect(controller.snapshot().items[0].id).assertEqual('latest');

      const leaving = controller.refresh();
      controller.deactivate();
      expect(repository.cancelCount).assertEqual(1);
      repository.succeed(2, page([feed('after-leave')], undefined, true));
      await leaving;
      expect(controller.snapshot().items[0].id).assertEqual('latest');
    });

    it('mapsEverySupportedCardToTypedContentDestination', 0, () => {
      expect(homeFeedDestination(feed('q', FeedTargetKind.QUESTION)).name).assertEqual('Question');
      expect(homeFeedDestination(feed('a', FeedTargetKind.ANSWER)).name).assertEqual('Answer');
      expect(homeFeedDestination(feed('z', FeedTargetKind.ARTICLE)).name).assertEqual('Article');
    });

    it('opensContinuousHomeAnswerAtTheClickedSeedWithoutExtraLookup', 0, async () => {
      const item = feed('seed');
      item.target.id = '2091206450836149421';
      item.target.questionId = '123456';
      let lookups = 0;
      const destination = await resolveHomeFeedDestination(item, 'continuous', async (_id: string): Promise<string> => {
        lookups += 1;
        return '999';
      });
      expect(JSON.stringify(destination)).assertEqual(JSON.stringify({
        name: 'ContinuousAnswer', questionId: '123456', answerId: '2091206450836149421'
      }));
      expect(lookups).assertEqual(0);
    });

    it('resolvesMissingQuestionIdBeforeOpeningContinuousHomeAnswer', 0, async () => {
      const item = feed('missing');
      let requestedAnswer = '';
      const destination = await resolveHomeFeedDestination(item, 'continuous', async (id: string): Promise<string> => {
        requestedAnswer = id;
        return ' 123456 ';
      });
      expect(requestedAnswer).assertEqual(item.target.id);
      expect(JSON.stringify(destination)).assertEqual(JSON.stringify({
        name: 'ContinuousAnswer', questionId: '123456', answerId: item.target.id
      }));
    });

    it('keepsSingleAndOtherContentRoutesWithoutResolvingQuestions', 0, async () => {
      let lookups = 0;
      const loader = async (_id: string): Promise<string> => { lookups += 1; return '123'; };
      const item = feed('answer');
      expect((await resolveHomeFeedDestination(item, 'single', loader)).name).assertEqual('Answer');
      expect((await resolveHomeFeedDestination(item, 'invalid', loader)).name).assertEqual('Answer');
      expect((await resolveHomeFeedDestination(feed('q', FeedTargetKind.QUESTION), 'continuous', loader)).name)
        .assertEqual('Question');
      expect((await resolveHomeFeedDestination(feed('z', FeedTargetKind.ARTICLE), 'continuous', loader)).name)
        .assertEqual('Article');
      expect((await resolveHomeFeedDestination(feed('v', FeedTargetKind.VIDEO), 'continuous', loader)).name)
        .assertEqual('Video');
      expect(lookups).assertEqual(0);
    });

    it('looksUpMalformedSummaryQuestionIdsAndRejectsInvalidResults', 0, async () => {
      const item = feed('invalid');
      item.target.questionId = 'not-a-question';
      let failed = false;
      try {
        await resolveHomeFeedDestination(item, 'continuous', async (_id: string): Promise<string> => '');
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });

    it('doesNotSilentlyOpenSingleModeWhenQuestionLookupFails', 0, async () => {
      let failed = false;
      try {
        await resolveHomeFeedDestination(feed('offline'), 'continuous', async (_id: string): Promise<string> => {
          throw new Error('offline');
        });
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });

    it('preservesFirstOccurrenceWhenMergingPages', 0, () => {
      const merged = mergeUniqueFeedItems(
        [feed('one'), feed('two')],
        [feed('two'), feed('two', FeedTargetKind.QUESTION), feed('three')]
      );
      expect(merged.length).assertEqual(4);
      expect(merged[2].target.kind).assertEqual(FeedTargetKind.QUESTION);
    });

    it('showsLocalReasonAndMobileSourceLabelsOnCards', 0, () => {
      const local = feed('local');
      local.recommendationReason = '热门推荐';
      local.actionText = '手机版推荐';
      expect(homeFeedActionLabel(local)).assertEqual('热门推荐');

      const mobile = feed('mobile');
      mobile.verb = '手机版推荐';
      mobile.actionText = '手机版推荐';
      expect(homeFeedActionLabel(mobile)).assertEqual('手机版推荐');

      const web = feed('web');
      web.verb = 'TOPIC_ACKNOWLEDGED_ANSWER';
      web.recommendationReason = undefined;
      expect(homeFeedActionLabel(web)).assertEqual('推荐内容');
    });

    it('showsOriginalMobileFooterWithoutInventingCommentPlaceholders', 0, () => {
      const mobile = feed('mobile');
      mobile.target.mobileFooterText = '1934 赞同 · 699 收藏';
      mobile.target.commentCount = undefined;
      expect(homeFeedFooterLabel(mobile)).assertEqual('1934 赞同 · 699 收藏 · 手机版推荐');
      mobile.target.qualityFilterReason = '规则：回答；赞数 < 2000，未关注作者';
      expect(homeFeedFooterLabel(mobile)).assertEqual('1934 赞同 · 699 收藏 · 手机版推荐');
      mobile.target.mobileFooterText = '1.9 万赞同 · 3069 评论';
      expect(homeFeedFooterLabel(mobile)).assertEqual('1.9 万赞同 · 3069 评论 · 手机版推荐');
      mobile.target.mobileFooterText = '';
      expect(homeFeedFooterLabel(mobile)).assertEqual('手机版推荐');
      expect(homeFeedFooterLabel(feed('web'))).assertEqual('2 赞同 · 1 评论');
    });

    it('hidesRawProtocolVerbFromCards', 0, () => {
      const item = feed('raw');
      item.verb = 'TOPIC_ACKNOWLEDGED_ANSWER';
      expect(homeFeedActionLabel(item)).assertEqual('推荐内容');
      item.actionText = '赞同了回答';
      expect(homeFeedActionLabel(item)).assertEqual('赞同了回答');
      item.actionText = undefined;
      item.verb = 'topic_acknowledged_answer';
      expect(homeFeedActionLabel(item)).assertEqual('推荐内容');
      item.verb = 'recommended by topic';
      expect(homeFeedActionLabel(item)).assertEqual('推荐内容');
    });

    it('buildsFooterDetailsWithTypeAndOriginalMobileText', 0, () => {
      // Web 卡对齐上游 detailsText：类型 + 统计。
      expect(homeFeedDetailsLabel(feed('web'))).assertEqual('回答 · 2 赞同 · 1 评论');
      const question = feed('q', FeedTargetKind.QUESTION);
      question.target.voteupCount = undefined;
      question.target.commentCount = undefined;
      expect(homeFeedDetailsLabel(question)).assertEqual('问题 · — 赞同 · — 评论');
      // 移动卡片保留服务端页脚原文，不重复拼类型与来源标注。
      const mobile = feed('mobile');
      mobile.target.mobileFooterText = '1934 赞同 · 699 收藏';
      expect(homeFeedDetailsLabel(mobile)).assertEqual('1934 赞同 · 699 收藏 · 手机版推荐');
      mobile.target.mobileFooterText = '';
      expect(homeFeedDetailsLabel(mobile)).assertEqual('手机版推荐');
    });
  });
}

function feed(id: string, kind: FeedTargetKind = FeedTargetKind.ANSWER): FeedItem {
  return {
    id: id,
    verb: '推荐了',
    createdAt: 1,
    updatedAt: 1,
    target: {
      kind: kind,
      id: `${id}-target`,
      title: `${id} title`,
      excerpt: `${id} excerpt`,
      url: `https://www.zhihu.com/${id}`,
      voteupCount: 2,
      commentCount: 1,
      topicIds: []
    }
  };
}

function page(items: Array<FeedItem>, next?: string, isEnd: boolean = false): FeedPage {
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
