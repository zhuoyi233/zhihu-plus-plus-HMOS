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
  decodeReaderTypographyPreset,
  normalizeReaderTypography,
  ReaderTypographyPreset
} from 'data';
import {
  readerBlockSpacing,
  readerBodyFontSize,
  readerBodyLineHeight,
  readerHeadingFontSize
} from '../main/ets/pages/ReaderTypography';
import { ReaderBlock, ReaderBlockKind } from 'reader';
import { readerBlockLeadingSpace } from '../main/ets/pages/ReaderBlockLayout';

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

    it('preservesLegacyValuesUnlessComfortablePresetIsExplicit', 0, () => {
      const legacy = normalizeReaderTypography({ fontSize: 140, lineHeight: 190, blockSpacing: 70 });
      expect(legacy.preset).assertEqual(ReaderTypographyPreset.CLASSIC);
      expect(legacy.fontSize).assertEqual(140);
      expect(legacy.lineHeight).assertEqual(190);
      expect(legacy.blockSpacing).assertEqual(70);
      expect(decodeReaderTypographyPreset('future')).assertEqual(ReaderTypographyPreset.CLASSIC);
      expect(decodeReaderTypographyPreset(true)).assertEqual(ReaderTypographyPreset.CLASSIC);
      expect(decodeReaderTypographyPreset('comfortable')).assertEqual(ReaderTypographyPreset.COMFORTABLE);
      const comfortable = normalizeReaderTypography({ fontSize: 140, lineHeight: 190, blockSpacing: 70,
        preset: ReaderTypographyPreset.COMFORTABLE });
      expect(comfortable.preset).assertEqual(ReaderTypographyPreset.COMFORTABLE);
      expect(comfortable.fontSize).assertEqual(140);
      expect(comfortable.lineHeight).assertEqual(190);
      expect(comfortable.blockSpacing).assertEqual(70);
    });

    it('mapsComfortablePresetWithoutRoundingSliderValues', 0, () => {
      expect(readerBodyFontSize(100, 'comfortable')).assertEqual(17);
      expect(readerBodyLineHeight(100, 160, 'comfortable')).assertEqual(29);
      expect(readerBlockSpacing(100, 'comfortable')).assertEqual(14);
      expect(readerBodyFontSize(200, 'comfortable')).assertEqual(34);
      expect(readerBodyLineHeight(200, 160, 'comfortable')).assertEqual(58);
      expect(readerBlockSpacing(0, 'comfortable')).assertEqual(0);
      expect(readerBlockSpacing(300, 'comfortable')).assertEqual(42);
      expect(readerBodyFontSize(100, 'future')).assertEqual(16);
    });

    it('addsHeadingSpaceOnceAndKeepsFirstHeadingFlush', 0, () => {
      const paragraph: ReaderBlock = { id: 'p', kind: ReaderBlockKind.PARAGRAPH, text: '正文',
        sourceUrl: '', inlineRuns: [] };
      const heading: ReaderBlock = { id: 'h', kind: ReaderBlockKind.HEADING, text: '标题',
        sourceUrl: '', inlineRuns: [] };
      expect(readerBlockLeadingSpace(heading, undefined, 12)).assertEqual(0);
      expect(12 + readerBlockLeadingSpace(heading, paragraph, 12)).assertEqual(24);
      expect(12 + readerBlockLeadingSpace(paragraph, heading, 12)).assertEqual(12);
      expect(readerBlockLeadingSpace(heading, heading, 12)).assertEqual(0);
      expect(readerBlockLeadingSpace(heading, paragraph, 0)).assertEqual(0);
      expect(36 + readerBlockLeadingSpace(heading, paragraph, 36)).assertEqual(72);
      heading.text = '推荐阅读';
      expect(12 + readerBlockLeadingSpace(heading, paragraph, 12)).assertEqual(42);
    });

    it('separatesImagesAndQuotesWithoutChangingNestedQuoteDepth', 0, () => {
      const image: ReaderBlock = { id: 'i', kind: ReaderBlockKind.IMAGE, text: '图注',
        sourceUrl: 'https://picx.zhimg.com/test.jpg', inlineRuns: [] };
      const paragraph: ReaderBlock = { id: 'p', kind: ReaderBlockKind.PARAGRAPH, text: '正文',
        sourceUrl: '', inlineRuns: [] };
      const quote: ReaderBlock = { id: 'q', kind: ReaderBlockKind.PARAGRAPH, text: '引用',
        sourceUrl: '', inlineRuns: [], quoteDepth: 2 };
      expect(12 + readerBlockLeadingSpace(paragraph, image, 12)).assertEqual(18);
      expect(12 + readerBlockLeadingSpace(quote, paragraph, 12)).assertEqual(18);
      expect(readerBlockLeadingSpace(quote, quote, 12)).assertEqual(0);
      expect(readerBlockLeadingSpace(paragraph, image, 0)).assertEqual(0);
      expect(quote.quoteDepth).assertEqual(2);
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
