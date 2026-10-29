import { describe, expect, it } from '@ohos/hypium';
import {
  DailyStoryCompleteness,
  DailyStoryDiagnosticCode,
  DailyStoryParseResult,
  parseDailyStoryHtml,
  ReaderBlock,
  ReaderBlockKind,
  ReaderInlineRun
} from 'reader';

/**
 * 日报方言解析用例。
 *
 * 主样本（story 9793572）结构已用最小化 HTML 复刻：保留容器层级、class token、
 * 作者头像 / 正文 figure / 卡片封面的角色差异，去掉真实账号与图片地址。
 * 安全与边界用例为合成输入，只验证防御逻辑。
 */

function texts(blocks: Array<ReaderBlock>): Array<string> {
  return blocks.map((block: ReaderBlock): string => block.text);
}

function linksOf(blocks: Array<ReaderBlock>): Array<string> {
  const urls: Array<string> = [];
  blocks.forEach((block: ReaderBlock): void => {
    block.inlineRuns.forEach((run: ReaderInlineRun): void => {
      if ((run.linkUrl ?? '').length > 0) {
        urls.push(run.linkUrl ?? '');
      }
    });
  });
  return urls;
}

/** 主样本的最小化复刻（5 组问答 + 1 张正文图 + 1 张卡片 + 空占位 + script）。 */
const SAMPLE_BODY: string = '<div class="main-wrap content-wrap"><div class="headline">' +
  '<div class="img-place-holder"></div></div><div class="content-inner"><div class="question">' +
  '<h2 class="question-title">瞎扯 如何看待某个现象？</h2><div class="answer"><div class="meta">' +
  '<img class="avatar" src="https://picx.zhimg.com/v2-avatar.jpg">' +
  '<span class="author">知乎日报</span>' +
  '<a href="https://www.zhihu.com/question/None/answer/None" class="originUrl" hidden>查看知乎原文</a>' +
  '</div><div class="content">' +
  '<div>Q：<a class="internal" href="https://www.zhihu.com/question/1/answer/11">如何看待某个现象？</a>' +
  '<blockquote><div class="css-user"><a class="UserLink-link" href="https://www.zhihu.com/people/a">@甲</a></div>' +
  '：第一条回答</blockquote>' +
  'Q：<a class="internal" href="https://www.zhihu.com/question/2/answer/22">第二个问题？</a>' +
  '<blockquote><div class="css-user"><a class="UserLink-link" href="https://www.zhihu.com/people/b">@乙</a></div>' +
  '：第二条回答</blockquote>' +
  'Q：<a class="internal" href="https://www.zhihu.com/question/3/answer/33">第三个问题？</a>' +
  '<blockquote><div class="css-user"><a class="UserLink-link" href="https://www.zhihu.com/people/c">@丙</a></div>' +
  '：第三条回答</blockquote>' +
  'Q：<a class="internal" href="https://www.zhihu.com/question/4/answer/44">第四个问题？</a>' +
  '<blockquote><div class="css-user"><a class="UserLink-link" href="https://www.zhihu.com/people/d">@丁</a></div>' +
  '：第四条回答</blockquote>' +
  '<figure><div class="portal"><img class="content-image" src="https://pica.zhimg.com/v2-body.jpg" alt="">' +
  '</div><figcaption>这是一张图注</figcaption></figure>' +
  'Q：<a class="internal" href="https://www.zhihu.com/question/5/answer/55">第五个问题？</a>' +
  '<blockquote><div class="css-user"><a class="UserLink-link" href="https://www.zhihu.com/people/e">@戊</a></div>' +
  '：第五条回答</blockquote>' +
  '<hr>✨加入圈子，每天看点段子。' +
  '<div class="RichText-LinkCardContainer"><a class="LinkCard new" href="https://www.zhihu.com/ring/host/1">' +
  '<span class="LinkCard-image"><img class="content-image" src="https://pic1.zhimg.com/v2-cover.jpg" alt=""></span>' +
  '<span class="LinkCard-contents"><span class="LinkCard-title two-line">扯点好笑的</span></span></a></div>' +
  '</div><p><br><br><br></p></div></div></div></div>' +
  '<script type=“text/javascript”>window.daily=true</script>';

export default function dailyStoryDocumentTest(): void {
  describe('dailyStoryDocumentTest', () => {
    it('parsesSamplePreservingOrderAndRoles', 0, () => {
      const result: DailyStoryParseResult = parseDailyStoryHtml(SAMPLE_BODY);
      expect(result.completeness).assertEqual(DailyStoryCompleteness.COMPLETE);
      // 5 组引用、5 个回答链接、5 个用户链接。
      expect(result.stats.quoteBlockCount).assertEqual(5);
      const links = linksOf(result.blocks);
      expect(links.filter((url: string): boolean => url.includes('/answer/')).length).assertEqual(5);
      expect(links.filter((url: string): boolean => url.includes('/people/')).length).assertEqual(5);
      // 正文图 1 张（来自 figure），卡片封面不重复计入。
      expect(result.stats.imageCount).assertEqual(1);
      const image = result.blocks.find((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.IMAGE);
      expect(image?.sourceUrl).assertEqual('https://pica.zhimg.com/v2-body.jpg');
      expect(image?.text).assertEqual('这是一张图注');
      // 卡片 1 张，带封面与标题。
      expect(result.stats.linkCardCount).assertEqual(1);
      const card = result.blocks.find((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.LINK_CARD);
      expect(card?.text).assertEqual('扯点好笑的');
      expect(card?.coverUrl).assertEqual('https://pic1.zhimg.com/v2-cover.jpg');
      // 头像与空占位不计入正文。
      expect(result.stats.avatarCount).assertEqual(1);
      expect(result.stats.placeholderCount).assertEqual(1);
      // 标题保留、script 不产可见文本、尾空段不产块。
      expect(texts(result.blocks).some((text: string): boolean => text.includes('如何看待某个现象'))).assertTrue();
      expect(texts(result.blocks).some((text: string): boolean => text.includes('window.daily'))).assertFalse();
      expect(result.blocks.every((block: ReaderBlock): boolean =>
        block.kind === ReaderBlockKind.DIVIDER || block.text.trim().length > 0)).assertTrue();
    });

    it('keepsAuthorAndSectionMetadata', 0, () => {
      const result = parseDailyStoryHtml(SAMPLE_BODY);
      expect(result.sections.length).assertEqual(1);
      expect(result.sections[0].authorName).assertEqual('知乎日报');
      expect(result.sections[0].authorAvatarUrl).assertEqual('https://picx.zhimg.com/v2-avatar.jpg');
      expect(result.sections[0].questionTitle).assertEqual('瞎扯 如何看待某个现象？');
      // originUrl[hidden] 不是作者主页。
      expect(result.sections[0].authorUrl.length).assertEqual(0);
    });

    it('tracksNestedQuoteDepthInsteadOfFlatteningToOne', 0, () => {
      const result = parseDailyStoryHtml(
        '<div class="content"><p>外</p><blockquote><p>一层</p><blockquote><p>二层</p></blockquote></blockquote></div>');
      const depths = result.blocks.map((block: ReaderBlock): number => block.quoteDepth ?? 0);
      expect(JSON.stringify(depths)).assertEqual(JSON.stringify([0, 1, 2]));
      expect(depths.every((depth: number): boolean => depth <= 1)).assertFalse();
    });

    it('keepsTextAroundInlineLinksAndBold', 0, () => {
      const result = parseDailyStoryHtml(
        '<div class="content"><p>前<a href="https://www.zhihu.com/question/1/answer/2">链接</a>后<b>粗</b>尾</p></div>');
      expect(result.blocks[0].text).assertEqual('前链接后粗尾');
      const runs = result.blocks[0].inlineRuns;
      expect(runs.some((run: ReaderInlineRun): boolean =>
        run.linkUrl === 'https://www.zhihu.com/question/1/answer/2' && run.text === '链接')).assertTrue();
      expect(runs.some((run: ReaderInlineRun): boolean => run.bold === true && run.text === '粗')).assertTrue();
    });

    it('decodesEntitiesInTextAndHref', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><p>a&amp;b &lt;x&gt;</p>' +
        '<div class="RichText-LinkCardContainer"><a class="LinkCard" href="https://example.com/?a=1&amp;b=2" ' +
        'data-draft-cover="//pic1.zhimg.com/c.jpg">卡片</a></div></div>');
      expect(result.blocks[0].text).assertEqual('a&b <x>');
      const card = result.blocks.find((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.LINK_CARD);
      expect(card?.sourceUrl).assertEqual('https://example.com/?a=1&b=2');
      expect(card?.coverUrl).assertEqual('https://pic1.zhimg.com/c.jpg');
    });

    it('dropsScriptStyleAndComments', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><!-- 注释 -->' +
        '<script>var a = "<a href=\'https://evil\'>x</a>";</script><style>.a{}</style><p>正文</p></div>');
      expect(result.blocks.length).assertEqual(1);
      expect(result.blocks[0].text).assertEqual('正文');
      expect(result.diagnostics.some((item): boolean =>
        item.code === DailyStoryDiagnosticCode.DROPPED_SCRIPT)).assertTrue();
      expect(JSON.stringify(result.blocks).includes('evil')).assertFalse();
    });

    it('dropsViewMoreDiscussionStubIntoPageTailAction', 0, () => {
      // 页尾「查看知乎讨论」是导航入口：解析器把它丢掉，由阅读页底部按钮承接同一链接，
      // 不能作为一条孤立链接段留在正文里。
      const result = parseDailyStoryHtml('<div class="content"><p>正文</p></div>' +
        '<div class="view-more"><a href="https://www.zhihu.com/question/1996539298581870179">查看知乎讨论</a>' +
        '<span class="js-question-holder"></span></div>');
      expect(texts(result.blocks).join('|')).assertEqual('正文');
      expect(linksOf(result.blocks).length).assertEqual(0);
      expect(result.completeness).assertEqual(DailyStoryCompleteness.COMPLETE);
    });

    it('rejectsUntrustedImageHostsAndFallsBackToAltText', 0, () => {
      const hostile = parseDailyStoryHtml('<div class="content">' +
        '<figure><img src="https://pic1.zhimg.com.evil.example/a.jpg"></figure>' +
        '<figure><img src="https://user@pic1.zhimg.com/a.jpg"></figure>' +
        '<figure><img src="https://pic1.zhimg.com:8443/a.jpg"></figure>' +
        '<figure><img src="http://pic1.zhimg.com/a.jpg"></figure>' +
        '<img src="javascript:alert(1)" alt="坏图">' +
        '</div>');
      expect(hostile.stats.imageCount).assertEqual(0);
      expect(texts(hostile.blocks).includes('坏图')).assertTrue();
      expect(hostile.diagnostics.some((item): boolean =>
        item.code === DailyStoryDiagnosticCode.IMAGE_DROPPED)).assertTrue();
      expect(hostile.completeness).assertEqual(DailyStoryCompleteness.PARTIAL);
    });

    it('neverExposesDangerousLinkTargets', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><p>' +
        '<a href="javascript:alert(1)">点我</a><a href="data:text/html,x">数据</a></p></div>');
      expect(result.blocks[0].text).assertEqual('点我数据');
      expect(linksOf(result.blocks).every((url: string): boolean => url.length === 0)).assertTrue();
      const card = parseDailyStoryHtml('<div class="content">' +
        '<div class="RichText-LinkCardContainer"><a class="LinkCard" href="javascript:1">卡片</a></div></div>');
      expect(card.blocks.length).assertEqual(0);
      expect(card.diagnostics.some((item): boolean =>
        item.code === DailyStoryDiagnosticCode.LINK_DROPPED)).assertTrue();
    });

    it('treatsPureImageBodyAsReadable', 0, () => {
      const result = parseDailyStoryHtml(
        '<div class="content"><figure><img src="https://pic1.zhimg.com/z.jpg"></figure></div>');
      expect(result.completeness === DailyStoryCompleteness.UNSUPPORTED).assertFalse();
      expect(result.stats.imageCount).assertEqual(1);
      expect(result.stats.textLength).assertEqual(0);
    });

    it('reportsUnsupportedForEmptyOrBudgetExceededBodies', 0, () => {
      expect(parseDailyStoryHtml('   ').completeness).assertEqual(DailyStoryCompleteness.UNSUPPORTED);
      expect(parseDailyStoryHtml('   ').diagnostics.some((item): boolean =>
        item.code === DailyStoryDiagnosticCode.EMPTY_BODY)).assertTrue();
      expect(parseDailyStoryHtml('<div class="content"><p> </p><script>x</script></div>').completeness)
        .assertEqual(DailyStoryCompleteness.UNSUPPORTED);
      // 超预算不返回半篇块。
      const oversized = parseDailyStoryHtml('<div class="content">' + '<p>x</p>'.repeat(3000) + '</div>');
      expect(oversized.completeness).assertEqual(DailyStoryCompleteness.UNSUPPORTED);
      expect(oversized.blocks.length).assertEqual(0);
      expect(oversized.diagnostics.some((item): boolean =>
        item.code === DailyStoryDiagnosticCode.BUDGET_EXCEEDED)).assertTrue();
      const deep = parseDailyStoryHtml('<div>'.repeat(40) + 'x' + '</div>'.repeat(40));
      expect(deep.completeness).assertEqual(DailyStoryCompleteness.UNSUPPORTED);
    });

    it('isDeterministicAcrossRepeatedParses', 0, () => {
      const first = parseDailyStoryHtml(SAMPLE_BODY);
      const second = parseDailyStoryHtml(SAMPLE_BODY);
      expect(JSON.stringify(first.blocks)).assertEqual(JSON.stringify(second.blocks));
      expect(first.blocks.length).assertEqual(second.blocks.length);
      // 块 ID 唯一且只由确定性序号构成，阅读锚点可据此恢复。
      const ids = first.blocks.map((block: ReaderBlock): string => block.id);
      expect(new Set<string>(ids).size).assertEqual(ids.length);
      expect(ids.every((id: string): boolean => /^daily-block-[0-9]+$/.test(id))).assertTrue();
    });

    it('keepsDiagnosticsFreeOfBodyContent', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><p>机密正文内容</p>' +
        '<img src="javascript:1" alt="敏感替代文本"><table><tr><td>表格</td></tr></table></div>');
      const serialized = JSON.stringify(result.diagnostics);
      expect(serialized.includes('机密正文内容')).assertFalse();
      expect(serialized.includes('敏感替代文本')).assertFalse();
    });

    it('handlesUnclosedTagsAndAttributeGreaterThan', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><p title="a>b">属性内尖括号</p>' +
        '<p>未闭合<div>x</div></div>');
      expect(result.blocks[0].text).assertEqual('属性内尖括号');
      expect(texts(result.blocks).some((text: string): boolean => text.includes('x'))).assertTrue();
    });

    it('supportsMultipleQuestionsWithDistinctAuthors', 0, () => {
      const result = parseDailyStoryHtml('<div class="content-inner">' +
        '<div class="question"><h2 class="question-title">问题一</h2><div class="answer">' +
        '<div class="meta"><span class="author">作者甲</span></div>' +
        '<div class="content"><p>甲的回答</p></div></div></div>' +
        '<div class="question"><h2 class="question-title">问题二</h2><div class="answer">' +
        '<div class="meta"><span class="author">作者乙</span></div>' +
        '<div class="content"><p>乙的回答</p></div></div></div></div>');
      expect(result.stats.sectionCount).assertEqual(2);
      expect(result.sections[0].authorName).assertEqual('作者甲');
      expect(result.sections[1].authorName).assertEqual('作者乙');
      expect(result.sections[0].questionTitle).assertEqual('问题一');
      expect(result.sections[1].questionTitle).assertEqual('问题二');
      expect(texts(result.blocks).join('|')).assertEqual('问题一|甲的回答|问题二|乙的回答');
    });

    it('summarizesUnsupportedStructuresAsPartial', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><table><tr><td>表格内容</td></tr></table>' +
        '<iframe src="https://evil.example"></iframe><p>正文</p></div>');
      expect(result.completeness).assertEqual(DailyStoryCompleteness.PARTIAL);
      expect(texts(result.blocks).some((text: string): boolean => text.includes('表格内容'))).assertTrue();
      expect(JSON.stringify(result.blocks).includes('evil.example')).assertFalse();
      expect(result.diagnostics.some((item): boolean =>
        item.code === DailyStoryDiagnosticCode.UNSUPPORTED_ELEMENT)).assertTrue();
    });

    it('handlesExpressionImagesAsFormulaBlocks', 0, () => {
      const result = parseDailyStoryHtml('<div class="content">' +
        '<img eeimg="2" alt="E=mc^2" src="https://www.zhihu.com/equation?tex=E%3Dmc%5E2">' +
        '<p>正文</p></div>');
      const formula = result.blocks.find((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.FORMULA);
      expect(formula?.text).assertEqual('E=mc^2');
      expect(formula?.sourceUrl.length).assertEqual(0);
    });

    it('keepsListItemBlocks', 0, () => {
      const result = parseDailyStoryHtml('<div class="content"><ul><li>一项</li><li>二项</li></ul></div>');
      const filled = result.blocks.filter((block: ReaderBlock): boolean => block.text.length > 0);
      expect(filled.length).assertEqual(2);
      expect(filled[0].text).assertEqual('一项');
    });
  });
}
