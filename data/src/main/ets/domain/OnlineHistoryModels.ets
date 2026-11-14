import { PageCursor } from './DomainModels';

export enum OnlineHistoryKind {
  QUESTION = 'question',
  ANSWER = 'answer',
  ARTICLE = 'article',
  PIN = 'pin'
}

export interface OnlineHistoryEntry {
  contentKey: string;
  kind: OnlineHistoryKind;
  id: string;
  title: string;
  summary: string;
  authorName?: string;
  /** 封面图（响应 content.cover_image）；缺失/空串为 undefined，卡片按无图降级。
   *  实测多为空/缺失（回答/问题条目），文章类条目可能出现；header.icon 为固定类型图标非头像，不接。 */
  coverImageUrl?: string;
  readTime: number;
}

export interface OnlineHistoryPage {
  items: Array<OnlineHistoryEntry>;
  cursor: PageCursor;
}
