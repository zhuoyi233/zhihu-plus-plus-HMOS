/** 信息流渲染条目类型：通栏横幅由各页面自行解释，内容类型区分普通卡片与日报卡。 */
export enum FeedRenderKind {
  ERROR_BANNER,
  UPDATE_ANNOUNCEMENT,
  TOP_CONTENT,
  DATE_HEADING,
  CONTENT,
  DAILY_STORY,
  LOADING_FOOTER
}

/** LazyForEach 渲染条目：内容负载保存对象引用（引用稳定，索引位移不产生旧绑定）。 */
export interface FeedRenderItem {
  /** 稳定身份键：内容由 feedItemIdentity 派生，通栏项用 chrome: 前缀，日期项用 date: 前缀。 */
  key: string;
  kind: FeedRenderKind;
  /** 内容负载（FeedItem / ChannelFeedItem 等页面自有类型），通栏项缺省。 */
  payload?: Object;
  /** 内容/日期项在页面 items 数组中的当前索引（热榜排名等按位置展示的场景使用）。 */
  itemIndex: number;
  /** 日期通栏项的日期串（yyyyMMdd）。 */
  date: string;
}

export function feedRenderChrome(key: string, kind: FeedRenderKind): FeedRenderItem {
  return { key: key, kind: kind, itemIndex: 0, date: '' };
}

export function feedRenderContent(key: string, itemIndex: number, payload: Object): FeedRenderItem {
  return { key: key, kind: FeedRenderKind.CONTENT, payload: payload, itemIndex: itemIndex, date: '' };
}

export function feedRenderDailyStory(key: string, itemIndex: number, payload: Object): FeedRenderItem {
  return { key: key, kind: FeedRenderKind.DAILY_STORY, payload: payload, itemIndex: itemIndex, date: '' };
}

export function feedRenderDateHeading(key: string, itemIndex: number, date: string): FeedRenderItem {
  return { key: key, kind: FeedRenderKind.DATE_HEADING, itemIndex: itemIndex, date: date };
}

/**
 * 信息流统一渲染数据源：协调通栏项、日期标题、内容与加载尾的身份及数量，
 * 通知与 WaterFlowSections 消费同一份布局快照（buildFeedFlowLayout 结果）。
 * 内容负载按对象引用绑定，尾部追加与中部删除不会让存活卡片拿到旧索引。
 */
export class FeedFlowDataSource implements IDataSource {
  private listeners: Array<DataChangeListener> = [];
  private renderItems: Array<FeedRenderItem> = [];

  totalCount(): number {
    return this.renderItems.length;
  }

  getData(index: number): FeedRenderItem {
    return this.renderItems[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前渲染快照（调试与测试用）。 */
  snapshot(): Array<FeedRenderItem> {
    return this.renderItems.slice();
  }

  /**
   * 以新渲染项做最小化通知：键全同不通知（与原 ForEach 稳定身份复用语义一致）；
   * 纯尾部追加/收缩、单点中部增删走增量通知；中部同时存在较多增删或顺序变化
   * （刷新换序等）时整表重载。删除从后往前、插入从前往后，保持索引有效。
   */
  applyLayout(next: Array<FeedRenderItem>): void {
    const old: Array<FeedRenderItem> = this.renderItems;
    let prefix: number = 0;
    while (prefix < old.length && prefix < next.length && old[prefix].key === next[prefix].key) {
      prefix += 1;
    }
    let suffix: number = 0;
    while (suffix < old.length - prefix && suffix < next.length - prefix &&
      old[old.length - 1 - suffix].key === next[next.length - 1 - suffix].key) {
      suffix += 1;
    }
    const removed: number = old.length - prefix - suffix;
    const added: number = next.length - prefix - suffix;
    if (removed <= 0 && added <= 0) {
      this.renderItems = next;
      return;
    }
    if (removed > 0 && added > 0 && (removed > 2 || added > 2)) {
      this.renderItems = next;
      this.notifyReloaded();
      return;
    }
    // 先删后加：数组随每步通知同步变更，框架读到的数据与索引始终一致。
    for (let index = removed - 1; index >= 0; index -= 1) {
      const position: number = prefix + index;
      this.renderItems.splice(position, 1);
      this.notifyDeleted(position);
    }
    for (let index = 0; index < added; index += 1) {
      const position: number = prefix + index;
      this.renderItems.splice(position, 0, next[position]);
      this.notifyAdded(position);
    }
  }

  private notifyReloaded(): void {
    this.listeners.forEach((listener: DataChangeListener): void => {
      listener.onDataReloaded();
    });
  }

  private notifyDeleted(position: number): void {
    this.listeners.forEach((listener: DataChangeListener): void => {
      listener.onDataDelete(position);
    });
  }

  private notifyAdded(position: number): void {
    this.listeners.forEach((listener: DataChangeListener): void => {
      listener.onDataAdd(position);
    });
  }
}
