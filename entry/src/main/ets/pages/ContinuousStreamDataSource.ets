import { ReaderBlock, ReaderBlockKind } from 'reader';

/**
 * 连续阅读流的行类型（docs/continuous-answer-reading-plan.md §4.1）：
 * 每篇回答展开为 信息头 → 正文块… → 日期区 → 逐答操作栏 → 分隔带；
 * 未就绪/已释放的回答以占位行占住高度，正文回包或回看时原位替换。
 */
export enum ContinuousRowKind {
  ANSWER_HEADER,
  BLOCK,
  DATE_ROW,
  ACTIONS_ROW,
  DIVIDER_BAND,
  BODY_LOADING,
  BODY_RELEASED,
  BODY_ERROR,
  STREAM_END
}

/** 连续阅读流的一行。key 是稳定行身份：未涉及的行在增量更新后不换 key。 */
export interface ContinuousRow {
  readonly key: string;
  readonly answerId: string;
  readonly kind: ContinuousRowKind;
  /** BLOCK 行携带的正文块；其他行不设置。 */
  readonly block?: ReaderBlock;
  /** 占位/释放行的估算高度（vp）：加载占位用启发式，释放占位用被淘汰前的实测累计。 */
  readonly estimatedHeightVp: number;
  /** 非 BLOCK 行的展示文案（日期行/状态行）。 */
  readonly label: string;
  /** 日期行的完整属地，独立布局以便整段换行。 */
  readonly ipInfo?: string;
}

const STREAM_END_ANSWER_ID = 'stream-end';
const BODY_PLACEHOLDER_KEY = 'body';

/** 某回答信息头行的 key（数据源按此定位回答区间）。 */
export function continuousHeaderRowKey(answerId: string): string {
  return `${answerId}:header`;
}

export function continuousHeaderRow(answerId: string): ContinuousRow {
  return {
    key: continuousHeaderRowKey(answerId),
    answerId: answerId,
    kind: ContinuousRowKind.ANSWER_HEADER,
    estimatedHeightVp: 96,
    label: ''
  };
}

export function continuousBlockRows(answerId: string, blocks: Array<ReaderBlock>): Array<ContinuousRow> {
  const rows: Array<ContinuousRow> = [];
  blocks.forEach((block: ReaderBlock): void => {
    rows.push({
      key: `${answerId}:block:${block.id}`,
      answerId: answerId,
      kind: ContinuousRowKind.BLOCK,
      block: block,
      estimatedHeightVp: 0,
      label: ''
    });
  });
  return rows;
}

export function continuousDateRow(answerId: string, label: string, ipInfo: string = ''): ContinuousRow {
  return {
    key: `${answerId}:date`,
    answerId: answerId,
    kind: ContinuousRowKind.DATE_ROW,
    estimatedHeightVp: 24,
    label: label,
    ipInfo: ipInfo
  };
}

export function continuousActionsRow(answerId: string): ContinuousRow {
  return {
    key: `${answerId}:actions`,
    answerId: answerId,
    kind: ContinuousRowKind.ACTIONS_ROW,
    estimatedHeightVp: 56,
    label: ''
  };
}

export function continuousDividerRow(answerId: string): ContinuousRow {
  return {
    key: `${answerId}:divider`,
    answerId: answerId,
    kind: ContinuousRowKind.DIVIDER_BAND,
    estimatedHeightVp: 28,
    label: ''
  };
}

export function continuousLoadingBodyRow(answerId: string): ContinuousRow {
  return {
    key: `${answerId}:${BODY_PLACEHOLDER_KEY}`,
    answerId: answerId,
    kind: ContinuousRowKind.BODY_LOADING,
    estimatedHeightVp: 320,
    label: '正在加载回答正文…'
  };
}

export function continuousReleasedBodyRow(answerId: string, estimatedHeightVp: number): ContinuousRow {
  return {
    key: `${answerId}:${BODY_PLACEHOLDER_KEY}`,
    answerId: answerId,
    kind: ContinuousRowKind.BODY_RELEASED,
    estimatedHeightVp: Math.max(120, Math.round(estimatedHeightVp)),
    label: '正文已释放，回看将重新加载'
  };
}

export function continuousErrorBodyRow(answerId: string, label: string): ContinuousRow {
  return {
    key: `${answerId}:${BODY_PLACEHOLDER_KEY}`,
    answerId: answerId,
    kind: ContinuousRowKind.BODY_ERROR,
    estimatedHeightVp: 160,
    label: label
  };
}

export function continuousStreamEndRow(label: string): ContinuousRow {
  return {
    key: `${STREAM_END_ANSWER_ID}:end`,
    answerId: STREAM_END_ANSWER_ID,
    kind: ContinuousRowKind.STREAM_END,
    estimatedHeightVp: 72,
    label: label
  };
}

/**
 * 连续阅读流数据源：在 ReaderBlockDataSource（整表 replace + onDataReloaded）之上
 * 提供增量能力——尾部追加用逐行 onDataAdd，回答正文原位替换用「从后往前删、按序加」
 * 的细粒度事件，未涉及行的 key 不变，LazyForEach 不会重建已显示行。
 */
export class ContinuousStreamDataSource implements IDataSource {
  private readonly rows: Array<ContinuousRow> = [];
  private readonly listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): ContinuousRow {
    return this.rows[index];
  }

  /** 只读快照：锚点补偿按 key 找新索引用。 */
  rowAt(index: number): ContinuousRow {
    return this.rows[index];
  }

  indexOfRowKey(key: string): number {
    return this.rows.findIndex((row: ContinuousRow): boolean => row.key === key);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 整表重建（建流/换排序）：仅建流时使用，逐答更新不得走这里。 */
  replaceAll(rows: Array<ContinuousRow>): void {
    this.rows.splice(0, this.rows.length);
    rows.forEach((row: ContinuousRow): void => {
      this.rows.push(row);
    });
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  /** 尾部追加（分页到达的新回答）：逐行 onDataAdd。 */
  appendRows(rows: Array<ContinuousRow>): void {
    rows.forEach((row: ContinuousRow): void => {
      this.rows.push(row);
      const at = this.rows.length - 1;
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(at));
    });
  }

  /** 任意位插入（新回答插到结尾行之前）：单行 onDataAdd。 */
  insertRowAt(index: number, row: ContinuousRow): void {
    const bounded = Math.max(0, Math.min(index, this.rows.length));
    this.rows.splice(bounded, 0, row);
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(bounded));
  }

  /** 原位替换单行（增高试验/占位文案改写）：onDataChange。返回是否命中。 */
  updateRow(key: string, next: ContinuousRow): boolean {
    const index = this.indexOfRowKey(key);
    if (index < 0) {
      return false;
    }
    this.rows[index] = next;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataChange(index));
    return true;
  }

  /**
   * 以「同位删除+插入」替换单行并让 LazyForEach 重建该行组件。
   * onDataChange（不换 key）对按值传参的嵌套 @Builder 不会触发重渲染
   * （P0 实测：行内容更新后 bounds 不变），需要行内容变化可见时必须走这里。
   * 返回是否命中。
   */
  replaceRowAt(key: string, next: ContinuousRow): boolean {
    const index = this.indexOfRowKey(key);
    if (index < 0) {
      return false;
    }
    this.rows[index] = next;
    this.listeners.forEach((listener: DataChangeListener): void => {
      listener.onDataDelete(index);
      listener.onDataAdd(index);
    });
    return true;
  }

  /**
   * 原位替换某回答信息头之后的全部行（加载占位 ↔ 正文 ↔ 释放占位共用路径）：
   * 先从后往前 onDataDelete（删除事件索引按删除后的状态计，倒序保证未处理索引不被位移），
   * 再按序 onDataAdd。信息头行在替换区间之外，key 不变。
   * 返回替换区间起始索引；找不到该回答时返回 -1。
   */
  replaceBodyRows(answerId: string, nextBodyRows: Array<ContinuousRow>): number {
    const headerIndex = this.indexOfRowKey(continuousHeaderRowKey(answerId));
    if (headerIndex < 0) {
      return -1;
    }
    const start = headerIndex + 1;
    let end = start;
    while (end < this.rows.length && this.rows[end].answerId === answerId) {
      end += 1;
    }
    for (let i = end - 1; i >= start; i--) {
      this.rows.splice(i, 1);
      const deleting = i;
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(deleting));
    }
    for (let i = 0; i < nextBodyRows.length; i++) {
      const at = start + i;
      this.rows.splice(at, 0, nextBodyRows[i]);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(at));
    }
    return start;
  }

  /**
   * 整体移除某回答的全部行（信息头 + 正文区 + 分隔带，屏蔽重过滤用）：
   * 从后往前 onDataDelete（与 replaceBodyRows 同款倒序约定）。
   * 返回移除的行数；找不到该回答时返回 0。
   */
  removeAnswerRows(answerId: string): number {
    let removed = 0;
    for (let i = this.rows.length - 1; i >= 0; i--) {
      if (this.rows[i].answerId !== answerId) {
        continue;
      }
      this.rows.splice(i, 1);
      const deleting = i;
      removed += 1;
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(deleting));
    }
    return removed;
  }
}
