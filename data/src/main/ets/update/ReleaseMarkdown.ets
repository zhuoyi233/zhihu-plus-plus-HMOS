/**
 * Release 描述（GitHub Flavored Markdown 子集）的纯函数解析器。
 *
 * 覆盖本仓库发版说明实际使用的语法：标题（1-6 级）、段落（软换行按空格拼接）、
 * 无序/有序列表（支持缩进嵌套）、引用块（含 GitHub alert 标记如 `> [!IMPORTANT]`）、
 * 行内加粗/斜体/行内代码/链接/图片；其余语法（表格、围栏代码块等）按纯文本兜底。
 * 全部无副作用，便于 Hypium 单元测试覆盖；渲染端（WhatsNewPage）按扁平模型绘制，
 * 不做递归 @Builder。
 */

export enum ReleaseMarkdownBlockKind {
  HEADING = 'heading',
  PARAGRAPH = 'paragraph',
  LIST = 'list',
  BLOCKQUOTE = 'blockquote'
}

export enum ReleaseMarkdownSpanKind {
  TEXT = 'text',
  BOLD = 'bold',
  ITALIC = 'italic',
  CODE = 'code',
  LINK = 'link'
}

export interface ReleaseMarkdownSpan {
  kind: ReleaseMarkdownSpanKind;
  text: string;
  /** LINK 的目标地址，其余 kind 为空串。 */
  url: string;
}

export interface ReleaseMarkdownListItem {
  spans: ReleaseMarkdownSpan[];
  /** 缩进嵌套的子列表项。 */
  children: ReleaseMarkdownListItem[];
}

export interface ReleaseMarkdownBlock {
  kind: ReleaseMarkdownBlockKind;
  /** HEADING 层级 1..6，其余 kind 为 0。 */
  level: number;
  /** HEADING / PARAGRAPH 的行内内容。 */
  spans: ReleaseMarkdownSpan[];
  /** LIST 是否有序。 */
  ordered: boolean;
  /** LIST 有序起始编号（默认 1）。 */
  startNumber: number;
  /** LIST 顶层列表项。 */
  items: ReleaseMarkdownListItem[];
  /** BLOCKQUOTE 的 GitHub alert 类型（IMPORTANT/NOTE/TIP/WARNING/CAUTION），普通引用为空串。 */
  alert: string;
  /** BLOCKQUOTE 内部块。 */
  blocks: ReleaseMarkdownBlock[];
}

/** 渲染用的扁平列表行：嵌套子项展平后携带深度与（有序时）显示编号。 */
export interface ReleaseMarkdownListRow {
  spans: ReleaseMarkdownSpan[];
  /** 0 为顶层。 */
  depth: number;
  /** 有序列表的显示编号；无序列表为 0。 */
  number: number;
}

export interface ReleaseMarkdownDocument {
  blocks: ReleaseMarkdownBlock[];
}

function emptyBlock(kind: ReleaseMarkdownBlockKind): ReleaseMarkdownBlock {
  const block: ReleaseMarkdownBlock = {
    kind: kind,
    level: 0,
    spans: [],
    ordered: false,
    startNumber: 1,
    items: [],
    alert: '',
    blocks: []
  };
  return block;
}

function textSpan(text: string): ReleaseMarkdownSpan {
  const span: ReleaseMarkdownSpan = { kind: ReleaseMarkdownSpanKind.TEXT, text: text, url: '' };
  return span;
}

function styledSpan(kind: ReleaseMarkdownSpanKind, text: string): ReleaseMarkdownSpan {
  const span: ReleaseMarkdownSpan = { kind: kind, text: text, url: '' };
  return span;
}

function linkSpan(text: string, url: string): ReleaseMarkdownSpan {
  const span: ReleaseMarkdownSpan = { kind: ReleaseMarkdownSpanKind.LINK, text: text, url: url };
  return span;
}

function pushPlain(spans: ReleaseMarkdownSpan[], plain: string): void {
  if (plain.length > 0) {
    spans.push(textSpan(plain));
  }
}

function isWhitespaceChar(ch: string): boolean {
  return ch === ' ' || ch === '\t';
}

interface ListLineMatch {
  indent: number;
  ordered: boolean;
  number: number;
  text: string;
}

const BULLET_LIST_LINE = /^(\s*)[-*+]\s+(.*)$/;
const ORDERED_LIST_LINE = /^(\s*)(\d{1,9})[.)]\s+(.*)$/;
const HEADING_LINE = /^(#{1,6})\s+(.*?)\s*$/;
const HORIZONTAL_RULE_LINE = /^(?:-{3,}|\*{3,}|_{3,})\s*$/;
const ALERT_MARKER_LINE = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/i;

/** 行首缩进归一化：2-3 个空格算一层，4 个及以上再进一层（GitHub 发布说明常见 2 或 4 空格缩进）。 */
function normalizeListIndent(rawIndent: string): number {
  let spaces = 0;
  for (let index = 0; index < rawIndent.length; index += 1) {
    if (rawIndent.charAt(index) === '\t') {
      spaces += 2;
    } else {
      spaces += 1;
    }
  }
  if (spaces < 2) {
    return 0;
  }
  return Math.min(3, Math.floor(spaces / 2));
}

function matchListLine(line: string): ListLineMatch | undefined {
  const orderedMatch = ORDERED_LIST_LINE.exec(line);
  if (orderedMatch !== null) {
    const match: ListLineMatch = {
      indent: normalizeListIndent(orderedMatch[1]),
      ordered: true,
      number: Number(orderedMatch[2]),
      text: orderedMatch[3].trim()
    };
    return match;
  }
  const bulletMatch = BULLET_LIST_LINE.exec(line);
  if (bulletMatch !== null) {
    const match: ListLineMatch = {
      indent: normalizeListIndent(bulletMatch[1]),
      ordered: false,
      number: 0,
      text: bulletMatch[2].trim()
    };
    return match;
  }
  return undefined;
}

/**
 * 行内解析：行内代码（`x`）优先，其次加粗（**x**）、斜体（*x*，要求开闭内侧紧贴非空白）、
 * 链接与图片（[text](url) / ![alt](url)，图片降级为指向原图的链接）。未闭合的标记按纯文本保留。
 */
export function parseInlineSpans(text: string): ReleaseMarkdownSpan[] {
  const spans: ReleaseMarkdownSpan[] = [];
  let plain = '';
  let index = 0;
  while (index < text.length) {
    const ch = text.charAt(index);
    if (ch === '`') {
      const close = text.indexOf('`', index + 1);
      if (close > index + 1) {
        pushPlain(spans, plain);
        plain = '';
        spans.push(styledSpan(ReleaseMarkdownSpanKind.CODE, text.substring(index + 1, close)));
        index = close + 1;
        continue;
      }
    } else if (ch === '*') {
      if (text.charAt(index + 1) === '*') {
        const close = text.indexOf('**', index + 2);
        if (close > index + 2) {
          pushPlain(spans, plain);
          plain = '';
          spans.push(styledSpan(ReleaseMarkdownSpanKind.BOLD, text.substring(index + 2, close)));
          index = close + 2;
          continue;
        }
      } else if (!isWhitespaceChar(text.charAt(index + 1))) {
        const close = text.indexOf('*', index + 1);
        if (close > index + 1 && !isWhitespaceChar(text.charAt(close - 1))) {
          pushPlain(spans, plain);
          plain = '';
          spans.push(styledSpan(ReleaseMarkdownSpanKind.ITALIC, text.substring(index + 1, close)));
          index = close + 1;
          continue;
        }
      }
    } else if (ch === '[' || (ch === '!' && text.charAt(index + 1) === '[')) {
      const bracketStart = ch === '!' ? index + 1 : index;
      const isImage = ch === '!';
      const closeBracket = text.indexOf(']', bracketStart + 1);
      if (closeBracket > bracketStart + 1 && text.charAt(closeBracket + 1) === '(') {
        const closeParen = text.indexOf(')', closeBracket + 2);
        if (closeParen > closeBracket + 2) {
          const label = text.substring(bracketStart + 1, closeBracket);
          const url = text.substring(closeBracket + 2, closeParen);
          if (!/\s/.test(url)) {
            pushPlain(spans, plain);
            plain = '';
            spans.push(linkSpan(label.length > 0 ? label : url, url));
            index = closeParen + 1;
            continue;
          }
        }
      }
    }
    plain += ch;
    index += 1;
  }
  pushPlain(spans, plain);
  return spans;
}

function makeParagraph(text: string): ReleaseMarkdownBlock {
  const block = emptyBlock(ReleaseMarkdownBlockKind.PARAGRAPH);
  block.spans = parseInlineSpans(text);
  return block;
}

/** 解析一个行区间为块序列；`lines` 为原始行（blockquote 行已由调用方剥前缀的另行处理）。 */
function parseBlockLines(lines: string[], start: number, end: number): ReleaseMarkdownBlock[] {
  const blocks: ReleaseMarkdownBlock[] = [];
  let index = start;
  while (index < end) {
    const line = lines[index];
    const trimmed = line.trim();
    if (trimmed.length === 0 || HORIZONTAL_RULE_LINE.test(trimmed)) {
      index += 1;
      continue;
    }
    const headingMatch = HEADING_LINE.exec(trimmed);
    if (headingMatch !== null) {
      const heading = emptyBlock(ReleaseMarkdownBlockKind.HEADING);
      heading.level = headingMatch[1].length;
      heading.spans = parseInlineSpans(headingMatch[2]);
      blocks.push(heading);
      index += 1;
      continue;
    }
    if (trimmed.startsWith('>')) {
      let quoteEnd = index;
      while (quoteEnd < end && lines[quoteEnd].trim().startsWith('>')) {
        quoteEnd += 1;
      }
      blocks.push(parseBlockquoteLines(lines.slice(index, quoteEnd)));
      index = quoteEnd;
      continue;
    }
    if (matchListLine(line) !== undefined) {
      let listEnd = index;
      while (listEnd < end && lines[listEnd].trim().length > 0 && matchListLine(lines[listEnd]) !== undefined) {
        listEnd += 1;
      }
      blocks.push(parseListLines(lines.slice(index, listEnd)));
      index = listEnd;
      continue;
    }
    // 段落：连续普通行按空格拼接（GitHub 软换行语义）。
    let paragraphEnd = index;
    const paragraphLines: string[] = [];
    while (paragraphEnd < end) {
      const candidate = lines[paragraphEnd].trim();
      if (candidate.length === 0 || HEADING_LINE.test(candidate) || candidate.startsWith('>') ||
        HORIZONTAL_RULE_LINE.test(candidate) || matchListLine(lines[paragraphEnd]) !== undefined) {
        break;
      }
      paragraphLines.push(candidate);
      paragraphEnd += 1;
    }
    if (paragraphLines.length > 0) {
      blocks.push(makeParagraph(paragraphLines.join(' ')));
    }
    index = paragraphEnd;
  }
  return blocks;
}

function parseBlockquoteLines(quoteLines: string[]): ReleaseMarkdownBlock {
  const quote = emptyBlock(ReleaseMarkdownBlockKind.BLOCKQUOTE);
  const inner: string[] = [];
  quoteLines.forEach((line: string): void => {
    let content = line.trim().substring(1);
    if (content.startsWith(' ')) {
      content = content.substring(1);
    }
    inner.push(content);
  });
  if (inner.length > 0) {
    const marker = ALERT_MARKER_LINE.exec(inner[0].trim());
    if (marker !== null) {
      quote.alert = marker[1].toUpperCase();
      inner.shift();
    }
  }
  quote.blocks = parseBlockLines(inner, 0, inner.length);
  return quote;
}

interface ListLineEntry {
  indent: number;
  item: ReleaseMarkdownListItem;
}

/** 用缩进栈把连续列表行组装成嵌套列表块；混用有序/无序标记时以首行为准（防御性兜底）。 */
function parseListLines(listLines: string[]): ReleaseMarkdownBlock {
  const list = emptyBlock(ReleaseMarkdownBlockKind.LIST);
  const stack: ListLineEntry[] = [];
  let firstLine = true;
  listLines.forEach((line: string): void => {
    const match = matchListLine(line);
    if (match === undefined) {
      return;
    }
    if (firstLine) {
      list.ordered = match.ordered;
      list.startNumber = match.number > 0 ? match.number : 1;
      firstLine = false;
    }
    const item: ReleaseMarkdownListItem = { spans: parseInlineSpans(match.text), children: [] };
    while (stack.length > 0 && stack[stack.length - 1].indent >= match.indent) {
      stack.pop();
    }
    if (stack.length === 0) {
      list.items.push(item);
    } else {
      stack[stack.length - 1].item.children.push(item);
    }
    stack.push({ indent: match.indent, item: item });
  });
  return list;
}

/** 解析整段 Markdown 文本；空文本产出空文档。 */
export function parseReleaseMarkdown(body: string): ReleaseMarkdownDocument {
  const lines = body.replace(/\r\n/g, '\n').split('\n');
  const document: ReleaseMarkdownDocument = {
    blocks: parseBlockLines(lines, 0, lines.length)
  };
  return document;
}

/** 嵌套列表项展平为渲染行：子列表沿用同一标记类型，有序编号重新从 1 起算（同 GitHub）。 */
export function flattenReleaseMarkdownList(items: ReleaseMarkdownListItem[], ordered: boolean,
  startNumber: number): ReleaseMarkdownListRow[] {
  const rows: ReleaseMarkdownListRow[] = [];
  const walk = (level: ReleaseMarkdownListItem[], depth: number, orderedList: boolean,
    counterStart: number): void => {
    let counter = counterStart;
    level.forEach((item: ReleaseMarkdownListItem): void => {
      const row: ReleaseMarkdownListRow = { spans: item.spans, depth: depth, number: orderedList ? counter : 0 };
      rows.push(row);
      counter += 1;
      if (item.children.length > 0) {
        walk(item.children, depth + 1, orderedList, 1);
      }
    });
  };
  walk(items, 0, ordered, startNumber);
  return rows;
}

/** 引用块内部再嵌套引用时展开一层，避免渲染端递归 @Builder（发版说明不会出现，防御性兜底）。 */
export function flattenBlockquoteInner(quote: ReleaseMarkdownBlock): ReleaseMarkdownBlock[] {
  const result: ReleaseMarkdownBlock[] = [];
  quote.blocks.forEach((inner: ReleaseMarkdownBlock): void => {
    if (inner.kind === ReleaseMarkdownBlockKind.BLOCKQUOTE) {
      inner.blocks.forEach((deep: ReleaseMarkdownBlock): void => {
        result.push(deep);
      });
    } else {
      result.push(inner);
    }
  });
  return result;
}

/** GitHub alert 类型的中文短标签；普通引用返回空串。 */
export function releaseAlertLabel(alert: string): string {
  switch (alert.toUpperCase()) {
    case 'IMPORTANT':
      return '重要';
    case 'WARNING':
      return '注意';
    case 'CAUTION':
      return '警告';
    case 'NOTE':
      return '提示';
    case 'TIP':
      return '技巧';
    default:
      return '';
  }
}
