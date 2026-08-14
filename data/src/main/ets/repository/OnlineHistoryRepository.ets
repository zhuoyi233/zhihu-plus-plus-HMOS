import { OnlineHistoryPage } from '../domain/OnlineHistoryModels';

export interface OnlineHistoryRepository {
  loadPage(cursor?: string): Promise<OnlineHistoryPage>;
  cancel(): void;
}
