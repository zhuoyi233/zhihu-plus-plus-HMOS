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
  readTime: number;
}

export interface OnlineHistoryPage {
  items: Array<OnlineHistoryEntry>;
  cursor: PageCursor;
}
