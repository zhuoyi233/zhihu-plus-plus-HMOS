import { ReaderInlineKind, ReaderInlineRun } from 'reader';
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

/** 带内联样式的正文片段：由 styled runs × 他人划线区间展平而来。 */
export interface StyledTextSegment {
  text: string;
  bold: boolean;
  italic: boolean;
  strikethrough: boolean;
  code: boolean;
  mark: boolean;
  superscript: boolean;
  subscript: boolean;
  linkUrl: string;
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

/**
 * 将内联 runs 与他人划线区间展平为待渲染片段：每个 TEXT run 先按自身在段落文本中的
 * 偏移与划线区间求交，划线样式叠加在 run 样式之上。TEXT run 的拼接须与段落文本一致
 * （ReaderDocument 解析侧保证，含公式 run 的段落由调用方传入空划线列表）。
 */
export function flattenStyledTextSegments(
  runs: Array<ReaderInlineRun>,
  paragraphText: string,
  segments: Array<SegmentHighlightRef>
): Array<StyledTextSegment> {
  const covers: Array<SegmentCover> = [];
  segments.forEach((ref: SegmentHighlightRef): void => {
    const cover = clippedRange(paragraphText, ref);
    if (cover !== undefined) {
      covers.push(cover);
    }
  });
  const result: Array<StyledTextSegment> = [];
  let cursor = 0;
  runs.forEach((run: ReaderInlineRun): void => {
    if (run.kind !== ReaderInlineKind.TEXT) {
      // 公式 run：标题等路径退化为可读替代文本（与纯文本渲染一致）。
      result.push({
        text: `「${run.text}」`,
        bold: false, italic: false, strikethrough: false, code: false,
        mark: false, superscript: false, subscript: false, linkUrl: ''
      });
      return;
    }
    const start = cursor;
    const end = cursor + run.text.length;
    cursor = end;
    const points: Array<number> = [start, end];
    covers.forEach((cover: SegmentCover): void => {
      if (cover.start > start && cover.start < end && points.indexOf(cover.start) < 0) {
        points.push(cover.start);
      }
      if (cover.end > start && cover.end < end && points.indexOf(cover.end) < 0) {
        points.push(cover.end);
      }
    });
    points.sort((a: number, b: number): number => a - b);
    for (let i = 0; i < points.length - 1; i++) {
      const pieceStart = points[i];
      const pieceEnd = points[i + 1];
      if (pieceEnd <= pieceStart) {
        continue;
      }
      let segRef: SegmentHighlightRef | undefined = undefined;
      covers.forEach((cover: SegmentCover): void => {
        if (cover.start <= pieceStart && cover.end >= pieceEnd) {
          segRef = cover.ref;
        }
      });
      result.push({
        text: run.text.substring(pieceStart - start, pieceEnd - start),
        bold: run.bold === true,
        italic: run.italic === true,
        strikethrough: run.strikethrough === true,
        code: run.code === true,
        mark: run.mark === true,
        superscript: run.superscript === true,
        subscript: run.subscript === true,
        linkUrl: run.linkUrl ?? '',
        segmentRef: segRef
      });
    }
  });
  return result;
}
