import { FeedTargetKind, PageCursor } from './DomainModels';

export interface SearchResultItem {
  readonly wrapperId: string;
  readonly kind: FeedTargetKind;
  readonly contentId: string;
  readonly title: string;
  readonly excerpt: string;
  readonly authorId?: string;
  readonly authorName?: string;
  readonly topicIds: Array<string>;
  readonly voteupCount: number;
  readonly commentCount: number;
}

export interface SearchResultPage {
  readonly items: Array<SearchResultItem>;
  readonly cursor: PageCursor;
}

export function searchResultIdentity(item: SearchResultItem): string {
  return `${item.kind}:${item.contentId}`;
}
