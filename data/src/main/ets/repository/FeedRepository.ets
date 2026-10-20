import { FeedItem, FeedPage } from '../domain/DomainModels';

export interface FeedRepository {
  loadHomePage(cursor?: string): Promise<FeedPage>;
  cancel(): void;
  subscribeRemoteReads?(listener: () => void): () => void;
  filterRemoteReads?(items: Array<FeedItem>): Promise<Array<FeedItem>>;
  startRemoteReadSync?(): void;
}
