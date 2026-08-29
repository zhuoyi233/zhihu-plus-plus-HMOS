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
  filterReadHistoryItems,
  groupReadHistoryItems,
  mergeReadHistoryItems,
  ReadHistoryContentKind,
  ReadHistoryController,
  ReadHistoryItem,
  readHistoryKindLabel,
  readHistoryOpenTarget,
  ReadHistoryPhase,
  ReadHistorySourceFilter,
  readHistorySourceFilterLabel
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
  requestedCursors: Array<string | undefined> = [];
  cancelCount: number = 0;

  loadPage(cursor?: string): Promise<OnlineHistoryPage> {
    this.requestedCursors.push(cursor);
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
    const index = this.requestedCursors.length - 1;
    const page = this.pages[Math.min(index, this.pages.length - 1)];
    return Promise.resolve(page);
  }

  cancel(): void {
    this.cancelCount += 1;
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
      expect(valid?.deletable).assertTrue();
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

    it('filtersCorruptRowsAndPublishesReadyHistory', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'article:3', contentType: 'article', openedAt: 30 },
        { contentKey: 'bad', contentType: 'answer', openedAt: 20 }
      ];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().items[0].contentKey).assertEqual('article:3');
    });

    it('deletesOneRecordAndClearsAllWithReloadedState', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'question:1', contentType: 'question', openedAt: 20 },
        { contentKey: 'answer:2', contentType: 'answer', openedAt: 10 },
        { contentKey: 'pin:3', contentType: 'pin', openedAt: 5 }
      ];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      await controller.delete('pin:3');
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().items.some((item): boolean => item.kind === ReadHistoryContentKind.PIN))
        .assertFalse();
      await controller.clear();
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.EMPTY);
      expect(history.clearCount).assertEqual(1);
    });

    it('usesFixedReadErrorWithoutLeakingStoredValues', 0, async () => {
      const history = new FakeReadHistory();
      history.fail = true;
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().phase).assertEqual(ReadHistoryPhase.ERROR);
      expect(controller.snapshot().message).assertEqual('已读记录读取失败，请重试');
      expect(controller.snapshot().message.includes('record value')).assertFalse();
    });

    it('ignoresMutationsAfterDeactivation', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 1 }];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      controller.deactivate();
      await controller.clear();
      expect(history.clearCount).assertEqual(0);
      expect(history.items.length).assertEqual(1);
    });

    it('showsLoginGateAndLocalOnlyWhenOnlineHistoryIsDisabled', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 20 }];
      const controller = new ReadHistoryController(history);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.requiresLogin).assertTrue();
      expect(state.onlineEnabled).assertFalse();
      expect(state.canLoadMore).assertFalse();
      expect(state.items.length).assertEqual(1);
      expect(state.items[0].deletable).assertTrue();
      expect(state.items[0].inOnline).assertFalse();
    });

    it('mergesOnlineHistoryAndDeduplicatesByContentKey', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'answer:2', contentType: 'answer', openedAt: 10 }];
      const online = new FakeOnlineHistory();
      online.pages = [onlinePage([
        onlineEntry(OnlineHistoryKind.ANSWER, '2', 20, '在线回答标题'),
        onlineEntry(OnlineHistoryKind.QUESTION, '1', 30)
      ], undefined, true)];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.requiresLogin).assertFalse();
      expect(state.onlineEnabled).assertTrue();
      expect(state.items.length).assertEqual(2);
      expect(state.items[0].contentKey).assertEqual('question:1');
      expect(state.items[1].contentKey).assertEqual('answer:2');
      expect(state.items[1].title).assertEqual('在线回答标题');
      expect(state.items[1].openedAt).assertEqual(20);
      expect(state.items[1].deletable).assertTrue();
      expect(state.items[1].inOnline).assertTrue();
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

    it('keepsLocalHistoryWhenOnlineFetchFails', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'question:1', contentType: 'question', openedAt: 20 },
        { contentKey: 'answer:2', contentType: 'answer', openedAt: 10 }
      ];
      const online = new FakeOnlineHistory();
      online.fail = true;
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.READY);
      expect(state.items.length).assertEqual(2);
      expect(state.message.includes('在线历史加载失败')).assertTrue();
      expect(state.message.includes('sensitive')).assertFalse();
    });

    it('marksSessionExpiredOnOnlineAuthenticationFailure', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [{ contentKey: 'question:1', contentType: 'question', openedAt: 20 }];
      const online = new FakeOnlineHistory();
      online.authFail = true;
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.requiresLogin).assertTrue();
      expect(state.items.length).assertEqual(1);
      expect(state.message.includes('登录已失效')).assertTrue();
    });

    it('showsOnlineFailureMessageWhenMergedListIsEmpty', 0, async () => {
      const history = new FakeReadHistory();
      const online = new FakeOnlineHistory();
      online.fail = true;
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadHistoryPhase.EMPTY);
      expect(state.items.length).assertEqual(0);
      expect(state.message.includes('在线历史加载失败')).assertTrue();
      expect(state.message.includes('sensitive')).assertFalse();
    });

    it('deleteAndClearOnlyAffectLocalRecordsInMergedMode', 0, async () => {
      const history = new FakeReadHistory();
      history.items = [
        { contentKey: 'question:1', contentType: 'question', openedAt: 5 },
        { contentKey: 'answer:2', contentType: 'answer', openedAt: 4 }
      ];
      const online = new FakeOnlineHistory();
      online.pages = [onlinePage([
        onlineEntry(OnlineHistoryKind.QUESTION, '1', 30),
        onlineEntry(OnlineHistoryKind.PIN, '3', 40)
      ], undefined, true)];
      const controller = new ReadHistoryController(history, online, true);
      controller.activate();
      await controller.reload();
      expect(controller.snapshot().items.length).assertEqual(3);
      await controller.delete('question:1');
      const afterDelete = controller.snapshot();
      expect(afterDelete.items.length).assertEqual(3);
      const question = afterDelete.items.find((item): boolean => item.contentKey === 'question:1');
      expect(question?.deletable).assertFalse();
      expect(question?.inOnline).assertTrue();
      await controller.clear();
      const afterClear = controller.snapshot();
      expect(history.clearCount).assertEqual(1);
      expect(afterClear.items.length).assertEqual(2);
      expect(afterClear.items.every((item): boolean => !item.deletable)).assertTrue();
    });

    it('groupsAndMergesItemsInStableOrder', 0, () => {
      const local: Array<ReadHistoryItem> = [
        { contentKey: 'answer:1', kind: ReadHistoryContentKind.ANSWER, id: '1', openedAt: Date.UTC(2026, 7, 28, 12),
          deletable: true, inOnline: false },
        { contentKey: 'question:2', kind: ReadHistoryContentKind.QUESTION, id: '2', openedAt: Date.UTC(2026, 7, 27, 8),
          deletable: true, inOnline: false }
      ];
      const online: Array<ReadHistoryItem> = [
        { contentKey: 'answer:1', kind: ReadHistoryContentKind.ANSWER, id: '1', openedAt: Date.UTC(2026, 7, 28, 9),
          title: '在线回答', deletable: false, inOnline: true },
        { contentKey: 'pin:3', kind: ReadHistoryContentKind.PIN, id: '3', openedAt: Date.UTC(2026, 7, 27, 10),
          deletable: false, inOnline: true }
      ];
      const merged = mergeReadHistoryItems(local, online);
      expect(merged.length).assertEqual(3);
      const mergedAnswer = merged.find((item): boolean => item.contentKey === 'answer:1');
      expect(mergedAnswer?.deletable).assertTrue();
      expect(mergedAnswer?.inOnline).assertTrue();
      expect(mergedAnswer?.title).assertEqual('在线回答');
      const groups = groupReadHistoryItems(merged);
      expect(groups.map((group): string => group.dayKey)).assertDeepEquals(['2026-08-28', '2026-08-27']);
      expect(groups[0].items[0].contentKey).assertEqual('answer:1');
      expect(groups[1].items.map((item: ReadHistoryItem): string => item.contentKey))
        .assertDeepEquals(['pin:3', 'question:2']);
    });

    it('filtersMergedHistoryByRequestedSourceWithoutDroppingSharedRecords', 0, () => {
      const items: Array<ReadHistoryItem> = [
        { contentKey: 'question:1', kind: ReadHistoryContentKind.QUESTION, id: '1', openedAt: 30,
          deletable: true, inOnline: false },
        { contentKey: 'answer:2', kind: ReadHistoryContentKind.ANSWER, id: '2', openedAt: 20,
          deletable: true, inOnline: true },
        { contentKey: 'article:3', kind: ReadHistoryContentKind.ARTICLE, id: '3', openedAt: 10,
          deletable: false, inOnline: true }
      ];
      expect(filterReadHistoryItems(items, ReadHistorySourceFilter.ALL).length).assertEqual(3);
      expect(filterReadHistoryItems(items, ReadHistorySourceFilter.LOCAL)
        .map((item: ReadHistoryItem): string => item.contentKey)).assertDeepEquals(['question:1', 'answer:2']);
      expect(filterReadHistoryItems(items, ReadHistorySourceFilter.ONLINE)
        .map((item: ReadHistoryItem): string => item.contentKey)).assertDeepEquals(['answer:2', 'article:3']);
      expect(readHistorySourceFilterLabel(ReadHistorySourceFilter.ALL)).assertEqual('全部记录');
      expect(readHistorySourceFilterLabel(ReadHistorySourceFilter.LOCAL)).assertEqual('本地记录');
      expect(readHistorySourceFilterLabel(ReadHistorySourceFilter.ONLINE)).assertEqual('在线记录');
    });
  });
}
