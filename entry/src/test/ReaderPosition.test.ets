import { describe, expect, it } from '@ohos/hypium';
import {
  decodeReaderPosition,
  MAX_READER_POSITIONS,
  ReaderPosition,
  readerPositionKey,
  ReaderPositionRepository,
  ReaderPositionStorage
} from 'data';
import { ReaderBlock, ReaderBlockKind } from 'reader';
import {
  readerBlockSignature,
  readerPositionBlockIndex,
  readerPositionFraction,
  readerPositionTargetY
} from '../main/ets/pages/ReaderPositionAnchor';

class MemoryPositionStorage implements ReaderPositionStorage {
  readonly values: Map<string, string> = new Map();
  syncFlushes: number = 0;
  read(key: string): string { return this.values.get(key) ?? ''; }
  write(key: string, value: string): void { this.values.set(key, value); }
  remove(key: string): void { this.values.delete(key); }
  flush(synchronous: boolean): void { if (synchronous) { this.syncFlushes += 1; } }
}

function paragraph(id: string, text: string): ReaderBlock {
  const block: ReaderBlock = {
    id: id, kind: ReaderBlockKind.PARAGRAPH, text: text, sourceUrl: '', inlineRuns: []
  };
  return block;
}

function positionOf(block: ReaderBlock, index: number, fraction: number = 0.4): ReaderPosition {
  const position: ReaderPosition = {
    version: 1, blockId: block.id, signature: readerBlockSignature(block),
    blockIndex: index, fraction: fraction, atEnd: false
  };
  return position;
}

export default function readerPositionTest(): void {
  describe('readerPositionTest', () => {
    it('isolatesAnswersAndArticlesAndRejectsNonContentKeys', 0, () => {
      expect(readerPositionKey('answer', '123')).assertEqual('answer:123');
      expect(readerPositionKey('article', '123')).assertEqual('article:123');
      expect(readerPositionKey('question', '123')).assertEqual('');
      expect(readerPositionKey('answer', '../123')).assertEqual('');
      expect(readerPositionKey('answer', '0')).assertEqual('');
      expect(readerPositionKey('answer', '1'.repeat(31))).assertEqual('');
    });

    it('roundTripsAnchorsAndIgnoresCorruptOrFutureRecords', 0, () => {
      const position = positionOf(paragraph('block-4', '段落'), 4);
      expect(decodeReaderPosition(JSON.stringify(position))?.fraction).assertEqual(0.4);
      expect(decodeReaderPosition('null')).assertUndefined();
      expect(decodeReaderPosition('{bad')).assertUndefined();
      position.version = 2;
      expect(decodeReaderPosition(JSON.stringify(position))).assertUndefined();
      position.version = 1;
      position.fraction = -0.2;
      expect(decodeReaderPosition(JSON.stringify(position))).assertUndefined();
      position.fraction = Number.NaN;
      expect(decodeReaderPosition(JSON.stringify(position))).assertUndefined();
      position.fraction = 0.4;
      position.blockIndex = 1.5;
      expect(decodeReaderPosition(JSON.stringify(position))).assertUndefined();
    });

    it('retainsIndependentProgressWhenOpeningOtherContent', 0, () => {
      const storage = new MemoryPositionStorage();
      const repository = new ReaderPositionRepository(storage);
      repository.save('answer:1', positionOf(paragraph('block-5', '回答一'), 5));
      repository.save('answer:2', positionOf(paragraph('block-8', '回答二'), 8));
      repository.save('article:1', positionOf(paragraph('block-3', '文章'), 3));
      const reopened = new ReaderPositionRepository(storage);
      expect(reopened.load('answer:1')?.blockIndex).assertEqual(5);
      expect(reopened.load('answer:2')?.blockIndex).assertEqual(8);
      expect(reopened.load('article:1')?.blockIndex).assertEqual(3);
    });

    it('overwritesOldProgressWhenReaderReturnsToTheBeginning', 0, () => {
      const storage = new MemoryPositionStorage();
      const repository = new ReaderPositionRepository(storage);
      repository.save('answer:1', positionOf(paragraph('block-5', '中段'), 5));
      const top: ReaderPosition = {
        version: 1, blockId: '', signature: '00000000', blockIndex: -1, fraction: 0, atEnd: false
      };
      repository.save('answer:1', top, true);
      expect(new ReaderPositionRepository(storage).load('answer:1')?.blockIndex).assertEqual(-1);
      expect(storage.syncFlushes).assertEqual(1);
    });

    it('boundsSavedPositionsAndRetainsRecentlyUpdatedEntries', 0, () => {
      const storage = new MemoryPositionStorage();
      const repository = new ReaderPositionRepository(storage);
      const position = positionOf(paragraph('block-1', '正文'), 1);
      for (let index = 1; index <= MAX_READER_POSITIONS; index++) {
        repository.save(`answer:${index}`, position);
      }
      repository.save('answer:1', position);
      repository.save(`answer:${MAX_READER_POSITIONS + 1}`, position);
      expect(repository.load('answer:1')?.blockIndex).assertEqual(1);
      expect(repository.load('answer:2')).assertUndefined();
      expect(storage.values.size).assertEqual(MAX_READER_POSITIONS + 1);
    });

    it('ignoresInvalidSavesAndRecoversFromADamagedIndex', 0, () => {
      const storage = new MemoryPositionStorage();
      const repository = new ReaderPositionRepository(storage);
      const position = positionOf(paragraph('block-1', '正文'), 1);
      repository.save('question:1', position);
      expect(storage.values.size).assertEqual(0);
      storage.write('recent', '{broken');
      repository.save('answer:1', position);
      expect(repository.load('answer:1')?.blockIndex).assertEqual(1);
    });

    it('findsTheSameParagraphAfterContentIsInsertedBeforeIt', 0, () => {
      const original = paragraph('block-1', '原阅读段落');
      const saved = positionOf(original, 1);
      const blocks: ReaderBlock[] = [paragraph('block-0', '新段落'), paragraph('block-1', '旧首段'),
        paragraph('block-2', '原阅读段落')];
      expect(readerPositionBlockIndex(saved, blocks)).assertEqual(2);
      expect(readerBlockSignature(original)).assertEqual(readerBlockSignature(blocks[2]));
    });

    it('doesNotRestoreIntoUnrelatedReplacedTextOrPictures', 0, () => {
      const original = paragraph('block-1', '原段落');
      expect(readerPositionBlockIndex(positionOf(original, 0), [paragraph('block-1', '完全替换')])).assertEqual(-1);
      const firstImage: ReaderBlock = {
        id: 'block-2', kind: ReaderBlockKind.IMAGE, text: '', sourceUrl: 'https://pic1.zhimg.com/a', inlineRuns: []
      };
      const secondImage: ReaderBlock = {
        id: 'block-2', kind: ReaderBlockKind.IMAGE, text: '', sourceUrl: 'https://pic1.zhimg.com/b', inlineRuns: []
      };
      expect(readerBlockSignature(firstImage) === readerBlockSignature(secondImage)).assertFalse();
    });

    it('keepsRelativePositionWhenFontOrImageHeightChanges', 0, () => {
      const fraction = readerPositionFraction(-100, 400, 60);
      expect(fraction).assertEqual(0.4);
      expect(readerPositionTargetY(fraction, 800, 60)).assertEqual(-260);
      expect(readerPositionFraction(-260, 800, 60)).assertEqual(fraction);
      expect(readerPositionFraction(100, 400, 60)).assertEqual(0);
      expect(readerPositionFraction(-900, 400, 60)).assertEqual(1);
      expect(readerPositionFraction(0, 0, 60)).assertEqual(0);
    });
  });
}
