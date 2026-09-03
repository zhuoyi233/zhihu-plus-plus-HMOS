import { QuestionAnswerFeedRepository } from 'data';
import { QuestionAnswersController, QuestionAnswersViewState } from './QuestionAnswersState';

/** 连续阅读独占分页仓库，排序与列表从问题页快照继承，不改动返回栈。 */
export class QuestionAnswerNavigator {
  private readonly controller: QuestionAnswersController;
  private index: number;
  private busy: boolean = false;
  private active: boolean = true;

  constructor(questionId: string, answerId: string, seed: QuestionAnswersViewState,
    repository: QuestionAnswerFeedRepository) {
    this.index = seed.items.findIndex((item): boolean => item.feedItem.target.id === answerId);
    this.controller = new QuestionAnswersController(repository, questionId,
      (_state: QuestionAnswersViewState): void => {}, seed);
    this.controller.activate();
  }

  currentId(): string | undefined {
    return this.controller.snapshot().items[this.index]?.feedItem.target.id;
  }

  hasPrevious(): boolean { return this.index > 0; }
  hasNext(): boolean {
    const state = this.controller.snapshot();
    return this.index + 1 < state.items.length || state.canLoadMore;
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
    if (!this.active || this.busy || this.index < 0 || (direction !== -1 && direction !== 1)) {
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
      return item.feedItem.target.id;
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
