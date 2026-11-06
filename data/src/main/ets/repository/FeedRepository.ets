import { FeedItem, FeedPage } from '../domain/DomainModels';

export interface FeedRepository {
  loadHomePage(cursor?: string): Promise<FeedPage>;
  /** 首屏来自快照时是否还要补一次静默刷新（沿用「启动时自动刷新首页」）。 */
  refreshAfterStartupCache?(): boolean;
  cancel(): void;
  subscribeRemoteReads?(listener: () => void): () => void;
  filterRemoteReads?(items: Array<FeedItem>): Promise<Array<FeedItem>>;
  startRemoteReadSync?(): void;
}
