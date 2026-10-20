import { JsonArrayValue, JsonNullValue, jsonBoolean, jsonNumber, jsonObject, jsonString, parseStrictJson,
  resolveZhihuLink, DeepLinkType } from 'core';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FeedItem } from '../domain/DomainModels';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';
import { RecommendationFilterPreferencesGateway } from '../preferences/RecommendationFilterPreferences';

export const REMOTE_HISTORY_FIRST_URL = 'https://api.zhihu.com/unify-consumption/read_history?offset=0&limit=50';

export interface RemoteReadRecord {
  contentKey: string;
  readTime: number;
}

export interface RemoteHistoryPage {
  records: Array<RemoteReadRecord>;
  /** 保留无法映射内容的时间，用于验证排序及跨越增量边界。单位为毫秒。 */
  readTimes: Array<number>;
  isEnd: boolean;
  next?: string;
}

export interface RemoteHistorySource {
  load(url: string): Promise<RemoteHistoryPage>;
  cancel(): void;
}

export interface RemoteHistoryScheduler {
  schedule(action: () => void, delayMs: number): number;
  cancel(timer: number): void;
}

class SystemRemoteHistoryScheduler implements RemoteHistoryScheduler {
  schedule(action: () => void, delayMs: number): number { return setTimeout(action, delayMs); }
  cancel(timer: number): void { clearTimeout(timer); }
}

export interface RemoteReadGateway {
  claimSync(account: string, now: number): Promise<boolean>;
  watermark(account: string): Promise<number>;
  importPage(account: string, records: Array<RemoteReadRecord>): Promise<void>;
  saveWatermark(account: string, time: number): Promise<void>;
  readKeys(account: string, keys: Array<string>): Promise<Array<string>>;
  clear(account: string): Promise<void>;
}

export function isRemoteHistoryUrl(url: string): boolean {
  // 只接受固定 HTTPS 接口、唯一 offset/limit 参数；拒绝换域、凭据、片段及循环游标。
  return url.length < 4096 &&
    /^https:\/\/api\.zhihu\.com\/unify-consumption\/read_history\?(?:offset=(?:0|[1-9]\d*)&limit=50|limit=50&offset=(?:0|[1-9]\d*))$/.test(url);
}

function cursorKey(url: string): string {
  return url.substring(url.indexOf('?') + 1).split('&').sort().join('&');
}

export function decodeRemoteHistoryPage(body: string): RemoteHistoryPage {
  const root = jsonObject(parseStrictJson(body));
  const data = root?.get('data');
  const paging = jsonObject(root?.get('paging'));
  const isEnd = jsonBoolean(paging?.get('is_end'));
  const error = root?.get('error');
  if (!(data instanceof JsonArrayValue) || isEnd === undefined ||
    (error !== undefined && !(error instanceof JsonNullValue))) {
    throw new Error('Invalid remote history response');
  }
  const records: Array<RemoteReadRecord> = [];
  const readTimes: Array<number> = [];
  data.items.forEach((value): void => {
    const card = jsonObject(jsonObject(value)?.get('data'));
    const time = jsonNumber(jsonObject(card?.get('extra'))?.get('read_time'));
    // 缺失时间不允许被当作“更旧记录”提前结束同步。
    const readTime = time !== undefined && Number.isSafeInteger(time) && time > 0 &&
      Number.isSafeInteger(time * 1000) ? time * 1000 : 0;
    readTimes.push(readTime);
    const url = jsonString(jsonObject(card?.get('action'))?.get('url'));
    const destination = url === undefined ? undefined : resolveZhihuLink(url);
    if (destination === undefined) return;
    const type = destination.type;
    if (type === DeepLinkType.ANSWER || type === DeepLinkType.ARTICLE ||
      type === DeepLinkType.QUESTION || type === DeepLinkType.PIN) {
      records.push({ contentKey: `${type}:${destination.id}`, readTime: readTime });
    }
  });
  const next = jsonString(paging?.get('next'));
  if (!isEnd && (readTimes.length === 0 || next === undefined || !isRemoteHistoryUrl(next))) {
    throw new Error('Invalid remote history pagination');
  }
  return { records: records, readTimes: readTimes, isEnd: isEnd, next: next };
}

export class HttpRemoteHistorySource implements RemoteHistorySource {
  private readonly http: ZhihuHttpClient;

  constructor(http: ZhihuHttpClient) { this.http = http; }

  async load(url: string): Promise<RemoteHistoryPage> {
    if (!isRemoteHistoryUrl(url)) throw new Error('Invalid remote history URL');
    let timer: number = -1;
    const timeout = new Promise<RemoteHistoryPage>((_resolve, reject): void => {
      timer = setTimeout((): void => {
        this.http.cancel();
        reject(new Error('Remote history timeout'));
      }, 15000);
    });
    const request = this.http.execute({ url: url, useSession: true, accept: 'application/json' })
      .then((response): RemoteHistoryPage => decodeRemoteHistoryPage(response.body));
    try { return await Promise.race([request, timeout]); } finally { clearTimeout(timer); }
  }

  cancel(): void { this.http.cancel(); }
}

/** 首页所有推荐模式共用；同步生命周期独立于 Feed 请求及标签页切换。 */
export class RemoteHistorySync {
  private readonly source: RemoteHistorySource;
  private readonly store: RemoteReadGateway;
  private readonly account: () => string;
  private readonly preferences: RecommendationFilterPreferencesGateway;
  private readonly now: () => number;
  private readonly scheduler: RemoteHistoryScheduler;
  private running?: Promise<void>;
  private recentPage: Promise<void> = Promise.resolve();
  private lastAccount: string = '';
  private lastAttempt: number = -Infinity;
  private generation: number = 0;
  private readonly listeners: Set<() => void> = new Set<() => void>();

  constructor(source: RemoteHistorySource, store: RemoteReadGateway, account: () => string,
    preferences: RecommendationFilterPreferencesGateway, now: () => number = (): number => Date.now(),
    scheduler: RemoteHistoryScheduler = new SystemRemoteHistoryScheduler()) {
    this.source = source;
    this.store = store;
    this.account = account;
    this.preferences = preferences;
    this.now = now;
    this.scheduler = scheduler;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  start(): Promise<void> {
    const account = this.account();
    if (account !== this.lastAccount) {
      this.generation += 1;
      this.source.cancel();
      this.running = undefined;
      this.lastAttempt = -Infinity;
      this.lastAccount = account;
    }
    if (account.length === 0) return Promise.resolve();
    if (this.running !== undefined) return this.running;
    if (this.now() - this.lastAttempt < 60000) return Promise.resolve();
    const generation = this.generation;
    let release: () => void = (): void => {};
    this.recentPage = new Promise<void>((resolve): void => { release = resolve; });
    const work = this.sync(account, generation, release).catch((): void => {
      hilog.warn(0xD001, 'RemoteHistorySync', 'sync failed; progress retained');
    }).finally((): void => {
      release();
      if (generation === this.generation) this.running = undefined;
    });
    this.running = work;
    return work;
  }

  async awaitRecentPage(): Promise<void> {
    let timer: number = -1;
    const timeout = new Promise<void>((resolve): void => { timer = this.scheduler.schedule(resolve, 300); });
    try { await Promise.race([this.recentPage, timeout]); } finally { this.scheduler.cancel(timer); }
  }

  async filter(items: Array<FeedItem>): Promise<Array<FeedItem>> {
    const account = this.account();
    if (account.length === 0 || items.length === 0) return items;
    const preferences = await this.preferences.loadRecommendationFilterPreferences();
    if (!preferences.enableContentFilter || preferences.reverseBlock) return items;
    const keys = items.map((item: FeedItem): string => `${item.target.kind}:${item.target.id}`);
    const read = new Set<string>(await this.store.readKeys(account, keys));
    if (account !== this.account()) return items;
    return items.filter((item: FeedItem): boolean => item.target.authorIsFollowing === true ||
      !read.has(`${item.target.kind}:${item.target.id}`));
  }

  async clear(): Promise<void> {
    const account = this.account();
    this.generation += 1;
    this.source.cancel();
    this.running = undefined;
    this.lastAttempt = -Infinity;
    if (account.length > 0) await this.store.clear(account);
  }

  private current(account: string, generation: number): boolean {
    return generation === this.generation && account === this.account();
  }

  private async sync(account: string, generation: number, release: () => void): Promise<void> {
    const attemptAt = this.now();
    if (!await this.store.claimSync(account, attemptAt) || !this.current(account, generation)) return;
    this.lastAttempt = attemptAt;
    const boundary = await this.store.watermark(account);
    let newest = boundary;
    let previous = Infinity;
    let ordered = true;
    let url = REMOTE_HISTORY_FIRST_URL;
    const requested = new Set<string>();
    let scanned = 0;
    while (this.current(account, generation)) {
      const key = cursorKey(url);
      if (!isRemoteHistoryUrl(url) || requested.has(key)) throw new Error('Repeated remote history cursor');
      requested.add(key);
      const page = await this.source.load(url);
      if (!this.current(account, generation)) return;
      for (const time of page.readTimes) {
        if (time <= 0 || time > previous) ordered = false;
        previous = time;
        newest = Math.max(newest, time);
      }
      await this.store.importPage(account, page.records);
      scanned += page.readTimes.length;
      if (!this.current(account, generation)) return;
      release();
      this.listeners.forEach((listener: () => void): void => listener());
      if (!this.current(account, generation)) return;
      if (page.isEnd || (boundary > 0 && ordered && page.readTimes.some((time: number): boolean => time < boundary))) {
        await this.store.saveWatermark(account, newest);
        hilog.info(0xD001, 'RemoteHistorySync', 'completed pages=%{public}d records=%{public}d incremental=%{public}s',
          requested.size, scanned, boundary > 0 ? 'true' : 'false');
        return;
      }
      if (page.next === undefined) throw new Error('Missing remote history cursor');
      url = page.next;
    }
  }
}
