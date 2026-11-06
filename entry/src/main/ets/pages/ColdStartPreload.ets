import { common } from '@kit.AbilityKit';
import {
  AppPreferencesStore,
  decodeFeedPage,
  decodeMobileHomeFeedPage,
  FeedItem,
  RecommendationMode
} from 'data';

/**
 * 冷启动预加载：EntryAbility 把硬盘快照解码进内存，首页首帧直接渲染，
 * 随后按「启动时自动刷新首页」静默刷新；没有快照或解码失败时走原有异步加载。
 */
let startupItems: Array<FeedItem> | undefined = undefined;

export function setHomeStartupFeedItems(items: Array<FeedItem>): void {
  startupItems = items.length > 0 ? items : undefined;
}

export function takeHomeStartupFeedItems(): Array<FeedItem> | undefined {
  const items = startupItems;
  startupItems = undefined;
  return items;
}

/**
 * 冷启动预热：把硬盘里的首页快照解码进内存暂存（EntryAbility 在窗口内容加载前调用）。
 *
 * 优先 WEB 推荐模式的快照，没有或为空时回落移动端推荐快照。读取失败静默忽略——
 * 页面会走原有异步加载，不因为预热失败影响启动。
 */
export async function warmHomeStartupFeed(context: common.Context): Promise<void> {
  try {
    const store = new AppPreferencesStore(context);
    const webRaw: string | undefined = await store.loadHomeFeedStartupResponse(RecommendationMode.WEB);
    if (webRaw !== undefined) {
      const page = decodeFeedPage(webRaw);
      if (page.items.length > 0) {
        setHomeStartupFeedItems(page.items);
        return;
      }
    }
    const mobileRaw: string | undefined = await store.loadHomeFeedStartupResponse(RecommendationMode.ANDROID);
    if (mobileRaw !== undefined) {
      setHomeStartupFeedItems(decodeMobileHomeFeedPage(mobileRaw).items);
    }
  } catch (_error) {
    // 预热失败静默忽略：页面会走原有异步加载。
  }
}
