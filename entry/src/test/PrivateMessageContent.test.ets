import { ZhihuPrivateMessage } from 'data';

import { describe, expect, it } from '@ohos/hypium';
import { notificationPlainText, parsePrivateMessageSegments, privateMessageDisplaySource } from '../main/ets/pages/PrivateMessageContent';

export default function privateMessageContentTest(): void {
  describe('privateMessageContentTest', () => {
    it('parsesAnchorsIntoLinkSegmentsAndPlainText', 0, () => {
      const html = '前缀 <a href="https://www.zhihu.com/question/1">问题链接</a> 后缀';
      const segments = parsePrivateMessageSegments(html);
      expect(segments.length).assertEqual(3);
      expect(segments[0].text).assertEqual('前缀 ');
      expect(segments[0].url).assertEqual('');
      expect(segments[1].text).assertEqual('问题链接');
      expect(segments[1].url).assertEqual('https://www.zhihu.com/question/1');
      expect(segments[2].text).assertEqual(' 后缀');
    });

    it('dropsUnsafeHrefsAndKeepsTheirText', 0, () => {
      const html = '<a href="javascript:alert(1)">危险</a> 之后 <a href="/relative">相对</a>';
      const segments = parsePrivateMessageSegments(html);
      expect(segments.length).assertEqual(1);
      expect(segments[0].text).assertEqual('危险 之后 相对');
      expect(segments[0].url).assertEqual('');
    });

    it('convertsBrToNewlineAndUnescapesEntities', 0, () => {
      const html = '第一行<br/>第二行 &lt;标记&gt; &amp; &quot;引号&quot;';
      const text = notificationPlainText(html);
      expect(text).assertEqual('第一行\n第二行 <标记> & "引号"');
    });

    it('stripsNestedTagsInsideAnchors', 0, () => {
      const html = '<a href="https://ok.zhihu.com/a?b=1"><b>加粗</b>链接</a>';
      const segments = parsePrivateMessageSegments(html);
      expect(segments.length).assertEqual(1);
      expect(segments[0].text).assertEqual('加粗链接');
      expect(segments[0].url).assertEqual('https://ok.zhihu.com/a?b=1');
    });

    it('mergesAdjacentSegmentsWithSameUrlState', 0, () => {
      const segments = parsePrivateMessageSegments('a<a href="https://x.zhihu.com/">链</a>接');
      expect(segments.length).assertEqual(3);
      expect(segments[0].text).assertEqual('a');
      expect(segments[0].url).assertEqual('');
      expect(segments[1].text).assertEqual('链');
      expect(segments[1].url).assertEqual('https://x.zhihu.com/');
      expect(segments[2].text).assertEqual('接');

      const merged = parsePrivateMessageSegments(
        '<a href="https://x.zhihu.com/">链</a><a href="https://x.zhihu.com/">接</a>');
      expect(merged.length).assertEqual(1);
      expect(merged[0].text).assertEqual('链接');
      expect(merged[0].url).assertEqual('https://x.zhihu.com/');
    });

    it('returnsEmptyForBlankInput', 0, () => {
      expect(parsePrivateMessageSegments('   ').length).assertEqual(0);
    });

    it('prefersPluginExcerptOverContent', 0, () => {
      expect(privateMessageDisplaySource(makeMessage('<br>html', '摘要'))).assertEqual('摘要');
      expect(privateMessageDisplaySource(makeMessage('<br>html', ''))).assertEqual('<br>html');
      expect(privateMessageDisplaySource(makeMessage('', ''))).assertEqual('暂不支持显示这条消息');
    });
  });
}

function makeMessage(content: string, pluginExcerpt: string): ZhihuPrivateMessage {
  const message: ZhihuPrivateMessage = {
    id: 'm1',
    type: 'message',
    contentType: 0,
    content: content,
    createdTime: 1760000000,
    pluginExcerpt: pluginExcerpt,
    sender: undefined,
    receiver: undefined
  };
  return message;
}
