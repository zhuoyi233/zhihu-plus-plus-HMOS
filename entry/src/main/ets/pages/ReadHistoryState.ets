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

/** 历史卡片条目：在线与本地两个页面共用，对齐上游 FeedDisplayItem 的展示字段。 */
export interface ReadHistoryItem {
  contentKey: string;
  kind: ReadHistoryContentKind;
  id: string;
  /** 毫秒时间戳；本地为打开时间，在线为知乎 read_time。 */
  openedAt: number;
  title: string;
  summary: string;
  authorName?: string;
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
    title: content.title ?? '',
    summary: '',
    authorName: undefined
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
    authorName: entry.authorName
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

/** 卡片元信息行的时间段：与知乎客户端一致展示到分钟。 */
export function readHistoryTimeLabel(openedAt: number): string {
  try {
    if (!Number.isFinite(openedAt)) {
      return '';
    }
    const value = new Date(openedAt);
    if (Number.isNaN(value.getFullYear())) {
      return '';
    }
    const month = `${value.getMonth() + 1}`.padStart(2, '0');
    const day = `${value.getDate()}`.padStart(2, '0');
    const hour = `${value.getHours()}`.padStart(2, '0');
    const minute = `${value.getMinutes()}`.padStart(2, '0');
    return `${value.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  } catch (_error) {
    return '';
  }
}

export class ReadHistoryController {
  /** 在线历史（主页面）：分页拉取知乎服务端浏览历史；清除时同时清空本地已读记录（对齐上游 clearAllHistory）。 */
  private readonly history: ReadHistoryGateway;
  private readonly onlineHistory?: OnlineHistoryRepository;
  private readonly onlineEnabled: boolean;
  private readonly observer: ReadHistoryObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: ReadHistoryViewState;
  private onlineCursor?: string;
  private onlineEnded: boolean;

  constructor(history: ReadHistoryGateway,
    onlineHistory?: OnlineHistoryRepository,
    onlineEnabled: boolean = false,
    observer: ReadHistoryObserver = (_state: ReadHistoryViewState): void => {}) {
    this.history = history;
    this.onlineHistory = onlineHistory;
    this.onlineEnabled = onlineEnabled;
    this.observer = observer;
    this.onlineEnded = !onlineEnabled;
    this.state = {
      phase: ReadHistoryPhase.LOADING,
      items: [],
      busy: false,
      message: onlineEnabled ? '正在加载历史记录' : '登录后可查看知乎账号的浏览历史',
      requiresLogin: !onlineEnabled,
      loadingMore: false,
      canLoadMore: false
    };
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    void this.reload();
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
    if (!this.onlineEnabled) {
      this.publish(ReadHistoryPhase.EMPTY, [], false, '登录后可查看知乎账号的浏览历史', false, false);
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.onlineCursor = undefined;
    this.onlineEnded = false;
    this.publish(ReadHistoryPhase.LOADING, this.state.items, true, '正在加载历史记录', false, false);
    return this.appendOnlinePage(generation, '历史记录已更新');
  }

  loadMore(): Promise<void> {
    if (!this.active || this.state.busy || this.state.loadingMore || this.onlineEnded ||
      this.onlineCursor === undefined) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publish(this.state.phase, this.state.items, false, this.state.message, true, this.state.canLoadMore);
    return this.appendOnlinePage(generation, '历史记录已更新');
  }

  /** 对齐上游 deleteItem：batch_del 单条删除成功后从列表移除。 */
  async deleteEntry(contentKey: string): Promise<void> {
    const repository = this.onlineHistory;
    if (!this.active || this.state.busy || repository === undefined) {
      return;
    }
    const generation = ++this.generation;
    this.publish(this.state.phase, this.state.items, true, '正在删除该条历史记录', false, this.state.canLoadMore);
    try {
      await repository.deleteEntry(contentKey);
      if (!this.isCurrent(generation)) {
        return;
      }
      const remaining = this.state.items.filter((item: ReadHistoryItem): boolean =>
        item.contentKey !== contentKey);
      this.publish(this.phaseOf(remaining), remaining, false, '已删除该条历史记录', false,
        !this.onlineEnded && this.onlineCursor !== undefined);
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish(this.state.phase, this.state.items, false, '操作失败，请重试', false,
          !this.onlineEnded && this.onlineCursor !== undefined);
      }
    }
  }

  /** 对齐上游 clearAllHistory：一次清空服务端在线历史 + 本机已读记录。 */
  async clearAll(): Promise<void> {
    const repository = this.onlineHistory;
    if (!this.active || this.state.busy || repository === undefined) {
      return;
    }
    const generation = ++this.generation;
    this.publish(this.state.phase, this.state.items, true, '正在清除历史记录', false, false);
    try {
      await this.history.clear();
      await repository.clearAll();
      if (!this.isCurrent(generation)) {
        return;
      }
      this.onlineCursor = undefined;
      this.onlineEnded = true;
      this.publish(ReadHistoryPhase.EMPTY, [], false, '已清除所有历史记录', false, false);
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish(this.state.phase, this.state.items, false, '清除失败，请重试', false,
          !this.onlineEnded && this.onlineCursor !== undefined);
      }
    }
  }

  private async appendOnlinePage(generation: number, successMessage: string): Promise<void> {
    const repository = this.onlineHistory;
    if (repository === undefined || this.onlineEnded) {
      return;
    }
    const replacing = this.onlineCursor === undefined;
    try {
      const page = await repository.loadPage(replacing ? undefined : this.onlineCursor);
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
      const merged = replacing ? incoming
        : appendUniqueItems(this.state.items, incoming);
      this.onlineCursor = page.cursor.next;
      this.onlineEnded = page.cursor.isEnd || incoming.length === 0;
      const message = merged.length === 0 ? '暂无浏览记录' : successMessage;
      this.publish(this.phaseOf(merged), merged, false, message, false,
        !this.onlineEnded && this.onlineCursor !== undefined);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.onlineEnded = true;
      if (error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION) {
        this.publish(ReadHistoryPhase.EMPTY, this.state.items, false, '登录已失效，请重新登录后查看历史记录',
          false, false);
        return;
      }
      if (replacing) {
        this.publish(ReadHistoryPhase.ERROR, [], false, '历史记录加载失败，请重试', false, false);
        return;
      }
      this.publish(this.state.phase, this.state.items, false, '加载更多失败，请重试', false, false);
    }
  }

  private phaseOf(items: Array<ReadHistoryItem>): ReadHistoryPhase {
    return items.length === 0 ? ReadHistoryPhase.EMPTY : ReadHistoryPhase.READY;
  }

  private publish(phase: ReadHistoryPhase, items: Array<ReadHistoryItem>, busy: boolean,
    message: string, loadingMore: boolean, canLoadMore: boolean): void {
    this.state = {
      phase: phase,
      items: items.map((item: ReadHistoryItem): ReadHistoryItem => copyReadHistoryItem(item)),
      busy: busy,
      message: message,
      requiresLogin: !this.onlineEnabled,
      loadingMore: loadingMore,
      canLoadMore: canLoadMore
    };
    this.observer(this.snapshot());
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }
}

export class LocalHistoryController {
  /** 本地历史（对齐上游 LegacyLocalHistoryScreen）：一次性读取本机已读记录，无分页。 */
  private readonly history: ReadHistoryGateway;
  private readonly observer: ReadHistoryObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: ReadHistoryViewState;

  constructor(history: ReadHistoryGateway,
    observer: ReadHistoryObserver = (_state: ReadHistoryViewState): void => {}) {
    this.history = history;
    this.observer = observer;
    this.state = {
      phase: ReadHistoryPhase.LOADING,
      items: [],
      busy: false,
      message: '正在读取本地历史记录',
      requiresLogin: false,
      loadingMore: false,
      canLoadMore: false
    };
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    void this.reload();
  }

  deactivate(): void {
    this.active = false;
    this.generation += 1;
  }

  snapshot(): ReadHistoryViewState {
    return copyReadHistoryState(this.state);
  }

  reload(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publishWith(this.state.items, ReadHistoryPhase.LOADING, true, '正在读取本地历史记录');
    return this.loadIntoState(generation, '本地历史记录已读取');
  }

  async delete(contentKey: string): Promise<void> {
    return this.mutate((): Promise<boolean> => this.history.delete(contentKey),
      '已删除该条本地记录', '删除失败，请重试');
  }

  async clear(): Promise<void> {
    return this.mutate(async (): Promise<boolean> => {
      await this.history.clear();
      return true;
    }, '已清空本地历史记录', '清空失败，请重试');
  }

  private async mutate(operation: () => Promise<boolean>, successMessage: string,
    failureMessage: string): Promise<void> {
    if (!this.active || this.state.busy) {
      return;
    }
    const generation = ++this.generation;
    this.publishWith(this.state.items, this.state.phase, true, '正在更新本地历史记录');
    try {
      await operation();
      if (this.isCurrent(generation)) {
        await this.loadIntoState(generation, successMessage);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publishWith(this.state.items, ReadHistoryPhase.ERROR, false, failureMessage);
      }
    }
  }

  private async loadIntoState(generation: number, successMessage: string): Promise<void> {
    try {
      const stored = await this.history.queryRecent(MAX_READ_HISTORY_ITEMS);
      const items: Array<ReadHistoryItem> = [];
      stored.forEach((content: OpenedContent): void => {
        const item = decodeReadHistoryItem(content);
        if (item !== undefined) {
          items.push(item);
        }
      });
      items.sort((left: ReadHistoryItem, right: ReadHistoryItem): number => right.openedAt - left.openedAt);
      if (!this.isCurrent(generation)) {
        return;
      }
      const message = items.length === 0 ? '暂无本地历史记录' : successMessage;
      this.publishWith(items, items.length === 0 ? ReadHistoryPhase.EMPTY : ReadHistoryPhase.READY,
        false, message);
    } catch (_error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.publishWith(this.state.items, ReadHistoryPhase.ERROR, false, '本地历史记录读取失败，请重试');
    }
  }

  private publishWith(items: Array<ReadHistoryItem>, phase: ReadHistoryPhase, busy: boolean,
    message: string): void {
    this.state = {
      phase: phase,
      items: items.map((item: ReadHistoryItem): ReadHistoryItem => copyReadHistoryItem(item)),
      busy: busy,
      message: message,
      requiresLogin: false,
      loadingMore: false,
      canLoadMore: false
    };
    this.observer(this.snapshot());
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }
}

function appendUniqueItems(current: Array<ReadHistoryItem>, incoming: Array<ReadHistoryItem>)
  : Array<ReadHistoryItem> {
  const seen = new Set<string>();
  current.forEach((item: ReadHistoryItem): void => {
    seen.add(item.contentKey);
  });
  const merged = current.slice();
  incoming.forEach((item: ReadHistoryItem): void => {
    if (seen.has(item.contentKey)) {
      return;
    }
    seen.add(item.contentKey);
    merged.push(item);
  });
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

function copyReadHistoryState(state: ReadHistoryViewState): ReadHistoryViewState {
  return {
    phase: state.phase,
    items: state.items.map((item: ReadHistoryItem): ReadHistoryItem => copyReadHistoryItem(item)),
    busy: state.busy,
    message: state.message,
    requiresLogin: state.requiresLogin,
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
    authorName: item.authorName
  };
}
