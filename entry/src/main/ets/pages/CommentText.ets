/**
 * 评论文本工具：评论正文是 HTML（如 `<p>text</p>`，含表情/图片锚点），
 * 列表预览与热评卡片都需要把可见文字与图片地址拆出来。
 *
 * 评论页与回答尾部热评共用这里的实现，避免两处正则漂移。
 */

/** 评论用户头像 URL：http 归一化为 https，缺失或不受信返回空串（走首字占位）。 */
export function commentAvatarUrl(raw: string): string {
  const trimmed = raw.trim();
  const url = trimmed.startsWith('http://') ? `https://${trimmed.substring(7)}` : trimmed;
  if (!/^https:\/\/[A-Za-z0-9.-]+/.test(url)) {
    return '';
  }
  return url;
}

/** 知乎图床域名白名单：pic1/pic2/…、picx、pica 等同属 `pic*` 前缀。 */
function isZhihuImageUrl(url: string): boolean {
  return /^https:\/\/pic[a-z0-9]*\.zhimg\.com\//i.test(url);
}

/** 仅接纳知乎图床；属性名前要求空白，避免把 data-src 当成 src。 */
function imageAttribute(tag: string, name: string): string {
  const match = tag.match(new RegExp('\\s' + name + '\\s*=\\s*["\']([^"\']+)["\']', 'i'));
  return match === null ? '' : commentAvatarUrl(match[1].replace(/&amp;/gi, '&'));
}

function supportedImageUrl(tag: string): string {
  const url = imageAttribute(tag, /^<a\b/i.test(tag) ? 'href' : 'src');
  return isZhihuImageUrl(url) ? url : '';
}

const COMMENT_IMAGE_PARTS: RegExp = /<a\b[^>]*\sclass\s*=\s*["'][^"']*\bcomment_(img|gif|sticker)\b[^"']*["'][^>]*>[\s\S]*?<\/a>|<img\b[^>]*>/gi;

/** 按正文顺序提取全部受支持图片（包括 GIF）；调用方逐张展示，不能只显示首图却删掉其余文字。 */
export function commentImageUrls(html: string): Array<string> {
  const urls: Array<string> = [];
  const parts = html.match(COMMENT_IMAGE_PARTS) ?? [];
  for (const part of parts) {
    const url = supportedImageUrl(part);
    if (url.length > 0 && !urls.includes(url)) { urls.push(url); }
  }
  return urls;
}

export function commentImageUrl(html: string): string {
  return commentImageUrls(html)[0] ?? '';
}

/** 只有实际进入图片展示列表的锚点才移除；不支持的来源保留锚点文字或 alt/可读占位。 */
export function stripCommentHtml(html: string): string {
  const text = html
    .replace(COMMENT_IMAGE_PARTS, (part: string): string => {
      if (supportedImageUrl(part).length > 0) { return ''; }
      if (/^<a\b/i.test(part)) {
        const label = part.replace(/<[^>]+>/g, '').trim();
        return label.length > 0 ? label : '[图片暂不支持]';
      }
      const alt = part.match(/\salt\s*=\s*["']([^"']*)["']/i);
      return alt !== null && alt[1].trim().length > 0 ? alt[1] : '[图片暂不支持]';
    })
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|blockquote)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, '\n\n');
  return text.trim();
}
