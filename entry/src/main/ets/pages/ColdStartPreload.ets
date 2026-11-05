import { common } from '@kit.AbilityKit';
import {
  AppPreferencesStore,
  decodeFeedPage,
  decodeMobileHomeFeedPage,
  FeedItem,
  RecommendationMode
} from 'data';

/**
 * 冷启动预加载（本轮新增的唯一冷启动文件）。
 *
 * 目标：开机进主页时**先出内容、后台再验证与刷新**，避免"先转圈加载、再出首页"的可见等待。
 *
 * 流程：
 * 1. `EntryAbility.onCreate` 调 `warmHomeStartupFeed(context)`：把硬盘里的首页快照解码进内存暂存；
 * 2. `HomeFeedPage` 首帧 `takeHomeStartupFeedItems()` 直接渲染这批条目（一次性语义，取走即清空）；
 * 3. 页面随后按「启动时自动刷新首页」静默刷新一次，并开始正常预取。
 *
 * 预热失败或没有快照时保持原有异步加载路径，不影响启动。
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
