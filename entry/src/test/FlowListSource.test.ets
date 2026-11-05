import { describe, expect, it } from '@ohos/hypium';
import { FlowListSource, flowListCard, flowListChrome } from '../main/ets/pages/FlowListSource';

class FlowRecordingListener implements DataChangeListener {
  readonly events: string[] = [];
  onDataReloaded(): void { this.events.push('reload'); }
  onDataAdd(index: number): void { this.events.push(`add:${index}`); }
  onDataDelete(index: number): void { this.events.push(`delete:${index}`); }
  onDataChange(index: number): void { this.events.push(`change:${index}`); }
  onDataMove(_from: number, _to: number): void {}
  onDataAdded(_index: number): void {}
  onDataDeleted(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDatasetChange(_operations: DataOperation[]): void {}
}

export default function flowListSourceTest(): void {
  describe('flowListSourceTest', () => {
    it('insertsNextPageBeforeStableFooterWithoutReloadingExistingCards', 0, () => {
      const source = new FlowListSource();
      const listener = new FlowRecordingListener();
      const header = flowListChrome('header', 'header');
      const first = flowListCard('a', 0, 'first');
      const footer = flowListChrome('footer', 'footer');
      source.applyLayout([header, first, footer]);
      source.registerDataChangeListener(listener);
      source.applyLayout([header, first, flowListCard('b', 1, 'second'), flowListCard('c', 2, 'third'), footer]);
      expect(listener.events.join(',')).assertEqual('add:2,add:3');
      expect(source.getData(1)).assertEqual(first);
      expect(source.getData(4)).assertEqual(footer);
      listener.events.length = 0;
      source.applyLayout([header, first, source.getData(2), source.getData(3), footer]);
      expect(listener.events.length).assertEqual(0);
    });
    it('updatesSameKeyPayloadAndRetainsUnchangedNeighbours', 0, () => {
      const source = new FlowListSource();
      const listener = new FlowRecordingListener();
      const footer = flowListChrome('footer', 'footer');
      source.applyLayout([flowListCard('a', 0, 'old'), footer]);
      source.registerDataChangeListener(listener);
      source.applyLayout([flowListCard('a', 0, 'new'), footer]);
      expect(listener.events.join(',')).assertEqual('change:0');
      expect(source.getData(0).payload).assertEqual('new');
      expect(source.getData(1)).assertEqual(footer);
    });
    it('replacesSectionContentWithoutReloadingProfileAndFooter', 0, () => {
      const source = new FlowListSource();
      const listener = new FlowRecordingListener();
      const header = flowListChrome('header', 'header');
      const footer = flowListChrome('footer', 'footer');
      source.applyLayout([header, flowListCard('a', 0, 'a'), flowListCard('b', 1, 'b'), footer]);
      source.registerDataChangeListener(listener);
      source.applyLayout([header, flowListCard('c', 0, 'c'), footer]);
      expect(listener.events.join(',')).assertEqual('delete:2,delete:1,add:1');
      expect(source.totalCount()).assertEqual(3);
      expect(source.getData(0)).assertEqual(header);
      expect(source.getData(2)).assertEqual(footer);
    });
    it('preservesExplicitReloadAndListenerUnregistration', 0, () => {
      const source = new FlowListSource();
      const listener = new FlowRecordingListener();
      source.registerDataChangeListener(listener);
      source.replace([flowListCard('a', 0, 'a')]);
      expect(listener.events.join(',')).assertEqual('reload');
      source.unregisterDataChangeListener(listener);
      source.applyLayout([]);
      expect(listener.events.join(',')).assertEqual('reload');
      expect(source.totalCount()).assertEqual(0);
    });
  });
}
