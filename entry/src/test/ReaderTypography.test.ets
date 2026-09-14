import { describe, expect, it } from '@ohos/hypium';
import {
  CONTENT_BLOCK_SPACING_MAX,
  CONTENT_BLOCK_SPACING_MIN,
  CONTENT_LINE_HEIGHT_MAX,
  CONTENT_LINE_HEIGHT_MIN,
  CONTENT_TYPOGRAPHY_STEP,
  contentFontSizeLevels,
  decodeContentBlockSpacing,
  decodeContentFontSize,
  decodeContentLineHeight,
  normalizeReaderTypography
} from 'data';
import {
  readerBlockSpacing,
  readerBodyFontSize,
  readerBodyLineHeight,
  readerHeadingFontSize
} from '../main/ets/pages/ReaderTypography';

export default function readerTypographyTest(): void {
  describe('readerTypographyTest', () => {
    it('exposesUpstreamFontSizeLevels', 0, () => {
      const levels = contentFontSizeLevels();
      // 50..120 step 5（15 档）+ 130..200 step 10（8 档）= 23 档，无 125。
      expect(levels.length).assertEqual(23);
      expect(levels[0]).assertEqual(50);
      expect(levels[14]).assertEqual(120);
      expect(levels[15]).assertEqual(130);
      expect(levels[22]).assertEqual(200);
      expect(levels.indexOf(125)).assertEqual(-1);
      expect(levels.indexOf(100)).assertEqual(10);
    });

    it('fallsBackToDefaultsForMissingOrDamagedValues', 0, () => {
      expect(decodeContentFontSize('100')).assertEqual(100);
      expect(decodeContentFontSize(true)).assertEqual(100);
      expect(decodeContentLineHeight('160')).assertEqual(160);
      expect(decodeContentLineHeight(true)).assertEqual(160);
      expect(decodeContentBlockSpacing('100')).assertEqual(100);
      expect(decodeContentBlockSpacing(true)).assertEqual(100);
    });

    it('snapsFontSizeOntoNearestLevel', 0, () => {
      expect(decodeContentFontSize(100)).assertEqual(100);
      expect(decodeContentFontSize(52)).assertEqual(50);
      expect(decodeContentFontSize(53)).assertEqual(55);
      expect(decodeContentFontSize(121)).assertEqual(120);
      expect(decodeContentFontSize(199)).assertEqual(200);
      // 等距时取较小档（对齐上游 minBy 的首个最小项）。
      expect(decodeContentFontSize(125)).assertEqual(120);
      expect(decodeContentFontSize(135)).assertEqual(130);
    });

    it('clampsFontSizeIntoLevelRange', 0, () => {
      expect(decodeContentFontSize(0)).assertEqual(50);
      expect(decodeContentFontSize(-40)).assertEqual(50);
      expect(decodeContentFontSize(500)).assertEqual(200);
    });

    it('snapsAndClampsLineHeightToTenPercentSteps', 0, () => {
      expect(CONTENT_LINE_HEIGHT_MIN).assertEqual(100);
      expect(CONTENT_LINE_HEIGHT_MAX).assertEqual(300);
      expect(CONTENT_TYPOGRAPHY_STEP).assertEqual(10);
      expect(decodeContentLineHeight(100)).assertEqual(100);
      expect(decodeContentLineHeight(160)).assertEqual(160);
      expect(decodeContentLineHeight(104)).assertEqual(100);
      expect(decodeContentLineHeight(155)).assertEqual(160);
      expect(decodeContentLineHeight(295)).assertEqual(300);
      expect(decodeContentLineHeight(50)).assertEqual(100);
      expect(decodeContentLineHeight(999)).assertEqual(300);
    });

    it('snapsAndClampsBlockSpacingToTenPercentSteps', 0, () => {
      expect(CONTENT_BLOCK_SPACING_MIN).assertEqual(0);
      expect(CONTENT_BLOCK_SPACING_MAX).assertEqual(300);
      expect(decodeContentBlockSpacing(0)).assertEqual(0);
      expect(decodeContentBlockSpacing(4)).assertEqual(0);
      expect(decodeContentBlockSpacing(6)).assertEqual(10);
      expect(decodeContentBlockSpacing(100)).assertEqual(100);
      expect(decodeContentBlockSpacing(305)).assertEqual(300);
      expect(decodeContentBlockSpacing(-20)).assertEqual(0);
    });

    it('normalizesAllThreeTypographyValuesTogether', 0, () => {
      const normalized = normalizeReaderTypography({
        fontSize: 128,
        lineHeight: 154,
        blockSpacing: 303
      });
      expect(normalized.fontSize).assertEqual(130);
      expect(normalized.lineHeight).assertEqual(150);
      expect(normalized.blockSpacing).assertEqual(300);
    });

    it('mapsDefaultTypographyOntoUnchangedBaseline', 0, () => {
      // 默认 100/160/100 必须与改造前的 16fp / 30 行高 / 12vp 段距逐像素一致。
      expect(readerBodyFontSize(100)).assertEqual(16);
      expect(readerBodyLineHeight(100, 160)).assertEqual(30);
      expect(readerBlockSpacing(100)).assertEqual(12);
      expect(readerHeadingFontSize(100)).assertEqual(20);
    });

    it('scalesTypographyByPercent', 0, () => {
      expect(readerBodyFontSize(50)).assertEqual(8);
      expect(readerBodyFontSize(200)).assertEqual(32);
      expect(readerHeadingFontSize(200)).assertEqual(40);
      expect(readerBlockSpacing(0)).assertEqual(0);
      expect(readerBlockSpacing(300)).assertEqual(36);
      // 行高按 160% 归一：100% 档 = 18.75，200% 档 = 60，字号同步放大。
      expect(readerBodyLineHeight(100, 100)).assertEqual(18.75);
      expect(readerBodyLineHeight(100, 300)).assertEqual(56.25);
      expect(readerBodyLineHeight(200, 160)).assertEqual(60);
    });
  });
}
