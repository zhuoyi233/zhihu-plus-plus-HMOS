import {
  ChannelContentItem,
  QuestionAnswerFeedRepository,
  QuestionAnswerFeedPage,
  QuestionAnswerSortOrder
} from 'data';
import { contentDetailRequiresLogin, contentDetailErrorMessage } from './ContentDetailState';

export enum QuestionAnswersPhase {
  IDLE = 'idle',
  INITIAL_LOADING = 'initial_loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface QuestionAnswersViewState {
  readonly phase: QuestionAnswersPhase;
  readonly items: Array<ChannelContentItem>;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly sortOrder: QuestionAnswerSortOrder;
  readonly errorMessage: string;
  readonly requiresLogin: boolean;
  readonly nextCursor?: string;
}

/**
 * 问题详情页回答信息流控制器（P1）：分页/排序/代际取消，模式对齐 ChannelFeedController。
 * 匿名态不创建控制器，由页面侧负责登录门禁（对齐上游 allowGuestAccess=false）。
 */
export class QuestionAnswersController {
  private readonly repository: QuestionAnswerFeedRepository;
  private readonly questionId: string;
  private readonly observer: (state: QuestionAnswersViewState) => void;
  private active: boolean = false;
  private generation: number = 0;
  private phase: QuestionAnswersPhase = QuestionAnswersPhase.IDLE;
  private items: Array<ChannelContentItem> = [];
  private loadingMore: boolean = false;
  private canLoadMore: boolean = false;
  private nextCursor?: string;
  private sortOrder: QuestionAnswerSortOrder = QuestionAnswerSortOrder.DEFAULT;
  private errorMessage: string = '';
  private requiresLogin: boolean = false;

  constructor(repository: QuestionAnswerFeedRepository, questionId: string,
    observer: (state: QuestionAnswersViewState) => void, seed?: QuestionAnswersViewState) {
    this.repository = repository;
    this.questionId = questionId;
    this.observer = observer;
    if (seed !== undefined) {
      this.items = seed.items.slice();
      this.sortOrder = seed.sortOrder;
      this.nextCursor = seed.nextCursor;
      this.canLoadMore = seed.canLoadMore;
      this.phase = this.items.length > 0 ? QuestionAnswersPhase.READY : QuestionAnswersPhase.IDLE;
    }
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    if (this.items.length === 0 && (this.phase === QuestionAnswersPhase.IDLE ||
      this.phase === QuestionAnswersPhase.INITIAL_LOADING)) {
      this.phase = QuestionAnswersPhase.INITIAL_LOADING;
      this.emit();
      void this.loadFirstPage();
      return;
    }
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.loadingMore = false;
    this.repository.cancel();
  }

  async setSortOrder(order: QuestionAnswerSortOrder): Promise<void> {
    if (!this.active || order === this.sortOrder) {
      return;
    }
    this.sortOrder = order;
    await this.resetAndReload();
  }

  async refresh(): Promise<void> {
    if (!this.active) {
      return;
    }
    await this.resetAndReload();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.loadingMore || !this.canLoadMore || this.phase !== QuestionAnswersPhase.READY) {
      return;
    }
    const cursor = this.nextCursor;
    if (cursor === undefined) {
      return;
    }
    this.loadingMore = true;
    this.errorMessage = '';
    this.requiresLogin = false;
    this.emit();
    const requestGeneration = this.generation;
    try {
      const page = await this.loadVisiblePage(cursor);
      if (!this.active || requestGeneration !== this.generation) {
        return;
      }
      const known = new Set<string>(this.items.map((item: ChannelContentItem): string =>
        feedItemKey(item)));
      const fresh: Array<ChannelContentItem> = [];
      page.items.forEach((item: ChannelContentItem): void => {
        const key = feedItemKey(item);
        if (known.has(key)) {
          return;
        }
        known.add(key);
        fresh.push(item);
      });
      this.items = this.items.concat(fresh);
      this.nextCursor = page.cursor.isEnd ? undefined : page.cursor.next;
      this.canLoadMore = this.nextCursor !== undefined;
      this.loadingMore = false;
      this.emit();
    } catch (error) {
      if (!this.active || requestGeneration !== this.generation) {
        return;
      }
      this.loadingMore = false;
      this.errorMessage = contentDetailErrorMessage(error);
      this.requiresLogin = contentDetailRequiresLogin(error);
      this.emit();
    }
  }

  private async resetAndReload(): Promise<void> {
    this.generation += 1;
    this.repository.cancel();
    this.errorMessage = '';
    this.requiresLogin = false;
    this.items = [];
    this.nextCursor = undefined;
    this.canLoadMore = false;
    this.loadingMore = false;
    this.phase = QuestionAnswersPhase.INITIAL_LOADING;
    this.emit();
    await this.loadFirstPage();
  }

  private async loadFirstPage(): Promise<void> {
    const requestGeneration = this.generation;
    try {
      const page = await this.loadVisiblePage();
      if (!this.active || requestGeneration !== this.generation) {
        return;
      }
      this.items = page.items;
      this.nextCursor = page.cursor.isEnd ? undefined : page.cursor.next;
      this.canLoadMore = this.nextCursor !== undefined;
      this.phase = this.items.length > 0 ? QuestionAnswersPhase.READY : QuestionAnswersPhase.EMPTY;
      this.errorMessage = '';
      this.emit();
    } catch (error) {
      if (!this.active || requestGeneration !== this.generation) {
        return;
      }
      this.phase = QuestionAnswersPhase.ERROR;
      this.errorMessage = contentDetailErrorMessage(error);
      this.requiresLogin = contentDetailRequiresLogin(error);
      this.emit();
    }
  }

  snapshot(): QuestionAnswersViewState {
    return {
      phase: this.phase,
      items: this.items.slice(),
      loadingMore: this.loadingMore,
      canLoadMore: this.canLoadMore,
      sortOrder: this.sortOrder,
      errorMessage: this.errorMessage,
      requiresLogin: this.requiresLogin,
      nextCursor: this.nextCursor
    };
  }

  private async loadVisiblePage(cursor?: string): Promise<QuestionAnswerFeedPage> {
    const generation = this.generation;
    let page = await this.repository.loadPage(this.questionId, this.sortOrder, cursor);
    // 被屏蔽/广告占满的一页不是终点；继续到可见回答或真正末页。
    while (this.active && generation === this.generation && page.items.length === 0 &&
      !page.cursor.isEnd && page.cursor.next !== undefined) {
      page = await this.repository.loadPage(this.questionId, this.sortOrder, page.cursor.next);
    }
    return page;
  }

  private emit(): void {
    this.observer(this.snapshot());
  }
}

function feedItemKey(item: ChannelContentItem): string {
  return `${item.feedItem.target.kind}:${item.feedItem.target.id}`;
}
