/**
 * 管理类列表页的通用瀑布流设施：渲染条目数据源 + sections 构建。
 * 卡片项（非通栏）按源数组顺序进入 crossCount=N 的连续 section（WaterFlow 内部
 * 按最短列放置，实现与首页信息流一致的高度不齐瀑布流）；通栏项（横幅/分割线/
 * 加载尾等 chrome）独占 crossCount=1 的 section；段间距沿用原 List space 语义。
 */

/** 瀑布流渲染条目：卡片项携带源数组索引与负载，通栏项由页面按 label 自行渲染。 */
export interface FlowListItem {
  /** 稳定身份键：卡片用内容身份，chrome 用 label 前缀 + 槽位名。 */
  key: string;
  /** 是否通栏（独占单列 section，打断卡片分组）。 */
  fullWidth: boolean;
  /** 渲染种类标记，页面 @Builder 按 label 分发（'card'/'footer'/'header'…）。 */
  label: string;
  /** 源数组索引；纯 chrome 项为 -1。 */
  sourceIndex: number;
  /** 源条目引用（引用稳定，索引位移不产生旧绑定）。 */
  payload?: Object;
}

/** 构建卡片条目（非通栏）。 */
export function flowListCard(key: string, sourceIndex: number, payload: Object,
  label: string = 'card'): FlowListItem {
  return { key: key, fullWidth: false, label: label, sourceIndex: sourceIndex, payload: payload };
}

/** 构建通栏条目（横幅/加载尾/分割线等 chrome）。 */
export function flowListChrome(key: string, label: string): FlowListItem {
  return { key: key, fullWidth: true, label: label, sourceIndex: -1 };
}

/**
 * 瀑布流渲染数据源：与 WaterFlowSections 消费同一份 entries 快照。
 * replace 保留整表重载语义；applyLayout 用于分页等需要保留可见节点的增量更新。
 */
export class FlowListSource implements IDataSource {
  private entries: FlowListItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): FlowListItem {
    return this.entries[index];
  }

  replace(items: FlowListItem[]): void {
    this.entries = items;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  /** 保留公共前后缀，只通知中间增删；同键负载变化单独更新，分页不重建已有卡片。 */
  applyLayout(next: FlowListItem[]): void {
    const old = this.entries.slice();
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
    for (let index = removed - 1; index >= 0; index -= 1) {
      const position: number = prefix + index;
      this.entries.splice(position, 1);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(position));
    }
    for (let index = 0; index < added; index += 1) {
      const position: number = prefix + index;
      this.entries.splice(position, 0, next[position]);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(position));
    }
    // 前缀/后缀的 key 不变，但刷新资料或同键内容时仍须通知实际负载变化。
    this.entries = next;
    for (let index = 0; index < next.length; index += 1) {
      const oldIndex: number = index < prefix ? index : index >= next.length - suffix
        ? index - added + removed : -1;
      if (oldIndex < 0) { continue; }
      const previous: FlowListItem = old[oldIndex];
      const current: FlowListItem = next[index];
      if (previous.payload !== current.payload || previous.sourceIndex !== current.sourceIndex ||
        previous.label !== current.label || previous.fullWidth !== current.fullWidth) {
        this.listeners.forEach((listener: DataChangeListener): void => listener.onDataChange(index));
      }
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}

/**
 * 按条目快照构建 sections：连续非通栏 run 合并为 crossCount=columns 的 section
 * （rowsGap/columnsGap=itemGap），通栏项独占 crossCount=1 的 section；段间
 * margin top=sectionGap（首段不加，复刻原 List space 的相邻条目间距语义）。
 * itemGap 缺省等于 sectionGap（原 List space 语义下两者一致）。
 */
export function buildFlowListSections(entries: FlowListItem[], columns: number,
  itemGap: number, sectionGap: number = itemGap): SectionOptions[] {
  const sections: SectionOptions[] = [];
  const cols: number = Math.max(1, Math.floor(columns));
  let runStart: number = -1;
  const flush = (endExclusive: number): void => {
    if (runStart < 0) {
      return;
    }
    sections.push({
      itemsCount: endExclusive - runStart,
      crossCount: cols,
      columnsGap: itemGap,
      rowsGap: itemGap,
      margin: { top: sections.length === 0 ? 0 : sectionGap }
    });
    runStart = -1;
  };
  for (let index = 0; index < entries.length; index += 1) {
    if (entries[index].fullWidth) {
      flush(index);
      sections.push({
        itemsCount: 1,
        crossCount: 1,
        margin: { top: sections.length === 0 ? 0 : sectionGap }
      });
    } else if (runStart < 0) {
      runStart = index;
    }
  }
  flush(entries.length);
  return sections;
}
