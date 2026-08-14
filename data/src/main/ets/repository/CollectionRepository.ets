import {
  CollectionContentPage,
  CollectionContentKind,
  CollectionPage,
  CollectionSummary
} from '../domain/CollectionModels';

export interface CollectionRepository {
  getCollectionsPage(urlToken: string, cursor?: string): Promise<CollectionPage>;
  getCollection(collectionId: string): Promise<CollectionSummary>;
  getCollectionItemsPage(collectionId: string, cursor?: string): Promise<CollectionContentPage>;
  getContentCollections(contentType: string, contentId: string): Promise<Array<CollectionSummary>>;
  createCollection(title: string, description: string, isPublic: boolean): Promise<void>;
  deleteCollection(collectionId: string): Promise<void>;
  addContentToCollection(collectionId: string, contentType: string, contentId: string): Promise<void>;
  removeContentFromCollection(collectionId: string, contentType: string, contentId: string): Promise<void>;
  cancel(): void;
}

export function isSupportedCollectionContentType(value: string): boolean {
  return value === CollectionContentKind.ANSWER || value === CollectionContentKind.ARTICLE;
}
