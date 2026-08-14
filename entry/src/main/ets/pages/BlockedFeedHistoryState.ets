import {
  BlockedFeedHistoryGateway,
  BlockedFeedRecord,
  BlockingRuleKind,
  MAX_BLOCKED_FEED_RECORDS
} from 'data';

export enum BlockedFeedHistoryPhase {
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface BlockedFeedHistoryViewState {
  phase: BlockedFeedHistoryPhase;
  records: Array<BlockedFeedRecord>;
  busy: boolean;
  message: string;
}

export type BlockedFeedHistoryObserver = (state: BlockedFeedHistoryViewState) => void;

export function blockedFeedHistoryItemLabel(kind: BlockingRuleKind): string {
  if (kind === BlockingRuleKind.KEYWORD) {
    return '屏蔽关键词';
  }
  if (kind === BlockingRuleKind.USER) {
    return '屏蔽用户';
  }
  return '屏蔽话题';
}

export class BlockedFeedHistoryController {
  private readonly history: BlockedFeedHistoryGateway;
  private readonly observer: BlockedFeedHistoryObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: BlockedFeedHistoryViewState = {
    phase: BlockedFeedHistoryPhase.LOADING,
    records: [],
    busy: false,
    message: '正在读取屏蔽记录'
  };

  constructor(history: BlockedFeedHistoryGateway,
    observer: BlockedFeedHistoryObserver = (_state: BlockedFeedHistoryViewState): void => {}) {
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

  snapshot(): BlockedFeedHistoryViewState {
    return copyBlockedFeedHistoryState(this.state);
  }

  reload(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publish({
      phase: BlockedFeedHistoryPhase.LOADING,
      records: this.state.records,
      busy: true,
      message: '正在读取屏蔽记录'
    });
    return this.loadIntoState(generation, '屏蔽记录已更新');
  }

  delete(id: number): Promise<void> {
    return this.mutate((): Promise<void> => this.history.delete(id), '已删除这条屏蔽记录', '删除失败，请重试');
  }

  clear(): Promise<void> {
    return this.mutate((): Promise<void> => this.history.clear(), '已清空屏蔽记录', '清空失败，请重试');
  }

  private async mutate(operation: () => Promise<void>, successMessage: string,
    failureMessage: string): Promise<void> {
    if (!this.active || this.state.busy) {
      return;
    }
    const generation = ++this.generation;
    this.publish({
      phase: this.state.phase,
      records: this.state.records,
      busy: true,
      message: '正在更新屏蔽记录'
    });
    try {
      await operation();
      if (this.isCurrent(generation)) {
        await this.loadIntoState(generation, successMessage);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockedFeedHistoryPhase.ERROR,
          records: this.state.records,
          busy: false,
          message: failureMessage
        });
      }
    }
  }

  private async loadIntoState(generation: number, successMessage: string): Promise<void> {
    try {
      const records = await this.history.queryRecent(MAX_BLOCKED_FEED_RECORDS);
      if (this.isCurrent(generation)) {
        this.publish({
          phase: records.length === 0 ? BlockedFeedHistoryPhase.EMPTY : BlockedFeedHistoryPhase.READY,
          records: records,
          busy: false,
          message: records.length === 0 ? '暂无屏蔽记录' : successMessage
        });
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockedFeedHistoryPhase.ERROR,
          records: this.state.records,
          busy: false,
          message: '屏蔽记录读取失败，请重试'
        });
      }
    }
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }

  private publish(state: BlockedFeedHistoryViewState): void {
    this.state = copyBlockedFeedHistoryState(state);
    this.observer(this.snapshot());
  }
}

function copyBlockedFeedHistoryState(state: BlockedFeedHistoryViewState): BlockedFeedHistoryViewState {
  return {
    phase: state.phase,
    records: state.records.map((record: BlockedFeedRecord): BlockedFeedRecord => ({
      id: record.id,
      kind: record.kind,
      ruleId: record.ruleId,
      ruleName: record.ruleName,
      contentTitle: record.contentTitle,
      contentKind: record.contentKind,
      contentId: record.contentId,
      blockedAt: record.blockedAt
    })),
    busy: state.busy,
    message: state.message
  };
}
