import { describe, expect, it } from '@ohos/hypium';
import { SegmentInfoMark, SegmentInfoParagraph, SegmentInfoMeta } from 'data';
import {
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
  });
}
