import { describe, expect, it } from '@ohos/hypium';
import {
  buildFeedFlowLayout,
  feedAnchorFlowIndex,
  feedColumnCandidates,
  feedMinCardWidthVp,
  FeedFlowLayout,
  feedSectionSignature,
  feedFlowItemIndex,
  homeFeedInitialItemTarget,
  resolveFeedColumnSpec
} from '../main/ets/pages/FeedWaterfallLayout';

export default function feedWaterfallLayoutTest(): void {
  describe('feedWaterfallLayoutTest', () => {
    it('sizesTheInitialBatchForWideViewportWithTwoBufferRows', 0, () => {
      expect(homeFeedInitialItemTarget(599, 1022, 94)).assertEqual(1);
      expect(homeFeedInitialItemTarget(600, 1022, 94)).assertEqual(22);
      expect(homeFeedInitialItemTarget(1138, 711, 94)).assertEqual(24);
      expect(homeFeedInitialItemTarget(1200, 1022, 94)).assertEqual(33);
      expect(homeFeedInitialItemTarget(1440, 1022, 94)).assertEqual(44);
      expect(homeFeedInitialItemTarget(1138, 0, 94)).assertEqual(1);
      expect(homeFeedInitialItemTarget(1138, 10000, 94)).assertEqual(60);
    });
    it('reducesInitialBatchWhenFontScaleShrinksColumnCount', 0, () => {
      // 字号放大提高最小卡宽：1440vp 从 4 列降为 2 列，首屏目标同步减半
      expect(feedMinCardWidthVp(1.8)).assertEqual(504);
      expect(resolveFeedColumnSpec(1440).columns).assertEqual(4);
      expect(resolveFeedColumnSpec(1440, { minCardWidthVp: 504 }).columns).assertEqual(2);
      expect(homeFeedInitialItemTarget(1440, 1022, 94, 504)).assertEqual(22);
    });
    it('resolvesColumnBreakpointsFromMeasuredPageWidth', 0, () => {
      // 对齐官方横向断点：sm/md 600、md/lg 840、lg/xl 1440
      expect(feedColumnCandidates(599)).assertEqual(1);
      expect(feedColumnCandidates(600)).assertEqual(2);
      expect(feedColumnCandidates(839)).assertEqual(2);
      expect(feedColumnCandidates(840)).assertEqual(3);
      expect(feedColumnCandidates(1439)).assertEqual(3);
      expect(feedColumnCandidates(1440)).assertEqual(4);
    });
    it('keepsCardWidthAboveMinimumAndSingleColumnFillsContent', 0, () => {
      // 进入 2/3/4 列边界时卡宽约 281/283/344vp（4 列自 xl 1440 起）
      expect(resolveFeedColumnSpec(600).cardWidth).assertEqual(281);
      expect(Math.round(resolveFeedColumnSpec(900).cardWidth)).assertEqual(283);
      expect(resolveFeedColumnSpec(1440).cardWidth).assertEqual(343.5);
      // 宽度容不下最小卡宽时回退单列，卡片占满内容宽度
      const narrow = resolveFeedColumnSpec(590);
      expect(narrow.columns).assertEqual(1);
      expect(narrow.cardWidth).assertEqual(566);
      const clamped = resolveFeedColumnSpec(620, { minCardWidthVp: 400 });
      expect(clamped.columns).assertEqual(1);
      expect(clamped.cardWidth).assertEqual(596);
    });
    it('handlesUnmeasuredAndDegenerateSizes', 0, () => {
      const unmeasured = resolveFeedColumnSpec(0);
      expect(unmeasured.columns).assertEqual(1);
      expect(unmeasured.cardWidth).assertEqual(0);
      expect(unmeasured.contentWidth).assertEqual(0);
      const tiny = resolveFeedColumnSpec(10);
      expect(tiny.columns).assertEqual(1);
      expect(tiny.cardWidth).assertEqual(0);
    });
    it('honorsRequestedColumnsWithinWidthProtection', 0, () => {
      expect(resolveFeedColumnSpec(1200, { requestedColumns: 2 }).columns).assertEqual(2);
      expect(resolveFeedColumnSpec(1200, { requestedColumns: 0 }).columns).assertEqual(3);
      expect(resolveFeedColumnSpec(1440, { requestedColumns: 0 }).columns).assertEqual(4);
      // 窄窗请求 4 列仍受最小卡宽保护，退到单列
      expect(resolveFeedColumnSpec(400, { requestedColumns: 4 }).columns).assertEqual(1);
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
    it('countsTopSpacerInEmptyAndDatedFeedAnchors', 0, () => {
      const empty = buildFeedFlowLayout([], [], 1, 1, false, 0);
      expect(empty.sections.length).assertEqual(1);
      expect(empty.sections[0].itemsCount).assertEqual(1);
      expect(feedFlowItemIndex(empty, 0)).assertEqual(-1);
      const dated = buildFeedFlowLayout(['a', 'b'], ['20261023', '20261022'], 4, 2, true, 14);
      // 顶部让位 + 错误横幅后才是日期标题；加载尾也映射到最后一条内容。
      expect(feedFlowItemIndex(dated, 0)).assertEqual(-1);
      expect(feedFlowItemIndex(dated, 1)).assertEqual(-1);
      expect(feedAnchorFlowIndex(dated, 0)).assertEqual(2);
      expect(feedAnchorFlowIndex(dated, 1)).assertEqual(4);
      expect(feedFlowItemIndex(dated, 6)).assertEqual(1);
    });
    it('skipsSectionSpliceOnlyWhenGroupingIsUnchanged', 0, () => {
      const first = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 1, true, 14);
      const sameGrouping = buildFeedFlowLayout(['a', 'x', 'c'], [], 2, 1, true, 14);
      const columnsChanged = buildFeedFlowLayout(['a', 'b', 'c'], [], 3, 1, true, 14);
      const footerGone = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 1, false, 14);
      const bannerAdded = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 2, true, 14);
      const gapChanged = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 1, true, 0);
      expect(feedSectionSignature(sameGrouping)).assertEqual(feedSectionSignature(first));
      expect(feedSectionSignature(columnsChanged) !== feedSectionSignature(first)).assertTrue();
      expect(feedSectionSignature(footerGone) !== feedSectionSignature(first)).assertTrue();
      expect(feedSectionSignature(bannerAdded) !== feedSectionSignature(first)).assertTrue();
      expect(feedSectionSignature(gapChanged) !== feedSectionSignature(first)).assertTrue();
    });
    it('mapsAnchorContentToFlowIndexAcrossColumnChanges', 0, () => {
      const wide: FeedFlowLayout = buildFeedFlowLayout(['a', 'b', 'c'], [], 2, 1, false, 14);
      expect(feedAnchorFlowIndex(wide, 0)).assertEqual(1);
      expect(feedAnchorFlowIndex(wide, 2)).assertEqual(3);
      // 日期标题与锚点内容同屏：锚点落在日期通栏项上
      const dated: FeedFlowLayout =
        buildFeedFlowLayout(['a', 'b', 'c'], ['20261023', '20261023', '20261022'], 2, 0, false, 14);
      expect(feedAnchorFlowIndex(dated, 2)).assertEqual(3);
      // 锚点被过滤后落在仍存在的相邻内容
      const filtered: FeedFlowLayout = buildFeedFlowLayout(['a', 'c'], [], 1, 0, false, 0);
      expect(feedAnchorFlowIndex(filtered, 1)).assertEqual(1);
      // 锚点超出末尾时取最后一项，空列表返回 -1
      expect(feedAnchorFlowIndex(wide, 9)).assertEqual(3);
      expect(feedAnchorFlowIndex(wide, -1)).assertEqual(-1);
      expect(feedAnchorFlowIndex(buildFeedFlowLayout([], [], 2, 0, false, 14), 0)).assertEqual(-1);
    });
  });
}
