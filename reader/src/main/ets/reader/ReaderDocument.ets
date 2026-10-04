import { parseAbsoluteUrl } from 'core';
import { isTrustedFormulaUrl } from './FormulaSourcePolicy';

export enum ReaderBlockKind {
  HEADING,
  PARAGRAPH,
  DIVIDER,
  FORMULA,
  IMAGE,
  VIDEO,
  LIST_ITEM,
  REFERENCE,
  LINK_CARD
}

export enum ReaderInlineKind {
  TEXT,
  FORMULA
}

export interface ReaderInlineRun {
  id: string;
  kind: ReaderInlineKind;
  text: string;
  sourceUrl: string;
  /** 内联加粗（b/strong，对齐上游 MdAst 的 StrongEmphasis）。 */
  bold?: boolean;
  /** 内联斜体（i/em，对齐上游 Emphasis）。 */
  italic?: boolean;
  /** 删除线（del/s/strike，对齐上游 Strikethrough）。 */
  strikethrough?: boolean;
  /** 行内代码（code/kbd，对齐上游 InlineCode/KeyboardInput）。 */
  code?: boolean;
  /** 高亮标记（mark，对齐上游 Highlight）。 */
  mark?: boolean;
  superscript?: boolean;
  subscript?: boolean;
  /** 链接目标（a[href]，已归一化为绝对 https URL）；无链接为空串。 */
  linkUrl?: string;
  /** 参考标记序号（sup[data-draft-type=reference] 的 data-numero）；非标记不设置。 */
  referenceNumero?: number;
}

/**
 * 参考条目：知乎参考资料标记（sup[data-draft-type=reference]）携带的文外信息，
 * 对齐上游 MdAst 的 FootnoteDefinition（data-text 说明 + 可选 data-url 链接）。
 */
export interface ReaderReferenceItem {
  /** 脚注序号（data-numero）。 */
  numero: number;
  /** 参考条目说明（data-text），可能为空串。 */
  text: string;
  /** 参考链接（data-url，已归一化），空串表示无链接。 */
  url: string;
}

export interface ReaderBlock {
  id: string;
  kind: ReaderBlockKind;
  text: string;
  sourceUrl: string;
  /** 引用嵌套层数；保持子段落、公式和参考标记各自的语义。 */
  quoteDepth?: number;
  /** 推荐阅读卡片的封面；不与点击目标 sourceUrl 混用。 */
  coverUrl?: string;
  /** 卡片展示地址：去掉知乎跳转包装，sourceUrl 仍用于点击。 */
  displayUrl?: string;
  /** 视频块的 data-lens-id；其他块不设置。 */
  targetId?: string;
  /** 正文段落的知乎段落 id（p/li 的 data-pid），用于对齐服务端 segment_infos 的他人划线。 */
  pid?: string;
  /** REFERENCE 块的参考条目；其他块不设置。 */
  reference?: ReaderReferenceItem;
  inlineRuns: Array<ReaderInlineRun>;
}

export interface ReaderDocumentStats {
  blockCount: number;
  textLength: number;
  headingCount: number;
  formulaCount: number;
  blockFormulaCount: number;
  inlineFormulaCount: number;
  imageCount: number;
}

interface HtmlBlockFragment {
  html: string;
  quoteDepth: number;
  pid: string;
}

/** 按同名标签闭合，避免 blockquote/figure 被内部 p 的结束标签截断。 */
function blockFragments(html: string): Array<HtmlBlockFragment> {
  const fragments: Array<HtmlBlockFragment> = [];
  const tags = /<!--[\s\S]*?-->|<\/?[a-z][a-z0-9]*\b(?:[^>"']|"[^"]*"|'[^']*')*>/gi;
  let quoteDepth = 0;
  const quotePids: Array<string> = [];
  let pending = '';
  let offset = 0;
  let active = '';
  let depth = 0;
  const flush = (): void => {
    if (pending.trim().length > 0) {
      fragments.push({ html: active.length > 0 ? pending : `<p>${pending}</p>`, quoteDepth: quoteDepth,
        pid: active.length === 0 ? (quotePids[quotePids.length - 1] ?? '') : '' });
    }
    pending = '';
  };
  let match: RegExpExecArray | null;
  while ((match = tags.exec(html)) !== null) {
    pending += html.slice(offset, match.index);
    const tag = match[0];
    offset = match.index + tag.length;
    if (tag.startsWith('<!--')) { continue; }
    const parsed = inlineTagName(tag);
    if (active.length > 0) {
      pending += tag;
      if (parsed.name === active) {
        depth += parsed.closing ? -1 : 1;
        if (depth === 0) { flush(); active = ''; }
      }
    } else if (parsed.name === 'blockquote') {
      flush();
      quoteDepth = Math.max(0, quoteDepth + (parsed.closing ? -1 : 1));
      if (parsed.closing) { quotePids.pop(); } else { quotePids.push(attributeValue(tag, 'data-pid')); }
    } else if (/^(h[1-6]|p|li|figure|pre|a)$/.test(parsed.name) && !parsed.closing) {
      flush();
      active = parsed.name;
      depth = 1;
      pending = tag;
    } else if (parsed.name === 'hr') {
      flush();
      fragments.push({ html: tag, quoteDepth: quoteDepth, pid: '' });
    } else if (/^(div|section|ul|ol)$/.test(parsed.name)) {
      flush();
    } else {
      pending += tag;
    }
  }
  pending += html.slice(offset);
  flush();
  return fragments;
}
const IMAGE_PATTERN = /<img\b[^>]*>/gi;
const NOSCRIPT_PATTERN = /<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi;
const ANCHOR_PATTERN = /<a\b[^>]*>[\s\S]*?<\/a>/gi;

function attributeValue(tag: string, name: string): string {
  const match = tag.match(new RegExp(`(?:^|\\s)${name}\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))`, 'i'));
  if (match === null) {
    return '';
  }
  return match[1] || match[2] || match[3] || '';
}

function decodeHtml(value: string): string {
  return value
    .replace(/&nbsp;/gi, ' ')
    .replace(/&quot;/gi, '"')
    .replace(/&#34;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&amp;/gi, '&');
}

function plainText(fragment: string): string {
  const withEquations = fragment.replace(IMAGE_PATTERN, (tag: string): string => {
    const alt = decodeHtml(attributeValue(tag, 'alt')).trim();
    return alt.length > 0 ? ` 「${alt}」 ` : ' ';
  });
  return decodeHtml(withEquations
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/ *\n */g, '\n'))
    .trim();
}

function contentOf(blockHtml: string): string {
  const start = blockHtml.indexOf('>');
  const end = blockHtml.lastIndexOf('</');
  return start >= 0 && end > start ? blockHtml.slice(start + 1, end) : '';
}

/** 对齐上游 ZhihuUtils.extractImageUrl：v2- 原图 token 优先，缩略图字段只作兜底。 */
function preferredImageSource(tag: string): string {
  const token = decodeHtml(attributeValue(tag, 'data-original-token')).trim();
  if (token.startsWith('v2-')) {
    return `https://pic1.zhimg.com/${token}`;
  }
  const candidate = decodeHtml(attributeValue(tag, 'data-original') ||
    attributeValue(tag, 'data-default-watermark-src') || attributeValue(tag, 'data-actualsrc') ||
    attributeValue(tag, 'data-thumbnail') || attributeValue(tag, 'src')).trim();
  if (candidate.startsWith('//')) {
    return `https:${candidate}`;
  }
  return candidate.startsWith('https://') ? candidate : '';
}

function formulaSource(tag: string): string {
  const candidate = decodeHtml(attributeValue(tag, 'src')).trim();
  return isTrustedFormulaUrl(candidate) ? candidate : '';
}

function videoAnchor(fragment: string): string | undefined {
  const anchors = fragment.match(ANCHOR_PATTERN);
  return anchors?.find((anchor: string): boolean => {
    const openingTag = anchor.slice(0, anchor.indexOf('>') + 1);
    const classes = decodeHtml(attributeValue(openingTag, 'class')).split(/\s+/);
    return classes.includes('video-box') && /^[1-9][0-9]{0,29}$/.test(attributeValue(openingTag, 'data-lens-id'));
  });
}

/** 内联样式栈帧：记录来源标签与叠加后的样式状态。 */
interface InlineFormatFrame {
  tag: string;
  state: InlineFormatState;
}

/** 当前生效的内联样式集合（跨嵌套标签折叠）。 */
interface InlineFormatState {
  bold: boolean;
  italic: boolean;
  strikethrough: boolean;
  code: boolean;
  mark: boolean;
  superscript: boolean;
  subscript: boolean;
  linkUrl: string;
  /** 参考标记序号；0 表示非参考标记。 */
  referenceNumero: number;
}

function baseFormatState(): InlineFormatState {
  return {
    bold: false, italic: false, strikethrough: false, code: false,
    mark: false, superscript: false, subscript: false, linkUrl: '', referenceNumero: 0
  };
}

function copyFormatState(state: InlineFormatState): InlineFormatState {
  return {
    bold: state.bold, italic: state.italic, strikethrough: state.strikethrough,
    code: state.code, mark: state.mark, superscript: state.superscript,
    subscript: state.subscript, linkUrl: state.linkUrl, referenceNumero: state.referenceNumero
  };
}

function hasInlineStyle(state: InlineFormatState): boolean {
  return state.bold || state.italic || state.strikethrough || state.code ||
    state.mark || state.superscript || state.subscript || state.linkUrl.length > 0 ||
    state.referenceNumero > 0;
}

/** 对齐上游 MdAst.extractInlineNode 的样式标签集合。 */
function isStyleTag(name: string): boolean {
  return name === 'b' || name === 'strong' || name === 'i' || name === 'em' ||
    name === 'del' || name === 's' || name === 'strike' || name === 'code' ||
    name === 'kbd' || name === 'mark' || name === 'sub' || name === 'sup' || name === 'a';
}

/**
 * 读取 reference sup 的脚注序号（data-numero）；非参考标记或序号非法返回 0。
 */
function referenceNumeroOf(tag: string): number {
  if (attributeValue(tag, 'data-draft-type') !== 'reference') {
    return 0;
  }
  const numero = Number.parseInt(decodeHtml(attributeValue(tag, 'data-numero')).trim(), 10);
  return Number.isFinite(numero) && numero > 0 ? numero : 0;
}

/** 登记 reference sup 携带的参考条目（numero → 条目，重复 numero 首见优先）；空条目跳过。 */
function collectReference(references: Map<number, ReaderReferenceItem>, tag: string): void {
  const numero = referenceNumeroOf(tag);
  if (numero <= 0 || references.has(numero)) {
    return;
  }
  const text = decodeHtml(attributeValue(tag, 'data-text')).trim();
  const url = normalizeLinkHref(attributeValue(tag, 'data-url'));
  if (text.length === 0 && url.length === 0) {
    return;
  }
  references.set(numero, { numero: numero, text: text, url: url });
}

function applyStyleTag(state: InlineFormatState, name: string, tag: string): InlineFormatState {
  const next = copyFormatState(state);
  if (name === 'b' || name === 'strong') {
    next.bold = true;
  } else if (name === 'i' || name === 'em') {
    next.italic = true;
  } else if (name === 'del' || name === 's' || name === 'strike') {
    next.strikethrough = true;
  } else if (name === 'code' || name === 'kbd') {
    next.code = true;
  } else if (name === 'mark') {
    next.mark = true;
  } else if (name === 'sub') {
    next.subscript = true;
  } else if (name === 'sup') {
    next.superscript = true;
    next.referenceNumero = referenceNumeroOf(tag);
  } else if (name === 'a') {
    next.linkUrl = normalizeLinkHref(attributeValue(tag, 'href'));
  }
  return next;
}

/** 链接归一化：协议相对补 https、站内根路径补域名；非 http(s) 安全方案一律视为纯文本。 */
function normalizeLinkHref(href: string): string {
  const trimmed = decodeHtml(href).trim();
  if (trimmed.length === 0) {
    return '';
  }
  const lower = trimmed.toLowerCase();
  if (lower.startsWith('javascript:') || lower.startsWith('data:') || lower.startsWith('vbscript:')) {
    return '';
  }
  if (trimmed.startsWith('//')) {
    return `https:${trimmed}`;
  }
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return trimmed;
  }
  if (lower.startsWith('www.')) {
    return `https://${trimmed}`;
  }
  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    return `https://www.zhihu.com${trimmed}`;
  }
  return '';
}

function linkCardDisplayUrl(url: string): string {
  let displayUrl = url;
  for (let depth = 0; depth < 3; depth++) {
    const parsed = parseAbsoluteUrl(displayUrl);
    if (parsed === undefined || parsed.hostname !== 'link.zhihu.com' ||
      parsed.hasUserInfo || parsed.port.length > 0) {
      break;
    }
    const target = parsed.params.get('target');
    if (target === undefined) { break; }
    const destination = parseAbsoluteUrl(target);
    if (destination === undefined || (destination.protocol !== 'https:' && destination.protocol !== 'http:')) {
      break;
    }
    displayUrl = target;
  }
  return displayUrl;
}

/**
 * 复刻 plainText 的空白归一化语义：连续空格/制表符折叠为一个空格，
 * 换行（含 <br>）连同两侧空白折叠为换行；供样式 run 的文本与 plainText 逐字对齐。
 */
class InlineTextStream {
  /** 已归一化的原始文本（实体未解码），由 flush 取走作为当前 run 的文本。 */
  output: string = '';
  private pendingSpaces: number = 0;
  private pendingNewlines: number = 0;

  addSpace(): void {
    if (this.pendingNewlines === 0) {
      this.pendingSpaces += 1;
    }
  }

  addNewline(): void {
    this.pendingNewlines += 1;
    this.pendingSpaces = 0;
  }

  /** 非空白 token：先落账挂起的空白（折叠后）再追加。 */
  addToken(token: string): void {
    if (token.length === 0) {
      return;
    }
    if (this.pendingNewlines > 0) {
      this.output += '\n'.repeat(this.pendingNewlines);
      this.pendingNewlines = 0;
    } else if (this.pendingSpaces > 0) {
      this.output += ' ';
      this.pendingSpaces = 0;
    }
    this.output += token;
  }

  /** 丢弃挂起的空白（公式 run 边界与 plainText 的逐段 trim 语义一致）。 */
  resetPending(): void {
    this.pendingSpaces = 0;
    this.pendingNewlines = 0;
  }

  takeOutput(): string {
    const out = this.output;
    this.output = '';
    return out;
  }
}

/**
 * 读取从 start（'<' 处）开始的标签串，对齐 plainText 的 `<[^>]+>` 识别口径；
 * 非标签（`<>`、无闭合 `>`）返回空串，`<` 按普通文本处理。
 */
function readInlineTag(html: string, start: number): string {
  if (start + 1 >= html.length || html.charAt(start + 1) === '>') {
    return '';
  }
  const end = html.indexOf('>', start + 1);
  return end < 0 ? '' : html.slice(start, end + 1);
}

/** 标签名解析结果：是否闭合标签 + 小写标签名（无法识别为空串）。 */
interface InlineTagName {
  closing: boolean;
  name: string;
}

function inlineTagName(tag: string): InlineTagName {
  const closing = tag.charAt(1) === '/';
  const rest = closing ? tag.slice(2) : tag.slice(1);
  const match = /^[a-zA-Z][a-zA-Z0-9]*/.exec(rest);
  const name = match === null ? '' : match[0].toLowerCase();
  const parsed: InlineTagName = { closing: closing, name: name };
  return parsed;
}

function inlineRuns(content: string, blockId: string,
  references?: Map<number, ReaderReferenceItem>): Array<ReaderInlineRun> {
  const runs: Array<ReaderInlineRun> = [];
  const stack: Array<InlineFormatFrame> = [];
  const stream = new InlineTextStream();

  const currentState = (): InlineFormatState =>
    stack.length > 0 ? stack[stack.length - 1].state : baseFormatState();

  const flush = (): void => {
    const text = stream.takeOutput();
    if (text.length === 0) {
      return;
    }
    const state = currentState();
    const run: ReaderInlineRun = {
      id: `${blockId}-inline-${runs.length}`,
      kind: ReaderInlineKind.TEXT,
      text: text,
      sourceUrl: '',
      bold: state.bold,
      italic: state.italic,
      strikethrough: state.strikethrough,
      code: state.code,
      mark: state.mark,
      superscript: state.superscript,
      subscript: state.subscript,
      linkUrl: state.linkUrl
    };
    if (state.referenceNumero > 0) {
      run.referenceNumero = state.referenceNumero;
    }
    runs.push(run);
  };

  const pushFormula = (tag: string): void => {
    const tex = decodeHtml(attributeValue(tag, 'alt')).trim();
    const sourceUrl = formulaSource(tag);
    if (tex.length === 0 || sourceUrl.length === 0) {
      // 不可信/缺字段的公式退化为可读替代文本（与 plainText 口径一致）。
      emitImageReplacement(tag);
      return;
    }
    flush();
    stream.resetPending();
    runs.push({
      id: `${blockId}-inline-${runs.length}`,
      kind: ReaderInlineKind.FORMULA,
      text: tex,
      sourceUrl: sourceUrl,
      bold: false,
      italic: false,
      strikethrough: false,
      code: false,
      mark: false,
      superscript: false,
      subscript: false,
      linkUrl: ''
    });
  };

  const emitImageReplacement = (tag: string): void => {
    const alt = decodeHtml(attributeValue(tag, 'alt')).trim();
    stream.addSpace();
    if (alt.length > 0) {
      feed(`「${alt}」`);
    }
    stream.addSpace();
  };

  const closeTag = (name: string): void => {
    let matchIndex = -1;
    for (let i = stack.length - 1; i >= 0; i--) {
      if (stack[i].tag === name) {
        matchIndex = i;
        break;
      }
    }
    if (matchIndex < 0) {
      return;
    }
    flush();
    stack.length = matchIndex;
  };

  const feed = (text: string): void => {
    let i = 0;
    while (i < text.length) {
      const ch = text.charAt(i);
      if (ch === '<') {
        const tag = readInlineTag(text, i);
        if (tag.length === 0) {
          stream.addToken(ch);
          i += 1;
          continue;
        }
        i += tag.length;
        const parsed = inlineTagName(tag);
        if (!parsed.closing && parsed.name === 'img') {
          // 知乎允许 display 公式与文字出现在同一个段落中（issue #47）。
          if (attributeValue(tag, 'eeimg') === '1' || attributeValue(tag, 'eeimg') === '2') {
            pushFormula(tag);
          } else {
            emitImageReplacement(tag);
          }
          continue;
        }
        if (!parsed.closing && parsed.name === 'br') {
          stream.addNewline();
          continue;
        }
        if (isStyleTag(parsed.name)) {
          if (parsed.closing) {
            closeTag(parsed.name);
          } else {
            if (parsed.name === 'sup' && references !== undefined) {
              collectReference(references, tag);
            }
            flush();
            stack.push({ tag: parsed.name, state: applyStyleTag(currentState(), parsed.name, tag) });
          }
          continue;
        }
        continue;
      }
      if (ch === '&') {
        const semi = text.indexOf(';', i + 1);
        if (semi >= 0 && semi - i >= 2 && semi - i <= 8) {
          // 实体作为不可拆分 token 输出，decode 在 run 拼装后统一进行（与 plainText 次序一致）。
          stream.addToken(text.slice(i, semi + 1));
          i = semi + 1;
          continue;
        }
        stream.addToken(ch);
        i += 1;
        continue;
      }
      if (ch === ' ' || ch === '\t') {
        stream.addSpace();
      } else if (ch === '\n') {
        stream.addNewline();
      } else {
        stream.addToken(ch);
      }
      i += 1;
    }
  };

  feed(content);
  flush();

  // 逐 run 解码后做端到端 trim（等价 plainText 的最终 trim）。
  runs.forEach((run: ReaderInlineRun): void => {
    if (run.kind === ReaderInlineKind.TEXT) {
      run.text = decodeHtml(run.text);
    }
  });
  trimRunsEdges(runs);

  const hasFormula = runs.some((run: ReaderInlineRun): boolean => run.kind === ReaderInlineKind.FORMULA);
  const hasStyle = runs.some((run: ReaderInlineRun): boolean => run.kind === ReaderInlineKind.TEXT &&
    hasInlineStyle({
      bold: run.bold === true,
      italic: run.italic === true,
      strikethrough: run.strikethrough === true,
      code: run.code === true,
      mark: run.mark === true,
      superscript: run.superscript === true,
      subscript: run.subscript === true,
      linkUrl: run.linkUrl ?? '',
      referenceNumero: run.referenceNumero ?? 0
    }));
  if (!hasFormula && !hasStyle) {
    return [];
  }
  if (!hasFormula) {
    // 无公式时 runs 拼接必须与 plainText 逐字一致，划线偏移才可靠；不一致则退回纯文本。
    const joined = runs.map((run: ReaderInlineRun): string => run.text).join('');
    if (joined !== plainText(content)) {
      return [];
    }
  }
  return runs;
}

/** 端到端 trim：剥掉首尾 run 上的空白（等价 plainText 的最终 trim），空 run 移除。 */
function trimRunsEdges(runs: Array<ReaderInlineRun>): void {
  while (runs.length > 0) {
    const first = runs[0];
    if (first.kind !== ReaderInlineKind.TEXT) {
      break;
    }
    const trimmed = first.text.replace(/^[\s]+/, '');
    if (trimmed.length === 0) {
      runs.shift();
      continue;
    }
    first.text = trimmed;
    break;
  }
  while (runs.length > 0) {
    const last = runs[runs.length - 1];
    if (last.kind !== ReaderInlineKind.TEXT) {
      break;
    }
    const trimmed = last.text.replace(/[\s]+$/, '');
    if (trimmed.length === 0) {
      runs.pop();
      continue;
    }
    last.text = trimmed;
    break;
  }
}

export function parseZhihuHtml(html: string): Array<ReaderBlock> {
  const matches = blockFragments(html.replace(NOSCRIPT_PATTERN, '')
    .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, ''));
  const references = new Map<number, ReaderReferenceItem>();
  const blocks: Array<ReaderBlock> = [];
  matches.forEach((fragment: HtmlBlockFragment) => {
    const firstBlock = blocks.length;
    const parseFragment = (): void => {
      const normalized = fragment.html.trim();
      const blockId = `block-${blocks.length}`;
      if (/^<hr\b/i.test(normalized)) {
        blocks.push({ id: blockId, kind: ReaderBlockKind.DIVIDER, text: '', sourceUrl: '', inlineRuns: [] });
        return;
      }

      // 顶层 a 自身携带 href，不能剥去外层后再解析行内样式。
      const content = /^<a\b/i.test(normalized) ? normalized : contentOf(normalized);
      const visibleContent = content.replace(NOSCRIPT_PATTERN, '');
      const video = videoAnchor(normalized);
      if (video !== undefined) {
        const openingTag = video.slice(0, video.indexOf('>') + 1);
        const imageTag = video.match(/<img\b[^>]*>/i)?.[0] ?? '';
        const label = decodeHtml(attributeValue(openingTag, 'data-title')).trim() || plainText(video) || '视频';
        blocks.push({
          id: blockId,
          kind: ReaderBlockKind.VIDEO,
          text: label,
          sourceUrl: imageTag.length > 0 ? preferredImageSource(imageTag) : '',
          targetId: attributeValue(openingTag, 'data-lens-id'),
          inlineRuns: []
        });
        return;
      }
      const anchors = content.match(ANCHOR_PATTERN);
      const anchor = anchors?.length === 1 && anchors[0] === content.trim() ?
        content.match(/^\s*(<a\b[^>]*>)/i) : null;
      if (anchor !== null && (attributeValue(anchor[1], 'class').split(/\s+/).includes('link-card') ||
        attributeValue(anchor[1], 'data-draft-type') === 'link-card')) {
        const url = normalizeLinkHref(attributeValue(anchor[1], 'href'));
        const displayUrl = linkCardDisplayUrl(url);
        const label = linkCardDisplayUrl(plainText(contentOf(content.trim())) ||
          decodeHtml(attributeValue(anchor[1], 'data-draft-title') || attributeValue(anchor[1], 'data-title')).trim() || url);
        if (label.length > 0) {
          const cover = decodeHtml(attributeValue(anchor[1], 'data-draft-cover')).trim();
          const coverUrl = cover.startsWith('//') ? `https:${cover}` : cover;
          blocks.push({ id: blockId, kind: ReaderBlockKind.LINK_CARD, text: label,
            sourceUrl: url, displayUrl: displayUrl,
            coverUrl: coverUrl.startsWith('https://') ? coverUrl : '', inlineRuns: [] });
        }
        return;
      }
      const imageTags = visibleContent.match(IMAGE_PATTERN);
      const singleImage = imageTags !== null && imageTags.length === 1 &&
        visibleContent.replace(IMAGE_PATTERN, '').trim().length === 0;
      if (singleImage && attributeValue(imageTags[0], 'eeimg') === '2') {
        blocks.push({
          id: blockId,
          kind: ReaderBlockKind.FORMULA,
          text: decodeHtml(attributeValue(imageTags[0], 'alt')),
          sourceUrl: formulaSource(imageTags[0]),
          inlineRuns: []
        });
        return;
      }
      if (imageTags !== null && /^<figure\b/i.test(normalized)) {
        const sourceUrl = preferredImageSource(imageTags[0]);
        if (sourceUrl.length > 0) {
          const alt = decodeHtml(attributeValue(imageTags[0], 'alt')).trim();
          blocks.push({
            id: blockId,
            kind: ReaderBlockKind.IMAGE,
            text: alt.length > 0 ? alt : plainText(visibleContent.replace(IMAGE_PATTERN, '')),
            sourceUrl: sourceUrl,
            inlineRuns: []
          });
        }
        return;
      }

      const text = plainText(content);
      if (text.length === 0) {
        return;
      }
      const kind = /^<h[1-6]\b/i.test(normalized) ? ReaderBlockKind.HEADING :
        (/^<li\b/i.test(normalized) ? ReaderBlockKind.LIST_ITEM : ReaderBlockKind.PARAGRAPH);
      blocks.push({
        id: blockId,
        kind: kind,
        text: text,
        sourceUrl: '',
        pid: attributeValue(normalized.slice(0, normalized.indexOf('>') + 1), 'data-pid') || fragment.pid,
        inlineRuns: inlineRuns(content, blockId, references)
      });
    };
    parseFragment();
    for (let index = firstBlock; index < blocks.length; index++) {
      blocks[index].quoteDepth = fragment.quoteDepth;
    }
  });
  // 文末参考条目区（对齐上游：reference sup 注册 FootnoteDefinition 追加到文档末尾）：
  // 分隔线 + 标题 + 按序号升序逐条成块；正文标记经 referenceNumero 关联到条目块。
  // 分区标题为知乎网页版行为（上游渲染库不渲染标题，这里按网页形态补齐）。
  if (references.size > 0) {
    blocks.push({ id: `block-${blocks.length}`, kind: ReaderBlockKind.DIVIDER, text: '', sourceUrl: '', inlineRuns: [] });
    blocks.push({
      id: `block-${blocks.length}`,
      kind: ReaderBlockKind.HEADING,
      text: '参考',
      sourceUrl: '',
      inlineRuns: []
    });
    const numeros = Array.from(references.keys()).sort((a: number, b: number): number => a - b);
    numeros.forEach((numero: number): void => {
      const item: ReaderReferenceItem | undefined = references.get(numero);
      if (item === undefined) {
        return;
      }
      blocks.push({
        id: `block-${blocks.length}`,
        kind: ReaderBlockKind.REFERENCE,
        text: item.text,
        sourceUrl: '',
        reference: item,
        inlineRuns: []
      });
    });
  }
  return blocks;
}

export function readerDocumentStats(blocks: Array<ReaderBlock>): ReaderDocumentStats {
  let textLength = 0;
  let headingCount = 0;
  let blockFormulaCount = 0;
  let inlineFormulaCount = 0;
  let imageCount = 0;
  blocks.forEach((block: ReaderBlock) => {
    textLength += block.text.length;
    headingCount += block.kind === ReaderBlockKind.HEADING ? 1 : 0;
    blockFormulaCount += block.kind === ReaderBlockKind.FORMULA ? 1 : 0;
    block.inlineRuns.forEach((run: ReaderInlineRun) => {
      inlineFormulaCount += run.kind === ReaderInlineKind.FORMULA ? 1 : 0;
    });
    imageCount += block.kind === ReaderBlockKind.IMAGE ? 1 : 0;
  });
  return {
    blockCount: blocks.length,
    textLength: textLength,
    headingCount: headingCount,
    formulaCount: blockFormulaCount + inlineFormulaCount,
    blockFormulaCount: blockFormulaCount,
    inlineFormulaCount: inlineFormulaCount,
    imageCount: imageCount
  };
}
