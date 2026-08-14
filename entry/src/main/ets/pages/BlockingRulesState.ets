import {
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule,
  BlockingPreferences,
  BlockingPreferencesGateway,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlocklistBackupImportSummary,
  defaultBlockingPreferences,
  encodeBlocklistBackup,
  importBlocklistBackup,
  normalizeBlockingPreferences
} from 'data';

export enum BlockingRulesPhase {
  LOADING = 'loading',
  READY = 'ready',
  ERROR = 'error'
}

export interface BlockingRulesViewState {
  phase: BlockingRulesPhase;
  selectedKind: BlockingRuleKind;
  keywords: Array<BlockedKeywordRule>;
  users: Array<BlockedUserRule>;
  topics: Array<BlockedTopicRule>;
  preferences: BlockingPreferences;
  busy: boolean;
  message: string;
}

export type BlockingRulesObserver = (state: BlockingRulesViewState) => void;

export class BlockingRulesController {
  private readonly rules: BlockingRuleGateway;
  private readonly preferences: BlockingPreferencesGateway;
  private readonly observer: BlockingRulesObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: BlockingRulesViewState = {
    phase: BlockingRulesPhase.LOADING,
    selectedKind: BlockingRuleKind.KEYWORD,
    keywords: [],
    users: [],
    topics: [],
    preferences: defaultBlockingPreferences(),
    busy: false,
    message: '正在读取屏蔽规则'
  };

  constructor(rules: BlockingRuleGateway, preferences: BlockingPreferencesGateway,
    observer: BlockingRulesObserver = (_state: BlockingRulesViewState): void => {}) {
    this.rules = rules;
    this.preferences = preferences;
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

  snapshot(): BlockingRulesViewState {
    return copyBlockingRulesState(this.state);
  }

  selectKind(kind: BlockingRuleKind): void {
    if (!this.active || this.state.busy || this.state.selectedKind === kind) {
      return;
    }
    this.publish({
      phase: this.state.phase,
      selectedKind: kind,
      keywords: this.state.keywords,
      users: this.state.users,
      topics: this.state.topics,
      preferences: this.state.preferences,
      busy: false,
      message: this.state.message
    });
  }

  reload(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    const generation = ++this.generation;
    this.publish({
      phase: BlockingRulesPhase.LOADING,
      selectedKind: this.state.selectedKind,
      keywords: this.state.keywords,
      users: this.state.users,
      topics: this.state.topics,
      preferences: this.state.preferences,
      busy: true,
      message: '正在读取屏蔽规则'
    });
    return this.loadIntoState(generation, '屏蔽规则已更新');
  }

  addKeyword(keyword: string, caseSensitive: boolean, isRegex: boolean): Promise<void> {
    return this.mutate((): Promise<void> => this.rules.addKeyword(keyword, caseSensitive, isRegex),
      '关键词规则已添加', '关键词格式无效或保存失败');
  }

  addUser(userId: string, userName: string): Promise<void> {
    return this.mutate((): Promise<void> => this.rules.addUser(userId, userName),
      '用户规则已添加', '用户 ID 或名称无效，保存失败');
  }

  addTopic(topicId: string, topicName: string): Promise<void> {
    return this.mutate((): Promise<void> => this.rules.addTopic(topicId, topicName),
      '话题规则已添加', '话题 ID 或名称无效，保存失败');
  }

  deleteKeyword(id: number): Promise<void> {
    return this.mutate((): Promise<void> => this.rules.deleteKeyword(id), '关键词规则已删除', '删除失败，请重试');
  }

  deleteUser(userId: string): Promise<void> {
    return this.mutate((): Promise<void> => this.rules.deleteUser(userId), '用户规则已删除', '删除失败，请重试');
  }

  deleteTopic(topicId: string): Promise<void> {
    return this.mutate((): Promise<void> => this.rules.deleteTopic(topicId), '话题规则已删除', '删除失败，请重试');
  }

  clearSelected(): Promise<void> {
    const kind = this.state.selectedKind;
    return this.mutate((): Promise<void> => this.rules.clear(kind), '当前分类已清空', '清空失败，请重试');
  }

  savePreferences(value: BlockingPreferences): Promise<void> {
    const normalized = normalizeBlockingPreferences(value);
    return this.mutate((): Promise<void> => this.preferences.saveBlockingPreferences(normalized),
      '屏蔽开关已保存', '屏蔽开关保存失败');
  }

  exportBackup(): Promise<string | undefined> {
    if (!this.active || this.state.busy) {
      return Promise.resolve(undefined);
    }
    const generation = ++this.generation;
    this.publish({
      phase: this.state.phase,
      selectedKind: this.state.selectedKind,
      keywords: this.state.keywords,
      users: this.state.users,
      topics: this.state.topics,
      preferences: this.state.preferences,
      busy: true,
      message: '正在导出屏蔽规则'
    });
    return this.loadSnapshotAndEncode(generation);
  }

  importBackup(text: string): Promise<BlocklistBackupImportSummary | undefined> {
    if (!this.active || this.state.busy) {
      return Promise.resolve(undefined);
    }
    const generation = ++this.generation;
    this.publish({
      phase: this.state.phase,
      selectedKind: this.state.selectedKind,
      keywords: this.state.keywords,
      users: this.state.users,
      topics: this.state.topics,
      preferences: this.state.preferences,
      busy: true,
      message: '正在导入屏蔽规则'
    });
    return this.importIntoState(text, generation);
  }

  private async loadSnapshotAndEncode(generation: number): Promise<string | undefined> {
    try {
      const snapshot = await this.rules.loadSnapshot();
      const text = encodeBlocklistBackup(snapshot);
      if (this.isCurrent(generation)) {
        const total = snapshot.keywords.length + snapshot.users.length + snapshot.topics.length;
        this.publish({
          phase: BlockingRulesPhase.READY,
          selectedKind: this.state.selectedKind,
          keywords: this.state.keywords,
          users: this.state.users,
          topics: this.state.topics,
          preferences: this.state.preferences,
          busy: false,
          message: `已导出 ${total} 条规则`
        });
      }
      return text;
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockingRulesPhase.ERROR,
          selectedKind: this.state.selectedKind,
          keywords: this.state.keywords,
          users: this.state.users,
          topics: this.state.topics,
          preferences: this.state.preferences,
          busy: false,
          message: '导出失败，请重试'
        });
      }
      return undefined;
    }
  }

  private async importIntoState(text: string, generation: number):
    Promise<BlocklistBackupImportSummary | undefined> {
    try {
      const summary = await importBlocklistBackup(text, this.rules);
      if (this.isCurrent(generation)) {
        await this.loadIntoState(generation,
          `导入完成：关键词 ${summary.keywords} · 用户 ${summary.users} · 话题 ${summary.topics}`);
      }
      return summary;
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockingRulesPhase.ERROR,
          selectedKind: this.state.selectedKind,
          keywords: this.state.keywords,
          users: this.state.users,
          topics: this.state.topics,
          preferences: this.state.preferences,
          busy: false,
          message: '导入失败，请检查文本格式'
        });
      }
      return undefined;
    }
  }

  private async mutate(operation: () => Promise<void>, successMessage: string, failureMessage: string): Promise<void> {
    if (!this.active || this.state.busy) {
      return;
    }
    const generation = ++this.generation;
    this.publish({
      phase: this.state.phase,
      selectedKind: this.state.selectedKind,
      keywords: this.state.keywords,
      users: this.state.users,
      topics: this.state.topics,
      preferences: this.state.preferences,
      busy: true,
      message: '正在保存本地规则'
    });
    try {
      await operation();
      if (this.isCurrent(generation)) {
        await this.loadIntoState(generation, successMessage);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockingRulesPhase.ERROR,
          selectedKind: this.state.selectedKind,
          keywords: this.state.keywords,
          users: this.state.users,
          topics: this.state.topics,
          preferences: this.state.preferences,
          busy: false,
          message: failureMessage
        });
      }
    }
  }

  private async loadIntoState(generation: number, successMessage: string): Promise<void> {
    try {
      const rules = await this.rules.loadSnapshot();
      const preferences = await this.preferences.loadBlockingPreferences();
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockingRulesPhase.READY,
          selectedKind: this.state.selectedKind,
          keywords: rules.keywords,
          users: rules.users,
          topics: rules.topics,
          preferences: preferences,
          busy: false,
          message: successMessage
        });
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.publish({
          phase: BlockingRulesPhase.ERROR,
          selectedKind: this.state.selectedKind,
          keywords: this.state.keywords,
          users: this.state.users,
          topics: this.state.topics,
          preferences: this.state.preferences,
          busy: false,
          message: '屏蔽规则读取失败，请重试'
        });
      }
    }
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }

  private publish(state: BlockingRulesViewState): void {
    this.state = copyBlockingRulesState(state);
    this.observer(this.snapshot());
  }
}

function copyBlockingRulesState(state: BlockingRulesViewState): BlockingRulesViewState {
  return {
    phase: state.phase,
    selectedKind: state.selectedKind,
    keywords: state.keywords.map((rule: BlockedKeywordRule): BlockedKeywordRule => ({
      id: rule.id,
      keyword: rule.keyword,
      caseSensitive: rule.caseSensitive,
      isRegex: rule.isRegex,
      createdAt: rule.createdAt
    })),
    users: state.users.map((rule: BlockedUserRule): BlockedUserRule => ({
      userId: rule.userId,
      userName: rule.userName,
      createdAt: rule.createdAt
    })),
    topics: state.topics.map((rule: BlockedTopicRule): BlockedTopicRule => ({
      topicId: rule.topicId,
      topicName: rule.topicName,
      createdAt: rule.createdAt
    })),
    preferences: normalizeBlockingPreferences(state.preferences),
    busy: state.busy,
    message: state.message
  };
}
