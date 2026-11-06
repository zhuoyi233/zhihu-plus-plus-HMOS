/**
 * 预加载中心：预取队列（PreloadService）、热榜首屏（HotFeedPending）、
 * 主页双缓冲（HomePendingFeed）与开关落地（applyPreloadOptimization）。
 */

import {
  ChannelFeedPage,
  ChannelFeedRepository,
  ChannelFeedSource,
  CommentItem,
  CommentRepository,
  CommentSortOrder,
  ContentRepository,
  decodePreloadCacheBudget,
  decodePreloadOptimization,
  effectiveSegmentMeta,
  FeedItem,
  FeedPage,
  FeedRepository,
  FeedTargetKind,
  HttpFailure,
  HttpFailureKind,
  PreloadCacheTier,
  preloadAnswerKey,
  preloadArticleKey,
  preloadCache,
  PRELOAD_CACHE_BUDGET_2GB,
  PRELOAD_CACHE_BUDGET_4GB,
  PRELOAD_CACHE_BUDGET_512MB,
  PreloadCacheBudget,
  preloadCommentsKey,
  preloadFeedKey,
  PreloadOptimizationMode,
  SegmentCommentTarget,
  SegmentInfoParagraph
} from 'data';

/** 子评论预热条数上限：根评论首屏里前 N 条有子评论的逐条预热。 */
const CHILD_COMMENT_PREFETCH_LIMIT: number = 20;

/** 进入评论页后「全部评论」预取的最大页数：首屏已在缓存里，这里继续往后翻几页备用。 */
const COMMENT_PAGES_PREFETCH_LIMIT: number = 3;

/** BUSY（同一 client 单飞占位被占）时的重试：退到本档队尾延迟重试，最多 3 次。 */
const BUSY_MAX_RETRIES: number = 3;
const BUSY_RETRY_BASE_DELAY_MS: number = 800;

/**
 * 任务存活上限：主页预取与「回答页的下一个回答」不设上限（`exempt`）；
 * 评论/子评论/段评/翻页给 15s，其余（热榜）5s。到点没跑完就丢弃/中止。
 */
const TASK_DEADLINE_MS: number = 5000;
const COMMENT_TASK_DEADLINE_MS: number = 15000;

/**
 * 任务优先级（数值越小越先执行）。
 *
 * - `URGENT`：用户刚点开、马上要看的（段评、评论页子评论）；
 * - `NORMAL`：回答页逐级预取、评论页全部评论、主页当前显示页的回答；
 * - `HOT_FEED`：热榜首屏，切到热榜前备好即可；
 * - `HOME_PENDING`：最低档；当前无任务使用（主页缓冲的正文改排 NORMAL 队尾）。
 */
export enum PreloadPriority {
  URGENT = 0,
  NORMAL = 1,
  HOT_FEED = 2,
  HOME_PENDING = 3
}

interface PreloadTask {
  readonly kind: string;
  readonly contentType: string;
  readonly contentId: string;
  readonly priority: PreloadPriority;
  /** 段评任务的目标（划线段元信息），重跑时需要原样重建仓库。 */
  readonly segment?: SegmentCommentTarget;
  /** 热榜首屏取回后的落点（由 HotFeedPending 提供）。 */
  readonly onHotPage?: (page: ChannelFeedPage) => void;
  /** BUSY 重试次数（0 表示首次执行）。 */
  attempt: number;
  /** 存活截止时刻（ms）；0 表示不限制（主页预取、回答页的下一答）。 */
  deadlineAt: number;
  /** 超时被中止：不再重试、结果不采纳。 */
  aborted: boolean;
}

function taskKey(task: PreloadTask): string {
  // 段评按「内容 + 划线段」去重：同一回答的不同划线互不相同，避免后点的段评被当成重复任务丢掉。
  const segmentSuffix: string = task.segment === undefined ? '' : `:${task.segment.segmentId}`;
  return `${task.kind}:${task.contentType}:${task.contentId}${segmentSuffix}`;
}

function isBusyFailure(error: Object): boolean {
  return error instanceof HttpFailure && error.kind === HttpFailureKind.BUSY;
}

/**
 * 预取队列：单线程串行。
 *
 * 四档依次执行：URGENT > NORMAL > HOT_FEED > HOME_PENDING；同档后进先出（批内顺序不变）。
 * 主页双缓冲的正文排 NORMAL 队尾（页面本身由 HomePendingFeed 独立请求，不进队列）；
 * 只有关闭「预加载优化」才清空并取消。
 * 任务存活上限：评论/子评论/段评/评论翻页 15s，其余非豁免（热榜）5s；主页预取与
 * 回答页的下一答不设上限。BUSY（client 单飞被占）退到本档队尾重试，最多 3 次。
 */
export class PreloadService {
  private answerRepositoryFactory?: () => ContentRepository | undefined;
  private commentRepositoryFactory?: () => CommentRepository | undefined;
  private segmentRepositoryFactory?: (target: SegmentCommentTarget) => CommentRepository | undefined;
  private hotFeedRepositoryFactory?: () => ChannelFeedRepository | undefined;
  private answerRepository?: ContentRepository;
  private commentRepository?: CommentRepository;
  private segmentRepository?: CommentRepository;
  private hotFeedRepository?: ChannelFeedRepository;
  private readonly queue: Array<PreloadTask> = [];
  private readonly queued: Set<string> = new Set<string>();
  private running: boolean = false;
  /** 正在执行的任务：存活定时器到点时用它判断是否仍是同一个任务。 */
  private current?: PreloadTask;
  private epoch: number = 0;
  private enabled: boolean = false;
  /** 当前钉住窗口（当前答 ±1 的正文与评论），任务完成后据此补钉住。 */
  private pinnedKeys: Array<string> = [];
  /** 正在执行任务的存活定时器；-1 表示未在计时。 */
  private deadlineTimer: number = -1;
  /** 因超过存活上限被丢弃的任务数（仅累计，暂未对外暴露）。 */
  private droppedExpired: number = 0;

  configure(answerRepositoryFactory: () => ContentRepository | undefined,
    commentRepositoryFactory: () => CommentRepository | undefined,
    segmentRepositoryFactory?: (target: SegmentCommentTarget) => CommentRepository | undefined,
    hotFeedRepositoryFactory?: () => ChannelFeedRepository | undefined): void {
    this.answerRepositoryFactory = answerRepositoryFactory;
    this.commentRepositoryFactory = commentRepositoryFactory;
    this.segmentRepositoryFactory = segmentRepositoryFactory;
    this.hotFeedRepositoryFactory = hotFeedRepositoryFactory;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (!enabled) {
      this.cancel();
    }
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  /** 主页当前显示页：只取回答与文章正文；热评随「进入回答后的评论任务」一起取。 */
  prefetchFeedAnswers(items: Array<FeedItem>): void {
    this.enqueueBlock(this.feedAnswerTasks(items, PreloadPriority.NORMAL));
  }

  /**
   * 主页双缓冲那一页：**连同它的回答/文章正文一起预热**。
   * 排在 NORMAL 档队尾（当前页正文优先），保证用户下次下拉前能跑完；
   * 只有「页面本身」可以最低优先级，正文不能跟着垫底，否则永远抢不到执行权。
   */
  prefetchPendingFeedAnswers(items: Array<FeedItem>): void {
    this.enqueueBlock(this.feedAnswerTasks(items, PreloadPriority.NORMAL), false, true);
  }

  /**
   * 打开回答后按批次顺序预取：下一个回答正文 → 当前回答评论（首屏含热评）→ 下一个回答评论。
   * 热评不再单独排队，跟随评论一起取；不预取上一个回答与所属问题。
   * 同时把「当前答 ±1」设为缓存钉住窗口。
   */
  prefetchOnAnswerOpened(previousAnswerId: string | undefined, answerId: string,
    nextAnswerId: string | undefined): void {
    if (!this.enabled || answerId.length === 0) {
      return;
    }
    const hasNext: boolean = nextAnswerId !== undefined && nextAnswerId.length > 0;
    const tasks: Array<PreloadTask> = [];
    if (hasNext) {
      tasks.push(this.task('answerOnly', 'answer', nextAnswerId as string, PreloadPriority.NORMAL, true));
    }
    tasks.push(this.task('comments', 'answer', answerId, PreloadPriority.NORMAL));
    if (hasNext) {
      tasks.push(this.task('comments', 'answer', nextAnswerId as string, PreloadPriority.NORMAL));
    }
    this.pinAnswerWindow(previousAnswerId, answerId, nextAnswerId);
    this.enqueueBlock(tasks);
  }

  /** 评论页：根评论首屏就绪后，把前 N 条有子评论的根评论排进 URGENT（用户可能马上点开）。 */
  prefetchChildCommentsFor(items: Array<CommentItem>): void {
    if (!this.enabled) {
      return;
    }
    const tasks: Array<PreloadTask> = [];
    for (let index = 0; index < items.length && tasks.length < CHILD_COMMENT_PREFETCH_LIMIT; index += 1) {
      if (items[index].childCommentCount > 0) {
        tasks.push(this.task('child', '', items[index].id, PreloadPriority.URGENT));
      }
    }
    this.enqueueBlock(tasks);
  }

  /** 评论页：进入后继续把该内容的后续评论页（热度排序，最多 3 页）排进 NORMAL。 */
  prefetchCommentPages(contentType: string, contentId: string): void {
    if (!this.enabled || contentType.length === 0 || contentId.length === 0) {
      return;
    }
    this.enqueueBlock([this.task('commentPages', contentType, contentId, PreloadPriority.NORMAL)]);
  }

  /** 段评：划线小窗弹出后立刻把**当前这一段**排进 URGENT。 */
  prefetchSegmentComments(paragraph: SegmentInfoParagraph, markIndex: number, contentType: string,
    contentId: string): void {
    if (!this.enabled || contentType.length === 0 || contentId.length === 0) {
      return;
    }
    const mark = paragraph.marks[markIndex];
    if (mark === undefined) {
      return;
    }
    const meta = effectiveSegmentMeta(mark);
    if (meta === undefined || meta.segIds.length === 0) {
      return;
    }
    const target: SegmentCommentTarget = {
      contentType: contentType,
      contentId: contentId,
      segmentId: meta.segIds.join(','),
      segmentContent: paragraph.text.substring(mark.startIndex, mark.endIndex),
      paragraphId: paragraph.pid,
      startOffset: mark.startIndex,
      endOffset: mark.endIndex
    };
    const task: PreloadTask = {
      kind: 'segment',
      contentType: contentType,
      contentId: contentId,
      priority: PreloadPriority.URGENT,
      segment: target,
      attempt: 0,
      deadlineAt: Date.now() + COMMENT_TASK_DEADLINE_MS,
      aborted: false
    };
    this.enqueueBlock([task]);
  }

  /** 热榜首屏：走队列的热榜档，取回后写缓存并交给 HotFeedPending。 */
  prefetchHotFeed(onPage: (page: ChannelFeedPage) => void): void {
    if (!this.enabled) {
      return;
    }
    const task: PreloadTask = {
      kind: 'hotFeed',
      contentType: '',
      contentId: 'hot',
      priority: PreloadPriority.HOT_FEED,
      onHotPage: onPage,
      attempt: 0,
      deadlineAt: Date.now() + TASK_DEADLINE_MS,
      aborted: false
    };
    this.enqueueBlock([task]);
  }

  /** 关闭预加载优化：清空队列并取消在途请求（唯一的“打断”，由用户开关触发）。 */
  cancel(): void {
    this.epoch += 1;
    this.queue.splice(0, this.queue.length);
    this.queued.clear();
    this.pinnedKeys = [];
    this.current = undefined;
    this.clearDeadline();
    this.answerRepository?.cancel();
    this.commentRepository?.cancel();
    this.segmentRepository?.cancel();
    this.hotFeedRepository?.cancel();
  }

  /**
   * @param exempt true 表示不设存活上限（主页预取、回答页的下一答）
   */
  private task(kind: string, contentType: string, contentId: string, priority: PreloadPriority,
    exempt: boolean = false): PreloadTask {
    return {
      kind: kind,
      contentType: contentType,
      contentId: contentId,
      priority: priority,
      attempt: 0,
      deadlineAt: exempt ? 0 : Date.now() + this.deadlineFor(kind),
      aborted: false
    };
  }

  /** 评论/子评论/段评/翻页给 15s，其余非豁免任务 5s。 */
  private deadlineFor(kind: string): number {
    if (kind === 'comments' || kind === 'child' || kind === 'segment' || kind === 'commentPages') {
      return COMMENT_TASK_DEADLINE_MS;
    }
    return TASK_DEADLINE_MS;
  }

  /** 主页一页内容：回答与文章都只拆正文任务（不含热评），一律不设存活上限。 */
  private feedAnswerTasks(items: Array<FeedItem>, priority: PreloadPriority): Array<PreloadTask> {
    const tasks: Array<PreloadTask> = [];
    if (!this.enabled) {
      return tasks;
    }
    for (let index = 0; index < items.length; index += 1) {
      const target = items[index].target;
      if (target.kind === FeedTargetKind.ANSWER) {
        tasks.push(this.task('answerOnly', 'answer', target.id, priority, true));
      } else if (target.kind === FeedTargetKind.ARTICLE) {
        tasks.push(this.task('articleOnly', 'article', target.id, priority, true));
      }
    }
    return tasks;
  }

  /** 钉住窗口：当前答 ±1 的正文与评论；切换回答时整体换窗口，避免钉住集合越用越大。 */
  private pinAnswerWindow(previousId: string | undefined, answerId: string,
    nextId: string | undefined): void {
    const keys: Array<string> = [];
    const ids: Array<string> = [];
    if (previousId !== undefined) {
      ids.push(previousId);
    }
    ids.push(answerId);
    if (nextId !== undefined) {
      ids.push(nextId);
    }
    for (let index = 0; index < ids.length; index += 1) {
      keys.push(preloadAnswerKey(ids[index]));
      keys.push(preloadCommentsKey('answer', ids[index]));
    }
    this.pinnedKeys = keys;
    preloadCache().repin(keys);
  }

  /** 入队一个批次：同档 LIFO；传 toBackOfTier 时插到本档队尾；同键任务用新的替换旧的。 */
  private enqueueBlock(tasks: Array<PreloadTask>, urgent: boolean = false,
    toBackOfTier: boolean = false): void {
    if (tasks.length === 0) {
      return;
    }
    const accepted: Array<PreloadTask> = [];
    const seen: Set<string> = new Set<string>();
    for (let index = 0; index < tasks.length; index += 1) {
      const task: PreloadTask = tasks[index];
      const key: string = taskKey(task);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      this.removeQueued(key);
      this.queued.add(key);
      accepted.push(task);
    }
    if (accepted.length === 0) {
      return;
    }
    const priority: PreloadPriority = accepted[0].priority;
    if (urgent) {
      for (let index = accepted.length - 1; index >= 0; index -= 1) {
        this.queue.unshift(accepted[index]);
      }
    } else if (toBackOfTier) {
      // 插到本档（含更高档）之后：当前页任务先跑，这批随后跟上，但不会被后续批次永久压住。
      let insertAt = 0;
      while (insertAt < this.queue.length && this.queue[insertAt].priority <= priority) {
        insertAt += 1;
      }
      for (let index = 0; index < accepted.length; index += 1) {
        this.queue.splice(insertAt + index, 0, accepted[index]);
      }
    } else {
      let insertAt = 0;
      while (insertAt < this.queue.length && this.queue[insertAt].priority < priority) {
        insertAt += 1;
      }
      for (let index = 0; index < accepted.length; index += 1) {
        this.queue.splice(insertAt + index, 0, accepted[index]);
      }
    }
    this.pump();
  }

  /** BUSY 重试：退到本档队尾（不抢新请求的位置），延迟后重新入队。 */
  private scheduleBusyRetry(task: PreloadTask): void {
    if (task.aborted || task.attempt >= BUSY_MAX_RETRIES) {
      return;
    }
    if (task.deadlineAt > 0 && Date.now() >= task.deadlineAt) {
      this.droppedExpired += 1;
      return;
    }
    task.attempt += 1;
    const delay: number = BUSY_RETRY_BASE_DELAY_MS * task.attempt;
    setTimeout((): void => {
      if (!this.enabled || task.aborted) {
        return;
      }
      const key: string = taskKey(task);
      if (this.queued.has(key)) {
        return;
      }
      this.queued.add(key);
      let insertAt = this.queue.length;
      while (insertAt > 0 && this.queue[insertAt - 1].priority > task.priority) {
        insertAt -= 1;
      }
      this.queue.splice(insertAt, 0, task);
      this.pump();
    }, delay);
  }

  /** 给正在执行的任务装上存活定时器：到点仍未结束就中止（取消在途请求，不再重试）。 */
  private armDeadline(task: PreloadTask): void {
    this.clearDeadline();
    if (task.deadlineAt <= 0) {
      return;
    }
    const delay: number = Math.max(0, task.deadlineAt - Date.now());
    this.deadlineTimer = setTimeout((): void => {
      this.deadlineTimer = -1;
      if (this.current !== task || task.aborted) {
        return;
      }
      task.aborted = true;
      this.droppedExpired += 1;
      this.cancelInFlight();
    }, delay);
  }

  private clearDeadline(): void {
    if (this.deadlineTimer >= 0) {
      clearTimeout(this.deadlineTimer);
      this.deadlineTimer = -1;
    }
  }

  private cancelInFlight(): void {
    this.answerRepository?.cancel();
    this.commentRepository?.cancel();
    this.segmentRepository?.cancel();
    this.hotFeedRepository?.cancel();
  }

  private removeQueued(key: string): void {
    if (!this.queued.has(key)) {
      return;
    }
    for (let index = 0; index < this.queue.length; index += 1) {
      if (taskKey(this.queue[index]) === key) {
        this.queue.splice(index, 1);
        break;
      }
    }
    this.queued.delete(key);
  }

  private pump(): void {
    if (this.running || !this.enabled || this.queue.length === 0) {
      return;
    }
    this.running = true;
    void this.drain(this.epoch);
  }

  private async drain(epoch: number): Promise<void> {
    while (this.enabled && epoch === this.epoch) {
      const task = this.queue.shift();
      if (task === undefined) {
        break;
      }
      this.queued.delete(taskKey(task));
      // 排队期间已超时的任务直接丢弃，不再浪费一次请求。
      if (task.deadlineAt > 0 && Date.now() >= task.deadlineAt) {
        this.droppedExpired += 1;
        continue;
      }
      this.current = task;
      this.armDeadline(task);
      try {
        await this.run(task);
      } catch (error) {
        // 超时被中止的任务不再重试；BUSY 退到本档队尾延迟重试；其他失败静默忽略。
        if (!task.aborted && error instanceof Object && isBusyFailure(error as Object)) {
          this.scheduleBusyRetry(task);
        }
      } finally {
        this.clearDeadline();
      }
      if (this.current === task) {
        this.current = undefined;
      }
    }
    this.running = false;
    if (this.enabled && epoch === this.epoch && this.queue.length > 0) {
      this.pump();
    }
  }

  private async run(task: PreloadTask): Promise<void> {
    if (task.kind === 'segment') {
      await this.runSegment(task);
      return;
    }
    if (task.kind === 'hotFeed') {
      await this.runHotFeed(task);
      return;
    }
    if (task.kind === 'commentPages') {
      // 用独立仓库实例翻页：避免与常规首屏预取共享游标状态。
      const repository = this.commentRepositoryFactory?.();
      if (repository === undefined) {
        return;
      }
      await this.loadCommentPages(repository, task.contentType, task.contentId);
      return;
    }
    if (task.kind === 'answerOnly' || task.kind === 'articleOnly') {
      const content = this.answerRepository ?? this.answerRepositoryFactory?.();
      if (content === undefined) {
        return;
      }
      this.answerRepository = content;
      if (task.kind === 'answerOnly') {
        await content.getAnswer(task.contentId);
        this.pinIfInWindow(preloadAnswerKey(task.contentId));
      } else {
        await content.getArticle(task.contentId);
        this.pinIfInWindow(preloadArticleKey(task.contentId));
      }
      return;
    }
    const comments = this.commentRepository ?? this.commentRepositoryFactory?.();
    if (comments === undefined) {
      return;
    }
    this.commentRepository = comments;
    if (task.kind === 'comments') {
      await comments.getRootCommentsPage(task.contentType, task.contentId, CommentSortOrder.SCORE);
      this.pinIfInWindow(preloadCommentsKey(task.contentType, task.contentId));
      return;
    }
    if (task.kind === 'child') {
      await comments.getChildCommentsPage(task.contentId);
    }
  }

  /** 只有落在当前钉住窗口里的条目才升级为 PINNED（home 预取等不再无差别钉住）。 */
  private pinIfInWindow(key: string): void {
    for (let index = 0; index < this.pinnedKeys.length; index += 1) {
      if (this.pinnedKeys[index] === key) {
        preloadCache().promote(key);
        return;
      }
    }
  }

  /** 段评：按划线段元信息现建仓库（带登录态），取一次热度排序首屏。 */
  private async runSegment(task: PreloadTask): Promise<void> {
    const target: SegmentCommentTarget | undefined = task.segment;
    const factory = this.segmentRepositoryFactory;
    if (target === undefined || factory === undefined) {
      return;
    }
    const repository = factory(target);
    this.segmentRepository = repository;
    if (repository === undefined) {
      return;
    }
    await repository.getRootCommentsPage(task.contentType, task.contentId, CommentSortOrder.SCORE);
  }

  /** 热榜首屏：取回后写 feed:hot 缓存并交给 HotFeedPending（是否生效由它判断）。 */
  private async runHotFeed(task: PreloadTask): Promise<void> {
    const factory = this.hotFeedRepositoryFactory;
    if (factory === undefined) {
      return;
    }
    const repository = this.hotFeedRepository ?? factory();
    this.hotFeedRepository = repository;
    if (repository === undefined) {
      return;
    }
    const page: ChannelFeedPage = await repository.loadPage(ChannelFeedSource.HOT);
    preloadCache().put(preloadFeedKey('hot'), JSON.stringify(page), PreloadCacheTier.FEED);
    task.onHotPage?.(page);
  }

  /** 顺着游标把后续评论页取回（仓库按游标写入缓存，评论页翻到时直接命中）。 */
  private async loadCommentPages(repository: CommentRepository, contentType: string,
    contentId: string): Promise<void> {
    const first = await repository.getRootCommentsPage(contentType, contentId, CommentSortOrder.SCORE);
    let cursor: string | undefined = first.cursor.next;
    for (let page = 1; page < COMMENT_PAGES_PREFETCH_LIMIT && cursor !== undefined && cursor.length > 0;
      page += 1) {
      const next = await repository.getRootCommentsPage(contentType, contentId, CommentSortOrder.SCORE, cursor);
      cursor = next.cursor.next;
    }
  }


}

const SHARED_SERVICE: PreloadService = new PreloadService();

export function preloadService(): PreloadService {
  return SHARED_SERVICE;
}


/** 热榜首屏：请求走队列的 HOT_FEED 档，这里只持有「已取回但未生效」的一份（10 分钟新鲜度）。 */
export const HOT_PENDING_TTL_MS: number = 10 * 60 * 1000;

export class HotFeedPending {
  private pending?: ChannelFeedPage = undefined;
  private pendingAtMs: number = 0;

  /** 排队预取热榜首屏（单飞：队列里已有同键任务时不会重复）。 */
  prefetch(): void {
    if (!preloadCache().isEnabled()) {
      return;
    }
    preloadService().prefetchHotFeed((page: ChannelFeedPage): void => {
      this.pending = page;
      this.pendingAtMs = Date.now();
    });
  }

  /** 切到热榜：有新鲜 pending 时返回 true（表示"本次可以直接生效"），并立刻重置+重取。 */
  consumeForDisplay(): boolean {
    if (this.pending === undefined) {
      return false;
    }
    const fresh = Date.now() - this.pendingAtMs <= HOT_PENDING_TTL_MS;
    this.pending = undefined;
    this.pendingAtMs = 0;
    this.prefetch();
    return fresh;
  }

  reset(): void {
    this.pending = undefined;
    this.pendingAtMs = 0;
    preloadCache().invalidate(preloadFeedKey('hot'));
  }
}

const SHARED: HotFeedPending = new HotFeedPending();

export function hotFeedPending(): HotFeedPending {
  return SHARED;
}


/** 双缓冲预取页的新鲜度上限（ms）：超时视为过期，下拉时退回控制器自身刷新。 */
const PENDING_PAGE_TTL_MS: number = 10 * 60 * 1000;

/** 小页阈值：pending 条目明显少于当前列表时不予提交（避免界面先只剩一条再被替换）。 */
const PENDING_MIN_ITEMS: number = 3;

/**
 * 首页双缓冲预取页：用独立 FeedRepository（不共享游标与 cancel）提前取下一页，
 * 下拉时直接提交；只写内部字段，不改变当前显示内容。
 */
export class HomePendingFeed {
  private pending?: FeedPage;
  private pendingAtMs: number = 0;
  private loading: boolean = false;
  private repository?: FeedRepository;

  /** 预取一页：已有新鲜 pending 或正在请求时跳过。 */
  prefetch(factory: () => FeedRepository | undefined, enabled: boolean,
    onReady: (page: FeedPage) => void = (_page: FeedPage): void => {
    }): void {
    if (!enabled || this.loading) {
      return;
    }
    if (this.pending !== undefined && Date.now() - this.pendingAtMs <= PENDING_PAGE_TTL_MS) {
      return;
    }
    if (this.repository === undefined) {
      this.repository = factory();
    }
    const repository: FeedRepository | undefined = this.repository;
    if (repository === undefined) {
      return;
    }
    this.loading = true;
    repository.loadHomePage().then((page: FeedPage): void => {
      this.pending = page;
      this.pendingAtMs = Date.now();
      // 新一页已在内存里但还没显示：立刻把它包含的回答/文章正文排进预取队列，
      // 用户下拉提交后点开任意一条都不用等（调用方决定优先级）。
      onReady(page);
    }).catch((_error: Error): void => {
      // 预取失败静默忽略：真正下拉时回落到控制器自身刷新。
    }).finally((): void => {
      this.loading = false;
    });
  }

  /** 丢弃 pending（提交后或过期时调用）。 */
  clear(): void {
    this.pending = undefined;
    this.pendingAtMs = 0;
  }

  /** 取走可提交的 pending：过期或明显小于当前列表时返回 undefined（走原刷新）。 */
  take(currentItemCount: number): FeedPage | undefined {
    const page: FeedPage | undefined = this.pending;
    if (page === undefined) {
      return undefined;
    }
    if (Date.now() - this.pendingAtMs > PENDING_PAGE_TTL_MS) {
      this.clear();
      return undefined;
    }
    if (page.items.length < PENDING_MIN_ITEMS && page.items.length < currentItemCount) {
      this.clear();
      return undefined;
    }
    this.clear();
    return page;
  }
}


/** 开关落地：开启即启用缓存与队列并后台预取热榜；关闭即清空并回到原有加载。只改内存状态。 */
export function applyPreloadOptimization(mode: string): void {
  const enabled: boolean = decodePreloadOptimization(mode) === PreloadOptimizationMode.ON;
  preloadCache().setEnabled(enabled);
  preloadService().setEnabled(enabled);
  if (enabled) {
    hotFeedPending().prefetch();
  } else {
    hotFeedPending().reset();
  }
}

/** 切到热榜时调用：pending「生效一次」并重新预取；返回是否新鲜。 */
export function consumeHotFeedPending(): boolean {
  return hotFeedPending().consumeForDisplay();
}

/** 缓存预算落地：512MB / 2GB / 4GB 三档，切换后立即按新配额回收。 */
export function applyPreloadCacheBudget(raw: string): void {
  const budget: PreloadCacheBudget = decodePreloadCacheBudget(raw);
  if (budget === PreloadCacheBudget.LARGE) {
    preloadCache().setQuota(PRELOAD_CACHE_BUDGET_4GB);
    return;
  }
  if (budget === PreloadCacheBudget.MEDIUM) {
    preloadCache().setQuota(PRELOAD_CACHE_BUDGET_2GB);
    return;
  }
  preloadCache().setQuota(PRELOAD_CACHE_BUDGET_512MB);
}

