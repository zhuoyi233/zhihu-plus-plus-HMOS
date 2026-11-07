/**
 * 顶级页签滚动容器登记表。
 *
 * HdsNavigation 需要经 `bindToScrollable` 绑定可滚动容器，才知道内容区的滚动偏移，
 * 进而驱动标题栏的滚动模糊（华为官方「HdsNavigation 嵌套 HdsTabs 滚动模糊丢失」
 * 解决方案口径）。各页签页各自持有 Scroller，这里按“所属页签”登记。
 *
 * 根标题栏是所有页签共用的一个，必须只绑定当前可见页签的滚动容器：若把全部页签的
 * 容器一起绑定，在某一页滚动后，切到其他页（那些页偏移为 0、不会再发滚动事件）时
 * 标题栏会继续保持模糊，出现“别的页什么都没滚，顶栏却糊着”的问题。
 */
export const HOME_FEED_SCROLL_KEY: string = 'home';
export const READ_HISTORY_SCROLL_KEY: string = 'readHistory';
export const SETTINGS_SCROLL_KEY: string = 'settings';

export class TopLevelScrollRegistry {
  private readonly scrollers: Map<string, Scroller> = new Map<string, Scroller>();

  /** 登记某页签的滚动容器（key 用页签标识，频道页直接用自己的 source）；同 key 覆盖。 */
  register(key: string, scroller: Scroller): void {
    this.scrollers.set(key, scroller);
    // 每次登记都广播：页面挂载完成后会再登记一次（aboutToAppear 时容器还没挂到组件上，
    // 那时绑定会丢失订阅），AppShell 需按新状态重算绑定。
    AppStorage.setOrCreate('topLevelScrollableTick', (AppStorage.get<number>('topLevelScrollableTick') ?? 0) + 1);
  }

  /** 仅释放当前实例，避免旧组件销毁时移除同 key 的新容器。 */
  unregister(key: string, scroller: Scroller): void {
    if (this.scrollers.get(key) !== scroller) { return; }
    this.scrollers.delete(key);
    AppStorage.setOrCreate('topLevelScrollableTick', (AppStorage.get<number>('topLevelScrollableTick') ?? 0) + 1);
  }

  /** 按页签标识取滚动容器；尚未挂载的页签会被跳过。 */
  scrollersFor(keys: string[]): Array<Scroller> {
    const result: Array<Scroller> = [];
    for (const key of keys) {
      const scroller: Scroller | undefined = this.scrollers.get(key);
      if (scroller !== undefined) {
        result.push(scroller);
      }
    }
    return result;
  }
}

export const topLevelScrollRegistry: TopLevelScrollRegistry = new TopLevelScrollRegistry();
