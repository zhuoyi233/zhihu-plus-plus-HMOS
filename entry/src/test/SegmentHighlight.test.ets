import { describe, expect, it } from '@ohos/hypium';
import { SegmentInfoMark, SegmentInfoParagraph, SegmentInfoMeta } from 'data';
import {
  ContentAnnotation,
  HighlightSegment,
  SegmentHighlightRef,
  splitTextByHighlights
} from '../main/ets/pages/ContentAnnotations';

function annotation(id: string, quote: string): ContentAnnotation {
  return { id: id, contentId: 'c1', blockId: 'b1', quote: quote, comment: 'note', createdAt: 1 };
}

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
      const pieces = splitTextByHighlights('abcdefgh', [], []);
      expect(pieces.length).assertEqual(1);
      expect(pieces[0].text).assertEqual('abcdefgh');
      expect(pieces[0].annotationId).assertUndefined();
      expect(pieces[0].segmentRef).assertUndefined();
    });

    it('splitsAnnotationQuoteIntoThreePieces', 0, () => {
      const pieces = splitTextByHighlights('abcdefgh', [annotation('a1', 'cde')], []);
      expect(pieces.length).assertEqual(3);
      expect(pieces[0].text).assertEqual('ab');
      expect(pieces[1].text).assertEqual('cde');
      expect(pieces[1].annotationId).assertEqual('a1');
      expect(pieces[2].text).assertEqual('fgh');
      expect(pieces[2].annotationId).assertUndefined();
    });

    it('ignoresAnnotationQuoteMissingFromText', 0, () => {
      const pieces = splitTextByHighlights('abcdefgh', [annotation('a1', 'xyz')], []);
      expect(pieces.length).assertEqual(1);
      expect(pieces[0].text).assertEqual('abcdefgh');
    });

    it('clipsSegmentMarkOutOfRange', 0, () => {
      const value = paragraph('abcdefgh', [mark(6, 99)]);
      const pieces = splitTextByHighlights('abcdefgh', [], [refFor(value, 0)]);
      expect(pieces.length).assertEqual(2);
      expect(pieces[0].text).assertEqual('abcdef');
      expect(pieces[1].text).assertEqual('gh');
      expect((pieces[1].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
    });

    it('prioritizesSegmentOverAnnotationOnOverlap', 0, () => {
      const value = paragraph('abcdefgh', [mark(0, 6)]);
      const pieces = splitTextByHighlights(
        'abcdefgh',
        [annotation('a1', 'cde')],
        [refFor(value, 0)]
      );
      expect(pieces.length).assertEqual(4);
      expect(pieces[0].text).assertEqual('ab');
      expect((pieces[0].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
      expect(pieces[1].text).assertEqual('cde');
      expect((pieces[1].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
      expect(pieces[1].annotationId).assertUndefined();
      expect(pieces[2].text).assertEqual('f');
      expect((pieces[2].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
      expect(pieces[3].text).assertEqual('gh');
      expect(pieces[3].segmentRef).assertUndefined();
      expect(pieces[3].annotationId).assertUndefined();
    });

    it('rendersBothKindsSideBySideWithoutOverlap', 0, () => {
      const value = paragraph('abcdefgh', [mark(4, 6)]);
      const pieces: HighlightSegment[] = splitTextByHighlights(
        'abcdefgh',
        [annotation('a1', 'ab')],
        [refFor(value, 0)]
      );
      expect(pieces.length).assertEqual(4);
      expect(pieces[0].text).assertEqual('ab');
      expect(pieces[0].annotationId).assertEqual('a1');
      expect(pieces[1].text).assertEqual('cd');
      expect(pieces[1].segmentRef).assertUndefined();
      expect(pieces[2].text).assertEqual('ef');
      expect((pieces[2].segmentRef as SegmentHighlightRef).markIndex).assertEqual(0);
      expect(pieces[3].text).assertEqual('gh');
      expect(pieces[3].segmentRef).assertUndefined();
    });
  });
}
