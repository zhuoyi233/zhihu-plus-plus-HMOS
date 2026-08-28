import {
  HttpFailure,
  HttpFailureKind,
  MAX_READ_HISTORY_ITEMS,
  OnlineHistoryEntry,
  OnlineHistoryKind,
  OnlineHistoryRepository,
  OpenedContent,
  ReadHistoryGateway
} from 'data';

export enum ReadHistoryPhase {
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export enum ReadHistoryContentKind {
  QUESTION = 'question',
  ANSWER = 'answer',
  ARTICLE = 'article',
  PIN = 'pin'
}

export enum ReadHistorySourceFilter {
  ALL = 'all',
  LOCAL = 'local',
  ONLINE = 'online'
}

export interface ReadHistoryItem {
  contentKey: string;
  kind: ReadHistoryContentKind;
  id: string;
  openedAt: number;
  title?: string;
  summary?: string;
  authorName?: string;
  deletable: boolean;
  inOnline: boolean;
}

export interface ReadHistoryGroup {
  dayKey: string;
  label: string;
  items: Array<ReadHistoryItem>;
}

export interface ReadHistoryOpenTarget {
  kind: ReadHistoryContentKind;
  id: string;
}

export interface ReadHistoryViewState {
  phase: ReadHistoryPhase;
  items: Array<ReadHistoryItem>;
  busy: boolean;
  message: string;
  requiresLogin: boolean;
  onlineEnabled: boolean;
  loadingMore: boolean;
  canLoadMore: boolean;
}

export type ReadHistoryObserver = (state: ReadHistoryViewState) => void;

export function decodeReadHistoryItem(content: OpenedContent): ReadHistoryItem | undefined {
  if (!Number.isSafeInteger(content.openedAt) || content.openedAt < 0 || content.openedAt > 8640000000000000) {
    return undefined;
  }
  const separator = content.contentKey.indexOf(':');
  if (separator <= 0 || separator !== content.contentKey.lastIndexOf(':')) {
    return undefined;
  }
  const kind = content.contentKey.substring(0, separator);
  const id = content.contentKey.substring(separator + 1);
  if (!/^[1-9][0-9]{0,29}$/.test(id) || kind !== content.contentType) {
    return undefined;
  }
  let contentKind: ReadHistoryContentKind;
  if (kind === ReadHistoryContentKind.QUESTION) {
    contentKind = ReadHistoryContentKind.QUESTION;
  } else if (kind === ReadHistoryContentKind.ANSWER) {
    contentKind = ReadHistoryContentKind.ANSWER;
  } else if (kind === ReadHistoryContentKind.ARTICLE) {
    contentKind = ReadHistoryContentKind.ARTICLE;
  } else if (kind === ReadHistoryContentKind.PIN) {
    contentKind = ReadHistoryContentKind.PIN;
  } else {
    return undefined;
  }
  return {
    contentKey: content.contentKey,
    kind: contentKind,
    id: id,
    openedAt: content.openedAt,
    deletable: true,
    inOnline: false
  };
}

export function onlineHistoryEntryToReadItem(entry: OnlineHistoryEntry): ReadHistoryItem | undefined {
  const kind = readHistoryKindFromOnline(entry.kind);
  if (kind === undefined) {
    return undefined;
  }
  return {
    contentKey: entry.contentKey,
    kind: kind,
    id: entry.id,
    openedAt: entry.readTime,
    title: entry.title,
    summary: entry.summary,
    authorName: entry.authorName,
    deletable: false,
    inOnline: true
  };
}

export function readHistoryOpenTarget(item: ReadHistoryItem): ReadHistoryOpenTarget {
  return { kind: item.kind, id: item.id };
}

export function readHistoryKindLabel(kind: ReadHistoryContentKind): string {
  if (kind === ReadHistoryContentKind.QUESTION) {
    return '问题';
  }
  if (kind === ReadHistoryContentKind.ANSWER) {
    return '回答';
  }
  if (kind === ReadHistoryContentKind.ARTICLE) {
    return '文章';
  }
  return '想法';
}

export function readHistorySourceLabel(item: ReadHistoryItem): string {
  if (item.deletable && item.inOnline) {
    return '本地+在线';
  }
  return item.deletable ? '本地' : '在线';
}

export function readHistorySourceFilterLabel(filter: ReadHistorySourceFilter): string {
  if (filter === ReadHistorySourceFilter.LOCAL) {
    return '本地记录';
  }
  if (filter === ReadHistorySourceFilter.ONLINE) {
    return '在线记录';
  }
  return '全部记录';
}

export function filterReadHistoryItems(items: Array<ReadHistoryItem>,
  filter: ReadHistorySourceFilter): Array<ReadHistoryItem> {
  if (filter === ReadHistorySourceFilter.LOCAL) {
    return items.filter((item: ReadHistoryItem): boolean => item.deletable);
  }
  if (filter === ReadHistorySourceFilter.ONLINE) {
    return items.filter((item: ReadHistoryItem): boolean => item.inOnline);
  }
  return items.slice();
}

export function groupReadHistoryItems(items: Array<ReadHistoryItem>): Array<ReadHistoryGroup> {
  const groups = new Map<string, ReadHistoryGroup>();
  const orderedKeys: Array<string> = [];
  const orderedItems = items.slice().sort((left: ReadHistoryItem, right: ReadHistoryItem): number =>
    right.openedAt - left.openedAt);
  orderedItems.forEach((item: ReadHistoryItem): void => {
    const dayKey = readHistoryDayKey(item.openedAt);
    const current = groups.get(dayKey);
    if (current === undefined) {
      groups.set(dayKey, { dayKey: dayKey, label: readHistoryDayLabel(item.openedAt), items: [item] });
      orderedKeys.push(dayKey);
      return;
    }
    current.items.push(item);
  });
  const result: Array<ReadHistoryGroup> = [];
  orderedKeys.forEach((key: string): void => {
    const group = groups.get(key);
    if (group !== undefined) {
      result.push(group);
    }
  });
  return result;
}

function readHistoryDayKey(openedAt: number): string {
  const value = new Date(openedAt);
  return `${value.getFullYear()}-${`${value.getMonth() + 1}`.padStart(2, '0')}-${`${value.getDate()}`.padStart(2, '0')}`;
}

function readHistoryDayLabel(openedAt: number): string {
  const value = new Date(openedAt);
  return `${value.getFullYear()}年${value.getMonth() + 1}月${value.getDate()}日`;
}

export function mergeReadHistoryItems(local: Array<ReadHistoryItem>,
  online: Array<ReadHistoryItem>): Array<ReadHistoryItem> {
  const byKey = new Map<string, ReadHistoryItem>();
  local.forEach((item: ReadHistoryItem): void => {
    byKey.set(item.contentKey, copyReadHistoryItem(item));
  });
  online.forEach((item: ReadHistoryItem): void => {
    const existing = byKey.get(item.contentKey);
    if (existing === undefined) {
      byKey.set(item.contentKey, copyReadHistoryItem(item));
      return;
    }
    byKey.set(item.contentKey, {
      contentKey: existing.contentKey,
      kind: existing.kind,
      id: existing.id,
      openedAt: Math.max(existing.openedAt, item.openedAt),
      title: existing.title ?? item.title,
      summary: existing.summary ?? item.summary,
      authorName: existing.authorName ?? item.authorName,
      deletable: true,
      inOnline: true
    });
  });
  const merged: Array<ReadHistoryItem> = [];
  byKey.forEach((item: ReadHistoryItem): void => {
    merged.push(item);
  });
  merged.sort((a: ReadHistoryItem, b: ReadHistoryItem): number => b.openedAt - a.openedAt);
  return merged;
}

function readHistoryKindFromOnline(kind: OnlineHistoryKind): ReadHistoryContentKind | undefined {
  if (kind === OnlineHistoryKind.QUESTION) {
    return ReadHistoryContentKind.QUESTION;
  }
  if (kind === OnlineHistoryKind.ANSWER) {
    return ReadHistoryContentKind.ANSWER;
  }
  if (kind === OnlineHistoryKind.ARTICLE) {
    return ReadHistoryContentKind.ARTICLE;
  }
  if (kind === OnlineHistoryKind.PIN) {
    return ReadHistoryContentKind.PIN;
  }
  return undefined;
}

export class ReadHistoryController {
  private readonly history: ReadHistoryGateway;
  private readonly onlineHistory?: OnlineHistoryRepository;
  private readonly onlineEnabled: boolean;
  private readonly observer: ReadHistoryObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: ReadHistoryViewState;
  private localItems: Array<ReadHistoryItem> = [];
  private onlineItems: Array<ReadHistoryItem> = [];
  private onlineCursor?: string;
  private onlineEnded: boolean;
  private onlineFailureMessage?: string;
  private requiresLogin: boolean;

  constructor(history: ReadHistoryGateway,
    onlineHistory?: OnlineHistoryRepository,
    onlineEnabled: boolean = false,
    observer: ReadHistoryObserver = (_state: ReadHistoryViewState): void => {}) {
    this.history = history;
    this.onlineHistory = onlineHistory;
    this.onlineEnabled = onlineEnabled;
    this.observer = observer;
    this.onlineEnded = !onlineEnabled;
    this.requiresLogin = !onlineEnabled;
    this.state = {
      phase: ReadHistoryPhase.LOADING,
      items: [],
      busy: false,
      message: '正在读取本地已读记录',
      requiresLogin: this.requiresLogin,
      onlineEnabled: onlineEnabled,
      loadingMore: false,
      canLoadMore: false
    };
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.reload();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.onlineHistory?.cancel();
  }

  snapshot(): ReadHistoryViewState {
    return copyReadHistoryState(this.state);
  }

  reload(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publishWith(this.state.items, ReadHistoryPhase.LOADING, true,
      this.onlineEnabled ? '正在读取浏览记录' : '正在读取本地已读记录', false, false);
    return this.loadIntoState(generation, this.onlineEnabled ? '浏览记录已更新' : '已读记录已更新');
  }

  delete(contentKey: string): Promise<void> {
    return this.mutate((): Promise<boolean> => this.history.delete(contentKey),
      '已删除这条记录', '删除失败，请重试');
  }

  clear(): Promise<void> {
    return this.mutate(async (): Promise<boolean> => {
      await this.history.clear();
      return true;
    }, this.onlineEnabled ? '已清空本地已读记录，在线历史保留' : '已清空本地已读记录', '清空失败，请重试');
  }

  loadMore(): Promise<void> {
    if (!this.active || this.state.busy || this.onlineEnded || this.onlineCursor === undefined) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publishWith(this.state.items, this.state.phase, true, '正在加载更多在线历史', true, false);
    return this.appendOnlinePage(generation, '在线历史已更新');
  }

  private async mutate(operation: () => Promise<boolean>, successMessage: string,
    failureMessage: string): Promise<void> {
    if (!this.active || this.state.busy) {
      return;
    }
    const generation = ++this.generation;
    this.publishWith(this.state.items, this.state.phase, true, '正在更新本地已读记录', false,
      this.state.canLoadMore);
    try {
      await operation();
      if (this.isCurrent(generation)) {
        await this.loadIntoState(generation, successMessage);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publishWith(this.state.items, ReadHistoryPhase.ERROR, false, failureMessage, false,
          this.onlineEnabled && !this.onlineEnded && this.onlineCursor !== undefined);
      }
    }
  }

  private async loadIntoState(generation: number, successMessage: string): Promise<void> {
    try {
      const stored = await this.history.queryRecent(MAX_READ_HISTORY_ITEMS);
      const localItems: Array<ReadHistoryItem> = [];
      stored.forEach((content: OpenedContent): void => {
        const item = decodeReadHistoryItem(content);
        if (item !== undefined) {
          localItems.push(item);
        }
      });
      this.localItems = localItems;
      this.onlineItems = [];
      this.onlineCursor = undefined;
      this.onlineEnded = !this.onlineEnabled;
      this.onlineFailureMessage = undefined;
      if (!this.isCurrent(generation)) {
        return;
      }
      this.publishMerged(generation, localItems.length === 0 ? '暂无本地已读记录' : '本地已读记录已读取');
      if (this.onlineEnabled && this.onlineHistory !== undefined && this.isCurrent(generation)) {
        this.publishWith(this.state.items, this.state.phase, true, '正在加载在线历史', false, false);
        await this.appendOnlinePage(generation, successMessage);
      }
    } catch (_error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.publishWith(this.state.items, ReadHistoryPhase.ERROR, false, '已读记录读取失败，请重试', false, false);
    }
  }

  private async appendOnlinePage(generation: number, successMessage: string): Promise<void> {
    const repository = this.onlineHistory;
    if (repository === undefined || this.onlineEnded) {
      return;
    }
    try {
      const page = await repository.loadPage(this.onlineCursor);
      if (!this.isCurrent(generation)) {
        return;
      }
      const incoming: Array<ReadHistoryItem> = [];
      page.items.forEach((entry: OnlineHistoryEntry): void => {
        const item = onlineHistoryEntryToReadItem(entry);
        if (item !== undefined) {
          incoming.push(item);
        }
      });
      this.onlineItems = this.onlineItems.concat(incoming);
      this.onlineCursor = page.cursor.next;
      this.onlineEnded = page.cursor.isEnd || incoming.length === 0;
      this.onlineFailureMessage = undefined;
      this.publishMerged(generation, successMessage);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.onlineEnded = true;
      if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
        this.requiresLogin = true;
        this.onlineFailureMessage = '登录已失效，请重新登录后查看在线历史';
      } else {
        this.onlineFailureMessage = this.state.items.length === 0
          ? '在线历史加载失败，请重试'
          : '在线历史加载失败，已显示本地记录';
      }
      this.publishMerged(generation, this.onlineFailureMessage);
    }
  }

  private publishMerged(generation: number, message: string): void {
    if (!this.isCurrent(generation)) {
      return;
    }
    const merged = mergeReadHistoryItems(this.localItems, this.onlineItems);
    const finalMessage = merged.length === 0
      ? (this.onlineFailureMessage ?? (this.onlineEnabled ? '暂无浏览记录' : '暂无本地已读记录'))
      : message;
    this.publishWith(merged, merged.length === 0 ? ReadHistoryPhase.EMPTY : ReadHistoryPhase.READY,
      false, finalMessage, false,
      this.onlineEnabled && !this.onlineEnded && this.onlineCursor !== undefined);
  }

  private publishWith(items: Array<ReadHistoryItem>, phase: ReadHistoryPhase, busy: boolean,
    message: string, loadingMore: boolean, canLoadMore: boolean): void {
    this.publish({
      phase: phase,
      items: items,
      busy: busy,
      message: message,
      requiresLogin: this.requiresLogin,
      onlineEnabled: this.onlineEnabled,
      loadingMore: loadingMore,
      canLoadMore: canLoadMore
    });
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }

  private publish(state: ReadHistoryViewState): void {
    this.state = copyReadHistoryState(state);
    this.observer(this.snapshot());
  }
}

function copyReadHistoryState(state: ReadHistoryViewState): ReadHistoryViewState {
  return {
    phase: state.phase,
    items: state.items.map((item: ReadHistoryItem): ReadHistoryItem => copyReadHistoryItem(item)),
    busy: state.busy,
    message: state.message,
    requiresLogin: state.requiresLogin,
    onlineEnabled: state.onlineEnabled,
    loadingMore: state.loadingMore,
    canLoadMore: state.canLoadMore
  };
}

function copyReadHistoryItem(item: ReadHistoryItem): ReadHistoryItem {
  return {
    contentKey: item.contentKey,
    kind: item.kind,
    id: item.id,
    openedAt: item.openedAt,
    title: item.title,
    summary: item.summary,
    authorName: item.authorName,
    deletable: item.deletable,
    inOnline: item.inOnline
  };
}
