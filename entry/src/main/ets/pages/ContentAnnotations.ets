import { SegmentInfoParagraph } from 'data';

/** 他人划线引用（点击打开点赞/评论面板）。 */
export interface SegmentHighlightRef {
  paragraph: SegmentInfoParagraph;
  markIndex: number;
}

/** 高亮片段：他人划线（蓝色虚线下划线）。 */
export interface HighlightSegment {
  text: string;
  segmentRef?: SegmentHighlightRef;
}

/** 他人划线在文本中的覆盖区间（内部用，ArkTS 不允许在函数体内声明接口，故提到模块级）。 */
interface SegmentCover {
  start: number;
  end: number;
  ref: SegmentHighlightRef;
}

/** 读取划线 mark 在 text 上的裁剪后区间，非法（越界为空）时返回 undefined。 */
function clippedRange(text: string, ref: SegmentHighlightRef): SegmentCover | undefined {
  const mark = ref.paragraph.marks[ref.markIndex];
  if (mark === undefined) {
    return undefined;
  }
  const start = Math.max(0, Math.min(text.length, mark.startIndex));
  const end = Math.max(0, Math.min(text.length, mark.endIndex));
  if (end <= start) {
    return undefined;
  }
  return { start: start, end: end, ref: ref };
}

/**
 * 将一段文本按他人划线拆成片段，供正文渲染。
 * 他人划线的 start/end 是相对于段落文本（item.text）的偏移，越界自动裁剪，避免
 * 服务端文本与本地渲染文本不一致时高亮错位或崩溃。
 */
export function splitTextByHighlights(
  text: string,
  segments: Array<SegmentHighlightRef>
): Array<HighlightSegment> {
  if (text.length === 0) {
    return [];
  }
  const covers: Array<SegmentCover> = [];
  segments.forEach((ref: SegmentHighlightRef): void => {
    const cover = clippedRange(text, ref);
    if (cover !== undefined) {
      covers.push(cover);
    }
  });
  if (covers.length === 0) {
    return [{ text: text }];
  }
  const points: Array<number> = [0, text.length];
  covers.forEach((cover: SegmentCover): void => {
    if (points.indexOf(cover.start) < 0) {
      points.push(cover.start);
    }
    if (points.indexOf(cover.end) < 0) {
      points.push(cover.end);
    }
  });
  points.sort((a: number, b: number): number => a - b);
  const result: Array<HighlightSegment> = [];
  for (let i = 0; i < points.length - 1; i++) {
    const start = points[i];
    const end = points[i + 1];
    if (end <= start) {
      continue;
    }
    const piece = text.substring(start, end);
    let segRef: SegmentHighlightRef | undefined = undefined;
    covers.forEach((cover: SegmentCover): void => {
      if (cover.start <= start && cover.end >= end) {
        segRef = cover.ref;
      }
    });
    if (segRef !== undefined) {
      result.push({ text: piece, segmentRef: segRef });
    } else {
      result.push({ text: piece });
    }
  }
  return result;
}
