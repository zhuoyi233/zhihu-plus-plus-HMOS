import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';
import {
  contentIdentityKey,
  ContentFilterOutcome,
  ContentFilterRuntimeGateway,
  ContentFilterRuntimeSnapshot,
  ContentFilterStats
} from './BlockingRuleStore';
import { BlockedFeedHistoryGateway } from './BlockedFeedHistoryStore';

const VIEW_TABLE = 'content_filter_views';
const MAX_CONTENT_FILTER_RECORDS = 10000;

export class ContentFilterRuntimeStore implements ContentFilterRuntimeGateway {
  private readonly database: AppDatabase;
  private readonly history: BlockedFeedHistoryGateway;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(database: AppDatabase, history: BlockedFeedHistoryGateway) {
    this.database = database;
    this.history = history;
  }

  async loadSnapshot(): Promise<ContentFilterRuntimeSnapshot> {
    await this.mutationQueue;
    const store = await this.database.open();
    const viewCounts: Record<string, number> = {};
    const views = await store.query(new relationalStore.RdbPredicates(VIEW_TABLE), ['content_key', 'view_count']);
    try {
      if (views.goToFirstRow()) {
        do {
          viewCounts[views.getString(views.getColumnIndex('content_key'))] =
            views.getLong(views.getColumnIndex('view_count'));
        } while (views.goToNextRow());
      }
    } finally {
      views.close();
    }
    const openedKeys: Array<string> = [];
    const opened = await store.query(new relationalStore.RdbPredicates('opened_content'), ['content_key']);
    try {
      if (opened.goToFirstRow()) {
        do {
          openedKeys.push(opened.getString(opened.getColumnIndex('content_key')));
        } while (opened.goToNextRow());
      }
    } finally {
      opened.close();
    }
    return { viewCounts: viewCounts, openedKeys: openedKeys };
  }

  recordOutcomes(outcomes: Array<ContentFilterOutcome>): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const store = await this.database.open();
      const now = Date.now();
      for (let index = 0; index < outcomes.length; index += 1) {
        const outcome = outcomes[index];
        const key = contentIdentityKey(outcome.content);
        if (outcome.match === undefined && key.length > 0) {
          const current = await this.readViewCount(store, key);
          const values: relationalStore.ValuesBucket = {
            content_key: key,
            view_count: current + 1,
            last_viewed_at: now
          };
          await store.insert(VIEW_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        } else if (outcome.match !== undefined) {
          if ((outcome.content.contentId ?? '').length > 0 && (outcome.content.contentKind ?? '').length > 0) {
            await this.history.insert({
              kind: outcome.match.kind,
              ruleId: outcome.match.ruleId,
              ruleName: outcome.match.reason,
              contentTitle: outcome.content.title,
              contentKind: outcome.content.contentKind ?? 'content',
              contentId: outcome.content.contentId ?? 'unknown',
              blockedAt: now
            });
          }
        }
      }
    });
  }

  async loadStats(): Promise<ContentFilterStats> {
    await this.mutationQueue;
    return this.readComputedStats(await this.database.open());
  }

  cleanupOldData(cutoff: number): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const store = await this.database.open();
      await store.delete(new relationalStore.RdbPredicates(VIEW_TABLE).lessThan('last_viewed_at', cutoff));
      await this.history.deleteBefore?.(cutoff);
      const stats = await this.readComputedStats(store);
      if (stats.totalSeen > MAX_CONTENT_FILTER_RECORDS) {
        await store.delete(new relationalStore.RdbPredicates(VIEW_TABLE));
        await this.history.clear();
      }
    });
  }

  clearAllData(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const store = await this.database.open();
      await store.delete(new relationalStore.RdbPredicates(VIEW_TABLE));
      await this.history.clear();
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const result = this.mutationQueue.then(operation, operation);
    this.mutationQueue = result.then((): void => {}, (): void => {});
    return result;
  }

  private async readViewCount(store: relationalStore.RdbStore, key: string): Promise<number> {
    const result = await store.query(new relationalStore.RdbPredicates(VIEW_TABLE).equalTo('content_key', key),
      ['view_count']);
    try {
      return result.goToFirstRow() ? result.getLong(result.getColumnIndex('view_count')) : 0;
    } finally {
      result.close();
    }
  }

  private async readComputedStats(store: relationalStore.RdbStore): Promise<ContentFilterStats> {
    const result = await store.querySql('SELECT COALESCE(SUM(view_count), 0) AS kept_count FROM content_filter_views');
    try {
      const keptCount = result.goToFirstRow() ? result.getLong(result.getColumnIndex('kept_count')) : 0;
      const filteredRecords = await this.history.queryRecent();
      const totalFiltered = filteredRecords.length;
      const totalSeen = keptCount + totalFiltered;
      return {
        totalSeen: totalSeen,
        totalFiltered: totalFiltered,
        filterRate: totalSeen <= 0 ? 0 : totalFiltered / totalSeen,
        lastFilteredAt: filteredRecords.length === 0 ? 0 : filteredRecords[0].blockedAt
      };
    } finally {
      result.close();
    }
  }
}
