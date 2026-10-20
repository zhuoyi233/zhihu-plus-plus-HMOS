import { describe, expect, it } from '@ohos/hypium';
import {
  decodeRemoteHistoryPage, defaultRecommendationFilterPreferences, FeedItem, FeedTargetKind,
  isRemoteHistoryUrl, RecommendationFilterPreferences, RecommendationFilterPreferencesGateway,
  RemoteHistoryPage, RemoteHistoryScheduler, RemoteHistorySource, RemoteHistorySync, RemoteReadGateway, RemoteReadRecord,
  REMOTE_HISTORY_FIRST_URL, schemaMigrationTo
} from 'data';

class SyncPreferences implements RecommendationFilterPreferencesGateway {
  value: RecommendationFilterPreferences = defaultRecommendationFilterPreferences();
  async loadRecommendationFilterPreferences(): Promise<RecommendationFilterPreferences> { return this.value; }
  async saveRecommendationFilterPreferences(value: RecommendationFilterPreferences): Promise<void> { this.value = value; }
}

class MemoryRemoteReads implements RemoteReadGateway {
  readonly keys: Set<string> = new Set<string>();
  readonly times: Map<string, number> = new Map<string, number>();
  readonly attempts: Map<string, number> = new Map<string, number>();
  async claimSync(account: string, now: number): Promise<boolean> {
    const previous = this.attempts.get(account);
    if (previous !== undefined && now - previous < 60000) return false;
    this.attempts.set(account, now);
    return true;
  }
  async watermark(account: string): Promise<number> { return this.times.get(account) ?? 0; }
  async importPage(account: string, records: Array<RemoteReadRecord>): Promise<void> {
    records.forEach((record: RemoteReadRecord): void => { this.keys.add(`${account}/${record.contentKey}`); });
  }
  async saveWatermark(account: string, time: number): Promise<void> { this.times.set(account, time); }
  async readKeys(account: string, keys: Array<string>): Promise<Array<string>> {
    return keys.filter((key: string): boolean => this.keys.has(`${account}/${key}`));
  }
  async clear(account: string): Promise<void> {
    this.times.delete(account);
    this.attempts.delete(account);
    this.keys.forEach((key: string): void => { if (key.startsWith(`${account}/`)) this.keys.delete(key); });
  }
}

class HistoryPages implements RemoteHistorySource {
  readonly urls: Array<string> = [];
  pages: Array<RemoteHistoryPage> = [];
  failAt: number = -1;
  cancelCount: number = 0;
  async load(url: string): Promise<RemoteHistoryPage> {
    const index = this.urls.length;
    this.urls.push(url);
    if (index === this.failAt || this.pages.length === 0) throw new Error('offline');
    return this.pages.shift()!;
  }
  cancel(): void { this.cancelCount += 1; }
}

class PendingHistory implements RemoteHistorySource {
  requestCount: number = 0;
  resolve: (page: RemoteHistoryPage) => void = (_page: RemoteHistoryPage): void => {};
  async load(_url: string): Promise<RemoteHistoryPage> {
    this.requestCount += 1;
    return new Promise<RemoteHistoryPage>((resolve): void => { this.resolve = resolve; });
  }
  cancel(): void {}
}

interface ScheduledAction {
  id: number;
  due: number;
  action: () => void;
}

export class VirtualHistoryClock implements RemoteHistoryScheduler {
  now: number = 0;
  private nextId: number = 0;
  private actions: Array<ScheduledAction> = [];

  schedule(action: () => void, delayMs: number): number {
    const id = ++this.nextId;
    this.actions.push({ id: id, due: this.now + delayMs, action: action });
    return id;
  }

  cancel(timer: number): void {
    this.actions = this.actions.filter((action: ScheduledAction): boolean => action.id !== timer);
  }

  pendingCount(): number { return this.actions.length; }

  advance(ms: number): void {
    this.now += ms;
    const due = this.actions.filter((action: ScheduledAction): boolean => action.due <= this.now);
    this.actions = this.actions.filter((action: ScheduledAction): boolean => action.due > this.now);
    due.forEach((action: ScheduledAction): void => action.action());
  }
}

function historyPage(ids: Array<string>, times: Array<number>, next?: string): RemoteHistoryPage {
  return {
    records: ids.map((id: string, index: number): RemoteReadRecord => ({ contentKey: id, readTime: times[index] })),
    readTimes: times, isEnd: next === undefined, next: next
  };
}

function item(id: string, kind: FeedTargetKind = FeedTargetKind.ANSWER): FeedItem {
  return { id: id, verb: '', createdAt: 0, updatedAt: 0,
    target: { id: id, kind: kind, title: '', excerpt: '', url: '', topicIds: [] } };
}

async function flush(): Promise<void> {
  for (let index = 0; index < 12; index += 1) await Promise.resolve();
}

const NEXT = 'https://api.zhihu.com/unify-consumption/read_history?offset=50&limit=50';
const THIRD = 'https://api.zhihu.com/unify-consumption/read_history?offset=100&limit=50';

export default function remoteHistorySyncTest(): void {
  describe('remoteHistorySyncTest', () => {
    it('mapsSupportedIdentitiesWithoutRequiringDisplayTitlesAndKeepsUnsupportedTimes', 0, () => {
      const page = decodeRemoteHistoryPage('{"data":[' +
        '{"data":{"action":{"url":"zhihu://answers/123"},"extra":{"read_time":100}}},' +
        '{"data":{"action":{"url":"https://www.zhihu.com/people/a"},"extra":{"read_time":99}}},' +
        '{"data":{"action":{"url":"https://zhuanlan.zhihu.com/p/123"},"extra":{"read_time":98}}}' +
        '],"paging":{"is_end":true}}');
      expect(page.records.length).assertEqual(2);
      expect(page.records[0].contentKey).assertEqual('answer:123');
      expect(page.records[1].contentKey).assertEqual('article:123');
      expect(page.readTimes.join(',')).assertEqual('100000,99000,98000');
    });

    it('rejectsUntrustedPaginationAndIncompleteResponses', 0, () => {
      expect(isRemoteHistoryUrl(NEXT)).assertTrue();
      expect(isRemoteHistoryUrl(NEXT.replace('api.zhihu.com', 'api.zhihu.com.evil.test'))).assertFalse();
      expect(isRemoteHistoryUrl(NEXT + '#x')).assertFalse();
      expect(isRemoteHistoryUrl(NEXT + '&offset=0')).assertFalse();
      expect(() => decodeRemoteHistoryPage('{"data":[]}')).assertThrowError('Invalid remote history response');
      expect(() => decodeRemoteHistoryPage('{"data":[],"paging":{"is_end":false,"next":"' + NEXT + '"}}'))
        .assertThrowError('Invalid remote history pagination');
      expect(() => decodeRemoteHistoryPage('{"error":{"code":401},"data":[],"paging":{"is_end":true}}'))
        .assertThrowError('Invalid remote history response');
    });

    it('scansPastKnownAndUnmappedPagesUntilTheRemoteEnd', 0, async () => {
      const source = new HistoryPages();
      const store = new MemoryRemoteReads();
      store.keys.add('a/answer:1');
      source.pages = [historyPage(['answer:1'], [300], NEXT), historyPage([], [200], THIRD),
        historyPage(['article:1'], [100])];
      const sync = new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences());
      await sync.start();
      expect(source.urls.length).assertEqual(3);
      expect(store.keys.has('a/article:1')).assertTrue();
      expect(await store.watermark('a')).assertEqual(300);
    });

    it('includesAllBoundaryTiesAndStopsOnlyAfterAnOlderRecord', 0, async () => {
      const source = new HistoryPages();
      const store = new MemoryRemoteReads();
      store.times.set('a', 200);
      source.pages = [historyPage(['answer:1'], [300], NEXT),
        historyPage(['answer:2'], [200], THIRD), historyPage(['answer:3', 'answer:4'], [200, 199], NEXT)];
      await new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences(), (): number => 0).start();
      expect(source.urls.length).assertEqual(3);
      expect(store.keys.has('a/answer:3')).assertTrue();
      expect(await store.watermark('a')).assertEqual(300);
    });

    it('doesNotAdvanceProgressOnFailureAndRetriesFromFirstPage', 0, async () => {
      const source = new HistoryPages();
      const store = new MemoryRemoteReads();
      source.pages = [historyPage(['answer:1'], [300], NEXT)];
      source.failAt = 1;
      let now = 0;
      const sync = new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences(), (): number => now);
      await sync.start();
      expect(await store.watermark('a')).assertEqual(0);
      expect(store.keys.has('a/answer:1')).assertTrue();
      now = 60000;
      source.pages = [historyPage(['answer:1'], [300], NEXT), historyPage(['answer:2'], [200])];
      await sync.start();
      expect(source.urls[2]).assertEqual(REMOTE_HISTORY_FIRST_URL);
      expect(await store.watermark('a')).assertEqual(300);
      expect(store.keys.size).assertEqual(2);
    });

    it('disablesBoundaryShortcutsWhenRemoteTimesAreUnorderedOrMissing', 0, async () => {
      const source = new HistoryPages();
      const store = new MemoryRemoteReads();
      store.times.set('a', 200);
      source.pages = [historyPage(['answer:1', 'answer:2'], [300, 400], NEXT),
        historyPage(['answer:3'], [100], THIRD), historyPage(['answer:4'], [50])];
      await new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences()).start();
      expect(source.urls.length).assertEqual(3);
      expect(await store.watermark('a')).assertEqual(400);
      source.pages = [historyPage([], [0, 100], NEXT), historyPage(['answer:5'], [50])];
      const nextSync = new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences(),
        (): number => Date.now() + 60000);
      await nextSync.start();
      expect(store.keys.has('a/answer:5')).assertTrue();
    });

    it('rejectsRepeatedCursorsWithoutSavingPartialProgress', 0, async () => {
      const source = new HistoryPages();
      const store = new MemoryRemoteReads();
      source.pages = [historyPage(['answer:1'], [300], NEXT), historyPage(['answer:2'], [200], NEXT)];
      await new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences()).start();
      expect(source.urls.length).assertEqual(2);
      expect(await store.watermark('a')).assertEqual(0);
    });

    it('sharesTheActiveJobAndThrottlesNewAttemptsForSixtySeconds', 0, async () => {
      const source = new HistoryPages();
      source.pages = [historyPage([], [])];
      let now = 0;
      const sync = new RemoteHistorySync(source, new MemoryRemoteReads(), (): string => 'a',
        new SyncPreferences(), (): number => now);
      const first = sync.start();
      expect(first === sync.start()).assertTrue();
      await first;
      now = 59999;
      await sync.start();
      expect(source.urls.length).assertEqual(1);
      now = 60000;
      source.pages = [historyPage([], [])];
      await sync.start();
      expect(source.urls.length).assertEqual(2);
    });

    it('keepsTheSixtySecondThrottleAcrossSyncObjectRecreationIncludingFailedAttempts', 0, async () => {
      const store = new MemoryRemoteReads();
      const failed = new HistoryPages();
      await new RemoteHistorySync(failed, store, (): string => 'a', new SyncPreferences(), (): number => 1000).start();
      const retry = new HistoryPages();
      retry.pages = [historyPage([], [])];
      await new RemoteHistorySync(retry, store, (): string => 'a', new SyncPreferences(), (): number => 60999).start();
      expect(retry.urls.length).assertEqual(0);
      await new RemoteHistorySync(retry, store, (): string => 'a', new SyncPreferences(), (): number => 61000).start();
      expect(retry.urls.length).assertEqual(1);
    });

    it('waitsAt299msReleasesAt300msAndFiltersTheLateResultWithoutAnotherRequest', 0, async () => {
      const source = new PendingHistory();
      const clock = new VirtualHistoryClock();
      const sync = new RemoteHistorySync(source, new MemoryRemoteReads(), (): string => 'a', new SyncPreferences(),
        (): number => clock.now, clock);
      const work = sync.start();
      expect(sync.start() === work).assertTrue();
      let released = false;
      const foreground = sync.awaitRecentPage().then((): void => { released = true; });
      await flush();
      clock.advance(299);
      await flush();
      expect(released).assertFalse();
      expect((await sync.filter([item('1')])).length).assertEqual(1);
      clock.advance(1);
      await foreground;
      expect(released).assertTrue();
      expect(clock.pendingCount()).assertEqual(0);
      expect(source.requestCount).assertEqual(1);
      source.resolve(historyPage(['answer:1'], [100]));
      await work;
      expect((await sync.filter([item('1')])).length).assertEqual(0);
      expect(source.requestCount).assertEqual(1);
    });

    it('releasesAsSoonAsTheFirstPageIsStoredAndCancelsTheRemainingTimer', 0, async () => {
      const source = new PendingHistory();
      const clock = new VirtualHistoryClock();
      const sync = new RemoteHistorySync(source, new MemoryRemoteReads(), (): string => 'a', new SyncPreferences(),
        (): number => clock.now, clock);
      const work = sync.start();
      let released = false;
      const foreground = sync.awaitRecentPage().then((): void => { released = true; });
      await flush();
      clock.advance(120);
      source.resolve(historyPage(['answer:1'], [100]));
      await work;
      await foreground;
      expect(released).assertTrue();
      expect(clock.now).assertEqual(120);
      expect(clock.pendingCount()).assertEqual(0);
    });

    it('filtersReadsByTypeWhileRetainingFollowedAuthorsAndHonoringFilterSettings', 0, async () => {
      const store = new MemoryRemoteReads();
      store.keys.add('a/answer:1');
      const preferences = new SyncPreferences();
      const sync = new RemoteHistorySync(new HistoryPages(), store, (): string => 'a', preferences);
      const followed = item('1');
      followed.target.authorIsFollowing = true;
      const items = [item('1'), item('1', FeedTargetKind.ARTICLE), followed];
      expect((await sync.filter(items)).length).assertEqual(2);
      preferences.value.enableContentFilter = false;
      expect((await sync.filter(items)).length).assertEqual(3);
      preferences.value.enableContentFilter = true;
      preferences.value.reverseBlock = true;
      expect((await sync.filter(items)).length).assertEqual(3);
    });

    it('skipsGuestsAndIsolatesAccountsAndTheirProgress', 0, async () => {
      let account = '';
      const source = new HistoryPages();
      const store = new MemoryRemoteReads();
      source.pages = [historyPage(['answer:1'], [100]), historyPage(['answer:2'], [200])];
      const sync = new RemoteHistorySync(source, store, (): string => account, new SyncPreferences());
      await sync.start();
      expect(source.urls.length).assertEqual(0);
      account = 'a';
      await sync.start();
      account = 'b';
      await sync.start();
      expect((await sync.filter([item('1'), item('2')]))[0].target.id).assertEqual('1');
      expect(await store.watermark('a')).assertEqual(100);
      expect(await store.watermark('b')).assertEqual(200);
    });

    it('discardsResponsesFromAnOldAccount', 0, async () => {
      let account = 'a';
      const source = new PendingHistory();
      const store = new MemoryRemoteReads();
      const sync = new RemoteHistorySync(source, store, (): string => account, new SyncPreferences());
      const work = sync.start();
      await flush();
      account = 'b';
      source.resolve(historyPage(['answer:1'], [100]));
      await work;
      expect(store.keys.size).assertEqual(0);
    });

    it('clearsImportedReadsAndCancelsLateImportsWithoutTouchingOtherAccounts', 0, async () => {
      const source = new PendingHistory();
      const store = new MemoryRemoteReads();
      store.keys.add('a/answer:1');
      store.keys.add('b/answer:1');
      store.times.set('a', 100);
      const sync = new RemoteHistorySync(source, store, (): string => 'a', new SyncPreferences());
      const work = sync.start();
      await flush();
      await sync.clear();
      source.resolve(historyPage(['answer:2'], [200]));
      await work;
      expect(store.keys.has('a/answer:1')).assertFalse();
      expect(store.keys.has('a/answer:2')).assertFalse();
      expect(store.keys.has('b/answer:1')).assertTrue();
      expect(await store.watermark('a')).assertEqual(0);
    });

    it('keepsRemoteReadIdentityStorageIndependentOfLocalHistoryRetention', 0, () => {
      const sql = schemaMigrationTo(9).statements.join(' ');
      expect(sql.includes('PRIMARY KEY (account_key, content_key)')).assertTrue();
      expect(sql.includes('remote_history_sync')).assertTrue();
      expect(sql.includes('opened_content')).assertFalse();
      expect(sql.includes('cookie')).assertFalse();
    });
  });
}
