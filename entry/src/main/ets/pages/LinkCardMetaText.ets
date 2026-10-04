import { LinkCardMeta, LinkCardResourceKind } from 'data';

/** 卡片计数格式化（对齐网页卡片 meta 行与站内惯例）：亿/万缩写，其余原样。 */
export function formatLinkCardCount(value: number): string {
  if (value >= 100000000) {
    return `${(value / 100000000).toFixed(1)} 亿`;
  }
  if (value >= 10000) {
    return `${(value / 10000).toFixed(1)} 万`;
  }
  return `${value}`;
}

/** 站内资源类型标注文案（对齐网页卡片的资源类型尾巴）。 */
export function linkCardKindLabel(kind: LinkCardResourceKind): string {
  switch (kind) {
    case LinkCardResourceKind.ANSWER:
      return '回答';
    case LinkCardResourceKind.ARTICLE:
      return '文章';
    case LinkCardResourceKind.QUESTION:
      return '问题';
    case LinkCardResourceKind.PIN:
      return '想法';
    default:
      return '';
  }
}

/** 卡片 meta 行：`赞同 X · 评论 Y · 类型`；问题资源为 `N 回答 · 问题`。 */
export function linkCardMetaLine(meta: LinkCardMeta): string {
  const parts: Array<string> = [];
  if (meta.kind === LinkCardResourceKind.QUESTION) {
    if (meta.answerCount !== undefined) {
      parts.push(`${formatLinkCardCount(meta.answerCount)} 回答`);
    }
  } else {
    if (meta.voteupCount !== undefined) {
      parts.push(`${formatLinkCardCount(meta.voteupCount)} 赞同`);
    }
    if (meta.commentCount !== undefined) {
      parts.push(`${formatLinkCardCount(meta.commentCount)} 评论`);
    }
  }
  const kindLabel = linkCardKindLabel(meta.kind);
  if (kindLabel.length > 0) {
    parts.push(kindLabel);
  }
  return parts.join(' · ');
}
