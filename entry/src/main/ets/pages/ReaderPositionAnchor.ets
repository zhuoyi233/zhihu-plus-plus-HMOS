import { ReaderPosition } from 'data';
import { ReaderBlock } from 'reader';

/** FNV-1a：用于辨认原段落，持久化记录不携带正文。 */
export function readerBlockSignature(block: ReaderBlock): string {
  const source = `${block.kind}:${block.pid ?? ''}:${block.text}:${block.sourceUrl}`;
  let hash = 2166136261;
  for (let index = 0; index < source.length; index++) {
    hash = Math.imul(hash ^ source.charCodeAt(index), 16777619) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

export function readerPositionBlockIndex(position: ReaderPosition, blocks: ReaderBlock[]): number {
  if (position.blockIndex === -1) { return -1; }
  const original = blocks[position.blockIndex];
  if (original !== undefined && readerBlockSignature(original) === position.signature) {
    return position.blockIndex;
  }
  // 插入段落会改变 block-N 的序号，用内容签名寻找原段落。
  return blocks.findIndex((block: ReaderBlock): boolean => readerBlockSignature(block) === position.signature);
}

export function readerPositionFraction(itemY: number, itemHeight: number, readingLine: number): number {
  return itemHeight > 0 && Number.isFinite(itemHeight)
    ? Math.max(0, Math.min(1, (readingLine - itemY) / itemHeight)) : 0;
}

export function readerPositionTargetY(fraction: number, itemHeight: number, readingLine: number): number {
  return readingLine - Math.max(0, Math.min(1, fraction)) * itemHeight;
}
