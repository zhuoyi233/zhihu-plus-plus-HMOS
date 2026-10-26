import { describe, expect, it } from '@ohos/hypium';
import {
  feedRenderChrome,
  feedRenderContent,
  FeedFlowDataSource,
  FeedRenderItem,
  FeedRenderKind
} from '../main/ets/pages/FeedFlowDataSource';

class RecordingListener implements DataChangeListener {
  readonly events: Array<string> = [];

  onDataReloaded(): void {
    this.events.push('reload');
  }

  onDataAdded(index: number): void {
    this.events.push(`added:${index}`);
  }

  onDataAdd(index: number): void {
    this.events.push(`add:${index}`);
  }

  onDataMoved(from: number, to: number): void {
    this.events.push(`moved:${from}:${to}`);
  }

  onDataMove(from: number, to: number): void {
    this.events.push(`move:${from}:${to}`);
  }

  onDataDeleted(index: number): void {
    this.events.push(`deleted:${index}`);
  }

  onDataDelete(index: number): void {
    this.events.push(`del:${index}`);
  }

  onDataChanged(index: number): void {
    this.events.push(`changed:${index}`);
  }

  onDataChange(index: number): void {
    this.events.push(`change:${index}`);
  }

  onDatasetChange(dataOperations: DataOperation[]): void {
    this.events.push(`dataset:${dataOperations.length}`);
  }
}

interface TestPayload {
  key: string;
}

function contentItem(key: string, itemIndex: number): FeedRenderItem {
  const payload: TestPayload = { key: key };
  return feedRenderContent(key, itemIndex, payload);
}

function keysOf(source: FeedFlowDataSource): Array<string> {
  return source.snapshot().map((item: FeedRenderItem): string => item.key);
}

export default function feedFlowDataSourceTest(): void {
  describe('feedFlowDataSourceTest', () => {
    it('notifiesAddsForTailAppends', 0, () => {
      const source = new FeedFlowDataSource();
      const listener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.applyLayout([contentItem('a', 0), contentItem('b', 1)]);
      expect(listener.events.join(',')).assertEqual('add:0,add:1');
      source.applyLayout([contentItem('a', 0), contentItem('b', 1), contentItem('c', 2),
        contentItem('d', 3)]);
      expect(listener.events.join(',')).assertEqual('add:0,add:1,add:2,add:3');
      expect(keysOf(source).join(',')).assertEqual('a,b,c,d');
    });

    it('notifiesDeletesFromTheEndForShrinkAndFilter', 0, () => {
      const source = new FeedFlowDataSource();
      const listener = new RecordingListener();
      source.applyLayout([contentItem('a', 0), contentItem('b', 1), contentItem('c', 2),
        feedRenderChrome('chrome:footer', FeedRenderKind.LOADING_FOOTER)]);
      source.registerDataChangeListener(listener);
      // 加载尾消失（尾部收缩）
      source.applyLayout([contentItem('a', 0), contentItem('b', 1), contentItem('c', 2)]);
      expect(listener.events.join(',')).assertEqual('del:3');
      // 过滤删除中部条目
      source.applyLayout([contentItem('a', 0), contentItem('c', 2)]);
      expect(listener.events.join(',')).assertEqual('del:3,del:1');
      expect(keysOf(source).join(',')).assertEqual('a,c');
    });

    it('reloadsWhenOrderChangesOrBothSidesChangeHeavily', 0, () => {
      const source = new FeedFlowDataSource();
      const listener = new RecordingListener();
      source.applyLayout([contentItem('a', 0), contentItem('b', 1), contentItem('c', 2)]);
      source.registerDataChangeListener(listener);
      // 关注动态切换时间排序：整体换序 → 整表重载
      source.applyLayout([contentItem('c', 0), contentItem('a', 1), contentItem('b', 2)]);
      expect(listener.events.join(',')).assertEqual('reload');
      // 刷新后大面积换血 → 整表重载
      listener.events.length = 0;
      source.applyLayout([contentItem('x', 0), contentItem('y', 1), contentItem('z', 2),
        contentItem('w', 3)]);
      expect(listener.events.join(',')).assertEqual('reload');
      expect(keysOf(source).join(',')).assertEqual('x,y,z,w');
    });

    it('keepsSilentWhenKeysAreUnchanged', 0, () => {
      const source = new FeedFlowDataSource();
      const listener = new RecordingListener();
      source.applyLayout([feedRenderChrome('chrome:error', FeedRenderKind.ERROR_BANNER),
        contentItem('a', 0), contentItem('b', 1),
        feedRenderChrome('chrome:footer', FeedRenderKind.LOADING_FOOTER)]);
      source.registerDataChangeListener(listener);
      // 同键快照（重复回调、同布局重算）不产生任何通知
      source.applyLayout([feedRenderChrome('chrome:error', FeedRenderKind.ERROR_BANNER),
        contentItem('a', 0), contentItem('b', 1),
        feedRenderChrome('chrome:footer', FeedRenderKind.LOADING_FOOTER)]);
      expect(listener.events.length).assertEqual(0);
      expect(source.totalCount()).assertEqual(4);
    });

    it('notifiesSingleInsertWhenChromeBannerAppearsAtHead', 0, () => {
      const source = new FeedFlowDataSource();
      const listener = new RecordingListener();
      const spacer = feedRenderChrome('chrome:spacer', FeedRenderKind.TOP_SPACER);
      source.applyLayout([spacer, contentItem('a', 0), contentItem('b', 1)]);
      source.registerDataChangeListener(listener);
      // 更新公告/错误横幅在顶部让位条目之后插入，保持让位条目在索引 0。
      source.applyLayout([spacer, feedRenderChrome('chrome:announcement', FeedRenderKind.UPDATE_ANNOUNCEMENT),
        contentItem('a', 0), contentItem('b', 1)]);
      expect(listener.events.join(',')).assertEqual('add:1');
      expect(source.getData(0).kind).assertEqual(FeedRenderKind.TOP_SPACER);
      expect(source.getData(1).key).assertEqual('chrome:announcement');
      // 头部横幅消失
      source.applyLayout([spacer, contentItem('a', 0), contentItem('b', 1)]);
      expect(listener.events.join(',')).assertEqual('add:1,del:1');
      expect(keysOf(source).join(',')).assertEqual('chrome:spacer,a,b');
    });

    it('appliesGranularDeleteThenInsertForSmallMiddleChanges', 0, () => {
      const source = new FeedFlowDataSource();
      const listener = new RecordingListener();
      source.applyLayout([contentItem('a', 0), contentItem('b', 1), contentItem('c', 2)]);
      source.registerDataChangeListener(listener);
      // 单点替换（删除 b 换入 x）
      source.applyLayout([contentItem('a', 0), contentItem('x', 1), contentItem('c', 2)]);
      expect(listener.events.join(',')).assertEqual('del:1,add:1');
      expect(keysOf(source).join(',')).assertEqual('a,x,c');
    });

    it('keepsListenersIsolatedAndUnregistered', 0, () => {
      const source = new FeedFlowDataSource();
      const first = new RecordingListener();
      const second = new RecordingListener();
      source.registerDataChangeListener(first);
      source.registerDataChangeListener(second);
      source.registerDataChangeListener(second);
      source.applyLayout([contentItem('a', 0)]);
      expect(first.events.length).assertEqual(1);
      expect(second.events.length).assertEqual(1);
      source.unregisterDataChangeListener(second);
      source.applyLayout([contentItem('a', 0), contentItem('b', 1)]);
      expect(first.events.join(',')).assertEqual('add:0,add:1');
      expect(second.events.length).assertEqual(1);
    });
  });
}
