import { describe, expect, it } from '@ohos/hypium';
import {
  HttpFailure,
  HttpFailureKind,
  OnlineHistoryEntry,
  OnlineHistoryKind,
  OnlineHistoryPage,
  OnlineHistoryRepository,
  OpenedContent,
  ReadHistoryGateway
} from 'data';
import {
  decodeReadHistoryItem,
  LocalHistoryController,
  ReadHistoryContentKind,
  ReadHistoryController,
  ReadHistoryItem,
  readHistoryKindLabel,
  readHistoryOpenTarget,
  ReadHistoryPhase,
  readHistoryTimeLabel
} from '../main/ets/pages/ReadHistoryState';

class FakeReadHistory implements ReadHistoryGateway {
  items: Array<OpenedContent> = [];
  fail: boolean = false;
  clearCount: number = 0;

  queryRecent(_limit?: number): Promise<Array<OpenedContent>> {
    if (this.fail) {
      return Promise.reject(new Error('database path and record value'));
    }
    return Promise.resolve(this.items.slice());
  }

  delete(contentKey: string): Promise<boolean> {
    const before = this.items.length;
    this.items = this.items.filter((item: OpenedContent): boolean => item.contentKey !== contentKey);
    return Promise.resolve(before !== this.items.length);
  }

  clear(): Promise<void> {
    this.clearCount += 1;
    this.items = [];
    return Promise.resolve();
  }
}

class FakeOnlineHistory implements OnlineHistoryRepository {
  pages: Array<OnlineHistoryPage> = [];
  fail: boolean = false;
  authFail: boolean = false;
  clearAllCount: number = 0;
  deletedKeys: Array<string> = [];
  // 与真实仓库一致：首页请求（cursor 为空）总是重置分页进度并返回第一页。
  private pageIndex: number = 0;

  loadPage(cursor?: string): Promise<OnlineHistoryPage> {
    if (cursor === undefined) {
      this.pageIndex = 0;
    } else {
      this.pageIndex += 1;
    }
    if (this.fail) {
      return Promise.reject(new Error('sensitive upstream payload'));
    }
    if (this.authFail) {
      return Promise.reject(new HttpFailure(HttpFailureKind.AUTHENTICATION, 401));
    }
    if (this.pages.length === 0) {
      const emptyPage: OnlineHistoryPage = {
        items: [],
        cursor: { isEnd: true, isStart: true, page: 1, total: 0 }
      };
      return Promise.resolve(emptyPage);
    }
    const page = this.pages[Math.min(this.pageIndex, this.pages.length - 1)];
    return Promise.resolve(page);
  }

  clearAll(): Promise<void> {
    this.clearAllCount += 1;
    return Promise.resolve();
  }

  deleteEntry(contentKey: string): Promise<void> {
    this.deletedKeys.push(contentKey);
    return Promise.resolve();
  }

  cancel(): void {
  }
}

function onlineEntry(kind: OnlineHistoryKind, id: string, readTime: number, title?: string): OnlineHistoryEntry {
  return {
    contentKey: `${kind}:${id}`,
    kind: kind,
    id: id,
    title: title ?? '',
    summary: '',
    readTime: readTime
  };
}

function onlinePage(items: Array<OnlineHistoryEntry>, next: string | undefined, isEnd: boolean): OnlineHistoryPage {
  return {
    items: items,
    cursor: { isEnd: isEnd, isStart: next === undefined, next: next, page: 1, total: items.length }
  };
}

export default function readHistoryStateTest(): void {
  describe('readHistoryStateTest', () => {
    it('decodesOnlyStrictSupportedTypeAndDecimalIdPairs', 0, () => {
      const valid = decodeReadHistoryItem({ contentKey: 'answer:123', contentType: 'answer', openedAt: 1 });
      expect(valid?.kind).assertEqual(ReadHistoryContentKind.ANSWER);
      expect(valid?.id).assertEqual('123');
      expect(decodeReadHistoryItem({ contentKey: 'answer:../123', contentType: 'answer', openedAt: 1 }))
        .assertUndefined();
      expect(decodeReadHistoryItem({ contentKey: 'answer:123', contentType: 'article', openedAt: 1 }))
        .assertUndefined();
      expect(decodeReadHistoryItem({ contentKey: 'video:123', contentType: 'video', openedAt: 1 }))
        .assertUndefined();
      const pin = decodeReadHistoryItem({ contentKey: 'pin:456', contentType: 'pin', openedAt: 2 });
      expect(pin?.kind).assertEqual(ReadHistoryContentKind.PIN);
      expect(pin?.id).assertEqual('456');
      if (pin !== undefined) {
        expect(readHistoryKindLabel(pin.kind)).assertEqual('想法');
        const target = readHistoryOpenTarget(pin);
        expect(target.kind).assertEqual(ReadHistoryContentKind.PIN);
        expect(target.id).assertEqual('456');
      }
      expect(decodeReadHistoryItem({ contentKey: 'pin:0', contentType: 'pin', openedAt: 2 }))
        .assertUndefined();
    });

    it('passesStoredTitleThroughForDisplay', 0, () => {
      const titled = decodeReadHistoryItem(
        { contentKey: 'answer:9', contentType: 'answer', openedAt: 3, title: '如何修复历史标题' });
      expect(titled?.title).assertEqual('如何修复历史标题');
      const untitled = decodeReadHistoryItem({ contentKey: 'answer:9', contentType: 'answer', openedAt: 3 });
      expect(untitled?.title ?? '').assertEqual('');
    });

    it('formatsCardTimeLabelToMinutePrecision', 0, () => {
      const label = readHistoryTimeLabel(new Date(2026, 7, 28, 9, 5).getTime());
      expect(label).assertEqual('2026-08-28 09:05');
      expect(readHistoryTimeLabel(Number.NaN)).assertEqual('');
    });

    it('loadsOnlineHistoryPagesAndMapsEntriesToCards', 0, async () => {
      const history = new FakeReadHistory();
      const online = new FakeOnlineHistory();
      online.pages = [
        onlinePage([
          onlineEntry(OnlineHistoryKind.ANSWER, '2', 20, '在线回答标题'),
          onlineEntry(OnlineHistoryKind.QUESTION, '1', 30)
        ], 'offset=10', false)
      ];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.READY);
      expect(state.requiresLogin).assertFalse();
      expect(state.canLoadMore).assertTrue();
      expect(state.items.length).assertEqual(2);
      expect(state.items[0].title).assertEqual('在线回答标题');
      expect(state.items[0].kind).assertEqual(ReadHistoryContentKind.ANSWER);
      expect(state.items[0].openedAt).assertEqual(20);
    });

    it('loadsMoreOnlinePagesUntilEnd', 0, async () => {
      const history = new FakeReadHistory();
      const online = new FakeOnlineHistory();
      online.pages = [
        onlinePage([onlineEntry(OnlineHistoryKind.ANSWER, '2', 20)], 'offset=10', false),
        onlinePage([onlineEntry(OnlineHistoryKind.QUESTION, '1', 10)], undefined, true)
      ];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().canLoadMore).assertTrue();
      await controller.loadMore();
      const state = controller.snapshot();
      expect(state.items.length).assertEqual(2);
      expect(state.canLoadMore).assertFalse();
      expect(state.loadingMore).assertFalse();
    });

    it('deduplicatesItemsAcrossPages', 0, async () => {
      const history = new FakeReadHistory();
      const online = new FakeOnlineHistory();
      online.pages = [
        onlinePage([onlineEntry(OnlineHistoryKind.ANSWER, '2', 20)], 'offset=10', false),
        onlinePage([onlineEntry(OnlineHistoryKind.ANSWER, '2', 30)], undefined, true)
      ];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      await controller.loadMore();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().items[0].openedAt).assertEqual(20);
    });

    it('showsLoginGateWithoutOnlineSession', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 20 }];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.requiresLogin).assertTrue();
      expect(state.phase).assertEqual(ReadHistoryPhase.EMPTY);
      expect(state.canLoadMore).assertFalse();
      expect(state.items.length).assertEqual(0);
    });

    it('marksSessionExpiredOnOnlineAuthenticationFailure', 0, async () => {
      const online = new FakeOnlineHistory();
      online.authFail = true;
      const controller = new ReadHistoryController(new FakeReadHistory(), online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.EMPTY);
      expect(state.message.includes('登录已失效')).assertTrue();
      expect(state.message.includes('401')).assertFalse();
    });

    it('reportsFixedLoadErrorWithoutLeakingUpstreamPayload', 0, async () => {
      const online = new FakeOnlineHistory();
      online.fail = true;
      const controller = new ReadHistoryController(new FakeReadHistory(), online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.ERROR);
      expect(state.message).assertEqual('历史记录加载失败，请重试');
      expect(state.message.includes('sensitive')).assertFalse();
    });

    it('deletesOneOnlineEntryAndRemovesCardFromList', 0, async () => {
      const online = new FakeOnlineHistory();
      online.pages = [onlinePage([
        onlineEntry(OnlineHistoryKind.QUESTION, '1', 30),
        onlineEntry(OnlineHistoryKind.PIN, '3', 40)
      ], undefined, true)];
      const controller = new ReadHistoryController(new FakeReadHistory(), online, true);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().items.length).assertEqual(2);
      await controller.deleteEntry('question:1');
      const afterDelete = controller.snapshot();
      expect(afterDelete.items.length).assertEqual(1);
      expect(afterDelete.items[0].contentKey).assertEqual('pin:3');
      expect(online.deletedKeys).assertDeepEquals(['question:1']);
    });

    it('clearAllClearsBothLocalStoreAndOnlineHistory', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 5 }];
      const online = new FakeOnlineHistory();
      online.pages = [onlinePage([onlineEntry(OnlineHistoryKind.ANSWER, '2', 20)], undefined, true)];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      await controller.clearAll();
      const afterClear = controller.snapshot();
      expect(history.clearCount).assertEqual(1);
      expect(online.clearAllCount).assertEqual(1);
      expect(afterClear.phase).assertEqual(ReadHistoryPhase.EMPTY);
      expect(afterClear.items.length).assertEqual(0);
      expect(afterClear.message).assertEqual('已清除所有历史记录');
    });

    it('ignoresMutationsAfterDeactivation', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 1 }];
      const online = new FakeOnlineHistory();
      online.pages = [onlinePage([onlineEntry(OnlineHistoryKind.ANSWER, '2', 20)], undefined, true)];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      controller.deactivate();
      await controller.clearAll();
      await controller.deleteEntry('answer:2');
      expect(history.clearCount).assertEqual(0);
      expect(online.clearAllCount).assertEqual(0);
      expect(online.deletedKeys.length).assertEqual(0);
    });

    it('localControllerLoadsDeletesAndClearsRecords', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'article:3', contentType: 'article', openedAt: 30, title: '本地文章' },
        { contentKey: 'bad', contentType: 'answer', openedAt: 20 },
        { contentKey: 'question:1', contentType: 'question', openedAt: 10 }
      ];
      const controller = new LocalHistoryController(history);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.READY);
      expect(state.items.length).assertEqual(2);
      expect(state.items[0].contentKey).assertEqual('article:3');
      expect(state.items[0].title).assertEqual('本地文章');
      await controller.delete('article:3');
      expect(controller.snapshot().items.length).assertEqual(1);
      await controller.clear();
      expect(history.clearCount).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.EMPTY);
    });

    it('localControllerReportsReadFailureWithFixedMessage', 0, async () => {
      const history = new FakeReadHistory();
      history.fail = true;
      const controller = new LocalHistoryController(history);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.ERROR);
      expect(state.message).assertEqual('本地历史记录读取失败，请重试');
      expect(state.message.includes('record value')).assertFalse();
    });
  });
}
