import { describe, expect, it } from '@ohos/hypium';
import { commentImageUrl, commentImageUrls, stripCommentHtml } from '../main/ets/pages/CommentText';

/** 评论正文解析：图片地址提取（含 pica 图床与裸 img 表情）与纯文本化。 */
export default function commentTextTest(): void {
  describe('commentTextTest', () => {
    it('extractsCommentImageFromPicaHostAnchor', 0, () => {
      // 知乎图床含 pica.zhimg.com（不是 pic1~pic9/picx），曾因白名单过窄取不到地址。
      const html = '这个<a href="https://pica.zhimg.com/v2-e160d8f4e19814480d181479cf56b528_qhd.jpg" ' +
        'class="comment_img" data-width="680" data-height="496">查看图片</a>';
      expect(commentImageUrl(html)).assertEqual(
        'https://pica.zhimg.com/v2-e160d8f4e19814480d181479cf56b528_qhd.jpg');
    });

    it('extractsStickerImageFromBareImgTag', 0, () => {
      const html = '<p>看这个</p><img src="https://pic4.zhimg.com/v2-sticker_l.jpg" class="comment_sticker">';
      expect(commentImageUrl(html)).assertEqual('https://pic4.zhimg.com/v2-sticker_l.jpg');
    });

    it('ignoresNonZhihuImageHosts', 0, () => {
      expect(commentImageUrl('<a href="https://evil.example.com/a.jpg" class="comment_img">查看图片</a>'))
        .assertEqual('');
      expect(commentImageUrl('<img src="https://evil.example.com/b.png">')).assertEqual('');
    });

    it('stripsImageAnchorAndKeepsVisibleText', 0, () => {
      const html = '这个<a href="https://pica.zhimg.com/v2-a.jpg" class="comment_img">查看图片</a>' +
        '<img src="https://pic4.zhimg.com/v2-b.png">[微笑]';
      expect(stripCommentHtml(html)).assertEqual('这个[微笑]');
    });

    it('keepsUnsupportedAnchorTextAndBareImageAlt', 0, () => {
      const html = '文字<a class="comment_img" href="https://example.com/a.jpg">查看原图</a>' +
        '<img src="https://example.com/b.png" alt="表情说明">[微笑]';
      expect(commentImageUrls(html).length).assertEqual(0);
      expect(stripCommentHtml(html)).assertEqual('文字查看原图表情说明[微笑]');
    });

    it('keepsReadableFallbackForUnsupportedEmptyImages', 0, () => {
      expect(stripCommentHtml('<a class="comment_gif" href="bad"></a><img src="bad">'))
        .assertEqual('[图片暂不支持][图片暂不支持]');
    });

    it('extractsMixedMultipleImagesAndGifInDocumentOrder', 0, () => {
      const html = '<img src="https://pic1.zhimg.com/first.png">中间[赞同]' +
        '<a class="comment_gif" href="http://pica.zhimg.com/second.gif?a=1&amp;b=2">动图</a>' +
        '<a class="comment_img" href="https://other.example/a">保留图片说明</a>' +
        '<img src="https://pic1.zhimg.com/first.png">';
      const urls = commentImageUrls(html);
      expect(urls.length).assertEqual(2);
      expect(urls[0]).assertEqual('https://pic1.zhimg.com/first.png');
      expect(urls[1]).assertEqual('https://pica.zhimg.com/second.gif?a=1&b=2');
      expect(stripCommentHtml(html)).assertEqual('中间[赞同]保留图片说明');
    });

    it('doesNotTreatDataSrcOrLookalikeHostsAsDisplayedImages', 0, () => {
      const html = '<img data-src="https://pic1.zhimg.com/a.jpg" alt="未加载图片">' +
        '<a class="comment_img" href="https://pic1.zhimg.com.evil/a.jpg">原图</a>';
      expect(commentImageUrls(html).length).assertEqual(0);
      expect(stripCommentHtml(html)).assertEqual('未加载图片原图');
    });

    it('keepsEmojiPlaceholdersAndBreaksLines', 0, () => {
      expect(stripCommentHtml('<p>哈哈[赞同]</p><p>第二段</p>')).assertEqual('哈哈[赞同]\n第二段');
    });
  });
}
