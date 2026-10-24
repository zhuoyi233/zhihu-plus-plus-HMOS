import { describe, expect, it } from '@ohos/hypium';
import { ReaderBlockKind } from 'reader';
import {
  ContinuousRow,
  ContinuousRowKind,
  ContinuousStreamDataSource,
  continuousBlockRows,
  continuousDividerRow,
  continuousHeaderRow,
  continuousLoadingBodyRow,
  continuousReleasedBodyRow,
  continuousStreamEndRow
} from '../main/ets/pages/ContinuousStreamDataSource';

/** 记录型监听器：把数据源发出的细粒度事件按序存为可断言字符串。 */
class RecordingListener implements DataChangeListener {
  readonly events: Array<string> = [];

  onDataReloaded(): void {
    this.events.push('reload');
  }

  onDataAdd(index: number): void {
    this.events.push(`add@${index}`);
  }

  onDataDelete(index: number): void {
    this.events.push(`delete@${index}`);
  }

  onDataChange(index: number): void {
    this.events.push(`change@${index}`);
  }

  onDataMove(from: number, to: number): void {
    this.events.push(`move@${from}->${to}`);
  }

  onDataAdded(index: number): void {
    this.events.push(`added@${index}`);
  }

  onDataDeleted(index: number): void {
    this.events.push(`deleted@${index}`);
  }

  onDataChanged(index: number): void {
    this.events.push(`changed@${index}`);
  }

  onDataMoved(from: number, to: number): void {
    this.events.push(`moved@${from}->${to}`);
  }

  onDatasetChange(dataOperations: DataOperation[]): void {
    this.events.push(`dataset:${dataOperations.length}`);
  }
}

function fixtureBlockRow(answerId: string, blockId: string): ContinuousRow {
  return continuousBlockRows(answerId, [{
    id: blockId,
    kind: ReaderBlockKind.PARAGRAPH,
    text: `text-${blockId}`,
    sourceUrl: '',
    inlineRuns: []
  }])[0];
}

function fixtureReadyBody(answerId: string, blockIds: Array<string>): Array<ContinuousRow> {
  const rows: Array<ContinuousRow> = [];
  blockIds.forEach((blockId: string): void => {
    rows.push(fixtureBlockRow(answerId, blockId));
  });
  rows.push(continuousDividerRow(answerId));
  return rows;
}

export default function continuousStreamDataSourceTest(): void {
  describe('continuousStreamDataSourceTest', () => {
    it('replaceAllAndAppendRowsEmitGranularEvents', 0, () => {
      const dataSource = new ContinuousStreamDataSource();
      const listener = new RecordingListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.replaceAll([
        continuousHeaderRow('a1'),
        continuousLoadingBodyRow('a1'),
        continuousDividerRow('a1')
      ]);
      dataSource.appendRows([
        continuousHeaderRow('a2'),
        continuousLoadingBodyRow('a2'),
        continuousDividerRow('a2')
      ]);
      expect(dataSource.totalCount()).assertEqual(6);
      expect(listener.events.join(',')).assertEqual('reload,add@3,add@4,add@5');
    });

    it('replaceBodyRowsReplacesOnlyTargetAnswerSpan', 0, () => {
      const dataSource = new ContinuousStreamDataSource();
      const listener = new RecordingListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.replaceAll([
        continuousHeaderRow('a1'),
        ...fixtureReadyBody('a1', ['p1', 'p2']),
        continuousHeaderRow('a2'),
        ...fixtureReadyBody('a2', ['p3']),
        continuousStreamEndRow('end')
      ]);
      listener.events.splice(0, listener.events.length);
      const start = dataSource.replaceBodyRows('a2', [
        continuousReleasedBodyRow('a2', 500),
        continuousDividerRow('a2')
      ]);
      expect(start).assertEqual(5);
      // 从后往前删、按序加：未涉及行索引与 key 均不变。
      expect(listener.events.join(',')).assertEqual('delete@6,delete@5,add@5,add@6');
      expect(dataSource.totalCount()).assertEqual(8);
      expect(dataSource.rowAt(0).key).assertEqual('a1:header');
      expect(dataSource.rowAt(1).key).assertEqual('a1:block:p1');
      expect(dataSource.rowAt(2).key).assertEqual('a1:block:p2');
      expect(dataSource.rowAt(3).key).assertEqual('a1:divider');
      expect(dataSource.rowAt(4).key).assertEqual('a2:header');
      expect(dataSource.rowAt(5).kind).assertEqual(ContinuousRowKind.BODY_RELEASED);
      expect(dataSource.rowAt(6).key).assertEqual('a2:divider');
      expect(dataSource.rowAt(7).key).assertEqual('stream-end:end');
    });

    it('replaceBodyRowsReturnsMinusOneForUnknownAnswer', 0, () => {
      const dataSource = new ContinuousStreamDataSource();
      dataSource.replaceAll([continuousHeaderRow('a1'), continuousDividerRow('a1')]);
      expect(dataSource.replaceBodyRows('missing', [continuousDividerRow('missing')])).assertEqual(-1);
      expect(dataSource.replaceBodyRows('a1', [continuousDividerRow('a1')])).assertEqual(1);
    });

    it('placeholderRowsShareStableKeyAcrossStates', 0, () => {
      const loading = continuousLoadingBodyRow('a9');
      const released = continuousReleasedBodyRow('a9', 50);
      expect(loading.key).assertEqual(released.key);
      expect(loading.key).assertEqual('a9:body');
      expect(released.estimatedHeightVp).assertEqual(120);
    });

    it('updateRowEmitsChangeAtMatchedIndex', 0, () => {
      const dataSource = new ContinuousStreamDataSource();
      const listener = new RecordingListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.replaceAll([
        continuousHeaderRow('a1'),
        continuousLoadingBodyRow('a1'),
        continuousDividerRow('a1')
      ]);
      listener.events.splice(0, listener.events.length);
      const updated = dataSource.updateRow('a1:body', continuousLoadingBodyRow('a1'));
      expect(updated).assertTrue();
      expect(listener.events.join(',')).assertEqual('change@1');
      expect(dataSource.updateRow('missing-key', continuousLoadingBodyRow('a1'))).assertFalse();
    });

    it('replaceRowAtEmitsDeleteThenAddAtSameIndex', 0, () => {
      const dataSource = new ContinuousStreamDataSource();
      const listener = new RecordingListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.replaceAll([
        continuousHeaderRow('a1'),
        fixtureBlockRow('a1', 'p1'),
        continuousDividerRow('a1')
      ]);
      listener.events.splice(0, listener.events.length);
      const replaced = dataSource.replaceRowAt('a1:block:p1', fixtureBlockRow('a1', 'p1'));
      expect(replaced).assertTrue();
      expect(listener.events.join(',')).assertEqual('delete@1,add@1');
      expect(dataSource.totalCount()).assertEqual(3);
      expect(dataSource.rowAt(1).key).assertEqual('a1:block:p1');
      expect(dataSource.replaceRowAt('missing-key', fixtureBlockRow('a1', 'x'))).assertFalse();
    });
  });
}
