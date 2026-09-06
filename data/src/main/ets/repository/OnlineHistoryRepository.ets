import { OnlineHistoryPage } from '../domain/OnlineHistoryModels';

export interface OnlineHistoryRepository {
  loadPage(cursor?: string): Promise<OnlineHistoryPage>;
  /** 对齐上游 clearAllHistory：batch_del(clear=true) 清空服务端全部浏览历史。 */
  clearAll(): Promise<void>;
  /** 对齐上游 deleteItem：batch_del 单条删除，contentKey 形如 "answer:123456"。 */
  deleteEntry(contentKey: string): Promise<void>;
  cancel(): void;
}
