import { describe, expect, it } from '@ohos/hypium';
import { CommentItem } from 'data';
import {
  HOT_COMMENT_PREVIEW_LIMIT,
  HotCommentPhase,
  hotCommentPreview,
  hotCommentSectionVisible
} from '../main/ets/pages/HotCommentState';

/** 构造一条评论：默认可见、未折叠、有正文、有赞同。 */
function comment(id: string, contentHtml: string, isDelete: boolean = false,
  collapsed: boolean = false, likeCount: number = 1): CommentItem {
  return {
    id: id,
    contentHtml: contentHtml,
    createdAt: 0,
    liked: false,
    likeCount: likeCount,
    collapsed: collapsed,
    reviewing: false,
    isDelete: isDelete,
    isAuthor: false,
    isAuthorTop: false,
    author: { id: 'author', urlToken: 'author', name: '作者', avatarUrl: '', headline: '' },
    commentTags: [],
    childCommentCount: 0,
    childComments: []
  };
}

export default function hotCommentStateTest(): void {
  describe('hotCommentStateTest', () => {
    it('keepsOnlyTheFirstVisibleCommentsUpToTheLimit', 0, () => {
      const items: Array<CommentItem> = [
        comment('1', '<p>甲</p>'),
        comment('2', '<p>乙</p>'),
        comment('3', '<p>丙</p>'),
        comment('4', '<p>丁</p>')
      ];
      const picked = hotCommentPreview(items, HOT_COMMENT_PREVIEW_LIMIT);
      expect(picked.length).assertEqual(HOT_COMMENT_PREVIEW_LIMIT);
      expect(picked[0].id).assertEqual('1');
      expect(picked[2].id).assertEqual('3');
    });

    it('skipsDeletedCollapsedAndEmptyComments', 0, () => {
      const items: Array<CommentItem> = [
        comment('deleted', '<p>已删</p>', true),
        comment('collapsed', '<p>折叠</p>', false, true),
        comment('empty', '<p> </p>'),
        comment('image', '<a class="comment_img" href="https://pic1.zhimg.com/a.jpg"></a>'),
        comment('visible', '<p>正文</p>')
      ];
      const picked = hotCommentPreview(items, HOT_COMMENT_PREVIEW_LIMIT);
      expect(picked.length).assertEqual(2);
      expect(picked[0].id).assertEqual('image');
      expect(picked[1].id).assertEqual('visible');
    });

    it('skipsZeroLikeComments', 0, () => {
      const items: Array<CommentItem> = [
        comment('zero', '<p>没人赞</p>', false, false, 0),
        comment('liked', '<p>有赞</p>', false, false, 5)
      ];
      const picked = hotCommentPreview(items, HOT_COMMENT_PREVIEW_LIMIT);
      expect(picked.length).assertEqual(1);
      expect(picked[0].id).assertEqual('liked');
    });

    it('returnsEmptyWhenLimitIsNotPositive', 0, () => {
      const items: Array<CommentItem> = [comment('1', '<p>甲</p>')];
      expect(hotCommentPreview(items, 0).length).assertEqual(0);
      expect(hotCommentPreview(items, -1).length).assertEqual(0);
    });

    it('hidesTheSectionOnlyWhenThereIsNothingToShow', 0, () => {
      // 有可展示热评、加载中、加载失败都占位；空结果（含评论都在但都没赞）整块隐藏。
      expect(hotCommentSectionVisible(HotCommentPhase.READY)).assertTrue();
      expect(hotCommentSectionVisible(HotCommentPhase.LOADING)).assertTrue();
      expect(hotCommentSectionVisible(HotCommentPhase.ERROR)).assertTrue();
      expect(hotCommentSectionVisible(HotCommentPhase.EMPTY)).assertFalse();
      expect(hotCommentSectionVisible(HotCommentPhase.IDLE)).assertFalse();
    });
  });
}
