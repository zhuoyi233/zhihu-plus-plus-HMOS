import { FeedPage } from '../domain/DomainModels';

export interface FeedRepository {
  loadHomePage(cursor?: string): Promise<FeedPage>;
}
