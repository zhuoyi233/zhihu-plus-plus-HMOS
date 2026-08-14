import { PageCursor } from './DomainModels';

export enum CollectionContentKind {
  ANSWER = 'answer',
  ARTICLE = 'article',
  QUESTION = 'question',
  PIN = 'pin'
}

export interface CollectionSummary {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly isPublic: boolean;
  readonly answerCount: number;
  readonly followerCount: number;
  readonly itemCount: number;
  readonly likeCount: number;
  readonly commentCount: number;
  readonly isFavorited: boolean;
  readonly updatedAt: number;
  readonly creatorName?: string;
}

export interface CollectionPage {
  readonly items: Array<CollectionSummary>;
  readonly cursor: PageCursor;
}

export interface CollectionContentItem {
  readonly kind: CollectionContentKind;
  readonly id: string;
  readonly title: string;
  readonly excerpt: string;
  readonly details: string;
  readonly voteupCount: number;
  readonly commentCount: number;
  readonly authorName?: string;
  readonly createdAt: number;
}

export interface CollectionContentPage {
  readonly items: Array<CollectionContentItem>;
  readonly cursor: PageCursor;
}

export function collectionIdentity(collection: CollectionSummary): string {
  return collection.id;
}

export function collectionContentIdentity(item: CollectionContentItem): string {
  return `${item.kind}:${item.id}`;
}
