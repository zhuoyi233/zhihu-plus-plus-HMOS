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
 * replace 全量替换并通知重载（追加/删除/整组替换统一走此路径，与首页一致）。
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
