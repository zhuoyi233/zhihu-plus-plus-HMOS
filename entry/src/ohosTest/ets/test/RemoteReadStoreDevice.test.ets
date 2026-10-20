import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { systemDateTime } from '@kit.BasicServicesKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeEach, afterEach, expect, it } from '@ohos/hypium';
import {
  AppDatabase, BlockableContentSummary, BlockedFeedHistoryStore, BlockingRuleMatcher, BlockingRuleStore, ContentBlockingStrategy,
  ContentFilterRuntimeStore, CURRENT_SCHEMA_VERSION, defaultRecommendationFilterPreferences, FeedItem, FeedTargetKind,
  OpenedContentStore, RecommendationFilterPreferences, RecommendationFilterPreferencesGateway,
  RemoteHistoryPage, RemoteHistorySource, RemoteHistorySync, RemoteReadRecord, RemoteReadStore,
  decodeRemoteHistoryPage, defaultBlockingPreferences, remoteReadQuerySql, schemaMigrationTo, BlockingRuleKind,
  BlockingPreferences, BlockingPreferencesGateway
} from 'data';
import { VirtualHistoryClock } from '../../../test/RemoteHistorySync.test';

class DevicePreferences implements RecommendationFilterPreferencesGateway, BlockingPreferencesGateway {
  value: RecommendationFilterPreferences = defaultRecommendationFilterPreferences();
  blocking: BlockingPreferences = defaultBlockingPreferences();
  async loadRecommendationFilterPreferences(): Promise<RecommendationFilterPreferences> { return this.value; }
  async saveRecommendationFilterPreferences(value: RecommendationFilterPreferences): Promise<void> { this.value = value; }
  async loadBlockingPreferences(): Promise<BlockingPreferences> { return this.blocking; }
  async saveBlockingPreferences(value: BlockingPreferences): Promise<void> { this.blocking = value; }
}

/** 只替代网络传输；解码、同步、存储、查询及过滤均使用生产实现。 */
class DeviceHistorySource implements RemoteHistorySource {
  readonly requests: Array<string> = [];
  pages: Array<string> = [];
  gate?: Promise<void>;
  onRequest: () => void = (): void => {};
  async load(url: string): Promise<RemoteHistoryPage> {
    this.requests.push(url);
    this.onRequest();
    await this.gate;
    const body = this.pages.shift();
    if (body === undefined) throw new Error('No fixture response');
    return decodeRemoteHistoryPage(body);
  }
  cancel(): void {}
}

function historyPage(ids: Array<number>, times: Array<number>, next?: string): string {
  const records = ids.map((id: number, index: number): string =>
    `{"data":{"action":{"url":"zhihu://answers/${id}"},"extra":{"read_time":${times[index]}}}}`);
  return `{"data":[${records.join(',')}],"paging":{"is_end":${next === undefined},` +
    `"next":"${next ?? ''}"}}`;
}

function candidate(id: string, kind: FeedTargetKind = FeedTargetKind.ANSWER): FeedItem {
  return { id: id, verb: '', createdAt: 0, updatedAt: 0,
    target: { id: id, kind: kind, title: '', excerpt: '', url: '', topicIds: [] } };
}

async function queryStrings(store: relationalStore.RdbStore, sql: string,
  args: Array<relationalStore.ValueType> = [], column: number = 0): Promise<Array<string>> {
  const rows: Array<string> = [];
  if (sql.startsWith('EXPLAIN')) {
    // API 23 的共享 ResultSet 对 EXPLAIN 报告 rowCount=0；使用 API 23 的 LiteResultSet 逐行读取。
    const plan = await store.querySqlWithoutRowCount(sql, args);
    try {
      while (plan.goToNextRow()) rows.push(plan.getString(column));
    } finally { plan.close(); }
    return rows;
  }
  const result = await store.querySql(sql, args);
  try {
    if (result.goToFirstRow()) {
      do { rows.push(result.getString(column)); } while (result.goToNextRow());
    }
  } finally { result.close(); }
  return rows;
}

function median(values: Array<number>): number {
  const sorted = values.slice().sort((left: number, right: number): number => left - right);
  return (sorted[14] + sorted[15]) / 2;
}

function monotonicMs(): number {
  return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, true) / 1000000;
}

export default function remoteReadStoreDeviceTest(): void {
  describe('RemoteReadStoreDeviceTest', () => {
    const context: common.Context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
      .getApplicationContext().createModuleContext('entry');
    let name = '';
    let database: AppDatabase;
    let reads: RemoteReadStore;
    let sequence = 0;

    beforeEach((): void => {
      name = `remote_history_test_${Date.now()}_${++sequence}.db`;
      database = new AppDatabase(context, name);
      reads = new RemoteReadStore(database);
    });

    afterEach(async (): Promise<void> => {
      await database.close();
      await relationalStore.deleteRdbStore(context, name);
      hilog.info(0xD001, 'RemoteReadDeviceTest', 'isolated database removed');
    });

    it('migratesVersionEightWithoutChangingExistingLocalReads', 0, async () => {
      const legacy = await relationalStore.getRdbStore(context,
        { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      try {
        for (let version = 1; version <= 8; version += 1) {
          for (const sql of schemaMigrationTo(version).statements) await legacy.executeSql(sql);
          legacy.version = version;
        }
        await legacy.insert('opened_content',
          { content_key: 'answer:42', opened_at: 123, content_type: 'answer', title: 'local' });
      } finally { await legacy.close(); }
      const upgraded = await database.open();
      expect(upgraded.version).assertEqual(CURRENT_SCHEMA_VERSION);
      const local = await new OpenedContentStore(database).query('answer:42');
      expect(local?.openedAt).assertEqual(123);
      expect(local?.title).assertEqual('local');
      expect((await reads.readKeys('a', ['answer:42'])).length).assertEqual(0);
      expect(await reads.watermark('a')).assertEqual(0);
    });

    it('deduplicatesRepeatedImportsAndSeparatesTypesAccountsAndLocalSources', 0, async () => {
      const local = new OpenedContentStore(database);
      await local.upsert({ contentKey: 'answer:43', openedAt: 999, contentType: 'answer', title: 'local' });
      const page: Array<RemoteReadRecord> = [
        { contentKey: 'answer:42', readTime: 100 }, { contentKey: 'answer:42', readTime: 200 },
        { contentKey: 'article:42', readTime: 100 }
      ];
      await reads.importPage('a', page);
      await reads.importPage('a', page);
      await reads.importPage('b', [{ contentKey: 'answer:44', readTime: 100 }]);
      const found = await reads.readKeys('a', ['answer:42', 'answer:42', 'article:42', 'answer:43', 'answer:44']);
      expect(found.slice().sort().join(',')).assertEqual('answer:42,article:42');
      expect((await reads.readKeys('b', ['answer:42', 'answer:44'])).join(',')).assertEqual('answer:44');
      expect(await local.query('answer:42')).assertUndefined();
      expect((await local.query('answer:43'))?.openedAt).assertEqual(999);
      const raw = await queryStrings(await database.open(), 'SELECT content_key FROM remote_read_content');
      expect(raw.length).assertEqual(3);
    });

    it('queriesMoreThanOneThousandCandidatesInBoundedBatchesWithoutDuplicates', 0, async () => {
      const records: Array<RemoteReadRecord> = [];
      const keys: Array<string> = [];
      for (let index = 1; index <= 1503; index += 1) {
        const key = `answer:${index}`;
        records.push({ contentKey: key, readTime: index });
        keys.push(key);
        keys.push(key);
      }
      await reads.importPage('a', records);
      keys.push('article:1', 'answer:999999');
      const found = await reads.readKeys('a', keys);
      expect(found.length).assertEqual(1503);
      expect(new Set<string>(found).size).assertEqual(1503);
      expect(found.includes('answer:1503')).assertTrue();
      expect(found.includes('article:1')).assertFalse();
      expect((await reads.readKeys('a', [])).length).assertEqual(0);
    });

    it('persistsReadIdentitiesAndWatermarksAcrossDatabaseAndRepositoryRecreation', 0, async () => {
      await reads.importPage('a', [{ contentKey: 'answer:1', readTime: 100 }]);
      await reads.saveWatermark('a', 100);
      await database.close();
      database = new AppDatabase(context, name);
      reads = new RemoteReadStore(database);
      expect(await reads.watermark('a')).assertEqual(100);
      expect((await reads.readKeys('a', ['answer:1'])).join(',')).assertEqual('answer:1');
      expect(await reads.watermark('b')).assertEqual(0);
      expect((await reads.readKeys('b', ['answer:1'])).length).assertEqual(0);
    });

    it('upgradesVersionNineAndPreservesTheExistingRemoteProgress', 0, async () => {
      const legacy = await relationalStore.getRdbStore(context,
        { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      try {
        for (let version = 1; version <= 9; version += 1) {
          for (const sql of schemaMigrationTo(version).statements) await legacy.executeSql(sql);
          legacy.version = version;
        }
        await legacy.insert('remote_history_sync', { account_key: 'a', read_time: 123000 });
        await legacy.insert('remote_read_content', { account_key: 'a', content_key: 'answer:42' });
      } finally { await legacy.close(); }
      expect(await reads.watermark('a')).assertEqual(123000);
      expect((await reads.readKeys('a', ['answer:42'])).length).assertEqual(1);
      expect(await reads.claimSync('a', 1000)).assertTrue();
      await reads.saveWatermark('a', 124000);
      expect(await reads.claimSync('a', 60999)).assertFalse();
      expect(await reads.watermark('a')).assertEqual(124000);
      expect((await database.open()).version).assertEqual(10);
    });

    it('persistsFailedSyncAttemptsAcrossRecreationAndClaimsOnlyOneConcurrentAttempt', 0, async () => {
      const failed = new DeviceHistorySource();
      failed.pages = ['{}'];
      await new RemoteHistorySync(failed, reads, (): string => 'a', new DevicePreferences(), (): number => 1000).start();
      await database.close();
      database = new AppDatabase(context, name);
      reads = new RemoteReadStore(database);
      const retry = new DeviceHistorySource();
      retry.pages = [historyPage([], [])];
      await new RemoteHistorySync(retry, reads, (): string => 'a', new DevicePreferences(), (): number => 60999).start();
      expect(retry.requests.length).assertEqual(0);
      await new RemoteHistorySync(retry, reads, (): string => 'a', new DevicePreferences(), (): number => 61000).start();
      expect(retry.requests.length).assertEqual(1);
      const left = new DeviceHistorySource();
      const right = new DeviceHistorySource();
      left.pages = [historyPage([], [])];
      right.pages = [historyPage([], [])];
      await Promise.all([
        new RemoteHistorySync(left, new RemoteReadStore(database), (): string => 'a', new DevicePreferences(),
          (): number => 121000).start(),
        new RemoteHistorySync(right, new RemoteReadStore(database), (): string => 'a', new DevicePreferences(),
          (): number => 121000).start()
      ]);
      expect(left.requests.length + right.requests.length).assertEqual(1);
    });

    it('filtersLocalReadsThroughTheProductionHomeMatcherAndHonorsSettings', 0, async () => {
      const local = new OpenedContentStore(database);
      await local.upsert({ contentKey: 'answer:1', openedAt: 99, contentType: 'answer' });
      const preferences = new DevicePreferences();
      const history = new BlockedFeedHistoryStore(database);
      const runtime = new ContentFilterRuntimeStore(database, history);
      const matcher = new BlockingRuleMatcher(new BlockingRuleStore(database), preferences,
        ContentBlockingStrategy.HOME_FULL, preferences, runtime);
      const summary: BlockableContentSummary = {
        contentId: '1', contentKind: 'answer', title: '', excerpt: '', topicIds: []
      };
      const session = await matcher.createSession(['answer:1', 'article:1']);
      expect(session.match(summary)?.kind).assertEqual(BlockingRuleKind.SMART);
      expect(session.match({ contentId: '1', contentKind: 'article', title: '', excerpt: '', topicIds: [] }))
        .assertUndefined();
      expect(session.match({ contentId: '1', contentKind: 'answer', title: '', excerpt: '', topicIds: [],
        authorIsFollowing: true })).assertUndefined();
      preferences.value.enableContentFilter = false;
      expect((await matcher.createSession(['answer:1'])).match(summary)).assertUndefined();
      preferences.value.enableContentFilter = true;
      preferences.value.reverseBlock = true;
      expect((await matcher.createSession(['answer:1'])).match(summary)?.kind).assertEqual(BlockingRuleKind.REVERSE);
    });

    it('retainsLocalReadIdentitiesBeyondTheDisplayLimitAndLoadsOnlyCandidateBatches', 0, async () => {
      const local = new OpenedContentStore(database);
      const keys: Array<string> = [];
      for (let id = 1; id <= 1503; id += 1) {
        keys.push(`answer:${id}`);
        await local.upsert({ contentKey: `answer:${id}`, openedAt: id, contentType: 'answer' });
      }
      expect((await local.queryRecent()).length).assertEqual(1000);
      await database.close();
      database = new AppDatabase(context, name);
      expect((await new OpenedContentStore(database).query('answer:1'))?.openedAt).assertEqual(1);
      const runtime = new ContentFilterRuntimeStore(database, new BlockedFeedHistoryStore(database));
      expect((await runtime.loadSnapshot(keys.concat(keys))).openedKeys.length).assertEqual(1503);
      expect((await runtime.loadSnapshot(['answer:1', 'article:1'])).openedKeys.join(',')).assertEqual('answer:1');
      expect((await runtime.loadSnapshot([])).openedKeys.length).assertEqual(0);
      await (await database.open()).insert('content_filter_views',
        { content_key: 'answer:1', view_count: 10001, last_viewed_at: 100 });
      await runtime.cleanupOldData(0);
      expect((await runtime.loadSnapshot(['answer:1'])).viewCounts['answer:1']).assertEqual(10001);
    });

    it('runsFullAndIncrementalSyncAgainstRealStorageIncludingKnownPagesAndBoundaryTies', 0, async () => {
      let now = 0;
      const next = 'https://api.zhihu.com/unify-consumption/read_history?offset=50&limit=50';
      const source = new DeviceHistorySource();
      source.pages = [historyPage([1, 2], [100, 90], next), historyPage([3], [80])];
      await new RemoteHistorySync(source, reads, (): string => 'a', new DevicePreferences(), (): number => now).start();
      expect(source.requests.length).assertEqual(2);
      expect(await reads.watermark('a')).assertEqual(100000);
      await database.close();
      database = new AppDatabase(context, name);
      reads = new RemoteReadStore(database);
      const incremental = new DeviceHistorySource();
      now += 60000;
      incremental.pages = [historyPage([1, 2], [110, 110], next), historyPage([4, 3], [100, 80])];
      await new RemoteHistorySync(incremental, reads, (): string => 'a', new DevicePreferences(), (): number => now).start();
      expect(incremental.requests.length).assertEqual(2);
      expect((await reads.readKeys('a', ['answer:1', 'answer:2', 'answer:3', 'answer:4'])).length).assertEqual(4);
      const ties = new DeviceHistorySource();
      now += 60000;
      ties.pages = [historyPage([1, 2], [110, 110], next), historyPage([5, 3], [110, 80])];
      await new RemoteHistorySync(ties, reads, (): string => 'a', new DevicePreferences(), (): number => now).start();
      expect(ties.requests.length).assertEqual(2);
      expect((await reads.readKeys('a', ['answer:5'])).length).assertEqual(1);
      const unchanged = new DeviceHistorySource();
      now += 60000;
      unchanged.pages = [historyPage([1, 2], [110, 109], next)];
      await new RemoteHistorySync(unchanged, reads, (): string => 'a', new DevicePreferences(), (): number => now).start();
      expect(unchanged.requests.length).assertEqual(1);
    });

    it('preservesTheSuccessfulBoundaryOnFailureAndImportsMissingRecordsOnRetry', 0, async () => {
      const next = 'https://api.zhihu.com/unify-consumption/read_history?offset=50&limit=50';
      await reads.saveWatermark('a', 100000);
      const failing = new DeviceHistorySource();
      failing.pages = [historyPage([1], [120], next), '{}'];
      await new RemoteHistorySync(failing, reads, (): string => 'a', new DevicePreferences(), (): number => 0).start();
      await database.close();
      database = new AppDatabase(context, name);
      reads = new RemoteReadStore(database);
      expect(await reads.watermark('a')).assertEqual(100000);
      expect((await reads.readKeys('a', ['answer:1'])).length).assertEqual(1);
      const retry = new DeviceHistorySource();
      retry.pages = [historyPage([1], [120], next), historyPage([2, 3], [110, 99])];
      await new RemoteHistorySync(retry, reads, (): string => 'a', new DevicePreferences(), (): number => 60000).start();
      expect(await reads.watermark('a')).assertEqual(120000);
      expect((await reads.readKeys('a', ['answer:1', 'answer:2', 'answer:3'])).length).assertEqual(3);
    });

    it('filtersFixedCandidatesUsingPersistedReadsAndPreservesFollowedAuthors', 0, async () => {
      await reads.importPage('a', [{ contentKey: 'answer:1', readTime: 100 }]);
      const preferences = new DevicePreferences();
      const sync = new RemoteHistorySync(new DeviceHistorySource(), reads, (): string => 'a', preferences);
      const followed = candidate('1');
      followed.target.authorIsFollowing = true;
      const items = [candidate('1'), candidate('1', FeedTargetKind.ARTICLE), followed];
      const kept = await sync.filter(items);
      expect(kept.length).assertEqual(2);
      expect(kept[0].target.kind).assertEqual(FeedTargetKind.ARTICLE);
      expect(kept[1].target.authorIsFollowing).assertTrue();
      preferences.value.enableContentFilter = false;
      expect((await sync.filter(items)).length).assertEqual(3);
      preferences.value.enableContentFilter = true;
      preferences.value.reverseBlock = true;
      expect((await sync.filter(items)).length).assertEqual(3);
    });

    it('waits299msThenReleasesAt300msAndFiltersLateReadsUsingTheRealDatabase', 0, async () => {
      const source = new DeviceHistorySource();
      const clock = new VirtualHistoryClock();
      let release: () => void = (): void => {};
      let onRequest: () => void = (): void => {};
      source.gate = new Promise<void>((resolve): void => { release = resolve; });
      const requested = new Promise<void>((resolve): void => { onRequest = resolve; });
      source.onRequest = onRequest;
      source.pages = [historyPage([1], [100])];
      const sync = new RemoteHistorySync(source, reads, (): string => 'a', new DevicePreferences(),
        (): number => clock.now, clock);
      const work = sync.start();
      expect(sync.start() === work).assertTrue();
      await Promise.race([requested, work.then((): void => { throw new Error('History request did not start'); })]);
      let released = false;
      const foreground = sync.awaitRecentPage().then((): void => { released = true; });
      clock.advance(299);
      for (let index = 0; index < 12; index += 1) await Promise.resolve();
      expect(released).assertFalse();
      clock.advance(1);
      await foreground;
      expect(released).assertTrue();
      expect((await sync.filter([candidate('1')])).length).assertEqual(1);
      release();
      await work;
      expect((await sync.filter([candidate('1')])).length).assertEqual(0);
      expect(source.requests.length).assertEqual(1);
      expect(clock.pendingCount()).assertEqual(0);
    });

    it('neverAdvancesDurableProgressForUntrustedOrLoopingPagination', 0, async () => {
      await reads.saveWatermark('a', 100000);
      const invalid = new DeviceHistorySource();
      invalid.pages = [historyPage([1], [120], 'https://example.com/steal')];
      await new RemoteHistorySync(invalid, reads, (): string => 'a', new DevicePreferences(), (): number => 0).start();
      expect(invalid.requests.length).assertEqual(1);
      expect(await reads.watermark('a')).assertEqual(100000);
      const next = 'https://api.zhihu.com/unify-consumption/read_history?offset=50&limit=50';
      const loop = new DeviceHistorySource();
      loop.pages = [historyPage([1], [120], next), historyPage([2], [119], next)];
      await new RemoteHistorySync(loop, reads, (): string => 'a', new DevicePreferences(), (): number => 60000).start();
      await database.close();
      database = new AppDatabase(context, name);
      reads = new RemoteReadStore(database);
      expect(loop.requests.length).assertEqual(2);
      expect(await reads.watermark('a')).assertEqual(100000);
      expect((await reads.readKeys('a', ['answer:1', 'answer:2'])).length).assertEqual(2);
    });

    it('clearsOnlyTheSelectedAccountAndLeavesLocalHistoryIntact', 0, async () => {
      const local = new OpenedContentStore(database);
      await local.upsert({ contentKey: 'answer:1', openedAt: 99, contentType: 'answer' });
      await reads.importPage('a', [{ contentKey: 'answer:1', readTime: 100 }]);
      await reads.importPage('b', [{ contentKey: 'answer:1', readTime: 200 }]);
      await reads.saveWatermark('a', 100);
      await reads.saveWatermark('b', 200);
      await reads.clear('a');
      expect((await reads.readKeys('a', ['answer:1'])).length).assertEqual(0);
      expect(await reads.watermark('a')).assertEqual(0);
      expect((await reads.readKeys('b', ['answer:1'])).length).assertEqual(1);
      expect(await reads.watermark('b')).assertEqual(200);
      expect((await local.query('answer:1'))?.openedAt).assertEqual(99);
    });

    it('usesTheCompositeIndexAndBenchmarksOneHundredThousandRowsWithEqualResults', 0, async () => {
      const store = await database.open();
      // 10 万行、5 万个内容身份、两个账号；直接批量准备隔离库，避免把造数开销算入查询。
      for (let start = 1; start <= 50000; start += 1000) {
        const values: Array<relationalStore.ValuesBucket> = [];
        for (let id = start; id < start + 1000; id += 1) {
          values.push({ account_key: 'a', content_key: `answer:${id}` });
          values.push({ account_key: 'b', content_key: `answer:${id}` });
        }
        expect(await store.batchInsert('remote_read_content', values)).assertEqual(2000);
      }
      const keys: Array<string> = [];
      for (let index = 1; index <= 50; index += 1) keys.push(`answer:${index * 997}`);
      const sql = remoteReadQuerySql(keys.length);
      const args: Array<relationalStore.ValueType> = ['a'];
      keys.forEach((key: string): void => { args.push(key); });
      const scanSql = sql.replace('FROM remote_read_content', 'FROM remote_read_content NOT INDEXED');
      const indexedPlan = (await queryStrings(store, 'EXPLAIN QUERY PLAN ' + sql, args, 3)).join(' ');
      const scanPlan = (await queryStrings(store, 'EXPLAIN QUERY PLAN ' + scanSql, args, 3)).join(' ');
      hilog.info(0xD001, 'RemoteReadQueryPlan', 'indexed=%{public}s scan=%{public}s', indexedPlan, scanPlan);
      expect(indexedPlan.includes('SEARCH')).assertTrue();
      expect(indexedPlan.includes('account_key=? AND content_key=?')).assertTrue();
      expect(scanPlan.includes('SCAN')).assertTrue();
      const baseline = (await queryStrings(store, scanSql, args)).sort().join(',');
      expect((await reads.readKeys('a', keys)).sort().join(',')).assertEqual(baseline);
      expect(baseline.split(',').length).assertEqual(50);
      for (let warmup = 0; warmup < 5; warmup += 1) {
        await queryStrings(store, scanSql, args);
        await reads.readKeys('a', keys);
      }
      const scanMs: Array<number> = [];
      const indexedMs: Array<number> = [];
      for (let run = 0; run < 30; run += 1) {
        let start = monotonicMs();
        const scanned = await queryStrings(store, scanSql, args);
        scanMs.push(monotonicMs() - start);
        start = monotonicMs();
        const indexed = await reads.readKeys('a', keys);
        indexedMs.push(monotonicMs() - start);
        expect(indexed.sort().join(',')).assertEqual(scanned.sort().join(','));
      }
      // 只报告，不以机器相关的速度阈值判成功；此处比较强制扫描基线与当前生产查询。
      hilog.info(0xD001, 'RemoteReadBenchmark', 'rows=100000 identities=50000 candidates=50 warmup=5 runs=30 ' +
        'scanMedianMs=%{public}s indexedMedianMs=%{public}s equal=true plan=%{public}s scanPlan=%{public}s',
        median(scanMs).toFixed(3), median(indexedMs).toFixed(3), indexedPlan, scanPlan);
    });
  });
}
