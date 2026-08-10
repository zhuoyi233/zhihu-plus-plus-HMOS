import { describe, expect, it } from '@ohos/hypium';
import { isTrustedFormulaUrl } from '../main/ets/reader/FormulaSourcePolicy';
import {
  parseZhihuHtml,
  ReaderBlockKind,
  ReaderInlineKind,
  readerDocumentStats
} from '../main/ets/reader/ReaderDocument';

export default function readerDocumentTest(): void {
  describe('readerDocumentTest', () => {
    it('parsesNativeBlockKinds', 0, () => {
      const blocks = parseZhihuHtml('<h2>标题</h2><p>正文 <strong>加粗</strong></p><hr><ul><li>列表项</li></ul>');
      expect(blocks.length).assertEqual(4);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.HEADING);
      expect(blocks[1].text).assertEqual('正文 加粗');
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.DIVIDER);
      expect(blocks[3].kind).assertEqual(ReaderBlockKind.LIST_ITEM);
    });

    it('parsesInlineEquationAndKeepsReadableFallback', 0, () => {
      const blocks = parseZhihuHtml('<p>欧拉公式<img eeimg="1" ' +
        'src="https://www.zhihu.com/equation?tex=e%5Ei" alt="e^{i&amp;pi;}+1=0">成立</p>');
      expect(blocks[0].text).assertEqual('欧拉公式 「e^{i&pi;}+1=0」 成立');
      expect(blocks[0].inlineRuns.length).assertEqual(3);
      expect(blocks[0].inlineRuns[1].kind).assertEqual(ReaderInlineKind.FORMULA);
      expect(blocks[0].inlineRuns[1].text).assertEqual('e^{i&pi;}+1=0');
      expect(blocks[0].inlineRuns[1].sourceUrl)
        .assertEqual('https://www.zhihu.com/equation?tex=e%5Ei');
    });

    it('detectsBlockEquation', 0, () => {
      const blocks = parseZhihuHtml('<p><img eeimg="2" src="https://www.zhihu.com/equation?tex=x%5E2" alt="x^2"></p>');
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.FORMULA);
      expect(blocks[0].sourceUrl).assertEqual('https://www.zhihu.com/equation?tex=x%5E2');
      expect(blocks[0].text).assertEqual('x^2');
    });

    it('reportsDocumentStats', 0, () => {
      const blocks = parseZhihuHtml('<h2>标题</h2><p>正文</p><p><img eeimg="2" src="formula" alt="x"></p>');
      const stats = readerDocumentStats(blocks);
      expect(stats.blockCount).assertEqual(3);
      expect(stats.headingCount).assertEqual(1);
      expect(stats.formulaCount).assertEqual(1);
      expect(stats.blockFormulaCount).assertEqual(1);
      expect(stats.inlineFormulaCount).assertEqual(0);
      expect(stats.imageCount).assertEqual(0);
      expect(stats.textLength).assertEqual(5);
    });

    it('countsBlockAndInlineEquationsSeparately', 0, () => {
      const blocks = parseZhihuHtml('<p>行内<img eeimg="1" ' +
        'src="https://www.zhihu.com/equation?tex=x" alt="x">公式</p>' +
        '<p><img eeimg="2" src="https://www.zhihu.com/equation?tex=y" alt="y"></p>');
      const stats = readerDocumentStats(blocks);

      expect(stats.formulaCount).assertEqual(2);
      expect(stats.blockFormulaCount).assertEqual(1);
      expect(stats.inlineFormulaCount).assertEqual(1);
    });

    it('rejectsUntrustedFormulaSourceButPreservesTex', 0, () => {
      const blocks = parseZhihuHtml('<p>公式<img eeimg="1" src="https://example.com/x.svg" alt="x^2">结束</p>');

      expect(blocks[0].inlineRuns.length).assertEqual(0);
      expect(blocks[0].text).assertEqual('公式 「x^2」 结束');
    });

    it('allowsOnlyZhihuEquationEndpoint', 0, () => {
      expect(isTrustedFormulaUrl('https://www.zhihu.com/equation?tex=x')).assertTrue();
      expect(isTrustedFormulaUrl('https://www.zhihu.com.evil.example/equation?tex=x')).assertFalse();
      expect(isTrustedFormulaUrl('http://www.zhihu.com/equation?tex=x')).assertFalse();
      expect(isTrustedFormulaUrl('https://user@www.zhihu.com/equation?tex=x')).assertFalse();
      expect(isTrustedFormulaUrl('https://www.zhihu.com/equation?tex=')).assertFalse();
      expect(isTrustedFormulaUrl('https://www.zhihu.com/equation/extra?tex=x')).assertFalse();
    });

    it('prefersActualZhihuImageAndCaption', 0, () => {
      const blocks = parseZhihuHtml('<figure><noscript><img src="fallback.jpg"></noscript>' +
        '<img src="placeholder.svg" data-original="https://picx.zhimg.com/original.jpg" ' +
        'data-actualsrc="https://picx.zhimg.com/reading.jpg">' +
        '<figcaption>图片说明</figcaption></figure>');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.IMAGE);
      expect(blocks[0].sourceUrl).assertEqual('https://picx.zhimg.com/reading.jpg');
      expect(blocks[0].text).assertEqual('图片说明');
    });

    it('normalizesProtocolRelativeImageAndRejectsUnsafeSource', 0, () => {
      const protocolRelative = parseZhihuHtml('<figure><img srcset="https://picx.zhimg.com/wrong.jpg 2x" ' +
        'src="//picx.zhimg.com/reading.jpg"></figure>');
      const unsafe = parseZhihuHtml('<figure><img src="javascript:alert(1)"></figure>');

      expect(protocolRelative[0].sourceUrl).assertEqual('https://picx.zhimg.com/reading.jpg');
      expect(unsafe.length).assertEqual(0);
    });
  });
}
