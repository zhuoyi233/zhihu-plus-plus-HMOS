import { isTrustedFormulaUrl } from './FormulaSourcePolicy';

export enum ReaderBlockKind {
  HEADING,
  PARAGRAPH,
  DIVIDER,
  FORMULA,
  IMAGE,
  LIST_ITEM
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
}

export interface ReaderBlock {
  id: string;
  kind: ReaderBlockKind;
  text: string;
  sourceUrl: string;
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

const BLOCK_PATTERN = /<(?:h[1-6]|p|li|figure)\b[^>]*>[\s\S]*?<\/(?:h[1-6]|p|li|figure)>|<hr\b[^>]*\/?>/gi;
const IMAGE_PATTERN = /<img\b[^>]*>/gi;
const NOSCRIPT_PATTERN = /<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi;

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

function preferredImageSource(tag: string): string {
  const candidate = decodeHtml(attributeValue(tag, 'data-actualsrc') ||
    attributeValue(tag, 'data-original') || attributeValue(tag, 'src')).trim();
  if (candidate.startsWith('//')) {
    return `https:${candidate}`;
  }
  return candidate.startsWith('https://') ? candidate : '';
}

function formulaSource(tag: string): string {
  const candidate = decodeHtml(attributeValue(tag, 'src')).trim();
  return isTrustedFormulaUrl(candidate) ? candidate : '';
}

function inlineRuns(content: string, blockId: string): Array<ReaderInlineRun> {
  const runs: Array<ReaderInlineRun> = [];
  let cursor = 0;
  // Keep the iterator independent from plainText(), which also uses IMAGE_PATTERN.
  // Reusing the same global RegExp resets lastIndex during nested parsing and loops forever on a formula tag.
  const inlineImagePattern = /<img\b[^>]*>/gi;
  let match: RegExpExecArray | null = inlineImagePattern.exec(content);
  while (match !== null) {
    const tag = match[0];
    if (attributeValue(tag, 'eeimg') === '1') {
      const leadingText = plainText(content.slice(cursor, match.index));
      if (leadingText.length > 0) {
        runs.push({
          id: `${blockId}-inline-${runs.length}`,
          kind: ReaderInlineKind.TEXT,
          text: leadingText,
          sourceUrl: ''
        });
      }
      const tex = decodeHtml(attributeValue(tag, 'alt')).trim();
      const sourceUrl = formulaSource(tag);
      if (tex.length > 0 && sourceUrl.length > 0) {
        runs.push({
          id: `${blockId}-inline-${runs.length}`,
          kind: ReaderInlineKind.FORMULA,
          text: tex,
          sourceUrl: sourceUrl
        });
      } else if (tex.length > 0) {
        runs.push({
          id: `${blockId}-inline-${runs.length}`,
          kind: ReaderInlineKind.TEXT,
          text: ` 「${tex}」 `,
          sourceUrl: ''
        });
      }
      cursor = match.index + tag.length;
    }
    match = inlineImagePattern.exec(content);
  }
  const trailingText = plainText(content.slice(cursor));
  if (trailingText.length > 0) {
    runs.push({
      id: `${blockId}-inline-${runs.length}`,
      kind: ReaderInlineKind.TEXT,
      text: trailingText,
      sourceUrl: ''
    });
  }
  return runs.some((run: ReaderInlineRun) => run.kind === ReaderInlineKind.FORMULA) ? runs : [];
}

export function parseZhihuHtml(html: string): Array<ReaderBlock> {
  const matches = html.match(BLOCK_PATTERN);
  if (matches === null) {
    return [];
  }

  const blocks: Array<ReaderBlock> = [];
  matches.forEach((blockHtml: string) => {
    const normalized = blockHtml.trim();
    const blockId = `block-${blocks.length}`;
    if (/^<hr\b/i.test(normalized)) {
      blocks.push({ id: blockId, kind: ReaderBlockKind.DIVIDER, text: '', sourceUrl: '', inlineRuns: [] });
      return;
    }

    const content = contentOf(normalized);
    const visibleContent = content.replace(NOSCRIPT_PATTERN, '');
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
      inlineRuns: inlineRuns(content, blockId)
    });
  });
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
