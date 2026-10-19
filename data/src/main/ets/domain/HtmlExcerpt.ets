/** 列表摘要只展示可读文字；正文 HTML 仍由阅读器处理。 */
export function htmlExcerptToText(html: string): string {
  return html
    // 属性里的 > 不代表标签结束；末尾可能是服务端截断的标签。
    .replace(/<!--[\s\S]*?(?:-->|$)/g, ' ')
    .replace(/<\/?[a-zA-Z](?:[^>"']|"[^"]*(?:"|$)|'[^']*(?:'|$))*(?:>|$)/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&quot;|&#34;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ')
    .trim();
}
