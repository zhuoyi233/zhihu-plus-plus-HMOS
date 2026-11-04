import { ChannelContentItem, feedItemIdentity } from 'data';
import { buildRowGroups } from './FeedWaterfallLayout';

/** 问题页回答多列布局的一行：等宽卡片分组，key 供 LazyForEach 复用判定。 */
export interface QuestionAnswerRowEntry {
  key: string;
  items: ChannelContentItem[];
}

/**
 * 问题页回答行的行键：绑定行首内容身份 + 行号。追加回答只新增行、既有行 key 不变；
 * 排序切换/刷新整体替换时 key 随内容变化，LazyForEach 按重载重建。
 */
export function buildAnswerRowEntries(items: ChannelContentItem[], columns: number): QuestionAnswerRowEntry[] {
  const groups: Array<Array<ChannelContentItem>> = buildRowGroups(items, columns);
  const rows: QuestionAnswerRowEntry[] = [];
  for (let index = 0; index < groups.length; index += 1) {
    const group: Array<ChannelContentItem> = groups[index];
    if (group.length === 0) {
      continue;
    }
    rows.push({ key: `row:${index}:${feedItemIdentity(group[0].feedItem)}`, items: group });
  }
  return rows;
}

/**
 * 问题页回答列表的行分组数据源（宽屏多列专用）：镜像控制器回调给出的回答数组并按列数分行。
 * 仅作用于呈现层——回答跳转、连续阅读与预取仍走原 answerDataSource 与控制器快照，不依赖行结构。
 */
export class QuestionAnswerRowSource implements IDataSource {
  private rows: QuestionAnswerRowEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): QuestionAnswerRowEntry {
    return this.rows[index];
  }

  /** 整组替换行快照并通知重载；调用方在回答数组或列数变化时调用。 */
  setRows(rows: QuestionAnswerRowEntry[]): void {
    this.rows = rows;
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
