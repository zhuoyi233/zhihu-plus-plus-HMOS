import { describe, expect, it } from '@ohos/hypium';
import {
  ChannelContentItem,
  ChannelFeedItem,
  ChannelFeedItemKind,
  ChannelFeedPage,
  ChannelFeedRepository,
  ChannelFeedSource,
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind
} from 'data';
import { P1DestinationName } from 'core';
import { channelFeedDestination } from '../main/ets/pages/ChannelFeedPage';
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
  private readonly pending: Array<PendingChannelRequest> = [];
  cancelCount: number = 0;

  loadPage(source: ChannelFeedSource, cursor?: string): Promise<ChannelFeedPage> {
    this.sources.push(source);
    this.cursors.push(cursor);
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
      expect(question?.name).assertEqual(P1DestinationName.QUESTION);
      expect(answer?.name).assertEqual(P1DestinationName.ANSWER);
      expect(article?.name).assertEqual(P1DestinationName.ARTICLE);
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

function daily(id: string): ChannelFeedItem {
  return {
    kind: ChannelFeedItemKind.DAILY_STORY,
    story: {
      id: id,
      title: `${id} daily`,
      hint: 'hint',
      url: `https://daily.zhihu.com/story/${id}`,
      storyType: 0,
      date: '20260811'
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
