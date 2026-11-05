/**
 * 预加载中心（本轮新增的唯一预加载实现文件）。
 *
 * 包含四部分：
 * 1. PreloadService：预取队列（四档优先级、同档后进先出、任务互不打断、BUSY 重试）；
 * 2. HotFeedPending：热榜首屏「已取回但未生效」的那一份；
 * 3. HomePendingFeed：主页双缓冲的待提交页；
 * 4. applyPreloadOptimization / consumeHotFeedPending：开关落地与切热榜时的一次性生效。
 */

import {
  ChannelFeedPage,
  ChannelFeedRepository,
  ChannelFeedSource,
  CommentItem,
  CommentRepository,
  CommentSortOrder,
  ContentRepository,
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
  preloadCache,
  preloadCommentsKey,
  preloadFeedKey,
  PreloadOptimizationMode,
  preloadSegmentCommentsKey,
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
 * 任务优先级（数值越小越先执行）。
 *
 * - `URGENT`：用户刚点开、马上要看的（段评、评论页子评论）；
 * - `NORMAL`：回答页逐级预取、评论页全部评论、主页当前显示页的回答；
 * - `HOT_FEED`：热榜首屏，切到热榜前备好即可；
 * - `HOME_PENDING`：主页双缓冲那一页（还没显示），永远排在整条队列最后。
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
 * 「预加载优化」的预取队列：单线程串行执行，**任务之间互不打断**。
 *
 * 排序规则：
 * - 四个优先级档依次执行：URGENT > NORMAL > HOT_FEED > HOME_PENDING；
 * - 同一档内**后进先出**（最新入队的批次先跑）；一个批次内部的顺序保持不变
 *   （例如回答页固定「热评 → 下一个回答 → 当前回答评论 → 下一个回答评论」）；
 * - 主页缓冲（还没显示的那一页）无论何时入队都追加到**整条队列最后**；
 * - 已经在跑的任务不会被打断，也不取消请求；只有关闭「预加载优化」才整体清空并取消；
 * - BUSY（client 单飞被占）不是真失败：退到本档队尾延迟重试，最多 3 次。
 *
 * 缓存读写由仓库层完成（命中即返回、未命中回填），这里只负责顺序与重试。
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
  private epoch: number = 0;
  private enabled: boolean = false;

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

  /**
   * 主页当前显示页：把这一页回答的正文与热评排进 NORMAL（最新一批最优先）。
   * 冷启动从快照直出后也走这里。
   */
  prefetchFeedAnswers(items: Array<FeedItem>): void {
    this.enqueueBlock(this.feedAnswerTasks(items, PreloadPriority.NORMAL));
  }

  /**
   * 主页双缓冲：还没显示的那一页，回答正文与热评全部排进 HOME_PENDING（整条队列最后）。
   * 用户下拉提交后这一页成为可见内容时，这批请求通常已经跑完。
   */
  prefetchPendingFeedAnswers(items: Array<FeedItem>): void {
    this.enqueueBlock(this.feedAnswerTasks(items, PreloadPriority.HOME_PENDING));
  }

  /**
   * 打开回答后的预取顺序（批次内部顺序，不会被 LIFO 打乱）：
   * 1. 当前回答热评（首屏，同时也填了评论页首屏）；
   * 2. 下一个回答正文；
   * 3. 当前回答评论（此时已在缓存里，直接命中，不再发请求）；
   * 4. 下一个回答的评论首屏。
   *
   * 不预取上一个回答与所属问题：上一个回答靠缓存回溯（未命中时由页面按需加载）。
   */
  prefetchOnAnswerOpened(answerId: string, nextAnswerId: string | undefined): void {
    if (!this.enabled || answerId.length === 0) {
      return;
    }
    const hasNext: boolean = nextAnswerId !== undefined && nextAnswerId.length > 0;
    const tasks: Array<PreloadTask> = [
      this.task('hot', 'answer', answerId, PreloadPriority.NORMAL)
    ];
    if (hasNext) {
      tasks.push(this.task('answerOnly', 'answer', nextAnswerId as string, PreloadPriority.NORMAL));
    }
    tasks.push(this.task('comments', 'answer', answerId, PreloadPriority.NORMAL));
    if (hasNext) {
      tasks.push(this.task('comments', 'answer', nextAnswerId as string, PreloadPriority.NORMAL));
    }
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
      attempt: 0
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
      attempt: 0
    };
    this.enqueueBlock([task]);
  }

  /** 关闭预加载优化：清空队列并取消在途请求（唯一的“打断”，由用户开关触发）。 */
  cancel(): void {
    this.epoch += 1;
    this.queue.splice(0, this.queue.length);
    this.queued.clear();
    this.answerRepository?.cancel();
    this.commentRepository?.cancel();
    this.segmentRepository?.cancel();
    this.hotFeedRepository?.cancel();
  }

  private task(kind: string, contentType: string, contentId: string, priority: PreloadPriority): PreloadTask {
    return { kind: kind, contentType: contentType, contentId: contentId, priority: priority, attempt: 0 };
  }

  /** 把一页回答拆成任务：正文 + 热评一起（冷启动也可以只取正文，由调用方决定）。 */
  private feedAnswerTasks(items: Array<FeedItem>, priority: PreloadPriority): Array<PreloadTask> {
    const tasks: Array<PreloadTask> = [];
    if (!this.enabled) {
      return tasks;
    }
    for (let index = 0; index < items.length; index += 1) {
      const target = items[index].target;
      if (target.kind !== FeedTargetKind.ANSWER) {
        continue;
      }
      tasks.push(this.task('answer', 'answer', target.id, priority));
    }
    return tasks;
  }

  /**
   * 入队一个批次（批内顺序保持不变）。
   *
   * - 同档 LIFO：插在同一档已有任务之前；
   * - `HOME_PENDING`：追加到整条队列最后（它只在用户真正下拉前后才有价值）；
   * - 同一内容已在队列里：用新任务替换旧任务（相当于“这次要看的是最新那次请求”）。
   */
  private enqueueBlock(tasks: Array<PreloadTask>): void {
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
    if (priority === PreloadPriority.HOME_PENDING) {
      for (let index = 0; index < accepted.length; index += 1) {
        this.queue.push(accepted[index]);
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
    if (task.attempt >= BUSY_MAX_RETRIES) {
      return;
    }
    task.attempt += 1;
    const delay: number = BUSY_RETRY_BASE_DELAY_MS * task.attempt;
    setTimeout((): void => {
      if (!this.enabled) {
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
      try {
        await this.run(task);
      } catch (error) {
        // BUSY 是“另一个请求正占着同一个 client”，退到本档队尾延迟重试；其他失败静默忽略。
        if (error instanceof Object && isBusyFailure(error as Object)) {
          this.scheduleBusyRetry(task);
        }
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
    if (task.kind === 'answer' || task.kind === 'answerOnly') {
      const answers = this.answerRepository ?? this.answerRepositoryFactory?.();
      if (answers !== undefined) {
        this.answerRepository = answers;
        await answers.getAnswer(task.contentId);
      }
      // 正文钉住：上下切答、返回后仍常驻，不被主队列 LRU 挤掉。
      preloadCache().promote(preloadAnswerKey(task.contentId), PreloadCacheTier.PINNED);
      if (task.kind === 'answerOnly') {
        return;
      }
      await this.loadHotComments(task.contentType, task.contentId);
      return;
    }
    if (task.kind === 'hot') {
      await this.loadHotComments(task.contentType, task.contentId);
      return;
    }
    const comments = this.commentRepository ?? this.commentRepositoryFactory?.();
    if (comments === undefined) {
      return;
    }
    this.commentRepository = comments;
    if (task.kind === 'comments') {
      await comments.getRootCommentsPage(task.contentType, task.contentId, CommentSortOrder.SCORE);
      preloadCache().promote(preloadCommentsKey(task.contentType, task.contentId), PreloadCacheTier.PINNED);
      return;
    }
    if (task.kind === 'child') {
      await comments.getChildCommentsPage(task.contentId);
    }
  }

  /** 段评：按划线段元信息现建仓库（带登录态），取一次热度排序首屏并钉住。 */
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
    preloadCache().promote(preloadSegmentCommentsKey(target.contentId, target.segmentId),
      PreloadCacheTier.PINNED);
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

  /** 取一次热度排序的根评论首屏（热评区与评论页首屏共用同一份缓存）并钉住。 */
  private async loadHotComments(contentType: string, contentId: string): Promise<void> {
    const comments = this.commentRepository ?? this.commentRepositoryFactory?.();
    if (comments === undefined) {
      return;
    }
    this.commentRepository = comments;
    await comments.getRootCommentsPage(contentType, contentId, CommentSortOrder.SCORE);
    preloadCache().promote(preloadCommentsKey(contentType, contentId), PreloadCacheTier.PINNED);
  }
}

const SHARED_SERVICE: PreloadService = new PreloadService();

export function preloadService(): PreloadService {
  return SHARED_SERVICE;
}


/**
 * 热榜首屏预取（「预加载优化」开启时生效）。
 *
 * 规则：
 * - 启动进入主页后，把「取热榜首屏」排进预取队列的热榜档（不改变当前界面）；
 * - 之后只在「应用回到前台」或「切换到热榜页」时更新；
 * - 切到热榜时若 pending 新鲜（10 分钟）则直接生效（首屏零等待），生效后立即重置并重新预取；
 * - 在 app 内切到其他页再切回热榜同样走"生效一次 + 重新预取"，不会反复使用同一份旧数据。
 *
 * 真正的网络请求走 PreloadService 的队列（后进先出、不打断其它预取），这里只持有
 * 「已取回但还没生效」的那一份，以及它落进 PreloadCache 的 `feed:hot` 副本。
 */
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
 * 首页「双缓冲」预取页。
 *
 * 与页面控制器完全隔离：用独立的 FeedRepository（不共享游标与 cancel 状态）提前把下一页
 * 首页结果拿在手里，用户下拉刷新时直接提交，零等待。预取只写内部字段，不改变当前显示的
 * 内容——不生效、不回滚，规则简单到不会和下拉手势抢状态。
 */
export class HomePendingFeed {
  private pending?: FeedPage;
  private pendingAtMs: number = 0;
  private loading: boolean = false;
  private repository?: FeedRepository;

  /**
   * 预取一页：已有新鲜 pending 或正在请求时直接跳过（挂载、点页签都会调用）。
   *
   * @param factory 独立仓库工厂，与控制器用的仓库隔离
   * @param enabled 预加载优化是否开启；关闭时完全不发请求
   */
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
      // 新一页已在内存里但还没显示：立刻把它包含的回答与热评排进预取队列，
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

  /**
   * 取走可提交的 pending：过期、或明显小于当前列表时返回 undefined（调用方走原刷新）。
   * 成功取走即清空，调用方随后应再预取一次。
   */
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


/**
 * 「预加载优化」开关落地：把设置里的两态开关同步到缓存与调度器。
 *
 * - 开启：启用统一内存缓存与逐级预加载，并立刻在后台预取热榜首屏（不改变当前界面）；
 * - 关闭：两层缓存全部清空、调度器停止，完全回到项目原有的按需加载。
 *
 * 只改内存状态，不写偏好；偏好由设置页负责持久化，这里在启动与开关变化时各调用一次。
 */
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

/**
 * 页签切到热榜时调用：把预取的热榜首屏「生效一次」并立刻重新预取。
 * 返回 true 表示这份 pending 还新鲜（页面重载即可命中缓存，首屏零等待）。
 */
export function consumeHotFeedPending(): boolean {
  return hotFeedPending().consumeForDisplay();
}

