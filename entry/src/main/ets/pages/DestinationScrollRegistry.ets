/**
 * 二级页按路由登记已挂载的滚动容器，供宿主 HDS 显式绑定。
 * WaterFlow 不会像 List 一样被 HDS 自动发现；在 onAppear 后广播，避免绑定未挂载的 Scroller。
 * 每个路由独立保存，覆盖页与返回栈中的页面不会互相接管顶栏滚动效果。
 */
export function destinationScrollKey(name: string, id: string = ''): string {
  return `${name}:${id}`;
}

class DestinationScrollRegistry {
  private readonly scrollers: Map<string, Scroller> = new Map<string, Scroller>();

  register(key: string, scroller: Scroller): void {
    if (key.length === 0) { return; }
    this.scrollers.set(key, scroller);
    this.broadcast();
  }

  unregister(key: string, scroller: Scroller): void {
    // 同一路由重建时，旧组件销毁不能移除新组件刚登记的容器。
    if (this.scrollers.get(key) !== scroller) { return; }
    this.scrollers.delete(key);
    this.broadcast();
  }

  snapshot(): Map<string, Scroller> {
    return new Map<string, Scroller>(this.scrollers);
  }

  private broadcast(): void {
    AppStorage.setOrCreate('destinationScrollableTick',
      (AppStorage.get<number>('destinationScrollableTick') ?? 0) + 1);
  }
}

export const destinationScrollRegistry: DestinationScrollRegistry = new DestinationScrollRegistry();
