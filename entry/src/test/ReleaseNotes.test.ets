import { describe, expect, it } from '@ohos/hypium';
import {
  decodeReleaseDetail,
  flattenBlockquoteInner,
  flattenReleaseMarkdownList,
  formatReleaseDate,
  parseInlineSpans,
  parseReleaseMarkdown,
  releaseAlertLabel,
  ReleaseMarkdownBlockKind,
  ReleaseMarkdownSpanKind,
  shouldShowWhatsNewOnLaunch
} from 'data';

export default function releaseNotesTest(): void {
  describe('releaseNotesTest', () => {
    it('gatesWhatsNewPageByVersionChange', 0, () => {
      expect(shouldShowWhatsNewOnLaunch('0.4.0', '0.5.0')).assertTrue();
      expect(shouldShowWhatsNewOnLaunch('0.5.0', '0.5.0')).assertFalse();
      // 首次安装（从未展示过）也展示一次。
      expect(shouldShowWhatsNewOnLaunch('', '0.5.0')).assertTrue();
      // 读不到本机版本时不展示。
      expect(shouldShowWhatsNewOnLaunch('0.5.0', '')).assertFalse();
    });

    it('decodesReleaseDetailPayload', 0, () => {
      const payload = '{"tag_name":"HMOSv0.5.0","name":"HMOSv0.5.0","html_url":' +
        '"https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/tag/HMOSv0.5.0",' +
        '"published_at":"2026-08-29T00:00:00Z","body":"# 标题\\n\\n内容"}';
      const detail = decodeReleaseDetail(payload);
      expect(detail !== undefined).assertTrue();
      expect(detail?.tagName).assertEqual('HMOSv0.5.0');
      expect(detail?.versionName).assertEqual('0.5.0');
      expect(detail?.body).assertEqual('# 标题\n\n内容');
    });

    it('rejectsMalformedReleaseDetailPayload', 0, () => {
      expect(decodeReleaseDetail('not-json')).assertEqual(undefined);
      expect(decodeReleaseDetail('{"name":"no tag"}')).assertEqual(undefined);
      expect(decodeReleaseDetail('{"tag_name":"nightly","body":"x"}')).assertEqual(undefined);
      // body 缺失时回退空串，不视为失败。
      const missingBody = decodeReleaseDetail('{"tag_name":"HMOSv0.5.0"}');
      expect(missingBody?.body).assertEqual('');
    });

    it('formatsReleaseDate', 0, () => {
      expect(formatReleaseDate('2026-08-29T10:00:00Z')).assertEqual('2026-08-29');
      expect(formatReleaseDate(' 2026-08-29T10:00:00Z ')).assertEqual('2026-08-29');
      expect(formatReleaseDate('garbage')).assertEqual('');
      expect(formatReleaseDate('')).assertEqual('');
    });

    it('parsesHeadingsAndSoftWrappedParagraphs', 0, () => {
      const doc = parseReleaseMarkdown('# ZhihuPlusPlus-HMOS v0.5.0\n\n第一段第一行\n第一段第二行\n\n## 📨 主题');
      expect(doc.blocks.length).assertEqual(3);
      expect(doc.blocks[0].kind).assertEqual(ReleaseMarkdownBlockKind.HEADING);
      expect(doc.blocks[0].level).assertEqual(1);
      expect(doc.blocks[0].spans[0].text).assertEqual('ZhihuPlusPlus-HMOS v0.5.0');
      expect(doc.blocks[1].kind).assertEqual(ReleaseMarkdownBlockKind.PARAGRAPH);
      expect(doc.blocks[1].spans[0].text).assertEqual('第一段第一行 第一段第二行');
      expect(doc.blocks[2].level).assertEqual(2);
      expect(doc.blocks[2].spans[0].text).assertEqual('📨 主题');
    });

    it('parsesNestedBulletLists', 0, () => {
      const doc = parseReleaseMarkdown('- 顶层一\n- 顶层二\n  - 子项一\n  - 子项二');
      expect(doc.blocks.length).assertEqual(1);
      const list = doc.blocks[0];
      expect(list.kind).assertEqual(ReleaseMarkdownBlockKind.LIST);
      expect(list.ordered).assertFalse();
      expect(list.items.length).assertEqual(2);
      expect(list.items[0].children.length).assertEqual(0);
      expect(list.items[1].children.length).assertEqual(2);
      expect(list.items[1].children[0].spans[0].text).assertEqual('子项一');
    });

    it('parsesOrderedListWithStartNumber', 0, () => {
      const doc = parseReleaseMarkdown('3. 第三步\n4. 第四步');
      const list = doc.blocks[0];
      expect(list.kind).assertEqual(ReleaseMarkdownBlockKind.LIST);
      expect(list.ordered).assertTrue();
      expect(list.startNumber).assertEqual(3);
      expect(list.items.length).assertEqual(2);
    });

    it('skipsHorizontalRulesAndBlankLines', 0, () => {
      const doc = parseReleaseMarkdown('段一\n\n---\n\n段二');
      expect(doc.blocks.length).assertEqual(2);
      expect(doc.blocks[0].kind).assertEqual(ReleaseMarkdownBlockKind.PARAGRAPH);
      expect(doc.blocks[1].kind).assertEqual(ReleaseMarkdownBlockKind.PARAGRAPH);
    });

    it('parsesImportantAlertBlockquote', 0, () => {
      const body = '> [!IMPORTANT]\n> 首段要求 **HarmonyOS 6.1.0** 及以上。\n>\n> 第二段声明。';
      const doc = parseReleaseMarkdown(body);
      expect(doc.blocks.length).assertEqual(1);
      const quote = doc.blocks[0];
      expect(quote.kind).assertEqual(ReleaseMarkdownBlockKind.BLOCKQUOTE);
      expect(quote.alert).assertEqual('IMPORTANT');
      expect(quote.blocks.length).assertEqual(2);
      const firstParagraph = quote.blocks[0];
      expect(firstParagraph.kind).assertEqual(ReleaseMarkdownBlockKind.PARAGRAPH);
      expect(firstParagraph.spans.length).assertEqual(3);
      expect(firstParagraph.spans[1].kind).assertEqual(ReleaseMarkdownSpanKind.BOLD);
      expect(firstParagraph.spans[1].text).assertEqual('HarmonyOS 6.1.0');
      expect(quote.blocks[1].spans[0].text).assertEqual('第二段声明。');
    });

    it('parsesPlainBlockquoteWithoutAlert', 0, () => {
      const doc = parseReleaseMarkdown('> 普通引用');
      const quote = doc.blocks[0];
      expect(quote.kind).assertEqual(ReleaseMarkdownBlockKind.BLOCKQUOTE);
      expect(quote.alert).assertEqual('');
      expect(quote.blocks.length).assertEqual(1);
    });

    it('parsesInlineSpans', 0, () => {
      const spans = parseInlineSpans('前缀**加粗**与`代码`与[链接](https://example.com/a)后缀');
      expect(spans.length).assertEqual(7);
      expect(spans[0].kind).assertEqual(ReleaseMarkdownSpanKind.TEXT);
      expect(spans[0].text).assertEqual('前缀');
      expect(spans[1].kind).assertEqual(ReleaseMarkdownSpanKind.BOLD);
      expect(spans[1].text).assertEqual('加粗');
      expect(spans[2].text).assertEqual('与');
      expect(spans[3].kind).assertEqual(ReleaseMarkdownSpanKind.CODE);
      expect(spans[3].text).assertEqual('代码');
      expect(spans[5].kind).assertEqual(ReleaseMarkdownSpanKind.LINK);
      expect(spans[5].text).assertEqual('链接');
      expect(spans[5].url).assertEqual('https://example.com/a');
      expect(spans[6].text).assertEqual('后缀');
    });

    it('downgradesImagesToLinks', 0, () => {
      const spans = parseInlineSpans('![截图](https://img.example/a.png)');
      expect(spans.length).assertEqual(1);
      expect(spans[0].kind).assertEqual(ReleaseMarkdownSpanKind.LINK);
      expect(spans[0].text).assertEqual('截图');
      expect(spans[0].url).assertEqual('https://img.example/a.png');
    });

    it('keepsUnbalancedMarkersAsPlainText', 0, () => {
      const spans = parseInlineSpans('**未闭合 与 [缺链接](');
      expect(spans.length).assertEqual(1);
      expect(spans[0].kind).assertEqual(ReleaseMarkdownSpanKind.TEXT);
      expect(spans[0].text).assertEqual('**未闭合 与 [缺链接](');
    });

    it('flattensNestedListsForRendering', 0, () => {
      const doc = parseReleaseMarkdown('3. 甲\n4. 乙\n   1. 乙一\n   2. 乙二\n- 丙');
      const list = doc.blocks[0];
      // 混用有序/无序标记时以首行为准（防御性兜底）。
      const rows = flattenReleaseMarkdownList(list.items, list.ordered, list.startNumber);
      expect(rows.length).assertEqual(5);
      expect(rows[0].number).assertEqual(3);
      expect(rows[0].depth).assertEqual(0);
      expect(rows[1].number).assertEqual(4);
      expect(rows[2].number).assertEqual(1);
      expect(rows[2].depth).assertEqual(1);
      expect(rows[3].number).assertEqual(2);
      expect(rows[3].depth).assertEqual(1);
      expect(rows[4].number).assertEqual(5);
      expect(rows[4].depth).assertEqual(0);
    });

    it('flattensBulletsWithZeroNumbers', 0, () => {
      const doc = parseReleaseMarkdown('- 甲\n  - 甲一');
      const list = doc.blocks[0];
      const rows = flattenReleaseMarkdownList(list.items, list.ordered, list.startNumber);
      expect(rows.length).assertEqual(2);
      expect(rows[0].number).assertEqual(0);
      expect(rows[1].number).assertEqual(0);
      expect(rows[1].depth).assertEqual(1);
    });

    it('unwrapsNestedBlockquotesOneLevel', 0, () => {
      const doc = parseReleaseMarkdown('> 外层\n> > 内层');
      const quote = doc.blocks[0];
      const inner = flattenBlockquoteInner(quote);
      expect(inner.length).assertEqual(2);
      expect(inner[0].kind).assertEqual(ReleaseMarkdownBlockKind.PARAGRAPH);
      expect(inner[0].spans[0].text).assertEqual('外层');
      expect(inner[1].kind).assertEqual(ReleaseMarkdownBlockKind.PARAGRAPH);
      expect(inner[1].spans[0].text).assertEqual('内层');
    });

    it('mapsAlertLabelsToChinese', 0, () => {
      expect(releaseAlertLabel('IMPORTANT')).assertEqual('重要');
      expect(releaseAlertLabel('WARNING')).assertEqual('注意');
      expect(releaseAlertLabel('NOTE')).assertEqual('提示');
      expect(releaseAlertLabel('')).assertEqual('');
      expect(releaseAlertLabel('UNKNOWN')).assertEqual('');
    });

    it('parsesEmptyBodyToEmptyDocument', 0, () => {
      expect(parseReleaseMarkdown('').blocks.length).assertEqual(0);
      expect(parseReleaseMarkdown('\n\n  \n').blocks.length).assertEqual(0);
    });
  });
}
