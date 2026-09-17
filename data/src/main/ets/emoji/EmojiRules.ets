import { util } from '@kit.ArkTS';
import { jsonArray, JsonObjectValue, jsonObject, jsonString, JsonValue, parseStrictJson } from 'core';

/**
 * 知乎小表情纯逻辑，行为对齐上游 EmojiManager / processTextWithEmoji：
 * 评论、通知等富文本中的 `[占位符]`（如 `[惊喜]`）在表情表命中时渲染为行内图片，
 * 未命中保持原文。本文件不触碰网络与文件系统，供 EmojiStore 与单测复用。
 */

export const EMOJI_STICKER_API_URL: string =
  'https://www.zhihu.com/api/v4/sticker-groups/1114161698310770688';

/** 递增可强制重新下载表情数据（对齐上游 CURRENT_EMOJI_VERSION）。 */
export const EMOJI_CACHE_VERSION: string = '1';

export const EMOJI_DATA_URL_PREFIX: string = 'data:image/png;base64,';

export interface EmojiSticker {
  id: string;
  placeholder: string;
  staticImageUrl: string;
}

export interface EmojiSegment {
  kind: 'text' | 'emoji';
  /** text 段为文本内容，emoji 段为占位符原文。 */
  text: string;
  /** emoji 本地文件路径；text 段为空串。 */
  path: string;
}

export type EmojiPathResolver = (placeholder: string) => string;

export function emojiFileName(stickerId: string): string {
  return `emoji_${stickerId}.png`;
}

export function isValidEmojiPlaceholder(placeholder: string): boolean {
  return /^\[[^\[\]]{1,32}\]$/.test(placeholder);
}

function stickerFromObject(value: JsonObjectValue): EmojiSticker | undefined {
  const id = jsonString(value.get('id'));
  const placeholder = jsonString(value.get('placeholder'));
  const staticImageUrl = jsonString(value.get('static_image_url'));
  if (id === undefined || id.length === 0 || placeholder === undefined ||
    staticImageUrl === undefined || staticImageUrl.length === 0) {
    return undefined;
  }
  if (!isValidEmojiPlaceholder(placeholder)) {
    return undefined;
  }
  return { id: id, placeholder: placeholder, staticImageUrl: staticImageUrl };
}

/** 解析 sticker-group API 响应，结构异常或字段缺失时返回空表。 */
export function parseStickerResponse(body: string): Array<EmojiSticker> {
  let root: JsonValue;
  try {
    root = parseStrictJson(body);
  } catch (_error) {
    return [];
  }
  const rootData = jsonObject(root);
  const group = rootData === undefined ? undefined : jsonObject(rootData.get('data'));
  const stickers = group === undefined ? undefined : jsonArray(group.get('stickers'));
  if (stickers === undefined) {
    return [];
  }
  const result: Array<EmojiSticker> = [];
  for (const entry of stickers.items) {
    const value = jsonObject(entry);
    if (value === undefined) {
      continue;
    }
    const sticker = stickerFromObject(value);
    if (sticker !== undefined) {
      result.push(sticker);
    }
  }
  return result;
}

/** 解析 base64 PNG data URL，前缀不符或内容为空返回 undefined。 */
export function decodeStickerDataUrl(dataUrl: string): Uint8Array | undefined {
  if (!dataUrl.startsWith(EMOJI_DATA_URL_PREFIX)) {
    return undefined;
  }
  const base64 = dataUrl.substring(EMOJI_DATA_URL_PREFIX.length).replace(/\s/g, '');
  if (base64.length === 0) {
    return undefined;
  }
  return new util.Base64Helper().decodeSync(base64);
}

/**
 * 将文本按 `[占位符]` 切分为 text/emoji 段，与上游 processTextWithEmoji 的逐字符
 * 双缓冲扫描一致：未闭合的 `[` 连同后续字符原样保留，未命中的占位符保持原文，
 * 相邻文本段合并。
 */
export function parseEmojiSegments(text: string, resolve: EmojiPathResolver): Array<EmojiSegment> {
  const segments: Array<EmojiSegment> = [];
  const appendText = (value: string): void => {
    if (value.length === 0) {
      return;
    }
    const last = segments[segments.length - 1];
    if (last !== undefined && last.kind === 'text') {
      last.text += value;
      return;
    }
    segments.push({ kind: 'text', text: value, path: '' });
  };
  let plainBuffer = '';
  let emojiBuffer = '';
  let isEmoji = false;
  for (const ch of text) {
    if (ch === '[') {
      appendText(plainBuffer);
      plainBuffer = '';
      isEmoji = true;
      emojiBuffer += '[';
    } else if (ch === ']') {
      if (isEmoji) {
        emojiBuffer += ']';
        const path = resolve(emojiBuffer);
        if (path.length > 0) {
          segments.push({ kind: 'emoji', text: emojiBuffer, path: path });
        } else {
          appendText(emojiBuffer);
        }
        emojiBuffer = '';
        isEmoji = false;
      } else {
        plainBuffer += ']';
      }
    } else if (isEmoji) {
      emojiBuffer += ch;
    } else {
      plainBuffer += ch;
    }
  }
  appendText(plainBuffer);
  if (isEmoji && emojiBuffer.length > 0) {
    appendText(emojiBuffer);
  }
  return segments;
}
