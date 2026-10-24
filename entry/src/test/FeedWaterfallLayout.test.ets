import { describe, expect, it } from '@ohos/hypium';
import { buildFeedFlowLayout, feedFlowItemIndex, homeFeedInitialItemTarget } from '../main/ets/pages/FeedWaterfallLayout';

export default function feedWaterfallLayoutTest(): void {
  describe('feedWaterfallLayoutTest', () => {
    it('sizesTheInitialBatchForWideViewportWithTwoBufferRows', 0, () => {
      expect(homeFeedInitialItemTarget(599, 1022, 94)).assertEqual(1);
      expect(homeFeedInitialItemTarget(600, 1022, 94)).assertEqual(22);
      expect(homeFeedInitialItemTarget(1138, 711, 94)).assertEqual(16);
      expect(homeFeedInitialItemTarget(1138, 0, 94)).assertEqual(1);
      expect(homeFeedInitialItemTarget(1138, 10000, 94)).assertEqual(60);
    });
    it('keepsOddContentAsIndependentItemsBetweenFullWidthChrome', 0, () => {
      const layout = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 2, true, 14);
      expect(layout.entries.length).assertEqual(3);
      expect(layout.sections.length).assertEqual(3);
      expect(layout.sections[0].crossCount).assertEqual(1);
      expect(layout.sections[1].crossCount).assertEqual(2);
      expect(layout.sections[1].itemsCount).assertEqual(3);
      expect(layout.sections[2].crossCount).assertEqual(1);
      expect(feedFlowItemIndex(layout, 0)).assertEqual(-1);
      expect(feedFlowItemIndex(layout, 3)).assertEqual(1);
      expect(feedFlowItemIndex(layout, 5)).assertEqual(2);
    });
    it('separatesDatesAndMapsHeadingsBackToSourceItems', 0, () => {
      const layout = buildFeedFlowLayout(['a', 'b', 'c'], ['20261023', '20261023', '20261022'], 2, 1, false, 14);
      expect(layout.entries.length).assertEqual(5);
      expect(layout.sections.length).assertEqual(5);
      expect(layout.sections[2].itemsCount).assertEqual(2);
      expect(layout.sections[4].itemsCount).assertEqual(1);
      expect(layout.entries[3].date).assertEqual('20261022');
      expect(feedFlowItemIndex(layout, 4)).assertEqual(2);
      expect(feedFlowItemIndex(layout, 5)).assertEqual(2);
    });
    it('keepsStableContentKeysWhenColumnsChangeOrContentIsRemoved', 0, () => {
      const wide = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 0, false, 14);
      const narrow = buildFeedFlowLayout(['a', 'c'], [], 1, 0, false, 0);
      expect(wide.entries[2].key).assertEqual(narrow.entries[1].key);
      expect(narrow.sections[0].crossCount).assertEqual(1);
      expect(narrow.entries[1].itemIndex).assertEqual(1);
    });
    it('doesNotCreateZeroCountSectionsForEmptyFeeds', 0, () => {
      const layout = buildFeedFlowLayout([], [], 2, 0, false, 14);
      expect(layout.sections.length).assertEqual(0);
      expect(feedFlowItemIndex(layout, 0)).assertEqual(-1);
    });
  });
}
