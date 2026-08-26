import { describe, expect, it } from '@ohos/hypium';
import { FeedItem, FeedPage, FeedRepository, FeedTargetKind, HttpFailure, HttpFailureKind } from 'data';
import {
  HomeFeedController,
  HomeFeedPhase,
  mergeUniqueFeedItems
} from '../main/ets/pages/HomeFeedState';
import { homeFeedActionLabel, homeFeedDestination } from '../main/ets/pages/HomeFeedPage';

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

class MissingSessionHomeFeedRepository implements FeedRepository {
  async loadHomePage(_cursor?: string): Promise<FeedPage> {
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
  }

  cancel(): void {
  }
}

export default function homeFeedStateTest(): void {
  describe('homeFeedStateTest', () => {
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

    it('preservesFirstOccurrenceWhenMergingPages', 0, () => {
      const merged = mergeUniqueFeedItems(
        [feed('one'), feed('two')],
        [feed('two'), feed('two', FeedTargetKind.QUESTION), feed('three')]
      );
      expect(merged.length).assertEqual(4);
      expect(merged[2].target.kind).assertEqual(FeedTargetKind.QUESTION);
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
