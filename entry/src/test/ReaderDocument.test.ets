import { describe, expect, it } from '@ohos/hypium';
import { parseZhihuHtml, ReaderBlockKind, readerDocumentStats } from '../main/ets/reader/ReaderDocument';

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

    it('preservesInlineEquationAsReadableText', 0, () => {
      const blocks = parseZhihuHtml('<p>欧拉公式<img eeimg="1" src="equation" alt="e^{i&amp;pi;}+1=0">成立</p>');
      expect(blocks[0].text).assertEqual('欧拉公式 「e^{i&pi;}+1=0」 成立');
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
      expect(stats.imageCount).assertEqual(0);
      expect(stats.textLength).assertEqual(5);
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
}
