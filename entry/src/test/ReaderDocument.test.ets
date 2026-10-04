import { describe, expect, it } from '@ohos/hypium';
import {
  FORMULA_MAX_DECODE_PIXELS_PER_EX,
  FORMULA_MAX_RASTER_DIMENSION_PX,
  FORMULA_MIN_DECODE_PIXELS_PER_EX,
  blockFormulaDisplayAspectRatio,
  formulaDecodePixelsPerEx,
  formulaDisplaySize,
  formulaSvgExSize,
  isMathJaxErrorSvg,
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

    it('rendersDisplayEquationsMixedWithTextAndInlineEquations', 0, () => {
      // issue #47：牛顿—莱布尼茨公式与“其中 F'(x)=f(x)”处于同一段。
      const blocks = parseZhihuHtml('<p><img eeimg="2" ' +
        'src="https://www.zhihu.com/equation?tex=int" alt="积分"/>其中 ' +
        '<img eeimg="1" src="https://www.zhihu.com/equation?tex=F" alt="F&#39;(x)=f(x)"/>。</p>');
      expect(blocks[0].inlineRuns.length).assertEqual(4);
      expect(blocks[0].inlineRuns[0].kind).assertEqual(ReaderInlineKind.FORMULA);
      expect(blocks[0].inlineRuns[1].text).assertEqual('其中');
      expect(blocks[0].inlineRuns[2].kind).assertEqual(ReaderInlineKind.FORMULA);
      expect(blocks[0].inlineRuns[2].text).assertEqual("F'(x)=f(x)");
      const trailing = parseZhihuHtml('<p>积分 <b><img eeimg="2" ' +
        'src="https://www.zhihu.com/equation?tex=x" alt="x"/></b></p>');
      expect(trailing[0].inlineRuns[1].kind).assertEqual(ReaderInlineKind.FORMULA);
      const untrusted = parseZhihuHtml('<p>积分<img eeimg="2" ' +
        'src="https://example.com/x.svg" alt="x"/></p>');
      expect(untrusted[0].inlineRuns.length).assertEqual(0);
    });

    it('sizesFormulasByFontAndIntrinsicSizeWithoutStretchingToLineWidth', 0, () => {
      // 入参为公式 SVG 的 ex 固有尺寸（如 6ex × 2ex 的公式，18fp 正文按 0.5em/ex 换算）。
      const small = formulaDisplaySize(6, 2, 18, 1200);
      expect(small.width).assertEqual(54);
      expect(small.height).assertEqual(18);
      const largeFont = formulaDisplaySize(6, 2, 24, 1200);
      expect(largeFont.width).assertEqual(72);
      expect(largeFont.height).assertEqual(24);
      const tall = formulaDisplaySize(6, 8, 18, 320);
      expect(tall.height).assertEqual(72);
      const wide = formulaDisplaySize(80, 8, 18, 300);
      expect(wide.width).assertEqual(300);
      expect(wide.height).assertEqual(30);
      expect(formulaDisplaySize(0, 2).width).assertEqual(20);
      expect(formulaDisplaySize(6, 2, Number.NaN, 0).width).assertEqual(54);
    });

    it('parsesFormulaSvgExSizeFromRootAttributes', 0, () => {
      const svg = '<svg width="13.491ex" height="5.676ex" style="font-size: 15px;"></svg>';
      const exSize = formulaSvgExSize(svg);
      expect(exSize?.width).assertEqual(13.491);
      expect(exSize?.height).assertEqual(5.676);
      expect(formulaSvgExSize('<svg width="10px" height="5ex"></svg>')).assertUndefined();
      expect(formulaSvgExSize('<svg width="0ex" height="5ex"></svg>')).assertUndefined();
    });

    it('detectsMathJaxErrorSvgAsFormulaFailure', 0, () => {
      // 知乎端点对无法解析的 LaTeX 返回红底红字（rgb(247, 86, 89)）的错误提示框。
      const errorSvg = '<svg width="17.048ex" height="3.843ex">' +
        '<rect fill="rgba(247, 86, 89, 0.08)" stroke="none"></rect>' +
        '<g fill="rgb(247, 86, 89)"><text>Misplaced &amp;</text></g></svg>';
      expect(isMathJaxErrorSvg(errorSvg)).assertTrue();
      expect(isMathJaxErrorSvg(
        '<svg width="0.84ex" height="2.009ex"><path stroke="currentColor" d="M26 385"></path></svg>')).assertFalse();
    });

    it('clampsFormulaDecodePixelsPerExForSharpnessAndLimits', 0, () => {
      // 常规公式：目标密度（字号×0.5em/ex×屏幕密度）原样生效。
      expect(formulaDecodePixelsPerEx(6, 2, 29)).assertEqual(29);
      // 目标过高时钳到上限，目标过低时钳到下限。
      expect(formulaDecodePixelsPerEx(6, 2, 500)).assertEqual(FORMULA_MAX_DECODE_PIXELS_PER_EX);
      expect(formulaDecodePixelsPerEx(6, 2, 1)).assertEqual(FORMULA_MIN_DECODE_PIXELS_PER_EX);
      // issue #51 超长公式（423.75ex 宽）：按 4096 上限压低采样密度而非放弃解码，
      // ceil 换算后的栅格宽度不越尺寸上限。
      const longFormula = formulaDecodePixelsPerEx(423.75, 3.843, 29);
      expect(longFormula > 0).assertTrue();
      expect(Math.ceil(423.75 * longFormula) <= FORMULA_MAX_RASTER_DIMENSION_PX).assertTrue();
      // 极端超宽：尺寸上限压过密度下限，宁可低精度也不整条失败。
      const extreme = formulaDecodePixelsPerEx(2000, 8, 29);
      expect(Math.ceil(2000 * extreme) <= FORMULA_MAX_RASTER_DIMENSION_PX).assertTrue();
      expect(extreme < FORMULA_MIN_DECODE_PIXELS_PER_EX).assertTrue();
      // 非法输入回退到兜底采样密度。
      expect(formulaDecodePixelsPerEx(0, 2, 29)).assertEqual(15);
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

    it('preservesQuoteDepthAndPreText', 0, () => {
      const blocks = parseZhihuHtml('<p>开场</p><blockquote>记者问：如何看待信教人数增长？</blockquote>' +
        '<blockquote><p>答：依法管理宗教事务。</p></blockquote><pre>code sample</pre>');

      expect(blocks.length).assertEqual(4);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[0].text).assertEqual('开场');
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[1].text).assertEqual('记者问：如何看待信教人数增长？');
      expect(blocks[1].quoteDepth).assertEqual(1);
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[2].text).assertEqual('答：依法管理宗教事务。');
      expect(blocks[2].quoteDepth).assertEqual(1);
      expect(blocks[3].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[3].text).assertEqual('code sample');
      expect(blocks[3].quoteDepth).assertEqual(0);
    });

    it('preservesNestedQuoteParagraphsAndReferences', 0, () => {
      const blocks = parseZhihuHtml('<blockquote><p data-pid="first">第一段<b>加粗</b></p>' +
        '<blockquote><p>内层</p></blockquote><p data-pid="last">末段' +
        '<sup data-draft-type="reference" data-numero="1" data-text="资料">[1]</sup></p>' +
        '引用尾文</blockquote><p>正文</p>');
      expect(blocks.length).assertEqual(8);
      expect(blocks[0].text).assertEqual('第一段加粗');
      expect(blocks[0].pid).assertEqual('first');
      expect(blocks[0].inlineRuns[1].bold).assertTrue();
      expect(blocks[1].quoteDepth).assertEqual(2);
      expect(blocks[2].quoteDepth).assertEqual(1);
      expect(blocks[2].pid).assertEqual('last');
      expect(blocks[3].text).assertEqual('引用尾文');
      expect(blocks[4].quoteDepth).assertEqual(0);
      expect(blocks[7].reference?.text).assertEqual('资料');
    });

    it('preservesTopLevelLinksAndRecommendationCards', 0, () => {
      const blocks = parseZhihuHtml('<p>推荐阅读</p><a href="https://example.com">网页</a>' +
        '<a class="extra link-card" href="/question/123/answer/456">站内回答</a>' +
        '<p><a data-draft-type="link-card" href="https://zhuanlan.zhihu.com/p/123">文章</a></p>');
      expect(blocks.length).assertEqual(4);
      expect(blocks[1].inlineRuns[0].linkUrl).assertEqual('https://example.com');
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.LINK_CARD);
      expect(blocks[2].sourceUrl).assertEqual('https://www.zhihu.com/question/123/answer/456');
      expect(blocks[3].text).assertEqual('文章');
      expect(blocks[3].kind).assertEqual(ReaderBlockKind.LINK_CARD);
    });

    it('parsesConsecutiveRecommendationCardsIntoBlocks', 0, () => {
      // 还原线上真实结构：h2 后连续多个 link-card <a>（无块级标签分隔、标题在 data-text），
      // 此前整组被塞进同一片段且仅处理单 anchor，卡片整体消失（模拟器回归发现）。
      const blocks = parseZhihuHtml('<h2>推荐阅读</h2>' +
        '<a target="_blank" href="https://zhuanlan.zhihu.com/p/2439992031" data-draft-node="block" ' +
        'data-draft-type="link-card" data-text="政治是思维杀手" class="LinkCard new">' +
        '<span class="LinkCard-image LinkCard-image--default"></span>' +
        '<span class="LinkCard-contents"><span class="LinkCard-title loading" data-text="true"></span>' +
        '<span class="LinkCard-desc loading"></span></span></a>' +
        '<a target="_blank" href="https://zhuanlan.zhihu.com/p/2618776559" data-draft-node="block" ' +
        'data-draft-type="link-card" data-text="政策辩论不应一边倒" class="LinkCard new">' +
        '<span class="LinkCard-contents"></span></a>');
      expect(blocks.length).assertEqual(3);
      expect(blocks[0].text).assertEqual('推荐阅读');
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.LINK_CARD);
      expect(blocks[1].text).assertEqual('政治是思维杀手');
      expect(blocks[1].sourceUrl).assertEqual('https://zhuanlan.zhihu.com/p/2439992031');
      expect(blocks[1].inlineRuns.length).assertEqual(0);
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.LINK_CARD);
      expect(blocks[2].text).assertEqual('政策辩论不应一边倒');
    });

    it('rejectsUnsafeCardTargetsAndKeepsFigureCaption', 0, () => {
      const blocks = parseZhihuHtml('<a class="link-card" href="javascript:alert(1)">说明</a>' +
        '<blockquote><figure><img src="https://picx.zhimg.com/test.jpg"><figcaption><p>图注</p>' +
        '</figcaption></figure><p>图后</p></blockquote><p>外部</p>');
      expect(blocks.length).assertEqual(4);
      expect(blocks[0].sourceUrl).assertEqual('');
      expect(blocks[1].text).assertEqual('图注');
      expect(blocks[1].quoteDepth).assertEqual(1);
      expect(blocks[2].text).assertEqual('图后');
      expect(blocks[3].text).assertEqual('外部');
    });

    it('supportsZhihuDraftCardTitlesAndQuoteParagraphIds', 0, () => {
      const blocks = parseZhihuHtml('<a class="internal" data-draft-node="block" ' +
        'data-draft-type="link-card" data-draft-title="推荐文章" href="https://zhuanlan.zhihu.com/p/123"></a>' +
        '<blockquote data-pid="quote">首行<br/>末行</blockquote><p>后文</p>');
      expect(blocks[0].text).assertEqual('推荐文章');
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.LINK_CARD);
      expect(blocks[1].pid).assertEqual('quote');
      expect(blocks[1].text).assertEqual('首行\n末行');
      expect(blocks[2].quoteDepth).assertEqual(0);
    });

    it('doesNotCollapseMultipleInlineLinksIntoOneCard', 0, () => {
      const blocks = parseZhihuHtml('<p><a data-draft-type="link-card" href="https://example.com/a">甲</a>' +
        '与<a href="https://example.com/b">乙</a></p>');
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[0].text).assertEqual('甲与乙');
      expect(blocks[0].inlineRuns[2].linkUrl).assertEqual('https://example.com/b');
    });

    it('preservesDraftCardCoverSeparatelyFromLinkTarget', 0, () => {
      const blocks = parseZhihuHtml('<a data-draft-type="link-card" href="https://zhuanlan.zhihu.com/p/123" ' +
        'data-draft-cover="//picx.zhimg.com/cover.jpg?source=test&amp;needBackground=1">推荐文章</a>');
      expect(blocks[0].coverUrl).assertEqual('https://picx.zhimg.com/cover.jpg?source=test&needBackground=1');
      expect(blocks[0].sourceUrl).assertEqual('https://zhuanlan.zhihu.com/p/123');
      expect(blocks[0].text).assertEqual('推荐文章');
    });

    it('keepsTextCardsWhenCoverIsMissingOrUnsafe', 0, () => {
      const blocks = parseZhihuHtml('<a data-draft-type="link-card" href="https://example.com">无图</a>' +
        '<a data-draft-type="link-card" href="https://example.com" data-draft-cover="javascript:alert(1)">坏图</a>' +
        '<a data-draft-type="link-card" href="https://example.com" data-draft-cover="https://picx.zhimg.com/a.jpg">有图</a>');
      expect(blocks.length).assertEqual(3);
      expect(blocks[0].coverUrl).assertEqual('');
      expect(blocks[1].coverUrl).assertEqual('');
      expect(blocks[1].text).assertEqual('坏图');
      expect(blocks[2].coverUrl).assertEqual('https://picx.zhimg.com/a.jpg');
    });

    it('hidesZhihuRedirectWrapperOnlyInCardDisplay', 0, () => {
      const redirect = 'https://link.zhihu.com/?target=https%3A%2F%2Fexample.com%2Fpaper%3Fa%3D1%26b%3D2';
      const blocks = parseZhihuHtml('<a data-draft-type="link-card" href="' + redirect + '">论文</a>' +
        '<a data-draft-type="link-card" href="' + redirect + '">' + redirect + '</a>');
      expect(blocks[0].displayUrl).assertEqual('https://example.com/paper?a=1&b=2');
      expect(blocks[0].sourceUrl).assertEqual(redirect);
      expect(blocks[0].text).assertEqual('论文');
      expect(blocks[1].text).assertEqual('https://example.com/paper?a=1&b=2');
    });

    it('keepsMalformedOrNonZhihuRedirectAddressesUnchanged', 0, () => {
      const urls = [
        'https://link.zhihu.com/?target=%ZZ',
        'https://link.zhihu.com/?target=javascript%3Aalert(1)',
        'https://example.com/?target=https%3A%2F%2Fother.com',
        'https://link.zhihu.com.evil.test/?target=https%3A%2F%2Fother.com'
      ];
      urls.forEach((url: string): void => {
        const blocks = parseZhihuHtml('<a data-draft-type="link-card" href="' + url + '">资料</a>');
        expect(blocks[0].displayUrl).assertEqual(url);
        expect(blocks[0].sourceUrl).assertEqual(url);
      });
    });

    it('normalizesProtocolRelativeImageAndRejectsUnsafeSource', 0, () => {
      const protocolRelative = parseZhihuHtml('<figure><img srcset="https://picx.zhimg.com/wrong.jpg 2x" ' +
        'src="//picx.zhimg.com/reading.jpg"></figure>');
      const unsafe = parseZhihuHtml('<figure><img src="javascript:alert(1)"></figure>');

      expect(protocolRelative[0].sourceUrl).assertEqual('https://picx.zhimg.com/reading.jpg');
      expect(unsafe.length).assertEqual(0);
    });

    it('parsesReferenceSupAndSynthesizesFootnoteBlocks', 0, () => {
      // 真实知乎参考资料形态（issue：正文参考链接无法渲染）：sup 携带 data-text/data-url 属性
      const blocks = parseZhihuHtml('<p>绳结理论<sup data-text="Reidemeister Moves" ' +
        'data-url="http://www.amazon.com/exec/obidos/ASIN/9810238789" data-draft-node="inline" ' +
        'data-draft-type="reference" data-numero="1">[1]</sup> 与' +
        '<sup data-text="A Quick Trip Through Knot Theory, 1962" data-url="" ' +
        'data-draft-type="reference" data-numero="2">[2]</sup>。</p>');

      expect(blocks.length).assertEqual(5);
      expect(blocks[0].kind).assertEqual(ReaderBlockKind.PARAGRAPH);
      expect(blocks[0].text).assertEqual('绳结理论[1] 与[2]。');
      const runs = blocks[0].inlineRuns;
      expect(runs.length).assertEqual(5);
      expect(runs[1].superscript === true).assertTrue();
      expect(runs[1].text).assertEqual('[1]');
      expect(runs[1].referenceNumero).assertEqual(1);
      expect(runs[3].text).assertEqual('[2]');
      expect(runs[3].referenceNumero).assertEqual(2);
      // 文末合成：分隔线 + "参考"标题 + 按序号升序的参考条目块
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.DIVIDER);
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.HEADING);
      expect(blocks[2].text).assertEqual('参考');
      expect(blocks[3].kind).assertEqual(ReaderBlockKind.REFERENCE);
      expect(blocks[3].reference?.numero).assertEqual(1);
      expect(blocks[3].text).assertEqual('Reidemeister Moves');
      expect(blocks[3].reference?.url).assertEqual('http://www.amazon.com/exec/obidos/ASIN/9810238789');
      expect(blocks[4].kind).assertEqual(ReaderBlockKind.REFERENCE);
      expect(blocks[4].reference?.numero).assertEqual(2);
      expect(blocks[4].text).assertEqual('A Quick Trip Through Knot Theory, 1962');
      expect(blocks[4].reference?.url).assertEqual('');
    });

    it('keepsPlainSuperscriptWithoutReferenceBlocks', 0, () => {
      const blocks = parseZhihuHtml('<p>x<sup>2</sup>=4</p>');

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].inlineRuns[1].superscript === true).assertTrue();
      expect(blocks[0].inlineRuns[1].referenceNumero).assertUndefined();
    });

    it('dedupsReferenceNumerosAndRejectsUnsafeUrls', 0, () => {
      const blocks = parseZhihuHtml('<p>重复<sup data-text="第一条" data-url="https://a.com" ' +
        'data-draft-type="reference" data-numero="3">[3]</sup>' +
        '<sup data-text="后到忽略" data-url="https://b.com" data-draft-type="reference" ' +
        'data-numero="3">[3]</sup>' +
        '<sup data-text="危险链接" data-url="javascript:alert(1)" data-draft-type="reference" ' +
        'data-numero="4">[4]</sup></p>');

      expect(blocks.length).assertEqual(5);
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.DIVIDER);
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.HEADING);
      expect(blocks[3].kind).assertEqual(ReaderBlockKind.REFERENCE);
      expect(blocks[3].reference?.numero).assertEqual(3);
      expect(blocks[3].text).assertEqual('第一条');
      expect(blocks[4].reference?.numero).assertEqual(4);
      expect(blocks[4].reference?.url).assertEqual('');
    });

    it('skipsEmptyEntriesAndNormalizesReferenceUrls', 0, () => {
      const blocks = parseZhihuHtml('<p>站点内<sup data-text="目录" data-url="/special/000" ' +
        'data-draft-type="reference" data-numero="1">[1]</sup>' +
        '<sup data-text="" data-url="" data-draft-type="reference" data-numero="2">[2]</sup></p>');

      // 空条目（无说明无链接）不生成参考块，站内根路径归一化为绝对地址
      expect(blocks.length).assertEqual(4);
      expect(blocks[2].kind).assertEqual(ReaderBlockKind.HEADING);
      expect(blocks[3].reference?.numero).assertEqual(1);
      expect(blocks[3].reference?.url).assertEqual('https://www.zhihu.com/special/000');
      // 空条目的标记仍按上标渲染，但无跳转目标
      expect(blocks[0].inlineRuns[2].referenceNumero).assertEqual(2);
    });
  });
}
