import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SegmentInfoParagraph } from 'data';

/**
 * 正文划线句子评论（迁移自上游"正文中划线评论"能力）：
 * 用户在回答/文章/问题正文中为某句话添加评论，评论以划线高亮形式持久化在正文内，
 * 点击高亮即可查看/删除。数据按 contentId 维度本地持久化（不依赖服务端接口）。
 */
export interface ContentAnnotation {
  id: string;
  contentId: string;
  blockId: string;
  quote: string;
  comment: string;
  createdAt: number;
}

const STORE_NAME: string = 'content_annotations';
const KEY_PREFIX: string = 'annotations_';

/** 按 contentId 维度读写划线评论的本地存储。 */
export class ContentAnnotationStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  private async preferences(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(this.context, STORE_NAME);
  }

  async load(contentId: string): Promise<ContentAnnotation[]> {
    const store = await this.preferences();
    const raw = await store.get(KEY_PREFIX + contentId, '[]') as string;
    try {
      const parsed = JSON.parse(raw) as ContentAnnotation[];
      if (Array.isArray(parsed)) {
        return parsed;
      }
    } catch (_error) {
      // 损坏数据回退为空列表，不阻塞正文渲染。
    }
    return [];
  }

  private async persist(contentId: string, items: ContentAnnotation[]): Promise<void> {
    const store = await this.preferences();
    await store.put(KEY_PREFIX + contentId, JSON.stringify(items));
    await store.flush();
  }

  async add(contentId: string, annotation: ContentAnnotation): Promise<ContentAnnotation[]> {
    const items = await this.load(contentId);
    items.push(annotation);
    await this.persist(contentId, items);
    return items;
  }

  async remove(contentId: string, id: string): Promise<ContentAnnotation[]> {
    const items = await this.load(contentId);
    const next = items.filter((item: ContentAnnotation): boolean => item.id !== id);
    await this.persist(contentId, next);
    return next;
  }
}

export function createContentAnnotationStore(context: common.UIAbilityContext): ContentAnnotationStore {
  return new ContentAnnotationStore(context);
}

/** 高亮片段：被划线引用的文本带有 annotationId。 */
export interface AnnotationSegment {
  text: string;
  annotationId?: string;
}

/** 划线引用在文本中的位置区间（片段拆分中间结构）。 */
export interface AnnotationRange {
  start: number;
  end: number;
  id: string;
}

/** 正文块的可划线句子集合（划线评论管理面板用）。 */
export interface AnnotationBlockSentences {
  blockId: string;
  preview: string;
  sentences: string[];
}

/** 添加批注时的目标（所属正文块 + 引用文本）。 */
export interface AnnotationTarget {
  blockId: string;
  quote: string;
}

/**
 * 将一段文本按若干划线引用拆成带高亮标记的片段（用于正文渲染）。
 * 相同文本出现多处时只高亮第一处；重叠引用按起始位置去重。
 */
export function splitTextByAnnotations(text: string, annotations: ContentAnnotation[]): Array<AnnotationSegment> {
  if (text.length === 0 || annotations.length === 0) {
    return [{ text: text }];
  }
  const ranges: Array<AnnotationRange> = [];
  annotations.forEach((annotation: ContentAnnotation): void => {
    const quote = annotation.quote;
    if (quote.length === 0) {
      return;
    }
    const index = text.indexOf(quote);
    if (index >= 0) {
      ranges.push({ start: index, end: index + quote.length, id: annotation.id });
    }
  });
  if (ranges.length === 0) {
    return [{ text: text }];
  }
  ranges.sort((a: AnnotationRange, b: AnnotationRange): number => a.start - b.start);
  const accepted: Array<AnnotationRange> = [];
  ranges.forEach((range: AnnotationRange): void => {
    const last = accepted.length > 0 ? accepted[accepted.length - 1] : undefined;
    if (last === undefined || range.start >= last.end) {
      accepted.push(range);
    }
  });
  const segments: Array<AnnotationSegment> = [];
  let cursor = 0;
  accepted.forEach((range: AnnotationRange): void => {
    if (range.start > cursor) {
      segments.push({ text: text.substring(cursor, range.start) });
    }
    segments.push({ text: text.substring(range.start, range.end), annotationId: range.id });
    cursor = range.end;
  });
  if (cursor < text.length) {
    segments.push({ text: text.substring(cursor) });
  }
  return segments;
}

/** 划线高亮背景色（黄底半透明，浅色/深色主题均可见）。 */
export const ANNOTATION_HIGHLIGHT_COLOR: string = 'rgba(255, 196, 0, 0.40)';

/**
 * 将一段文本切分为句子（用于划线评论的句子选择）：以中英文句末标点与换行切分，
 * 过滤空串与纯空白。返回的句子可直接作为划线引用。
 */
export function splitIntoSentences(text: string): Array<string> {
  const raw = text.split(/([。！？!?；;\n])/);
  const sentences: Array<string> = [];
  let buffer = '';
  raw.forEach((part: string): void => {
    if (part.length === 0) {
      return;
    }
    buffer += part;
    if (/[。！？!?；;\n]/.test(part)) {
      const trimmed = buffer.trim();
      if (trimmed.length > 0) {
        sentences.push(trimmed);
      }
      buffer = '';
    }
  });
  const tail = buffer.trim();
  if (tail.length > 0) {
    sentences.push(tail);
  }
  return sentences;
}

/** 他人划线引用（点击打开点赞/评论面板）。 */
export interface SegmentHighlightRef {
  paragraph: SegmentInfoParagraph;
  markIndex: number;
}

/** 合并高亮片段：可能同时携带本地划线评论（黄）与/或他人划线（蓝）。 */
export interface HighlightSegment {
  text: string;
  annotationId?: string;
  segmentRef?: SegmentHighlightRef;
}

/** 合并高亮时的单条覆盖区间（内部用，ArkTS 不允许在函数体内声明接口，故提到模块级）。 */
interface SegmentCover {
  start: number;
  end: number;
  kind: 'annotation' | 'segment';
  annotationId?: string;
  ref?: SegmentHighlightRef;
}

/**
 * 将一段文本按"本地划线评论 + 他人划线"两类高亮拆成片段，供正文渲染。
 * 两段区间重叠时他人划线优先（社交功能为主），否则本地划线优先。
 * 他人划线的 start/end 是相对于段落文本（item.text）的偏移，越界自动裁剪，避免
 * 服务端文本与本地渲染文本不一致时高亮错位或崩溃。
 */
export function splitTextByHighlights(
  text: string,
  annotations: ContentAnnotation[],
  segments: Array<SegmentHighlightRef>
): Array<HighlightSegment> {
  if (text.length === 0) {
    return [];
  }
  const covers: Array<SegmentCover> = [];
  annotations.forEach((annotation: ContentAnnotation): void => {
    const quote = annotation.quote;
    if (quote.length === 0) {
      return;
    }
    const index = text.indexOf(quote);
    if (index >= 0) {
      covers.push({ start: index, end: index + quote.length, kind: 'annotation', annotationId: annotation.id });
    }
  });
  segments.forEach((ref: SegmentHighlightRef): void => {
    const mark = ref.paragraph.marks[ref.markIndex];
    if (mark === undefined) {
      return;
    }
    const start = Math.max(0, Math.min(text.length, mark.startIndex));
    const end = Math.max(0, Math.min(text.length, mark.endIndex));
    if (end <= start) {
      return;
    }
    covers.push({ start: start, end: end, kind: 'segment', ref: ref });
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
    let annotationId: string | undefined = undefined;
    let segRef: SegmentHighlightRef | undefined = undefined;
    covers.forEach((cover: SegmentCover): void => {
      if (cover.start <= start && cover.end >= end) {
        if (cover.kind === 'segment') {
          segRef = cover.ref;
        } else {
          annotationId = cover.annotationId;
        }
      }
    });
    if (segRef !== undefined) {
      result.push({ text: piece, segmentRef: segRef });
    } else if (annotationId !== undefined) {
      result.push({ text: piece, annotationId: annotationId });
    } else {
      result.push({ text: piece });
    }
  }
  return result;
}
