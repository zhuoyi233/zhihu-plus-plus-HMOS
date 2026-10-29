import { parseAbsoluteUrl, ParsedAbsoluteUrl } from 'core';
import {
  ReaderBlock,
  ReaderBlockKind,
  ReaderInlineRun,
  readerAttributeValue,
  readerDecodeHtml,
  readerInlineRuns,
  readerLinkCardDisplayUrl,
  readerNormalizeLinkHref,
  readerPlainText,
  readerPreferredImageSource
} from './ReaderDocument';
import { trustedReaderImageUrl } from './ReaderImageSourcePolicy';

/**
 * 知乎日报正文（`daily.zhihu.com/api/7/story/{id}` 的 `body`）原生适配。
 *
 * 与普通回答/文章正文的差别（以 [9793572] 样本为准）：
 * - 外层是 `div.main-wrap > div.content-inner`，内部按 `div.question` 分组，
 *   每组 = `h2.question-title` + `div.answer`（`div.meta` 作者 + `div.content` 正文）；
 * - `div.meta` 里的 `img.avatar` 是作者头像，不是正文图，不能进入图片块；
 * - 正文图可能在 `figure` 里（带 `figcaption`），也可能裸在段落之间；
 * - 推荐阅读卡片是 `div.RichText-LinkCardContainer > a.LinkCard`（大小写与普通正文不同），
 *   卡片内的封面 `img` 已被卡片消费，不能再输出为 IMAGE 块；
 * - 结尾可能有 `<p><br><br></p>` 空段与 `<script>`，都要丢弃。
 *
 * 本模块只做「日报方言 → 既有 Reader 块模型」的有界适配，复用 `parseZhihuHtml` 的行内样式、
 * 实体解码、图片源优选与链接归一化，不新写一整套 HTML5 解析器，也不改变普通正文解析行为。
 *
 * 稳定性：相同输入必须产生完全一致的块 ID 与顺序（块 ID 只由确定性的块序号构成），
 * 便于阅读锚点按块身份恢复。
 */

/** 转换完整性：调用方据此决定 READY / PARTIAL / UNSUPPORTED。 */
export enum DailyStoryCompleteness {
  /** 全部可识别内容都转换成了受支持块。 */
  COMPLETE = 'complete',
  /** 可读，但有明确未支持/降级内容（仍应展示，并就地提示）。 */
  PARTIAL = 'partial',
  /** 无可展示内容或超出预算，无法可靠转换。 */
  UNSUPPORTED = 'unsupported'
}

/** 受限诊断码：不记录正文，只记可枚举的问题类别。 */
export enum DailyStoryDiagnosticCode {
  /** body 缺失或为空。 */
  EMPTY_BODY = 'empty_body',
  /** 超出标签 token / 嵌套深度 / 块与 run 预算。 */
  BUDGET_EXCEEDED = 'budget_exceeded',
  /** 未知或不支持的结构（table/iframe/音视频等）。 */
  UNSUPPORTED_ELEMENT = 'unsupported_element',
  /** script/style/template 被丢弃（正常，但记录以便排查「内容缺失」）。 */
  DROPPED_SCRIPT = 'dropped_script',
  /** 图片地址不可信或缺失，已降级为说明文本。 */
  IMAGE_DROPPED = 'image_dropped',
  /** 链接目标不安全/不可用，已降级为不可点击文本。 */
  LINK_DROPPED = 'link_dropped',
  /** 图片被推荐卡片消费（信息性：避免误判「图片丢失」）。 */
  IMAGE_CONSUMED = 'image_consumed'
}

export interface DailyStoryDiagnostic {
  code: DailyStoryDiagnosticCode;
  /** 出现的次数（同一码聚合，不展开整篇正文）。 */
  count: number;
}

export interface DailyStoryStats {
  blockCount: number;
  textLength: number;
  headingCount: number;
  imageCount: number;
  linkCardCount: number;
  quoteBlockCount: number;
  /** 识别到的问题/回答分组数（保留顺序，不合并）。 */
  sectionCount: number;
  /** 不计入正文的作者头像数量（诊断用）。 */
  avatarCount: number;
  /** 丢弃的空占位图（`img-place-holder`）数量。 */
  placeholderCount: number;
}

/** 内容节作者信息：只展示确认的文本，不伪造可屏蔽的用户 ID。 */
export interface DailyStoryAuthorSection {
  /** 作者展示名（`span.author`），可能为空串。 */
  authorName: string;
  /** 作者一句话简介（`span.bio`），可能为空串；作为次级文本展示，不参与屏蔽匹配。 */
  authorBio: string;
  /** 作者头像（已过图片政策校验），空串表示无；只用于作者行，不计入正文图集。 */
  authorAvatarUrl: string;
  /** 作者链接（已校验的站内链接），空串表示无。 */
  authorUrl: string;
  /** 问题标题（`h2.question-title`），可能为空串。 */
  questionTitle: string;
  /** 该节在 blocks 中的起始下标（含）。 */
  blockStart: number;
  /** 该节在 blocks 中的结束下标（不含）。 */
  blockEnd: number;
}

export interface DailyStoryParseResult {
  blocks: Array<ReaderBlock>;
  stats: DailyStoryStats;
  diagnostics: Array<DailyStoryDiagnostic>;
  completeness: DailyStoryCompleteness;
  /** 每个内容节的作者信息（按出现顺序）。 */
  sections: Array<DailyStoryAuthorSection>;
}

/** 预算：与计划 §5.3 初值一致，可在设备测量后调整（不是平台限制）。 */
export const DAILY_STORY_MAX_TAG_TOKENS: number = 5000;
export const DAILY_STORY_MAX_NESTING_DEPTH: number = 32;
export const DAILY_STORY_MAX_BLOCKS: number = 2000;
export const DAILY_STORY_MAX_INLINE_RUNS: number = 10000;
const DAILY_STORY_MAX_DIAGNOSTICS: number = 50;

/** 内联标签：原样保留进文本缓冲，由共享行内解析处理样式与链接。 */
const INLINE_TAGS: Array<string> = [
  'a', 'b', 'strong', 'i', 'em', 'del', 's', 'strike', 'code', 'kbd', 'mark', 'sub', 'sup', 'span', 'br'
];

/** 完全丢弃内容的标签（其中内容是脚本/样式，不能变成可见文本）。 */
const DROPPED_CONTENT_TAGS: Array<string> = ['script', 'style', 'template', 'noscript'];

/** 记录为「不支持但保留可读摘要」的标签。 */
const UNSUPPORTED_TAGS: Array<string> = [
  'table', 'thead', 'tbody', 'tr', 'td', 'th', 'iframe', 'video', 'audio', 'object', 'embed', 'canvas', 'svg'
];

/** 无闭合标签的元素：不参与配对。 */
const VOID_TAGS: Array<string> = ['img', 'br', 'hr', 'input', 'meta', 'link', 'area', 'base', 'col', 'source', 'track', 'wbr'];

interface AttributeMap {
  classTokens: Array<string>;
  href: string;
  src: string;
  alt: string;
  draftCover: string;
}

interface HtmlToken {
  /** 起始标签名（小写）；闭合标签为空串。 */
  name: string;
  closing: boolean;
  selfClosing: boolean;
  /** 原始标签串（含 `<` `>`）。 */
  raw: string;
  attributes: AttributeMap;
  /** 在源串中的起始偏移。 */
  start: number;
  /** 在源串中的结束偏移（不含）。 */
  end: number;
}

interface DiagnosticCounter {
  counts: Map<DailyStoryDiagnosticCode, number>;
  overflow: number;
}

function emptyDiagnostics(): DiagnosticCounter {
  return { counts: new Map<DailyStoryDiagnosticCode, number>(), overflow: 0 };
}

function noteDiagnostic(counter: DiagnosticCounter, code: DailyStoryDiagnosticCode, times: number = 1): void {
  const previous = counter.counts.get(code) ?? 0;
  if (previous === 0 && counter.counts.size >= DAILY_STORY_MAX_DIAGNOSTICS) {
    counter.overflow += times;
    return;
  }
  counter.counts.set(code, previous + times);
}

function diagnosticsOf(counter: DiagnosticCounter): Array<DailyStoryDiagnostic> {
  const result: Array<DailyStoryDiagnostic> = [];
  counter.counts.forEach((count: number, code: DailyStoryDiagnosticCode): void => {
    if (count > 0) {
      result.push({ code: code, count: count });
    }
  });
  if (counter.overflow > 0) {
    result.push({ code: DailyStoryDiagnosticCode.UNSUPPORTED_ELEMENT, count: counter.overflow });
  }
  return result;
}

function emptyAttributes(): AttributeMap {
  return { classTokens: [], href: '', src: '', alt: '', draftCover: '' };
}

function attributeMapOf(tag: string): AttributeMap {
  const className = readerAttributeValue(tag, 'class');
  return {
    classTokens: className.split(/\s+/).filter((token: string): boolean => token.length > 0),
    href: readerAttributeValue(tag, 'href'),
    src: readerAttributeValue(tag, 'src'),
    alt: readerAttributeValue(tag, 'alt'),
    draftCover: readerAttributeValue(tag, 'data-draft-cover')
  };
}

function hasClass(attributes: AttributeMap, token: string): boolean {
  return attributes.classTokens.includes(token);
}

/** class token 大小写不敏感匹配（日报混用了 `LinkCard` 与 `link-card`）。 */
function hasClassIgnoreCase(attributes: AttributeMap, token: string): boolean {
  const target = token.toLowerCase();
  return attributes.classTokens.some((candidate: string): boolean => candidate.toLowerCase() === target);
}

/**
 * 有界 token 扫描：单遍线性扫描，识别标签/注释。
 *
 * - 处理单双引号、无引号属性、属性内 `>`、自闭合与缺失闭合；
 * - 注释整体跳过（既不是文本也不是标签）；
 * - 超预算返回 undefined，由调用方进入不支持态，不做半篇渲染。
 */
function tokenize(html: string): Array<HtmlToken> | undefined {
  const tokens: Array<HtmlToken> = [];
  let index = 0;
  let depth = 0;
  while (index < html.length) {
    const open = html.indexOf('<', index);
    if (open < 0) {
      break;
    }
    if (html.startsWith('<!--', open)) {
      const close = html.indexOf('-->', open + 4);
      index = close < 0 ? html.length : close + 3;
      continue;
    }
    const closing = html.charAt(open + 1) === '/';
    const nameStart = closing ? open + 2 : open + 1;
    const nameMatch = /^[a-zA-Z][a-zA-Z0-9:-]*/.exec(html.slice(nameStart, nameStart + 32));
    if (nameMatch === null) {
      index = open + 1;
      continue;
    }
    const name = nameMatch[0].toLowerCase();
    let cursor = nameStart + nameMatch[0].length;
    let quote = '';
    let closed = false;
    while (cursor < html.length) {
      const character = html.charAt(cursor);
      if (quote.length > 0) {
        if (character === quote) {
          quote = '';
        }
      } else if (character === '"' || character === '\'') {
        quote = character;
      } else if (character === '>') {
        closed = true;
        break;
      }
      cursor += 1;
    }
    if (!closed) {
      // 缺失闭合：跳过这个 `<`，余下内容按文本处理。
      index = open + 1;
      continue;
    }
    if (tokens.length >= DAILY_STORY_MAX_TAG_TOKENS) {
      return undefined;
    }
    const raw = html.slice(open, cursor + 1);
    const selfClosing = /\/\s*>$/.test(raw);
    if (!closing && !selfClosing && !VOID_TAGS.includes(name)) {
      depth += 1;
      if (depth > DAILY_STORY_MAX_NESTING_DEPTH) {
        return undefined;
      }
    } else if (closing) {
      depth = Math.max(0, depth - 1);
    }
    tokens.push({
      name: closing ? '' : name,
      closing: closing,
      selfClosing: selfClosing,
      raw: raw,
      attributes: closing ? emptyAttributes() : attributeMapOf(raw),
      start: open,
      end: cursor + 1
    });
    index = cursor + 1;
  }
  return tokens;
}

function emptyStats(): DailyStoryStats {
  return {
    blockCount: 0,
    textLength: 0,
    headingCount: 0,
    imageCount: 0,
    linkCardCount: 0,
    quoteBlockCount: 0,
    sectionCount: 0,
    avatarCount: 0,
    placeholderCount: 0
  };
}

/** 解析上下文：块构建 + 诊断 + 统计计数器。 */
class DailyStoryBuilder {
  readonly blocks: Array<ReaderBlock> = [];
  readonly diagnostics: DiagnosticCounter = emptyDiagnostics();
  readonly sections: Array<DailyStoryAuthorSection> = [];
  quoteDepth: number = 0;
  buffer: string = '';
  avatarCount: number = 0;
  placeholderCount: number = 0;
  budgetExceeded: boolean = false;
  private nextIndex: number = 0;
  private inlineRunCount: number = 0;

  nextId(): string {
    const id = `daily-block-${this.nextIndex}`;
    return id;
  }

  push(block: ReaderBlock): void {
    if (this.blocks.length >= DAILY_STORY_MAX_BLOCKS) {
      this.budgetExceeded = true;
      return;
    }
    block.quoteDepth = Math.max(0, Math.min(this.quoteDepth, 8));
    this.blocks.push(block);
    this.nextIndex += 1;
    this.inlineRunCount += block.inlineRuns.length;
    if (this.inlineRunCount > DAILY_STORY_MAX_INLINE_RUNS) {
      this.budgetExceeded = true;
    }
  }

  /** 文本缓冲落块：以当前缓冲构造段落（保留行内样式与链接），空文本丢弃。 */
  flush(): void {
    const raw = this.buffer;
    this.buffer = '';
    if (raw.trim().length === 0) {
      return;
    }
    const text = readerPlainText(raw);
    if (text.length === 0) {
      return;
    }
    const blockId = this.nextId();
    const runs: Array<ReaderInlineRun> = readerInlineRuns(raw, blockId);
    this.push({ id: blockId, kind: ReaderBlockKind.PARAGRAPH, text: text, sourceUrl: '', inlineRuns: runs });
  }

  currentSection(): DailyStoryAuthorSection | undefined {
    return this.sections.length === 0 ? undefined : this.sections[this.sections.length - 1];
  }

  beginSection(): void {
    this.flush();
    const current = this.currentSection();
    if (current !== undefined) {
      current.blockEnd = this.blocks.length;
    }
    this.sections.push({
      authorName: '',
      authorBio: '',
      authorAvatarUrl: '',
      authorUrl: '',
      questionTitle: '',
      blockStart: this.blocks.length,
      blockEnd: this.blocks.length
    });
  }

  finish(): void {
    this.flush();
    const current = this.currentSection();
    if (current !== undefined) {
      current.blockEnd = this.blocks.length;
    }
  }
}

/** 取标签内部 HTML（用于复算行内 run）。 */
function innerHtmlOf(fragment: string): string {
  const start = fragment.indexOf('>');
  const end = fragment.lastIndexOf('</');
  return start >= 0 && end > start ? fragment.slice(start + 1, end) : '';
}

/** 在 tokens 中查找同名起始标签的配对闭合下标；找不到返回 tokens.length。 */
function matchingCloseIndex(tokens: Array<HtmlToken>, startIndex: number, name: string): number {
  let depth = 1;
  for (let index = startIndex + 1; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token.closing && nameOfCloseToken(tokens, index) === name) {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    } else if (!token.closing && token.name === name && !token.selfClosing) {
      depth += 1;
    }
  }
  return tokens.length;
}

/** 闭合标签的标签名：tokenize 把闭合标签的 name 置空，这里从 raw 还原。 */
function nameOfCloseToken(tokens: Array<HtmlToken>, index: number): string {
  const token = tokens[index];
  if (!token.closing) {
    return token.name;
  }
  const match = /^<\/\s*([a-zA-Z][a-zA-Z0-9:-]*)/.exec(token.raw);
  return match === null ? '' : match[1].toLowerCase();
}

/** 区间原始 HTML：从 opening 的 `>` 之后到 closing 的 `<` 之前。 */
function regionInnerHtml(html: string, tokens: Array<HtmlToken>, openIndex: number,
  closeIndex: number): string {
  const start = tokens[openIndex].end;
  const end = closeIndex < tokens.length ? tokens[closeIndex].start : html.length;
  return end > start ? html.slice(start, end) : '';
}

/** 区间完整原始 HTML（含起始与闭合标签）。 */
function regionFullHtml(html: string, tokens: Array<HtmlToken>, openIndex: number,
  closeIndex: number): string {
  const start = tokens[openIndex].start;
  const end = closeIndex < tokens.length ? tokens[closeIndex].end : html.length;
  return end > start ? html.slice(start, end) : '';
}

/** 从区间内提取第一个匹配标签的原始标签串。 */
function firstTagIn(fragment: string, pattern: RegExp): string {
  const match = fragment.match(pattern);
  return match === null ? '' : match[0];
}

/** 从区间内提取 figcaption 文本（可能为空）。 */
function figcaptionText(fragment: string): string {
  const match = /<figcaption\b[^>]*>([\s\S]*?)<\/figcaption>/i.exec(fragment);
  return match === null ? '' : readerPlainText(match[1]).trim();
}

/** 推荐卡片标题（`span.LinkCard-title` 等），回退到卡片内纯文本。 */
function linkCardTitle(fragment: string): string {
  const spanMatch = /<span\b[^>]*class\s*=\s*(["'])([^"']*)\1[^>]*>([\s\S]*?)<\/span>/gi;
  let match: RegExpExecArray | null = spanMatch.exec(fragment);
  while (match !== null) {
    const classes = match[2].split(/\s+/).some((token: string): boolean => token.toLowerCase() === 'linkcard-title');
    if (classes) {
      const text = readerPlainText(match[3]).trim();
      if (text.length > 0) {
        return text;
      }
    }
    match = spanMatch.exec(fragment);
  }
  return readerPlainText(fragment).trim();
}

/** 作者信息（`span.author` / `span.bio`）与作者链接（`a.UserLink-link` / 首个站内 a）。 */
function metaAuthor(metaHtml: string): MetaAuthor {
  let authorName = '';
  let authorBio = '';
  const spanMatch = /<span\b[^>]*class\s*=\s*(["'])([^"']*)\1[^>]*>([\s\S]*?)<\/span>/gi;
  let match: RegExpExecArray | null = spanMatch.exec(metaHtml);
  while (match !== null) {
    const tokens = match[2].split(/\s+/);
    if (tokens.includes('author') && authorName.length === 0) {
      authorName = readerPlainText(match[3]).trim();
    } else if (tokens.includes('bio') && authorBio.length === 0) {
      authorBio = readerPlainText(match[3]).trim();
    }
    match = spanMatch.exec(metaHtml);
  }
  let authorUrl = '';
  const anchorPattern = /<a\b[^>]*>/gi;
  let anchor: RegExpExecArray | null = anchorPattern.exec(metaHtml);
  while (anchor !== null) {
    // `a.originUrl[hidden]` 是「查看知乎原文」隐藏链接，不是作者主页。
    if (!hasClassIgnoreCase(attributeMapOf(anchor[0]), 'originurl')) {
      const href = readerNormalizeLinkHref(readerAttributeValue(anchor[0], 'href'));
      if (href.length > 0 && isSafeHref(href)) {
        authorUrl = href;
        break;
      }
    }
    anchor = anchorPattern.exec(metaHtml);
  }
  return { authorName: authorName, authorBio: authorBio, authorUrl: authorUrl };
}

interface MetaAuthor {
  authorName: string;
  authorBio: string;
  authorUrl: string;
}

/** 链接是否可作为点击目标（https/http、无用户信息）。 */
function isSafeHref(value: string): boolean {
  const parsed: ParsedAbsoluteUrl | undefined = parseAbsoluteUrl(value);
  return parsed !== undefined && (parsed.protocol === 'https:' || parsed.protocol === 'http:') &&
    !parsed.hasUserInfo;
}

/**
 * 日报正文解析入口。
 *
 * 输入是不可信 HTML；输出固定顺序的语义块 + 统计 + 诊断 + 完整性。
 * 预算越界或无可展示内容时返回空 blocks 与 UNSUPPORTED，调用方据此进入不支持态。
 */
export function parseDailyStoryHtml(html: string): DailyStoryParseResult {
  const builder = new DailyStoryBuilder();
  if (html.trim().length === 0) {
    noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.EMPTY_BODY);
    return unsupportedResult(builder);
  }
  const tokens = tokenize(html);
  if (tokens === undefined) {
    noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.BUDGET_EXCEEDED);
    return unsupportedResult(builder);
  }
  walk(html, tokens, builder);
  builder.finish();
  if (builder.budgetExceeded) {
    noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.BUDGET_EXCEEDED);
    return unsupportedResult(builder);
  }
  return {
    blocks: builder.blocks,
    stats: statsOf(builder),
    diagnostics: diagnosticsOf(builder.diagnostics),
    completeness: classify(builder),
    sections: builder.sections
  };
}

function unsupportedResult(builder: DailyStoryBuilder): DailyStoryParseResult {
  return {
    blocks: [],
    stats: emptyStats(),
    diagnostics: diagnosticsOf(builder.diagnostics),
    completeness: DailyStoryCompleteness.UNSUPPORTED,
    sections: []
  };
}

function statsOf(builder: DailyStoryBuilder): DailyStoryStats {
  let textLength = 0;
  let headingCount = 0;
  let imageCount = 0;
  let linkCardCount = 0;
  let quoteBlockCount = 0;
  builder.blocks.forEach((block: ReaderBlock): void => {
    textLength += block.text.length;
    headingCount += block.kind === ReaderBlockKind.HEADING ? 1 : 0;
    imageCount += block.kind === ReaderBlockKind.IMAGE ? 1 : 0;
    linkCardCount += block.kind === ReaderBlockKind.LINK_CARD ? 1 : 0;
    quoteBlockCount += (block.quoteDepth ?? 0) > 0 ? 1 : 0;
  });
  return {
    blockCount: builder.blocks.length,
    textLength: textLength,
    headingCount: headingCount,
    imageCount: imageCount,
    linkCardCount: linkCardCount,
    quoteBlockCount: quoteBlockCount,
    sectionCount: builder.sections.length,
    avatarCount: builder.avatarCount,
    placeholderCount: builder.placeholderCount
  };
}

/**
 * 完整性判定：只有「有可展示内容」才可能通过。
 * 纯图正文（只有 IMAGE 块、无文本）也是有效内容，不能只用 textLength 判断。
 */
function classify(builder: DailyStoryBuilder): DailyStoryCompleteness {
  const hasContent = builder.blocks.some((block: ReaderBlock): boolean =>
    block.kind === ReaderBlockKind.IMAGE || block.kind === ReaderBlockKind.LINK_CARD || block.text.length > 0);
  if (!hasContent) {
    return DailyStoryCompleteness.UNSUPPORTED;
  }
  let partial = false;
  builder.diagnostics.counts.forEach((count: number, code: DailyStoryDiagnosticCode): void => {
    if (count <= 0) {
      return;
    }
    if (code === DailyStoryDiagnosticCode.UNSUPPORTED_ELEMENT ||
      code === DailyStoryDiagnosticCode.IMAGE_DROPPED ||
      code === DailyStoryDiagnosticCode.LINK_DROPPED) {
      partial = true;
    }
  });
  return partial ? DailyStoryCompleteness.PARTIAL : DailyStoryCompleteness.COMPLETE;
}

/** 单遍扫描：按结构单元（标题/引用/图片/卡片/meta/脚本体）跳过或成块，其余文本进缓冲。 */
function walk(html: string, tokens: Array<HtmlToken>, builder: DailyStoryBuilder): void {
  let index = 0;
  // cursor 始终指向「尚未消费的源串位置」：每个分支都必须把中间文本交给缓冲。
  let cursor = 0;
  // 被判定为「行内容器」的 div 的闭合 token 下标：其闭合标签按行内处理（不落段）。
  const inlineClosings: Set<number> = new Set<number>();

  /** 把 [cursor, boundary) 之间的源串并入文本缓冲（纯空白折叠为一个空格）。 */
  const takeTextUntil = (boundary: number): void => {
    if (boundary <= cursor) {
      return;
    }
    const text = html.slice(cursor, boundary);
    cursor = boundary;
    if (text.length === 0) {
      return;
    }
    if (text.trim().length > 0) {
      builder.buffer += text;
    } else if (builder.buffer.length > 0) {
      builder.buffer += ' ';
    }
  };

  /**
   * 跳到某个 token 之后：cursor 停在被消费区间的末尾（闭合标签之后），
   * 这样紧跟其后的普通文本（如 `</figure>` 与下一个 `<a>` 之间的「Q：」）不会丢。
   */
  const skipTo = (nextIndex: number): void => {
    index = nextIndex;
    if (nextIndex >= tokens.length) {
      cursor = html.length;
    } else if (nextIndex > 0) {
      cursor = tokens[nextIndex - 1].end;
    }
  };

  while (index < tokens.length) {
    if (builder.budgetExceeded) {
      return;
    }
    const token = tokens[index];
    if (token.closing) {
      takeTextUntil(token.start);
      const closingName = nameOfCloseToken(tokens, index);
      if (inlineClosings.has(index)) {
        // 行内容器的闭合：保留标签，交给共享行内解析（plainText 会剥掉标签）。
        builder.buffer += token.raw;
        cursor = token.end;
        index += 1;
        continue;
      }
      if (closingName === 'blockquote') {
        builder.flush();
        builder.quoteDepth = Math.max(0, builder.quoteDepth - 1);
      } else if (INLINE_TAGS.includes(closingName)) {
        // 行内标签闭合：必须与起始标签配对写入缓冲，否则行内样式/链接会延续到段尾。
        builder.buffer += token.raw;
        cursor = token.end;
        index += 1;
        continue;
      } else if (BLOCK_BOUNDARY_TAGS.includes(closingName)) {
        builder.flush();
      }
      cursor = token.end;
      index += 1;
      continue;
    }

    const name = token.name;
    if (DROPPED_CONTENT_TAGS.includes(name)) {
      takeTextUntil(token.start);
      noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.DROPPED_SCRIPT);
      skipTo(matchingCloseIndex(tokens, index, name) + 1);
      continue;
    }
    if (UNSUPPORTED_TAGS.includes(name)) {
      takeTextUntil(token.start);
      const closeIndex = matchingCloseIndex(tokens, index, name);
      const region = regionFullHtml(html, tokens, index, closeIndex);
      noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.UNSUPPORTED_ELEMENT);
      builder.flush();
      const summary = readerPlainText(region).trim();
      if (summary.length > 0) {
        builder.push({
          id: builder.nextId(),
          kind: ReaderBlockKind.PARAGRAPH,
          text: summary,
          sourceUrl: '',
          inlineRuns: []
        });
      }
      skipTo(closeIndex + 1);
      continue;
    }

    if (name === 'div' && hasClass(token.attributes, 'question')) {
      takeTextUntil(token.start);
      builder.beginSection();
      skipTo(index + 1);
      continue;
    }
    if (name === 'div' && hasClass(token.attributes, 'meta')) {
      takeTextUntil(token.start);
      const closeIndex = matchingCloseIndex(tokens, index, 'div');
      applyMeta(regionInnerHtml(html, tokens, index, closeIndex), builder);
      skipTo(closeIndex + 1);
      continue;
    }
    if (name === 'div' && hasClassIgnoreCase(token.attributes, 'view-more')) {
      // 页尾「查看知乎讨论」是导航入口，不是正文：阅读页用页尾按钮承接它，
      // 留在正文里会变成一个孤立链接段，被误读成引用内容的一部分。
      takeTextUntil(token.start);
      builder.flush();
      skipTo(matchingCloseIndex(tokens, index, 'div') + 1);
      continue;
    }
    if (name === 'div' && hasClass(token.attributes, 'img-place-holder')) {
      takeTextUntil(token.start);
      builder.placeholderCount += 1;
      skipTo(matchingCloseIndex(tokens, index, 'div') + 1);
      continue;
    }
    if (name === 'div' && hasClassIgnoreCase(token.attributes, 'RichText-LinkCardContainer')) {
      takeTextUntil(token.start);
      const closeIndex = matchingCloseIndex(tokens, index, 'div');
      emitLinkCard(regionFullHtml(html, tokens, index, closeIndex), builder);
      skipTo(closeIndex + 1);
      continue;
    }
    if (name === 'figure') {
      takeTextUntil(token.start);
      const closeIndex = matchingCloseIndex(tokens, index, 'figure');
      emitFigure(regionFullHtml(html, tokens, index, closeIndex), builder);
      skipTo(closeIndex + 1);
      continue;
    }
    if (name === 'blockquote') {
      takeTextUntil(token.start);
      builder.flush();
      builder.quoteDepth += 1;
      cursor = token.end;
      index += 1;
      continue;
    }
    if (name === 'hr') {
      takeTextUntil(token.start);
      builder.flush();
      builder.push({ id: builder.nextId(), kind: ReaderBlockKind.DIVIDER, text: '', sourceUrl: '', inlineRuns: [] });
      cursor = token.end;
      index += 1;
      continue;
    }
    if (/^h[1-6]$/.test(name)) {
      takeTextUntil(token.start);
      const closeIndex = matchingCloseIndex(tokens, index, name);
      const inner = regionInnerHtml(html, tokens, index, closeIndex);
      const full = regionFullHtml(html, tokens, index, closeIndex);
      builder.flush();
      emitHeading(full, inner, builder);
      const section = builder.currentSection();
      if (hasClass(token.attributes, 'question-title') && section !== undefined &&
        section.questionTitle.length === 0) {
        section.questionTitle = readerPlainText(full).trim();
      }
      skipTo(closeIndex + 1);
      continue;
    }
    if (name === 'img') {
      takeTextUntil(token.start);
      emitImageToken(token, builder);
      cursor = token.end;
      index += 1;
      continue;
    }
    if (name === 'a' && hasClassIgnoreCase(token.attributes, 'linkcard')) {
      takeTextUntil(token.start);
      const closeIndex = matchingCloseIndex(tokens, index, 'a');
      emitLinkCard(regionFullHtml(html, tokens, index, closeIndex), builder);
      skipTo(closeIndex + 1);
      continue;
    }
    if (token.selfClosing) {
      takeTextUntil(token.start);
      cursor = token.end;
      index += 1;
      continue;
    }
    if (INLINE_TAGS.includes(name)) {
      // 行内标签原样进入文本缓冲：保留 <a href> / <b> 等语义，由共享行内解析处理。
      takeTextUntil(token.start);
      builder.buffer += token.raw;
      cursor = token.end;
      index += 1;
      continue;
    }
    if (name === 'div') {
      const closeIndex = matchingCloseIndex(tokens, index, 'div');
      if (closeIndex < tokens.length && isInlineContainer(html, tokens, index, closeIndex)) {
        // 只含行内内容的 div（如日报的 `div.css-1gomreu` 用户名容器）：不落段，
        // 否则「@作者」与紧随其后的回答正文会被拆成两块，用户读到的引用会断开。
        takeTextUntil(token.start);
        builder.buffer += token.raw;
        inlineClosings.add(closeIndex);
        cursor = token.end;
        index += 1;
        continue;
      }
    }
    // 其他块级/未知容器：结束当前段落，子内容继续按文本处理（保留可读内容）。
    takeTextUntil(token.start);
    builder.flush();
    cursor = token.end;
    index += 1;
  }
  takeTextUntil(html.length);
}

/** 区间内是否只含行内内容（无块级标签），用于把「用户名容器」等 div 按行内处理。 */
function isInlineContainer(html: string, tokens: Array<HtmlToken>, openIndex: number,
  closeIndex: number): boolean {
  for (let index = openIndex + 1; index < closeIndex; index += 1) {
    const token = tokens[index];
    if (token.closing) {
      continue;
    }
    if (BLOCK_BOUNDARY_TAGS.includes(token.name) || token.name === 'figure' || token.name === 'blockquote' ||
      token.name === 'hr' || /^h[1-6]$/.test(token.name) || token.name === 'img' || token.name === 'table' ||
      token.name === 'ul' || token.name === 'ol') {
      return false;
    }
  }
  return true;
}

/** 触发段落边界（结束当前文本缓冲）的容器标签。 */
const BLOCK_BOUNDARY_TAGS: Array<string> = [
  'div', 'p', 'li', 'section', 'article', 'header', 'footer', 'figcaption', 'pre', 'ul', 'ol', 'main'
];

function applyMeta(metaHtml: string, builder: DailyStoryBuilder): void {
  // 头像只计数，不进入正文图片列表。
  const avatarPattern = /<img\b[^>]*>/gi;
  let match: RegExpExecArray | null = avatarPattern.exec(metaHtml);
  while (match !== null) {
    if (!hasClass(attributeMapOf(match[0]), 'img-place-holder')) {
      builder.avatarCount += 1;
    }
    match = avatarPattern.exec(metaHtml);
  }
  const author = metaAuthor(metaHtml);
  const avatarTag = firstTagIn(metaHtml, /<img\b[^>]*>/i);
  const avatarUrl = avatarTag.length > 0
    ? trustedReaderImageUrl(readerPreferredImageSource(avatarTag) ||
      readerDecodeHtml(readerAttributeValue(avatarTag, 'src')))
    : '';
  const section = builder.currentSection();
  if (section === undefined) {
    return;
  }
  if (section.authorName.length === 0 && author.authorName.length > 0) {
    section.authorName = author.authorName;
  }
  if (section.authorBio.length === 0 && author.authorBio.length > 0) {
    section.authorBio = author.authorBio;
  }
  if (section.authorAvatarUrl.length === 0 && avatarUrl.length > 0) {
    section.authorAvatarUrl = avatarUrl;
  }
  if (section.authorUrl.length === 0 && author.authorUrl.length > 0) {
    section.authorUrl = author.authorUrl;
  }
}

function emitHeading(fullHtml: string, innerHtml: string, builder: DailyStoryBuilder): void {
  const text = readerPlainText(fullHtml);
  if (text.length === 0) {
    return;
  }
  const blockId = builder.nextId();
  builder.push({
    id: blockId,
    kind: ReaderBlockKind.HEADING,
    text: text,
    sourceUrl: '',
    inlineRuns: readerInlineRuns(innerHtml, blockId)
  });
}

function emitImageToken(token: HtmlToken, builder: DailyStoryBuilder): void {
  if (hasClass(token.attributes, 'img-place-holder')) {
    builder.placeholderCount += 1;
    return;
  }
  if (hasClass(token.attributes, 'avatar')) {
    builder.avatarCount += 1;
    return;
  }
  const eeimg = readerAttributeValue(token.raw, 'eeimg');
  if (eeimg === '1' || eeimg === '2') {
    // 行内公式/独立公式：交给既有公式渲染（独立公式成块，行内公式留在段落 run 中）。
    const tex = readerDecodeHtml(token.attributes.alt).trim();
    if (tex.length > 0) {
      builder.flush();
      builder.push({
        id: builder.nextId(),
        kind: ReaderBlockKind.FORMULA,
        text: tex,
        sourceUrl: '',
        inlineRuns: []
      });
    }
    return;
  }
  const candidate = readerPreferredImageSource(token.raw) || readerDecodeHtml(token.attributes.src);
  builder.flush();
  pushImageBlock(builder, candidate, '', readerDecodeHtml(token.attributes.alt).trim());
}

function emitFigure(figureHtml: string, builder: DailyStoryBuilder): void {
  const imageTag = firstTagIn(figureHtml, /<img\b[^>]*>/i);
  const caption = figcaptionText(figureHtml);
  const alt = imageTag.length > 0 ? readerDecodeHtml(readerAttributeValue(imageTag, 'alt')).trim() : '';
  builder.flush();
  if (imageTag.length === 0) {
    if (caption.length > 0) {
      builder.push({
        id: builder.nextId(),
        kind: ReaderBlockKind.PARAGRAPH,
        text: caption,
        sourceUrl: '',
        inlineRuns: []
      });
    }
    return;
  }
  if (hasClass(attributeMapOf(imageTag), 'avatar')) {
    builder.avatarCount += 1;
    return;
  }
  const candidate = readerPreferredImageSource(imageTag) || readerDecodeHtml(readerAttributeValue(imageTag, 'src'));
  pushImageBlock(builder, candidate, caption, alt);
}

/**
 * 图片块：只接受可信图床 URL；不可信时用图注/alt 降级为段落说明（不静默丢弃）。
 * 图注（figcaption）优先作为块 text，与既有 `ReaderImageBlock` 的图注能力对齐，不新增 caption 字段。
 */
function pushImageBlock(builder: DailyStoryBuilder, candidate: string, caption: string, altText: string): void {
  const trusted = trustedReaderImageUrl(candidate);
  if (trusted.length === 0) {
    noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.IMAGE_DROPPED);
    const fallback = caption.length > 0 ? caption : altText;
    if (fallback.length > 0) {
      builder.push({
        id: builder.nextId(),
        kind: ReaderBlockKind.PARAGRAPH,
        text: fallback,
        sourceUrl: '',
        inlineRuns: []
      });
    }
    return;
  }
  builder.push({
    id: builder.nextId(),
    kind: ReaderBlockKind.IMAGE,
    text: caption.length > 0 ? caption : altText,
    sourceUrl: trusted,
    inlineRuns: []
  });
}

/**
 * 推荐阅读卡片：`a` 携带 `class=LinkCard`（任意大小写）。
 * 目标地址走共享归一化与跳转包装展开；封面走共享图片政策；卡片内封面图只消费一次。
 */
function emitLinkCard(regionHtml: string, builder: DailyStoryBuilder): void {
  const anchor = firstTagIn(regionHtml, /<a\b[^>]*>/i);
  if (anchor.length === 0) {
    return;
  }
  const href = readerNormalizeLinkHref(readerAttributeValue(anchor, 'href'));
  if (href.length === 0 || !isSafeHref(href)) {
    noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.LINK_DROPPED);
    return;
  }
  const imageTag = firstTagIn(regionHtml, /<img\b[^>]*>/i);
  const coverCandidate = imageTag.length > 0
    ? (readerPreferredImageSource(imageTag) || readerDecodeHtml(readerAttributeValue(imageTag, 'src')))
    : readerDecodeHtml(readerAttributeValue(anchor, 'data-draft-cover'));
  if (imageTag.length > 0) {
    noteDiagnostic(builder.diagnostics, DailyStoryDiagnosticCode.IMAGE_CONSUMED);
  }
  const cover = trustedReaderImageUrl(coverCandidate);
  const title = linkCardTitle(regionHtml);
  builder.flush();
  builder.push({
    id: builder.nextId(),
    kind: ReaderBlockKind.LINK_CARD,
    text: title.length > 0 ? title : href,
    sourceUrl: href,
    // 展示地址去掉知乎跳转包装；点击目标仍是原始 href（与普通正文卡片口径一致）。
    displayUrl: readerLinkCardDisplayUrl(href),
    coverUrl: cover,
    inlineRuns: []
  });
}
