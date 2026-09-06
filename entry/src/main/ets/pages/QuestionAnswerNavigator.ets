import { QuestionAnswerFeedRepository } from 'data';
import { QuestionAnswersController, QuestionAnswersViewState } from './QuestionAnswersState';

/** 下一个回答预览信息（对齐上游 CachedAnswerContent 的预览卡片数据）。 */
export interface AnswerNavigationPreview {
  readonly answerId: string;
  readonly authorName: string;
  readonly authorAvatarUrl: string;
  readonly excerpt: string;
  /** false：下一答还在未加载的分页里，暂无作者/摘要等详情。 */
  readonly detailLoaded: boolean;
}

/**
 * 连续阅读独占分页仓库，排序与列表从问题页快照继承，不改动返回栈。
 * 信息流直达回答（无种子）也可构造：控制器自动拉取问题回答列表并回填当前索引。
 */
export class QuestionAnswerNavigator {
  private readonly controller: QuestionAnswersController;
  private index: number;
  /** 当前回答 id：种子列表可能不含（信息流直达），索引待列表加载后回填。 */
  private currentAnswerId: string;
  private busy: boolean = false;
  private active: boolean = true;
  private readonly onStateChange?: () => void;

  constructor(questionId: string, answerId: string, seed: QuestionAnswersViewState | undefined,
    repository: QuestionAnswerFeedRepository, onStateChange?: () => void) {
    this.currentAnswerId = answerId;
    this.index = seed?.items.findIndex((item): boolean => item.feedItem.target.id === answerId) ?? -1;
    this.onStateChange = onStateChange;
    this.controller = new QuestionAnswersController(repository, questionId,
      (state: QuestionAnswersViewState): void => { this.onControllerState(state); }, seed);
    this.controller.activate();
  }

  /** 列表到达后回填当前索引（信息流直达时种子为空）。 */
  private onControllerState(state: QuestionAnswersViewState): void {
    if (this.index < 0 && state.items.length > 0) {
      const located = state.items.findIndex((item): boolean => item.feedItem.target.id === this.currentAnswerId);
      if (located >= 0) {
        this.index = located;
      }
    }
    if (this.onStateChange !== undefined) {
      this.onStateChange();
    }
  }

  currentId(): string | undefined {
    return this.currentAnswerId;
  }

  /** 下一答预览数据：无下一答返回 undefined；下一答在未加载分页时 detailLoaded=false。 */
  nextAnswerPreview(): AnswerNavigationPreview | undefined {
    if (!this.hasNext()) { return undefined; }
    const target = this.controller.snapshot().items[this.index + 1]?.feedItem.target;
    if (target === undefined) {
      return { answerId: '', authorName: '', authorAvatarUrl: '', excerpt: '', detailLoaded: false };
    }
    return {
      answerId: target.id,
      authorName: target.author?.name ?? '',
      authorAvatarUrl: target.author?.avatarUrl ?? '',
      excerpt: target.excerpt,
      detailLoaded: true
    };
  }

  /** 上一答预览数据：首答（无上一答）返回 undefined。 */
  previousAnswerPreview(): AnswerNavigationPreview | undefined {
    if (!this.hasPrevious()) { return undefined; }
    const target = this.controller.snapshot().items[this.index - 1]?.feedItem.target;
    if (target === undefined) {
      return { answerId: '', authorName: '', authorAvatarUrl: '', excerpt: '', detailLoaded: false };
    }
    return {
      answerId: target.id,
      authorName: target.author?.name ?? '',
      authorAvatarUrl: target.author?.avatarUrl ?? '',
      excerpt: target.excerpt,
      detailLoaded: true
    };
  }

  hasPrevious(): boolean { return this.index > 0; }
  hasNext(): boolean {
    const state = this.controller.snapshot();
    if (this.index >= 0) {
      return this.index + 1 < state.items.length || state.canLoadMore;
    }
    // 未定位（列表未加载或不含当前回答）：存在其他回答即可切下一答（首个非当前回答）。
    return state.items.some((item): boolean => item.feedItem.target.id !== this.currentAnswerId) ||
      state.canLoadMore;
  }
  errorMessage(): string { return this.controller.snapshot().errorMessage; }

  pause(): void {
    this.active = false;
    this.controller.deactivate();
  }

  resume(): void {
    this.active = true;
    this.controller.activate();
  }

  async move(direction: number): Promise<string | undefined> {
    if (!this.active || this.busy || (direction !== -1 && direction !== 1)) {
      return undefined;
    }
    this.busy = true;
    try {
      if (direction === 1 && this.index + 1 >= this.controller.snapshot().items.length && this.hasNext()) {
        await this.controller.loadMore();
      }
      if (!this.active) { return undefined; }
      const nextIndex = this.index + direction;
      const item = this.controller.snapshot().items[nextIndex];
      if (item === undefined) { return undefined; }
      this.index = nextIndex;
      this.currentAnswerId = item.feedItem.target.id;
      return this.currentAnswerId;
    } finally {
      this.busy = false;
    }
  }

  dispose(): void {
    this.pause();
  }
}

let pending: QuestionAnswerNavigator | undefined;

export function stageQuestionAnswerNavigator(navigator: QuestionAnswerNavigator): void {
  pending?.dispose();
  pending = navigator;
}

/** 与编辑种子相同，只在紧接着打开的回答页消费一次；不持久化。 */
export function takeQuestionAnswerNavigator(answerId: string): QuestionAnswerNavigator | undefined {
  const navigator = pending;
  pending = undefined;
  if (navigator?.currentId() !== answerId) {
    navigator?.dispose();
    return undefined;
  }
  return navigator;
}
