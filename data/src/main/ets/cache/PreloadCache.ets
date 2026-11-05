/**
 * 「预加载优化」统一内存缓存。
 *
 * 全局一份，按配额与分级 LRU 渐进回收；配额 2GB（字符串按 UTF-16 折算），
 * 到 85% 批量淘汰，顺序：子评论 → 评论 → 回答正文 → 热评 → 信息流（越靠前越先回收）；
 * 关闭开关时整体 no-op。
 */

export enum PreloadCacheTier {
  /** 钉住：相邻回答与其热评，永不参与 LRU 淘汰（进程内常驻，保证上下切答不掉缓存）。 */
  PINNED = -1,
  CHILD_COMMENTS = 0,
  COMMENTS = 1,
  ANSWER = 2,
  HOT_COMMENTS = 3,
  FEED = 4
}

export const PRELOAD_CACHE_QUOTA_BYTES: number = 2 * 1024 * 1024 * 1024;
/** 钉住层的容量上限：占 1GB 配额的一部分，超出后按最久未访问淘汰钉住层。 */
export const PRELOAD_PINNED_CAPACITY_BYTES: number = 256 * 1024 * 1024;
export const PRELOAD_CACHE_TRIM_THRESHOLD: number = Math.floor(PRELOAD_CACHE_QUOTA_BYTES * 0.85);

interface PreloadEntry {
  readonly payload: string;
  readonly size: number;
  tier: PreloadCacheTier;
  lastAccessMs: number;
}

export class PreloadCache {
  private readonly entries: Map<string, PreloadEntry> = new Map<string, PreloadEntry>();
  private totalBytes: number = 0;
  private enabled: boolean = false;

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
      lastAccessMs: Date.now()
    };
    this.entries.set(key, entry);
    this.totalBytes += entry.size;
    if (this.totalBytes > PRELOAD_CACHE_TRIM_THRESHOLD) {
      this.trim();
    }
  }

  /** 把已缓存条目提升为钉住（相邻回答/热评），不改变 payload。 */
  promote(key: string, tier: PreloadCacheTier): void {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    entry.tier = tier;
    entry.lastAccessMs = Date.now();
  }

  invalidate(key: string): void {
    const entry = this.entries.get(key);
    if (entry !== undefined) {
      this.totalBytes -= entry.size;
      this.entries.delete(key);
    }
  }

  private trimPinned(): void {
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
    // 钉住层不进入普通淘汰：先把钉住层压到自己的容量上限内（同样按最久未访问）。
    this.trimPinned();
    const target = Math.floor(PRELOAD_CACHE_QUOTA_BYTES * 0.7);
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

export function preloadHotCommentsKey(answerId: string): string {
  return `hot:${answerId}`;
}

export function preloadSegmentCommentsKey(contentId: string, segmentId: string): string {
  return `segment:${contentId}:${segmentId}`;
}

export function preloadFeedKey(name: string): string {
  return `feed:${name}`;
}

/**
 * 缓存读取的共享实现：解析失败、或解析结果不是对象时立刻作废该键并返回 undefined，
 * 调用方只需 `as` 成目标结构使用。仓库层因此各只需 2~3 行，不必各写一份 try/catch。
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

