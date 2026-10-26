import { describe, expect, it } from '@ohos/hypium';
import { effectiveSegmentMeta, SegmentInfoMark, SegmentInfoParagraph, SegmentInfoMeta } from 'data';
import {
  mergeSameRangeMarks,
  SegmentHighlightRef,
  splitTextByHighlights
} from '../main/ets/pages/ContentAnnotations';

function mark(startIndex: number, endIndex: number): SegmentInfoMark {
  const meta: SegmentInfoMeta = {
    segIds: ['seg-1'],
    isLike: false,
    likeCount: 2,
    commentCount: 1,
    myCommentCount: 0,
    isSpan: false
  };
  return { startIndex: startIndex, endIndex: endIndex, segInfo: meta };
}

function paragraph(text: string, marks: SegmentInfoMark[]): SegmentInfoParagraph {
  return { pid: 'p-1', text: text, marks: marks };
}

function refFor(paragraphValue: SegmentInfoParagraph, markIndex: number): SegmentHighlightRef {
  return { paragraph: paragraphValue, markIndex: markIndex };
}

export default function segmentHighlightTest(): void {
  describe('segmentHighlightTest', () => {
    it('returnsWholeTextWithoutHighlights', 0, () => {
      const pieces = splitTextByHighlights('abcdefgh', []);
      expect(pieces.length).assertEqual(1);
      expect(pieces[0].text).assertEqual('abcdefgh');
      expect(pieces[0].segmentRef).assertUndefined();
    });

    it('returnsEmptyPiecesForEmptyText', 0, () => {
      const pieces = splitTextByHighlights('', []);
      expect(pieces.length).assertEqual(0);
    });

    it('clipsSegmentMarkOutOfRange', 0, () => {
      const value = paragraph('abcdefgh', [mark(6, 99)]);
      const pieces = splitTextByHighlights('abcdefgh', [refFor(value, 0)]);
      expect(pieces.length).assertEqual(2);
      expect(pieces[0].text).assertEqual('abcdef');
      expect(pieces[1].text).assertEqual('gh');
      expect((pieces[1].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
    });

    it('splitsTwoSegmentMarksIntoPieces', 0, () => {
      const value = paragraph('abcdefgh', [mark(0, 2), mark(6, 8)]);
      const pieces = splitTextByHighlights('abcdefgh', [refFor(value, 0), refFor(value, 1)]);
      expect(pieces.length).assertEqual(3);
      expect(pieces[0].text).assertEqual('ab');
      expect((pieces[0].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
      expect(pieces[1].text).assertEqual('cdef');
      expect(pieces[1].segmentRef).assertUndefined();
      expect(pieces[2].text).assertEqual('gh');
      expect((pieces[2].segmentRef as SegmentHighlightRef).markIndex).assertEqual(1);
    });

    it('ignoresInvalidMarkIndex', 0, () => {
      const value = paragraph('abcdefgh', [mark(0, 2)]);
      const pieces = splitTextByHighlights('abcdefgh', [refFor(value, 5)]);
      expect(pieces.length).assertEqual(1);
      expect(pieces[0].text).assertEqual('abcdefgh');
      expect(pieces[0].segmentRef).assertUndefined();
    });

    it('mergeSameRangeMarksKeepsSingleMarkParagraphUnchanged', 0, () => {
      const value = paragraph('abcdefgh', [mark(0, 2)]);
      const merged = mergeSameRangeMarks([value]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].marks.length).assertEqual(1);
      expect((effectiveSegmentMeta(merged[0].marks[0]) as SegmentInfoMeta).likeCount).assertEqual(2);
    });

    it('mergeSameRangeMarksUnionsSegIdsMasterFirst', 0, () => {
      const slave = mark(0, 4);
      slave.segInfo = {
        segIds: ['slave-1'],
        isLike: false,
        likeCount: 2,
        commentCount: 1,
        myCommentCount: 0,
        isSpan: false
      };
      const master = masterMark(0, 4, ['master-1'], 5, true);
      const value = paragraph('abcdefgh', [slave, master]);
      const merged = mergeSameRangeMarks([value]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].marks.length).assertEqual(1);
      const meta = effectiveSegmentMeta(merged[0].marks[0]) as SegmentInfoMeta;
      // segIds master 优先去重拼接；isLike 取或；计数取最大。
      expect(meta.segIds.length).assertEqual(2);
      expect(meta.segIds[0]).assertEqual('master-1');
      expect(meta.segIds[1]).assertEqual('slave-1');
      expect(meta.isLike).assertTrue();
      expect(meta.likeCount).assertEqual(5);
      expect(meta.commentCount).assertEqual(1);
    });

    it('mergeSameRangeMarksKeepsDifferentRangesSeparateAndSorted', 0, () => {
      const later = mark(6, 8);
      const earlier = masterMark(0, 2, ['master-1'], 1, false);
      const value = paragraph('abcdefgh', [later, earlier]);
      const merged = mergeSameRangeMarks([value]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].marks.length).assertEqual(2);
      // 合并后按起点升序，划线渲染按区间叠加不串位。
      expect(merged[0].marks[0].startIndex).assertEqual(0);
      expect(merged[0].marks[1].startIndex).assertEqual(6);
    });

    it('mergeSameRangeMarksMergesAcrossParagraphsIndependently', 0, () => {
      const first = paragraph('aaaa', [mark(0, 2)]);
      const second = paragraph('bbbb', [masterMark(1, 3, ['m'], 1, false), mark(1, 3)]);
      const merged = mergeSameRangeMarks([first, second]);
      expect(merged.length).assertEqual(2);
      expect(merged[0].marks.length).assertEqual(1);
      expect(merged[1].marks.length).assertEqual(1);
      // 同区间 master+slave 合并：segIds 并集 master 优先。
      const meta = effectiveSegmentMeta(merged[1].marks[0]) as SegmentInfoMeta;
      expect(meta.segIds.length).assertEqual(2);
      expect(meta.segIds[0]).assertEqual('m');
      expect(meta.segIds[1]).assertEqual('seg-1');
    });
  });
}

/** 带 master 标记的划线 mark：点赞会为同一文本位置创建属于自己的 seg。 */
function masterMark(startIndex: number, endIndex: number, segIds: string[],
  likeCount: number, isLike: boolean): SegmentInfoMark {
  const meta: SegmentInfoMeta = {
    segIds: segIds,
    isLike: isLike,
    likeCount: likeCount,
    commentCount: 0,
    myCommentCount: 0,
    isSpan: false
  };
  return { startIndex: startIndex, endIndex: endIndex, masterSegInfo: meta };
}
