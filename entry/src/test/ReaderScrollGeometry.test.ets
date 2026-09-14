import { describe, expect, it } from '@ohos/hypium';
import {
  MIN_SCROLLABLE_VP,
  MIN_THUMB_HEIGHT_VP,
  readingProgress,
  scrollbarThumbHeightVp,
  scrollbarThumbOffsetVp,
  scrollbarThumbTravelVp,
  scrollbarTrackHeightVp
} from '../main/ets/pages/ReaderScrollGeometry';

const EPSILON = 0.000001;

export default function readerScrollGeometryTest(): void {
  describe('readerScrollGeometryTest', () => {
    it('subtractsBothInsetsFromAvailableHeight', 0, () => {
      expect(scrollbarTrackHeightVp(700, 0, 112)).assertEqual(588);
      expect(scrollbarTrackHeightVp(700, 4, 96)).assertEqual(600);
      // 留白超过可用高时收口到 0，不产生负长度。
      expect(scrollbarTrackHeightVp(100, 200, 200)).assertEqual(0);
      // 负留白按 0 计，避免反而把轨道拉长。
      expect(scrollbarTrackHeightVp(700, -50, -50)).assertEqual(700);
    });

    it('measuresThumbAgainstTrackHeightNotSourceViewport', 0, () => {
      // 轨道 100、可滚动 300 → 100 × 100 / 400 = 25（> 下限 24）。
      expect(scrollbarThumbHeightVp(100, 300)).assertEqual(25);
      // 同一可滚动量下若误用"正文视口高"（120）当轨道高：120 × 120 / 420 ≈ 34.29，
      // 与行程所用的轨道高不一致，正是拇指冲出轨道的原因。
      const viewportBased = 120 * (120 / (120 + 300));
      expect(Math.abs(viewportBased - scrollbarThumbHeightVp(100, 300)) > 5).assertTrue();
    });

    it('honoursMinThumbHeightAndTrackCap', 0, () => {
      expect(MIN_THUMB_HEIGHT_VP).assertEqual(24);
      // 视觉比例算出来低于下限（100 × 100 / 1100 ≈ 9.09）→ 取下限 24。
      expect(scrollbarThumbHeightVp(100, 1000)).assertEqual(24);
      // 无可滚动量时拇指铺满整条轨道，且不超过轨道高。
      expect(scrollbarThumbHeightVp(100, 0)).assertEqual(100);
      // 轨道比下限还短时按轨道高收口（上游 coerceIn 反序会抛异常，此处不抛）。
      expect(scrollbarThumbHeightVp(10, 0)).assertEqual(10);
    });

    it('returnsZeroThumbWhenNothingToRender', 0, () => {
      expect(scrollbarThumbHeightVp(0, 300)).assertEqual(0);
      expect(scrollbarThumbHeightVp(-10, 300)).assertEqual(0);
      // 可滚动量为负说明内容总高还没量准，先不渲染。
      expect(scrollbarThumbHeightVp(100, -1)).assertEqual(0);
    });

    it('keepsThumbInsideTrackAtEveryProgress', 0, () => {
      const track = 100;
      const thumb = scrollbarThumbHeightVp(track, 300);
      const travel = scrollbarThumbTravelVp(track, thumb);
      expect(travel).assertEqual(75);
      for (let step = 0; step <= 20; step += 1) {
        const offset = scrollbarThumbOffsetVp(step / 20, track, thumb);
        // 拇指底边（offset + thumb）任何进度下都不越过轨道底边。
        expect(offset + thumb <= track + EPSILON).assertTrue();
        expect(offset >= -EPSILON).assertTrue();
      }
      // 两端取满：0% 顶到轨道上端、100% 底边对齐轨道下端。
      expect(scrollbarThumbOffsetVp(0, track, thumb)).assertEqual(0);
      expect(scrollbarThumbOffsetVp(1, track, thumb)).assertEqual(travel);
      expect(scrollbarThumbOffsetVp(1, track, thumb) + thumb).assertEqual(track);
    });

    it('stopsShortOfBarBottomOnRealDeviceNumbers', 0, () => {
      // 模拟器实测（1256×2760、density 3.5）：正文/进度条盒高 694.6vp，
      // 下留白 96 + 导航条 16 = 112vp，内容总高 5360vp。
      const availableHeight = 694.6;
      const track = scrollbarTrackHeightVp(availableHeight, 0, 112);
      const maxScroll = 5360 - availableHeight;
      const thumb = scrollbarThumbHeightVp(track, maxScroll);
      const offsetAtEnd = scrollbarThumbOffsetVp(1, track, thumb);
      // 滑到底时拇指底边正好停在轨道底边，距盒子底边还有一整个下留白。
      expect(Math.abs(track - (offsetAtEnd + thumb)) < EPSILON).assertTrue();
      expect(Math.abs(availableHeight - 112 - track) < EPSILON).assertTrue();
      // 修复前：行程取的是盒子高 − 拇指高（629.94vp），比轨道可用的 517.94vp 长出
      // 一整个下留白（112vp），故滑到底时拇指被顶到盒子底边之外。
      const legacyTravel = availableHeight - thumb;
      expect(Math.abs((legacyTravel - scrollbarThumbTravelVp(track, thumb)) - 112) < EPSILON).assertTrue();
    });

    it('clampsAndGuardsReadingProgress', 0, () => {
      expect(MIN_SCROLLABLE_VP).assertEqual(1);
      expect(readingProgress(0, 300)).assertEqual(0);
      expect(readingProgress(150, 300)).assertEqual(0.5);
      expect(readingProgress(300, 300)).assertEqual(1);
      // 过滚/回弹越界一律 clamp。
      expect(readingProgress(400, 300)).assertEqual(1);
      expect(readingProgress(-20, 300)).assertEqual(0);
      // 无可滚动量时不产生除零。
      expect(readingProgress(120, 0)).assertEqual(0);
      expect(readingProgress(120, -5)).assertEqual(0);
    });
  });
}
