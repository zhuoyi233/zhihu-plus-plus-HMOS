import {
  BlockedFeedHistoryGateway,
  BlockedFeedRecordInput,
  BlockingRuleGateway,
  BlockingRuleKind,
  validateBlockingKeyword
} from 'data';

export enum BlockingActionPhase {
  IDLE = 'idle',
  BLOCKING = 'blocking',
  SUCCESS = 'success',
  ERROR = 'error'
}

export interface BlockingActionContext {
  contentTitle: string;
  contentKind: string;
  contentId: string;
}

export interface BlockingUserCandidate {
  userId: string;
  userName: string;
}

export interface BlockingActionViewState {
  phase: BlockingActionPhase;
  busy: boolean;
  message: string;
}

export type BlockingActionObserver = (state: BlockingActionViewState) => void;

export class BlockingActionController {
  private readonly rules: BlockingRuleGateway;
  private readonly history: BlockedFeedHistoryGateway;
  private readonly observer: BlockingActionObserver;
  private state: BlockingActionViewState = {
    phase: BlockingActionPhase.IDLE,
    busy: false,
    message: ''
  };

  constructor(rules: BlockingRuleGateway, history: BlockedFeedHistoryGateway,
    observer: BlockingActionObserver = (_state: BlockingActionViewState): void => {}) {
    this.rules = rules;
    this.history = history;
    this.observer = observer;
  }

  snapshot(): BlockingActionViewState {
    return copyBlockingActionState(this.state);
  }

  reset(): void {
    this.publish({
      phase: BlockingActionPhase.IDLE,
      busy: false,
      message: ''
    });
  }

  blockUser(userId: string, userName: string, context: BlockingActionContext): Promise<void> {
    return this.perform(async (): Promise<void> => {
      await this.rules.addUser(userId, userName);
      await this.record(BlockingRuleKind.USER, userId, userName, context);
    }, `已屏蔽用户：${userName}`);
  }

  blockKeyword(keyword: string, context: BlockingActionContext): Promise<void> {
    return this.perform(async (): Promise<void> => {
      const normalized = validateBlockingKeyword(keyword, false);
      await this.rules.addKeyword(normalized, false, false);
      await this.record(BlockingRuleKind.KEYWORD, normalized, normalized, context);
    }, `已屏蔽关键词：${keyword.trim()}`);
  }

  blockTopic(topicId: string, topicName: string, context: BlockingActionContext): Promise<void> {
    return this.perform(async (): Promise<void> => {
      await this.rules.addTopic(topicId, topicName);
      await this.record(BlockingRuleKind.TOPIC, topicId, topicName, context);
    }, `已屏蔽话题：${topicName}`);
  }

  private async record(kind: BlockingRuleKind, ruleId: string, ruleName: string,
    context: BlockingActionContext): Promise<void> {
    const record: BlockedFeedRecordInput = {
      kind: kind,
      ruleId: ruleId,
      ruleName: ruleName,
      contentTitle: context.contentTitle.substring(0, 500),
      contentKind: context.contentKind.substring(0, 32),
      contentId: context.contentId.substring(0, 200),
      blockedAt: Date.now()
    };
    try {
      await this.history.insert(record);
    } catch (_error) {
      // 屏蔽记录写入失败不阻塞屏蔽主流程：规则已写入，内容仍会被过滤。
    }
  }

  private async perform(operation: () => Promise<void>, successMessage: string): Promise<void> {
    if (this.state.busy) {
      return;
    }
    this.publish({
      phase: BlockingActionPhase.BLOCKING,
      busy: true,
      message: '正在保存屏蔽规则'
    });
    try {
      await operation();
      this.publish({
        phase: BlockingActionPhase.SUCCESS,
        busy: false,
        message: successMessage
      });
    } catch (_error) {
      this.publish({
        phase: BlockingActionPhase.ERROR,
        busy: false,
        message: '屏蔽失败，请重试'
      });
    }
  }

  private publish(state: BlockingActionViewState): void {
    this.state = copyBlockingActionState(state);
    this.observer(this.snapshot());
  }
}

function copyBlockingActionState(state: BlockingActionViewState): BlockingActionViewState {
  return {
    phase: state.phase,
    busy: state.busy,
    message: state.message
  };
}
