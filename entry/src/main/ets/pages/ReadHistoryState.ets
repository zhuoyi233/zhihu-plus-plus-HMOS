import {
  MAX_READ_HISTORY_ITEMS,
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

export interface ReadHistoryItem {
  contentKey: string;
  kind: ReadHistoryContentKind;
  id: string;
  openedAt: number;
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
    openedAt: content.openedAt
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

export class ReadHistoryController {
  private readonly history: ReadHistoryGateway;
  private readonly observer: ReadHistoryObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在读取本地已读记录'
  };

  constructor(history: ReadHistoryGateway,
    observer: ReadHistoryObserver = (_state: ReadHistoryViewState): void => {}) {
    this.history = history;
    this.observer = observer;
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
  }

  snapshot(): ReadHistoryViewState {
    return copyReadHistoryState(this.state);
  }

  reload(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publish({
      phase: ReadHistoryPhase.LOADING,
      items: this.state.items,
      busy: true,
      message: '正在读取本地已读记录'
    });
    return this.loadIntoState(generation, '已读记录已更新');
  }

  delete(contentKey: string): Promise<void> {
    return this.mutate((): Promise<boolean> => this.history.delete(contentKey), '已删除这条记录', '删除失败，请重试');
  }

  clear(): Promise<void> {
    return this.mutate(async (): Promise<boolean> => {
      await this.history.clear();
      return true;
    }, '已清空本地已读记录', '清空失败，请重试');
  }

  private async mutate(operation: () => Promise<boolean>, successMessage: string,
    failureMessage: string): Promise<void> {
    if (!this.active || this.state.busy) {
      return;
    }
    const generation = ++this.generation;
    this.publish({
      phase: this.state.phase,
      items: this.state.items,
      busy: true,
      message: '正在更新本地已读记录'
    });
    try {
      await operation();
      if (this.isCurrent(generation)) {
        await this.loadIntoState(generation, successMessage);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: ReadHistoryPhase.ERROR,
          items: this.state.items,
          busy: false,
          message: failureMessage
        });
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
      if (this.isCurrent(generation)) {
        this.publish({
          phase: items.length === 0 ? ReadHistoryPhase.EMPTY : ReadHistoryPhase.READY,
          items: items,
          busy: false,
          message: items.length === 0 ? '暂无本地已读记录' : successMessage
        });
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: ReadHistoryPhase.ERROR,
          items: this.state.items,
          busy: false,
          message: '已读记录读取失败，请重试'
        });
      }
    }
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
    items: state.items.map((item: ReadHistoryItem): ReadHistoryItem => ({
      contentKey: item.contentKey,
      kind: item.kind,
      id: item.id,
      openedAt: item.openedAt
    })),
    busy: state.busy,
    message: state.message
  };
}
