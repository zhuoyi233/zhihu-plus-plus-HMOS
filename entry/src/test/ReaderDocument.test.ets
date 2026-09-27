import { describe, expect, it } from '@ohos/hypium';
import {
  blockFormulaDisplayAspectRatio,
  inlineFormulaDisplayWidth,
  isTrustedFormulaUrl,
  normalizeFormulaSvgText,
  parseZhihuHtml,
  ReaderBlockKind,
  ReaderInlineKind,
  ReaderInlineRun,
  readerDocumentStats
} from 'reader';

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

    it('parsesBoldRunsFromBAndStrong', 0, () => {
      const blocks = parseZhihuHtml('<p>前<b>加粗</b>后</p>');
      expect(blocks[0].text).assertEqual('前加粗后');
      expect(blocks[0].inlineRuns.length).assertEqual(3);
      expect(blocks[0].inlineRuns[0].bold === true).assertFalse();
      expect(blocks[0].inlineRuns[1].bold === true).assertTrue();
      expect(blocks[0].inlineRuns[1].text).assertEqual('加粗');
      expect(blocks[0].inlineRuns[2].bold === true).assertFalse();

      const strong = parseZhihuHtml('<p>a<strong>B</strong>c</p>');
      expect(strong[0].inlineRuns[1].bold === true).assertTrue();
      expect(strong[0].inlineRuns[1].text).assertEqual('B');
    });

    it('parsesZhihuBoldParagraphWithEdgeNewlines', 0, () => {
      // 真实知乎 API 返回的加粗段落形态：p 内首尾换行 + 裸 <b>
      const blocks = parseZhihuHtml('<p data-pid="CUK7DQg5">\n' +
        '<b>对于第一次买手机，没有手机号的人，流程如下：</b>\n</p>');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].text).assertEqual('对于第一次买手机，没有手机号的人，流程如下：');
      expect(blocks[0].inlineRuns.length).assertEqual(1);
      expect(blocks[0].inlineRuns[0].bold === true).assertTrue();
      expect(blocks[0].inlineRuns[0].text).assertEqual('对于第一次买手机，没有手机号的人，流程如下：');
    });

    it('parsesNestedAndMultipleInlineStyles', 0, () => {
      const blocks = parseZhihuHtml('<p><b>粗<i>斜体</i></b> <em>em</em> <del>删</del></p>');
      const runs = blocks[0].inlineRuns;
      expect(runs.length).assertEqual(4);
      expect(runs[0].bold === true).assertTrue();
      expect(runs[0].italic === true).assertFalse();
      expect(runs[1].bold === true).assertTrue();
      expect(runs[1].italic === true).assertTrue();
      expect(runs[1].text).assertEqual('斜体');
      expect(runs[2].italic === true).assertTrue();
      expect(runs[2].bold === true).assertFalse();
      expect(runs[3].strikethrough === true).assertTrue();
      expect(blocks[0].text).assertEqual('粗斜体 em 删');
    });

    it('parsesCodeSupSubMark', 0, () => {
      const blocks = parseZhihuHtml('<p>x<code>foo()</code><sup>2</sup><sub>n</sub><mark>亮</mark></p>');
      const runs = blocks[0].inlineRuns;
      expect(runs.length).assertEqual(5);
      expect(runs[1].code === true).assertTrue();
      expect(runs[1].text).assertEqual('foo()');
      expect(runs[2].superscript === true).assertTrue();
      expect(runs[3].subscript === true).assertTrue();
      expect(runs[4].mark === true).assertTrue();
      expect(blocks[0].text).assertEqual('xfoo()2n亮');
    });

    it('parsesInlineLinksWithHrefNormalization', 0, () => {
      const blocks = parseZhihuHtml('<p>看<a href="//www.zhihu.com/people/foo">某人</a>' +
        '和<a href="https://zhuanlan.zhihu.com/p/123">文章</a>' +
        '与<a href="javascript:alert(1)">危险</a></p>');
      const runs = blocks[0].inlineRuns;
      expect(runs.length).assertEqual(6);
      expect(runs[0].linkUrl).assertEqual('');
      expect(runs[1].linkUrl).assertEqual('https://www.zhihu.com/people/foo');
      expect(runs[3].linkUrl).assertEqual('https://zhuanlan.zhihu.com/p/123');
      expect(runs[5].linkUrl).assertEqual('');
      expect(blocks[0].text).assertEqual('看某人和文章与危险');
    });

    it('keepsStyledRunTextAlignedWithPlainText', 0, () => {
      // runs 拼接须与 plainText 逐字一致（划线偏移依赖此前提），含实体与 <br> 也不例外
      const blocks = parseZhihuHtml('<p>\n前<b>加粗&amp;更多</b>后<br>换行</p>');
      expect(blocks[0].text).assertEqual('前加粗&更多后\n换行');
      const joined = blocks[0].inlineRuns.map((run: ReaderInlineRun): string => run.text).join('');
      expect(joined).assertEqual(blocks[0].text);
      expect(blocks[0].inlineRuns[1].bold === true).assertTrue();
      expect(blocks[0].inlineRuns[1].text).assertEqual('加粗&更多');
    });

    it('keepsFormulaRunsBesideStyledRuns', 0, () => {
      const blocks = parseZhihuHtml('<p><b>粗</b><img eeimg="1" ' +
        'src="https://www.zhihu.com/equation?tex=x" alt="x">尾</p>');
      expect(blocks[0].inlineRuns.length).assertEqual(3);
      expect(blocks[0].inlineRuns[0].bold === true).assertTrue();
      expect(blocks[0].inlineRuns[1].kind).assertEqual(ReaderInlineKind.FORMULA);
      expect(blocks[0].inlineRuns[2].text).assertEqual('尾');
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
      expect(isTrustedFormulaUrl('https://www.zhihu.com:443/equation?tex=x')).assertFalse();
      expect(isTrustedFormulaUrl('https://www.zhihu.com/equation?tex=')).assertFalse();
      expect(isTrustedFormulaUrl('https://www.zhihu.com/equation/extra?tex=x')).assertFalse();
    });

    it('usesThemeColorAndDecodedAspectRatioForFormulaRendering', 0, () => {
      const normalized = normalizeFormulaSvgText(
        '<svg width="2.5ex" height="1.2ex"><path fill="currentColor"/></svg>', '#F5F5F5');
      expect(normalized.includes('width="38px"')).assertTrue();
      expect(normalized.includes('height="18px"')).assertTrue();
      expect(normalized.includes('fill="#F5F5F5"')).assertTrue();
      expect(inlineFormulaDisplayWidth(90, 30)).assertEqual(72);
      expect(inlineFormulaDisplayWidth(30, 30)).assertEqual(24);
      expect(blockFormulaDisplayAspectRatio(600, 100)).assertEqual(6);
      expect(blockFormulaDisplayAspectRatio(0, 100)).assertEqual(4);
    });

    it('prefersOriginalZhihuImageAndCaption', 0, () => {
      const blocks = parseZhihuHtml('<figure><noscript><img src="fallback.jpg"></noscript>' +
        '<img src="placeholder.svg" data-actualsrc="https://picx.zhimg.com/reading.jpg" ' +
        'data-original="https://picx.zhimg.com/original.jpg">' +
        '<figcaption>图片说明</figcaption></figure>');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.IMAGE);
      expect(blocks[0].sourceUrl).assertEqual('https://picx.zhimg.com/original.jpg');
      expect(blocks[0].text).assertEqual('图片说明');
    });

    it('prefersOriginalTokenOverThumbnailAttributes', 0, () => {
      const blocks = parseZhihuHtml('<figure><img data-actualsrc="https://picx.zhimg.com/reading.jpg" ' +
        'data-original-token="v2-abc123def" src="https://picx.zhimg.com/thumb.jpg"></figure>');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.IMAGE);
      expect(blocks[0].sourceUrl).assertEqual('https://pic1.zhimg.com/v2-abc123def');
    });

    it('parsesEmbeddedZhihuVideoCard', 0, () => {
      const blocks = parseZhihuHtml('<p>视频如下</p>' +
        '<a class="video-box content-box" data-lens-id="1944534197600511075" ' +
        'data-title="演示视频"><img data-actualsrc="https://picx.zhimg.com/video-cover.jpg"></a>');

      expect(blocks.length).assertEqual(2);
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.VIDEO);
      expect(blocks[1].targetId).assertEqual('1944534197600511075');
      expect(blocks[1].text).assertEqual('演示视频');
      expect(blocks[1].sourceUrl).assertEqual('https://picx.zhimg.com/video-cover.jpg');
    });

    it('rejectsVideoCardWithoutSafeLensId', 0, () => {
      const blocks = parseZhihuHtml('<p><a class="video-box" data-lens-id="1/../2">视频</a></p>');

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[0].targetId).assertUndefined();
    });

    it('parsesBlockquoteAndPreAsParagraphs', 0, () => {
      const blocks = parseZhihuHtml('<p>开场</p><blockquote>记者问：如何看待信教人数增长？</blockquote>' +
        '<blockquote><p>答：依法管理宗教事务。</p></blockquote><pre>code sample</pre>');

      expect(blocks.length).assertEqual(4);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[0].text).assertEqual('开场');
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[1].text).assertEqual('记者问：如何看待信教人数增长？');
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[2].text).assertEqual('答：依法管理宗教事务。');
      expect(blocks[3].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[3].text).assertEqual('code sample');
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
