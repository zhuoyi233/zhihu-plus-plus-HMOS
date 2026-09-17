import { ZhihuPrivateMessage } from 'data';

/**
 * 私信/通知文本的 HTML 轻量解析（对齐上游 `displayContent` 的 ksoup 行为子集）：
 * <br> 转换行，<a href> 保留为链接分段（仅 http/https），其余标签剥离、实体反转义。
 * 仅用于展示，不作为通用 HTML 解析器。
 */

export interface PrivateMessageSegment {
  readonly text: string;
  /** 非 http(s) 链接会被丢弃，此字段为空表示普通文本。 */
  readonly url: string;
}

const ANCHOR_PATTERN = /<a\s+[^>]*href\s*=\s*"([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;
const BR_PATTERN = /<br\s*\/?\s*>/gi;
const TAG_PATTERN = /<[^>]*>/g;
const CONTROL_PATTERN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g;

function unescapeEntities(source: string): string {
  return source
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&');
}

function isSafeHttpUrl(value: string): boolean {
  return /^https?:\/\/[A-Za-z0-9._~:/?#[\]@!$&'()*+,;=%-]+$/.test(value);
}

function toPlainText(source: string): string {
  return unescapeEntities(source.replace(BR_PATTERN, '\n').replace(TAG_PATTERN, ''))
    .replace(CONTROL_PATTERN, '');
}

/**
 * 解析为文本/链接分段。链接段与上游一致：仅接受 http/https 且 href 与链接文本
 * 均非空；无法解析时退化为整段纯文本。
 */
export function parsePrivateMessageSegments(html: string): Array<PrivateMessageSegment> {
  if (html.trim().length === 0) {
    return [];
  }
  const segments: Array<PrivateMessageSegment> = [];
  let cursor = 0;
  ANCHOR_PATTERN.lastIndex = 0;
  let match = ANCHOR_PATTERN.exec(html);
  while (match !== null) {
    const url = unescapeEntities(match[1]).trim();
    const linkText = toPlainText(match[2]);
    if (isSafeHttpUrl(url) && linkText.length > 0) {
      if (match.index > cursor) {
        pushPlainText(segments, plainSegment(toPlainText(html.substring(cursor, match.index))));
      }
      pushPlainText(segments, { text: linkText, url: url });
      cursor = match.index + match[0].length;
    }
    match = ANCHOR_PATTERN.exec(html);
  }
  if (cursor < html.length) {
    pushPlainText(segments, plainSegment(toPlainText(html.substring(cursor))));
  }
  return segments;
}

/** 上游 `displayContent` 的纯文本分支：document.text()。 */
export function privateMessagePlainText(html: string): string {
  return parsePrivateMessageSegments(html).map((segment: PrivateMessageSegment): string => segment.text)
    .join('');
}

/** 消息展示源（对齐上游：plugin.excerpt 优先，其次 content，均空给出占位文案）。 */
export function privateMessageDisplaySource(message: ZhihuPrivateMessage): string {
  if (message.pluginExcerpt.trim().length > 0) {
    return message.pluginExcerpt;
  }
  if (message.content.trim().length > 0) {
    return message.content;
  }
  return '暂不支持显示这条消息';
}

function plainSegment(text: string): PrivateMessageSegment {
  return { text: text, url: '' };
}

function pushPlainText(segments: Array<PrivateMessageSegment>, segment: PrivateMessageSegment): void {
  if (segment.text.length === 0) {
    return;
  }
  const last = segments.length > 0 ? segments[segments.length - 1] : undefined;
  if (last !== undefined && last.url === segment.url) {
    segments[segments.length - 1] = { text: last.text + segment.text, url: last.url };
    return;
  }
  segments.push(segment);
}

/** 用于时间线正文等场景：剥离标签并压缩换行外的空白。 */
export function notificationPlainText(html: string): string {
  return toPlainText(html);
}
