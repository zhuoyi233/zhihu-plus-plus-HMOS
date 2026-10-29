import { QuestionAnswerFeedRepository } from 'data';
import { QuestionAnswersController, QuestionAnswersViewState } from './QuestionAnswersState';

/** 下一个回答预览信息（对齐上游 CachedAnswerContent 的预览卡片数据）。 */
export interface AnswerNavigationPreview {
  readonly answerId: string;
  readonly authorName: string;
  readonly authorAvatarUrl: string;
  readonly authorHeadline: string;
  readonly excerpt: string;
  readonly voteupCount: number;
  readonly commentCount: number;
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
  /** 打开本页时的那条回答：信息流直达的回答可能不在已加载的回答列表里（默认排序首屏不一定包含它），
   *  此时它是列表首条之前的"虚拟上一答"，否则切走后无法反向滑回来。 */
  private readonly entryAnswerId: string;
  private entryOutsideList: boolean = false;
  private generation: number = 0;
  private preparedId: string = '';
  private preparedDirection: number = 0;
  private busy: boolean = false;
  private active: boolean = true;
  private readonly onStateChange?: () => void;

  constructor(questionId: string, answerId: string, seed: QuestionAnswersViewState | undefined,
    repository: QuestionAnswerFeedRepository, onStateChange?: () => void) {
    this.currentAnswerId = answerId;
    this.entryAnswerId = answerId;
    this.index = seed?.items.findIndex((item): boolean => item.feedItem.target.id === answerId) ?? -1;
    this.onStateChange = onStateChange;
    this.controller = new QuestionAnswersController(repository, questionId,
      (state: QuestionAnswersViewState): void => { this.onControllerState(state); }, seed);
    this.controller.activate();
  }

  /** 列表到达后回填当前索引（信息流直达时种子为空）。 */
  private onControllerState(state: QuestionAnswersViewState): void {
    this.entryOutsideList = state.items.length > 0 &&
      !state.items.some((item): boolean => item.feedItem.target.id === this.entryAnswerId);
    this.index = state.items.findIndex((item): boolean => item.feedItem.target.id === this.currentAnswerId);
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
      return { answerId: '', authorName: '', authorAvatarUrl: '', authorHeadline: '', excerpt: '',
        voteupCount: 0, commentCount: 0, detailLoaded: false };
    }
    return {
      answerId: target.id,
      authorName: target.author?.name ?? '',
      authorAvatarUrl: target.author?.avatarUrl ?? '',
      authorHeadline: target.author?.headline ?? '',
      excerpt: target.excerpt,
      voteupCount: target.voteupCount ?? 0,
      commentCount: target.commentCount ?? 0,
      detailLoaded: true
    };
  }

  /** 上一答预览数据：首答（无上一答）返回 undefined。 */
  previousAnswerPreview(): AnswerNavigationPreview | undefined {
    if (!this.hasPrevious()) { return undefined; }
    if (this.index === 0 && this.entryOutsideList) {
      // 入口回答不在列表里：没有作者/摘要可预览，只带 id，等正文从缓存出来后自然回填。
      return { answerId: this.entryAnswerId, authorName: '', authorAvatarUrl: '', authorHeadline: '',
        excerpt: '', voteupCount: 0, commentCount: 0, detailLoaded: false };
    }
    const target = this.controller.snapshot().items[this.index - 1]?.feedItem.target;
    if (target === undefined) {
      return { answerId: '', authorName: '', authorAvatarUrl: '', authorHeadline: '', excerpt: '',
        voteupCount: 0, commentCount: 0, detailLoaded: false };
    }
    return {
      answerId: target.id,
      authorName: target.author?.name ?? '',
      authorAvatarUrl: target.author?.avatarUrl ?? '',
      authorHeadline: target.author?.headline ?? '',
      excerpt: target.excerpt,
      voteupCount: target.voteupCount ?? 0,
      commentCount: target.commentCount ?? 0,
      detailLoaded: true
    };
  }

  /** 上一答：列表首条之前还有"入口回答"时也算有（信息流直达的常见情形）。 */
  hasPrevious(): boolean { return this.index > 0 || (this.index === 0 && this.entryOutsideList); }
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
    this.cancelPreparedMove();
    this.controller.deactivate();
  }

  resume(): void {
    this.active = true;
    this.controller.activate();
  }

  /** 相邻查询只读已到达列表，绝不隐式分页。 */
  peekId(direction: number): string | undefined {
    if (!this.active || (direction !== -1 && direction !== 1)) { return undefined; }
    if (direction === -1 && this.index === 0 && this.entryOutsideList) { return this.entryAnswerId; }
    if (direction === -1 && this.index < 0) { return undefined; }
    const id = this.controller.snapshot().items[this.index + direction]?.feedItem.target.id;
    return id !== undefined && id.length > 0 && id !== this.currentAnswerId ? id : undefined;
  }

  /** 准备只确定目标；正式索引在正文可以提交时才改变。 */
  async prepareMove(direction: number): Promise<string | undefined> {
    if (!this.active || this.busy || (direction !== -1 && direction !== 1)) { return undefined; }
    this.cancelPreparedMove();
    const generation = this.generation;
    this.busy = true;
    try {
      if (this.peekId(direction) === undefined && direction === 1 && this.hasNext()) {
        await this.controller.loadMore();
      }
      if (!this.active || generation !== this.generation) { return undefined; }
      const id = this.peekId(direction);
      this.preparedId = id ?? '';
      this.preparedDirection = direction;
      return id;
    } finally {
      if (generation === this.generation) { this.busy = false; }
    }
  }

  canCommitMove(id: string): boolean {
    return this.active && id.length > 0 && this.preparedId === id &&
      this.peekId(this.preparedDirection) === id;
  }

  commitMove(id: string): boolean {
    if (!this.canCommitMove(id)) { return false; }
    this.currentAnswerId = id;
    this.index = this.controller.snapshot().items.findIndex((item): boolean => item.feedItem.target.id === id);
    this.cancelPreparedMove();
    return true;
  }

  cancelPreparedMove(): void {
    this.generation += 1;
    this.preparedId = '';
    this.preparedDirection = 0;
    this.busy = false;
  }

  /** 列表调用方的便利接口；阅读页必须使用 prepare/commit 分开的事务。 */
  async move(direction: number): Promise<string | undefined> {
    const id = await this.prepareMove(direction);
    return id !== undefined && this.commitMove(id) ? id : undefined;
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
