/**
 * 「预加载优化」统一内存缓存。
 *
 * 全局一份，按配额与分级 LRU 渐进回收；配额 512MB（字符串按 UTF-16 折算），
 * 到 85% 批量淘汰，顺序：子评论 → 评论 → 回答正文 → 热评 → 信息流（越靠前越先回收）。
 * 钉住层只放当前回答 ±1（正文与评论），有独立上限并单独回收，不参与普通淘汰。
 * 关闭开关时整体 no-op。
 */

export enum PreloadCacheTier {
  /** 钉住：当前回答 ±1 的正文与评论，不参与普通 LRU 淘汰。 */
  PINNED = -1,
  CHILD_COMMENTS = 0,
  COMMENTS = 1,
  ANSWER = 2,
  HOT_COMMENTS = 3,
  FEED = 4
}

/** 缓存预算三档：默认 512MB，可在设置里切到 2GB / 4GB。 */
export const PRELOAD_CACHE_BUDGET_512MB: number = 512 * 1024 * 1024;
export const PRELOAD_CACHE_BUDGET_2GB: number = 2 * 1024 * 1024 * 1024;
export const PRELOAD_CACHE_BUDGET_4GB: number = 4 * 1024 * 1024 * 1024;
export const PRELOAD_CACHE_QUOTA_DEFAULT_BYTES: number = PRELOAD_CACHE_BUDGET_512MB;
/** 钉住层容量上限：只放当前 ±1，正常远低于这个值，超出按最久未访问回收。 */
export const PRELOAD_PINNED_CAPACITY_BYTES: number = 64 * 1024 * 1024;

interface PreloadEntry {
  readonly payload: string;
  readonly size: number;
  tier: PreloadCacheTier;
  /** 写入时的层级：取消钉住时回到这里，不再一律落回 ANSWER。 */
  readonly baseTier: PreloadCacheTier;
  lastAccessMs: number;
}

export class PreloadCache {
  private readonly entries: Map<string, PreloadEntry> = new Map<string, PreloadEntry>();
  private totalBytes: number = 0;
  private enabled: boolean = false;
  private quotaBytes: number = PRELOAD_CACHE_QUOTA_DEFAULT_BYTES;

  /** 切换缓存预算：调小后立即按新配额回收一次。 */
  setQuota(bytes: number): void {
    this.quotaBytes = Math.max(PRELOAD_CACHE_BUDGET_512MB, Math.floor(bytes));
    if (this.totalBytes > this.quotaBytes) {
      this.trim();
    }
  }

  quota(): number {
    return this.quotaBytes;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (!enabled) {
      this.clear();
    }
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  get(key: string): string | undefined {
    if (!this.enabled) {
      return undefined;
    }
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return undefined;
    }
    entry.lastAccessMs = Date.now();
    return entry.payload;
  }

  has(key: string): boolean {
    return this.enabled && this.entries.has(key);
  }

  put(key: string, payload: string, tier: PreloadCacheTier): void {
    if (!this.enabled || payload.length === 0) {
      return;
    }
    const previous = this.entries.get(key);
    if (previous !== undefined) {
      this.totalBytes -= previous.size;
    }
    const entry: PreloadEntry = {
      payload: payload,
      size: payload.length * 2,
      tier: tier,
      baseTier: tier,
      lastAccessMs: Date.now()
    };
    this.entries.set(key, entry);
    this.totalBytes += entry.size;
    if (this.totalBytes > Math.floor(this.quotaBytes * 0.85)) {
      this.trim();
    }
  }

  /** 钉住单个键（回答页用它把窗口内条目补钉住；窗口换血由 `repin` 整体处理）。 */
  promote(key: string): void {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    entry.tier = PreloadCacheTier.PINNED;
    entry.lastAccessMs = Date.now();
  }

  /**
   * 重设钉住窗口：先把所有钉住项放回各自原始层级，再钉住给定键。
   * 回答页切换时调用，保证钉住集合只有「当前答 ±1」，不会越用越大。
   */
  repin(keys: Array<string>): void {
    this.entries.forEach((entry: PreloadEntry): void => {
      if (entry.tier === PreloadCacheTier.PINNED) {
        entry.tier = entry.baseTier;
      }
    });
    const now: number = Date.now();
    for (let index = 0; index < keys.length; index += 1) {
      const entry = this.entries.get(keys[index]);
      if (entry !== undefined) {
        entry.tier = PreloadCacheTier.PINNED;
        entry.lastAccessMs = now;
      }
    }
    this.enforcePinnedCap();
  }

  invalidate(key: string): void {
    const entry = this.entries.get(key);
    if (entry !== undefined) {
      this.totalBytes -= entry.size;
      this.entries.delete(key);
    }
  }

  /** 钉住层独立回收：超出 `PRELOAD_PINNED_CAPACITY_BYTES` 时按最久未访问淘汰。 */
  enforcePinnedCap(): void {
    const pinned: Array<string> = [];
    let pinnedBytes = 0;
    this.entries.forEach((entry: PreloadEntry, key: string): void => {
      if (entry.tier === PreloadCacheTier.PINNED) {
        pinned.push(key);
        pinnedBytes += entry.size;
      }
    });
    if (pinnedBytes <= PRELOAD_PINNED_CAPACITY_BYTES) {
      return;
    }
    pinned.sort((left: string, right: string): number => {
      const leftEntry = this.entries.get(left);
      const rightEntry = this.entries.get(right);
      return (leftEntry?.lastAccessMs ?? 0) - (rightEntry?.lastAccessMs ?? 0);
    });
    for (let index = 0; index < pinned.length && pinnedBytes > PRELOAD_PINNED_CAPACITY_BYTES; index += 1) {
      const entry = this.entries.get(pinned[index]);
      if (entry !== undefined) {
        pinnedBytes -= entry.size;
        this.totalBytes -= entry.size;
      }
      this.entries.delete(pinned[index]);
    }
  }

  clear(): void {
    this.entries.clear();
    this.totalBytes = 0;
  }

  /** 分级 + LRU 淘汰，直到回到配额的 70% 以下（一次回收到位，避免频繁抖动）。 */
  private trim(): void {
    // 钉住层不进入普通淘汰：先把钉住层压到自己的容量上限内。
    this.enforcePinnedCap();
    const target = Math.floor(this.quotaBytes * 0.7);
    if (this.totalBytes <= target) {
      return;
    }
    const keys: Array<string> = Array.from(this.entries.keys());
    keys.sort((left: string, right: string): number => {
      const leftEntry = this.entries.get(left);
      const rightEntry = this.entries.get(right);
      const leftTier = leftEntry?.tier ?? 0;
      const rightTier = rightEntry?.tier ?? 0;
      if (leftTier !== rightTier) {
        return leftTier - rightTier;
      }
      return (leftEntry?.lastAccessMs ?? 0) - (rightEntry?.lastAccessMs ?? 0);
    });
    for (let index = 0; index < keys.length && this.totalBytes > target; index += 1) {
      const entry = this.entries.get(keys[index]);
      if (entry !== undefined && entry.tier === PreloadCacheTier.PINNED) {
        continue;
      }
      if (entry !== undefined) {
        this.totalBytes -= entry.size;
      }
      this.entries.delete(keys[index]);
    }
  }
}

const SHARED_CACHE: PreloadCache = new PreloadCache();

export function preloadCache(): PreloadCache {
  return SHARED_CACHE;
}

/** 统一的缓存键：回答正文 / 根评论 / 子评论 / 热评 / 信息流。 */
export function preloadAnswerKey(id: string): string {
  return `answer:${id}`;
}

export function preloadArticleKey(id: string): string {
  return `article:${id}`;
}

export function preloadCommentsKey(contentType: string, contentId: string): string {
  return `comments:${contentType}:${contentId}`;
}

/** 评论翻页（游标）的缓存键：只有热度排序的页会被写入，供「全部评论」预取复用。 */
export function preloadCommentsPageKey(contentType: string, contentId: string, cursor: string): string {
  return `comments:${contentType}:${contentId}:${cursor}`;
}

export function preloadChildCommentsKey(rootId: string): string {
  return `child:${rootId}`;
}

export function preloadSegmentCommentsKey(contentId: string, segmentId: string): string {
  return `segment:${contentId}:${segmentId}`;
}

export function preloadFeedKey(name: string): string {
  return `feed:${name}`;
}

/**
 * 缓存读取的共享实现：解析失败、或解析结果不是对象时立刻作废该键并返回 undefined，
 * 调用方只需 `as` 成目标结构使用。
 */
export function readPreloadJson(key: string): Object | undefined {
  const payload: string | undefined = preloadCache().get(key);
  if (payload === undefined) {
    return undefined;
  }
  try {
    const parsed = JSON.parse(payload) as Object;
    if (parsed === null || typeof parsed !== 'object') {
      preloadCache().invalidate(key);
      return undefined;
    }
    return parsed;
  } catch (_error) {
    preloadCache().invalidate(key);
    return undefined;
  }
}

/** 回填缓存：关闭状态下自动 no-op（见 `PreloadCache.put`）。 */
export function writePreloadJson(key: string, value: Object, tier: PreloadCacheTier): void {
  preloadCache().put(key, JSON.stringify(value), tier);
}
