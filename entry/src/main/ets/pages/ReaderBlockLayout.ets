import { ReaderBlock, ReaderBlockKind } from 'reader';

/** 仅补足统一块间距之外的段前留白；不重复叠加 List.space，0% 段间距仍为零。 */
export function readerBlockLeadingSpace(item: ReaderBlock, previous: ReaderBlock | undefined,
  blockSpacing: number): number {
  if (previous === undefined) {
    return 0;
  }
  let multiplier = 1;
  if (item.kind === ReaderBlockKind.HEADING && previous.kind !== ReaderBlockKind.HEADING) {
    multiplier = item.text.trim() === '推荐阅读' ? 3.5 : 2;
  } else if (previous.kind === ReaderBlockKind.IMAGE ||
    ((item.quoteDepth ?? 0) > 0 && (previous.quoteDepth ?? 0) === 0)) {
    multiplier = 1.5;
  }
  return Math.max(0, blockSpacing) * (multiplier - 1);
}
