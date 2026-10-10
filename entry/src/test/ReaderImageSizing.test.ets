import { describe, expect, it } from '@ohos/hypium';
import { computeImageDisplaySize } from 'reader';

/**
 * 详情页图片显示尺寸策略测试（规则见 reader ReaderImageSizing.ets）。
 * 以 360×780vp 竖屏（宽高比 ≈ 0.4615）与 780×360vp 横屏为基准屏幕。
 */
export default function readerImageSizingTest(): void {
  describe('readerImageSizingTest', () => {
    const SCREEN_W = 360;
    const SCREEN_H = 780;

    it('scalesUpTinyWideImageTo30PercentScreen', 0, () => {
      // 图片 100×200（宽高比 0.5 ＞ 屏比 0.4615，横向主导），宽占比 27.8% ＜ 30% → 放大至 30% 屏宽。
      const size = computeImageDisplaySize(100, 200, SCREEN_W, SCREEN_H);
      expect(Math.round(size.width)).assertEqual(108);
      expect(Math.round(size.height)).assertEqual(216);
    });

    it('scalesUpTinyTallImageTo30PercentScreenHeight', 0, () => {
      // 竖长图 60×300（宽高比 0.2 ≤ 屏比，竖向主导），高占比 38.5% 已在 30%~80% → 保持原大小。
      // 改用高占比不足 30% 的图：60×200（比 0.3），高占比 25.6% ＜ 30% → 放大至 30% 屏高 234。
      const size = computeImageDisplaySize(60, 200, SCREEN_W, SCREEN_H);
      expect(Math.round(size.height)).assertEqual(234);
      expect(Math.round(size.width)).assertEqual(70);
    });

    it('keepsMidSizeImageNatural', 0, () => {
      // 横图 300×200（比 1.5 ＞ 屏比），宽占比 83.3% 在 30%~100% → 原比例原大小。
      const size = computeImageDisplaySize(300, 200, SCREEN_W, SCREEN_H);
      expect(Math.round(size.width)).assertEqual(300);
      expect(Math.round(size.height)).assertEqual(200);
    });

    it('keepsTallImageNaturalWithin30To80Percent', 0, () => {
      // 竖向主导图 150×500（比 0.3 ≤ 屏比），高占比 64.1% 在 30%~80% → 原比例原大小。
      const size = computeImageDisplaySize(150, 500, SCREEN_W, SCREEN_H);
      expect(Math.round(size.width)).assertEqual(150);
      expect(Math.round(size.height)).assertEqual(500);
    });

    it('scalesDownHugeWideImageTo100PercentScreen', 0, () => {
      // 大横图 720×480（比 1.5），宽占比 200% ≥ 100% → 缩小至整屏宽 360，高 240。
      const size = computeImageDisplaySize(720, 480, SCREEN_W, SCREEN_H);
      expect(Math.round(size.width)).assertEqual(360);
      expect(Math.round(size.height)).assertEqual(240);
    });

    it('scalesDownHugeTallImageTo80PercentScreenHeight', 0, () => {
      // 竖向主导图 400×1000（比 0.4 ≤ 屏比），高占比 128% ≥ 80% → 缩小至 80% 屏高 624，宽 249.6。
      const size = computeImageDisplaySize(400, 1000, SCREEN_W, SCREEN_H);
      expect(Math.round(size.height)).assertEqual(624);
      expect(Math.round(size.width * 10)).assertEqual(2496);
    });

    it('keepsImageExactlyAtMinProportionUnchanged', 0, () => {
      // 横图 108×72（比 1.5），宽占比恰为 30% → 属"保持"区间，不放大。
      const size = computeImageDisplaySize(108, 72, SCREEN_W, SCREEN_H);
      expect(Math.round(size.width)).assertEqual(108);
      expect(Math.round(size.height)).assertEqual(72);
    });

    it('keepsImageExactlyAtTallMaxProportionUnchanged', 0, () => {
      // 竖向主导图 249.6×624（比 0.4），高占比恰为 80% → 属"保持"区间，不缩小。
      const size = computeImageDisplaySize(249.6, 624, SCREEN_W, SCREEN_H);
      expect(Math.round(size.height)).assertEqual(624);
      expect(Math.round(size.width * 10)).assertEqual(2496);
    });

    it('capsPortraitImageOnLandscapeScreenTo80PercentHeight', 0, () => {
      // 竖图放横屏：屏 780×360（比 2.17），图 300×600（比 0.5 ≤ 屏比，竖向主导），
      // 高占比 167% ≥ 80% → 缩小至 80% 屏高 288，宽 144。
      const size = computeImageDisplaySize(300, 600, 780, 360);
      expect(Math.round(size.height)).assertEqual(288);
      expect(Math.round(size.width)).assertEqual(144);
    });

    it('scalesUpTinyImageOnLandscapeScreen', 0, () => {
      // 竖图放横屏小图：图 50×100（比 0.5 ≤ 屏比 2.17，竖向主导），高占比 27.8% ＜ 30%
      // → 放大至 30% 屏高 108，宽 54。
      const size = computeImageDisplaySize(50, 100, 780, 360);
      expect(Math.round(size.height)).assertEqual(108);
      expect(Math.round(size.width)).assertEqual(54);
    });

    it('keepsFullScreenSquareImageNatural', 0, () => {
      // 方图 360×360（比 1 ＞ 屏比），宽占比恰 100% → 属"保持"区间（＜ 100% 上界不含），
      // 占比等于 100% 时按规则归入"≥ 100% 缩小至 100%"，结果一致仍为整屏宽。
      const size = computeImageDisplaySize(360, 360, SCREEN_W, SCREEN_H);
      expect(Math.round(size.width)).assertEqual(360);
      expect(Math.round(size.height)).assertEqual(360);
    });

    it('returnsEmptySizeForInvalidInput', 0, () => {
      const size = computeImageDisplaySize(0, 100, SCREEN_W, SCREEN_H);
      expect(size.width).assertEqual(0);
      expect(size.height).assertEqual(0);
      const negative = computeImageDisplaySize(100, 100, -1, 780);
      expect(negative.width).assertEqual(0);
      expect(negative.height).assertEqual(0);
    });
  });
}
