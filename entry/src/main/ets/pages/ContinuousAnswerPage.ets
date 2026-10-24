import { pasteboard } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { AppDestination, AppDestinationName, resolveZhihuLink, toAppDestination } from 'core';
import {
  Answer,
  AnswerDoubleTapAction,
  AppPreferencesStore,
  ChannelContentItem,
  CollectionRepository,
  ContentDetailKind,
  ContentRepository,
  ContentVoteState,
  ContentVoteResult,
  createReaderPositionStore,
  DEFAULT_THEME_COLOR,
  effectiveSegmentMeta,
  FollowRepository,
  LinkCardMeta,
  LinkCardMetaRepository,
  LoginSessionGateway,
  onThemeColor,
  OpenedContentStore,
  Question,
  QuestionAnswerFeedRepository,
  ReadHistoryUploadRepository,
  ReaderPosition,
  ReaderPositionRepository,
  readerPositionKey,
  SegmentInfoMark,
  SegmentInfoMeta,
  SegmentInfoParagraph,
  SegmentReactionRepository,
  UserProfile,
  VoteRepository
} from 'data';
import {
  clearFormulaByteCache,
  parseZhihuHtml,
  ReaderBlock,
  ReaderBlockKind,
  ReaderInlineRun
} from 'reader';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { createSystemShareService } from '../platform/SystemShareService';
import { performConfirmHaptic } from '../platform/HapticFeedback';
import { ShareOutcome, SharePayloadKind, ShareTextPayload } from '../platform/ShareContracts';
import { CollectionDialogComponent } from './CollectionDialogComponent';
import { mergeSameRangeMarks } from './ContentAnnotations';
import { LinkCardMetaLoader, ReaderBlockView } from './ReaderBlockView';
import { SegmentPill } from './components/SegmentPill';
import { contentDetailErrorMessage, LoadedContentDetail, recordContentOpen } from './ContentDetailState';
import { formatContentDateTime } from './ContentDetailPages';
import {
  readerBlockSignature,
  readerPositionBlockIndex,
  readerPositionFraction,
  readerPositionTargetY
} from './ReaderPositionAnchor';
import { readerBlockSpacing } from './ReaderTypography';
import { ContinuousFullTextRecord, ContinuousFullTextScheduler, ContinuousFullTextSource } from './ContinuousAnswerState';
import { QuestionAnswersController, QuestionAnswersPhase, QuestionAnswersViewState } from './QuestionAnswersState';
import { QuestionAnswerSortOrder } from 'data';
import {
  ContinuousRow,
  ContinuousRowKind,
  ContinuousStreamDataSource,
  continuousActionsRow,
  continuousBlockRows,
  continuousDateRow,
  continuousDividerRow,
  continuousErrorBodyRow,
  continuousHeaderRow,
  continuousHeaderRowKey,
  continuousLoadingBodyRow,
  continuousReleasedBodyRow,
  continuousStreamEndRow
} from './ContinuousStreamDataSource';

/** 活动回答判定滞回（vp）与参考线（复用 P0 原型实测初值）。 */
const ACTIVE_ANSWER_HYSTERESIS_VP = 120;
const ACTIVE_REFERENCE_FRACTION = 1 / 3;
const ANCHOR_RESTORE_MAX_ATTEMPTS = 10;
/** 列表顶部让位（vp，与 List padding top 一致）：位置捕获/恢复的阅读线。 */
const CONTINUOUS_TOP_INSET_VP = 116;
/** 停留确认时长（ms，计划 §4.4 初值）：进入有效视口后短暂停留才写历史。 */
const DWELL_CONFIRM_MS = 800;
/** 种子不在首批时的额外搜索页数上限（计划 §2.2：不无限翻页寻找目标）。 */
const SEED_SEARCH_EXTRA_PAGES = 2;

interface AnswerVoteSnapshot {
  voteState?: ContentVoteState;
  voteupCount: number;
  commentCount: number;
}

interface AuthorInfo {
  id: string;
  name: string;
  urlToken: string;
  headline: string;
  avatarUrl: string;
  isFollowing: boolean;
}

function authorOfSummary(item: ChannelContentItem): AuthorInfo {
  const author: UserProfile | undefined = item.feedItem.target.author;
  return {
    id: author?.id ?? '',
    name: author?.name ?? '知乎用户',
    urlToken: author?.urlToken ?? '',
    headline: author?.headline ?? '',
    avatarUrl: author?.avatarUrl ?? '',
    isFollowing: author?.isFollowing ?? false
  };
}

function authorOfAnswer(answer: Answer): AuthorInfo {
  const author: UserProfile | undefined = answer.author;
  return {
    id: author?.id ?? '',
    name: author?.name ?? '知乎用户',
    urlToken: author?.urlToken ?? '',
    headline: author?.headline ?? '',
    avatarUrl: author?.avatarUrl ?? '',
    isFollowing: author?.isFollowing ?? false
  };
}

function formatVoteCount(value: number): string {
  if (value >= 10000) {
    const tenThousands = Math.floor(value / 1000) / 10;
    return `${tenThousands} 万`;
  }
  return `${value}`;
}

function answerDateLine(answer: Answer): string {
  const parts: Array<string> = [];
  const created = formatContentDateTime(answer.createdAt);
  if (created.length > 0) {
    parts.push(`发布于 ${created}`);
  }
  const updated = formatContentDateTime(answer.updatedAt);
  if (updated.length > 0 && updated !== created) {
    parts.push(`编辑于 ${updated}`);
  }
  if (answer.ipInfo !== undefined && answer.ipInfo.length > 0) {
    parts.push(`IP 属地 ${answer.ipInfo}`);
  }
  return parts.join(' · ');
}

/** 生产正文来源：包装独立 ContentRepository 实例（每个槽位独立 HTTP client）。 */
class RepositoryFullTextSource implements ContinuousFullTextSource {
  private readonly repository: ContentRepository;

  constructor(repository: ContentRepository) {
    this.repository = repository;
  }

  getAnswer(answerId: string): Promise<Answer> {
    return this.repository.getAnswer(answerId);
  }
}

/**
 * 连续阅读页（P3，docs/continuous-answer-reading-plan.md）：同一问题的真实回答连续滚动。
 * 顺序与摘要来自 QuestionAnswersController（独立分页仓库实例）；逐答全文由
 * ContinuousFullTextScheduler（两个独立 ContentRepository 槽位）调度；逐答投票/关注/
 * 收藏复用既有仓库，评论经路由跳转。渲染沿用 P0 验证的单 List 展平 + 锚点补偿 + 淘汰结构。
 */
@Component
export struct ContinuousAnswerPage {
  questionId: string = '';
  seedAnswerId: string = '';
  /** 问题页继承的排序（'default' | 'updated'，计划 §2.2）。 */
  sortOrder: string = 'default';
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {};
  onBack: () => void = (): void => {};
  feedRepository: QuestionAnswerFeedRepository | undefined = undefined;
  questionRepository: ContentRepository | undefined = undefined;
  fullTextRepositoryA: ContentRepository | undefined = undefined;
  fullTextRepositoryB: ContentRepository | undefined = undefined;
  voteRepository: VoteRepository | undefined = undefined;
  followRepository: FollowRepository | undefined = undefined;
  collectionRepository: CollectionRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  /** 阅读记录（本地 upsert + 云端上报）：停留确认后写入（计划 §4.4），预取不写。 */
  openedContentStore: OpenedContentStore | undefined = undefined;
  historyUploader: ReadHistoryUploadRepository | undefined = undefined;
  /** 他人划线点赞/评论仓库（连续页专属实例，避免与详情页共用单飞 client 互斥）。 */
  segmentReactionRepository: SegmentReactionRepository | undefined = undefined;
  /** 推荐阅读卡片元数据仓库（连续页专属实例）：串行拉取站内赞同/评论计数。 */
  linkCardMetaRepository: LinkCardMetaRepository | undefined = undefined;

  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('contentBlockSpacing') private blockSpacingPercent: number = 100;
  @StorageProp('contentTypographyPreset') private typographyPreset: string = 'comfortable';
  @StorageProp('imagePreviewUrl') @Watch('onImagePreviewChanged') private imagePreviewUrl: string = '';
  /** 沉浸阅读（与回答/文章页共用全局广播）：隐藏顶栏，返回键先退出沉浸。 */
  @StorageProp('detailImmersiveActive') private detailImmersiveActive: boolean = false;
  @StorageProp('detailImmersiveExitTick') @Watch('onImmersiveExitTick') private immersiveExitTick: number = 0;
  /** 路由可见性（AppShell onShown/onHidden 广播）：离页停止预取与分页，回页恢复。 */
  @StorageProp('continuousAnswerRouteVisible') @Watch('onRouteVisibleChanged') private routeVisible: boolean = true;

  private readonly dataSource: ContinuousStreamDataSource = new ContinuousStreamDataSource();
  private readonly scroller: Scroller = new Scroller();
  private feedController?: QuestionAnswersController;
  private scheduler?: ContinuousFullTextScheduler;

  private readonly summaries: Map<string, ChannelContentItem> = new Map();
  private readonly votes: Map<string, AnswerVoteSnapshot> = new Map();
  private readonly followStates: Map<string, boolean> = new Map();
  private readonly referenceRowKeys: Map<string, Map<number, string>> = new Map();
  private readonly referenceReturnOffsets: Map<string, number> = new Map();
  private readonly measuredRowHeightVp: Map<string, number> = new Map();
  private readonly measuredBodyHeightVp: Map<string, number> = new Map();
  private readonly materializedPhase: Map<string, string> = new Map();
  private readonly failedAvatarIds: Set<string> = new Set();
  /** 已确认阅读的回答（每次会话按回答去重，计划 §4.4）。 */
  private readonly recordedAnswers: Set<string> = new Set();
  /** 已物化回答的正文块（作用域 id），供逐答位置捕获与脚注定位。 */
  private readonly answerBlocks: Map<string, Array<ReaderBlock>> = new Map();
  private positionStore?: ReaderPositionRepository = undefined;
  private dwellTimer: number = -1;
  private dwellAnswerId: string = '';
  private seedRestored: boolean = false;

  private streamIds: Array<string> = [];
  private streamBuilt: boolean = false;
  private seedSearchPages: number = 0;
  private activeAnswerIndex: number = -1;
  private anchorKey: string = '';
  private anchorFraction: number = 0;
  private restoreTimer: number = -1;
  private restoreAttempt: number = 0;
  private firstVisibleIndex: number = 0;
  private lastVisibleIndex: number = 0;
  private viewportHeightVp: number = 0;
  private disposed: boolean = false;

  @State private statusLine: string = '正在加载回答列表…';
  @State private collectionAnswerId: string = '';
  @State private feedErrorLine: string = '';
  /** 双击动作偏好（单篇详情页同款 AppStorage 广播；aboutToAppear 从持久化恢复）。 */
  @StorageProp('answerDoubleTapAction') private answerDoubleTapAction: AnswerDoubleTapAction =
    AnswerDoubleTapAction.ASK;
  /** 推荐阅读卡片站内元数据（url → meta）：串行拉取后回填并强制对应卡片行重建。 */
  @State private linkCardMetas: Map<string, LinkCardMeta> = new Map();
  private linkCardMetaLoader?: LinkCardMetaLoader = undefined;
  /** 逐答他人划线（已合并同区间 mark）：按回答缓存，供划线叠加与面板读取。 */
  private readonly segmentInfosCache: Map<string, SegmentInfoParagraph[]> = new Map();
  @State private segmentSheetShown: boolean = false;
  @State private segmentSheetAnswerId: string = '';
  @State private segmentSheetPid: string = '';
  @State private segmentSheetMarkIndex: number = -1;
  @State private segmentSheetInfos: SegmentInfoParagraph[] = [];
  private segmentSheetOpenedAt: number = 0;
  private segmentLikeBusy: boolean = false;
  @State private doubleTapAskSheetShown: boolean = false;
  private doubleTapAskAnswerId: string = '';

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      try {
        this.positionStore = createReaderPositionStore(context);
      } catch (_error) {
        // 位置存储不可用只影响跨模式段落交接，不影响阅读。
      }
      // 双击动作偏好：与单篇详情页同键恢复并广播，双击分发与设置页修改实时联动。
      void new AppPreferencesStore(context).loadAnswerDoubleTapAction()
        .then((action: AnswerDoubleTapAction): void => {
          if (!this.disposed) {
            AppStorage.setOrCreate('answerDoubleTapAction', action);
          }
        }).catch((_error: Error): void => {});
    }
    // 卡片元数据串行加载：回填后强制对应卡片行重建（惰性行不随状态自动重渲染）。
    const metaRepository = this.linkCardMetaRepository;
    if (metaRepository !== undefined) {
      const loader = new LinkCardMetaLoader(metaRepository);
      loader.onUpdate = (url: string, meta: LinkCardMeta): void => {
        this.applyLinkCardMeta(url, meta);
      };
      this.linkCardMetaLoader = loader;
    }
    // 沉浸态是页面私有广播：进入连续页一律从非沉浸开始，离页同样复位避免污染其他页。
    AppStorage.setOrCreate('detailImmersiveActive', false);
    if (this.feedRepository !== undefined) {
      // 排序继承：经 seed 携带初始 sortOrder，避免 activate 首拉后再 setSortOrder 重拉一次。
      const initialOrder = this.sortOrder === 'updated'
        ? QuestionAnswerSortOrder.UPDATED : QuestionAnswerSortOrder.DEFAULT;
      const seed: QuestionAnswersViewState = {
        phase: QuestionAnswersPhase.IDLE,
        items: [],
        loadingMore: false,
        canLoadMore: false,
        sortOrder: initialOrder,
        errorMessage: '',
        requiresLogin: false
      };
      this.feedController = new QuestionAnswersController(this.feedRepository, this.questionId,
        (state: QuestionAnswersViewState): void => {
          this.onFeedState(state);
        }, seed);
      this.feedController.activate();
    }
    const repoA = this.fullTextRepositoryA;
    const repoB = this.fullTextRepositoryB;
    if (repoA !== undefined && repoB !== undefined) {
      let rotate = false;
      this.scheduler = new ContinuousFullTextScheduler((): ContinuousFullTextSource => {
        rotate = !rotate;
        return new RepositoryFullTextSource(rotate ? repoA : repoB);
      }, 2, (snapshot: Array<ContinuousFullTextRecord>): void => {
        this.onFullText(snapshot);
      });
      this.scheduler.activate();
      // 种子先行：不等回答列表，先拉种子正文（计划 §4.2 第 1 步）。
      if (this.seedAnswerId.length > 0) {
        this.scheduler.ensure([this.seedAnswerId]);
      }
    }
    this.buildProvisionalRows();
    void this.loadQuestionTitle();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.feedController?.deactivate();
    this.scheduler?.dispose();
    this.linkCardMetaLoader?.dispose();
    this.linkCardMetaLoader = undefined;
    AppStorage.setOrCreate('detailImmersiveActive', false);
    if (this.dwellTimer >= 0) {
      clearTimeout(this.dwellTimer);
      this.dwellTimer = -1;
    }
    // 离页同步落盘当前活动回答的阅读位置（对齐单篇页强停语义）。
    if (this.activeAnswerIndex >= 0 && this.activeAnswerIndex < this.streamIds.length) {
      this.saveAnswerPosition(this.streamIds[this.activeAnswerIndex], true);
    }
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    clearFormulaByteCache();
    if (AppStorage.get<string>('continuousAnswerTitle') !== undefined) {
      AppStorage.setOrCreate('continuousAnswerTitle', '');
    }
  }

  private loadQuestionTitle(): Promise<void> {
    const repository = this.questionRepository;
    if (repository === undefined) {
      return Promise.resolve();
    }
    return repository.getQuestion(this.questionId).then((question: Question): void => {
      if (this.disposed) {
        return;
      }
      AppStorage.setOrCreate('continuousAnswerTitle', question.title);
    }).catch((_error: Error): void => {
      // 标题加载失败保持占位标题，不阻塞正文流。
    });
  }

  // ---------- 行构建 ----------

  private buildProvisionalRows(): void {
    const rows: Array<ContinuousRow> = [];
    if (this.seedAnswerId.length > 0) {
      rows.push(continuousHeaderRow(this.seedAnswerId));
      rows.push(continuousLoadingBodyRow(this.seedAnswerId));
      rows.push(continuousDividerRow(this.seedAnswerId));
      this.materializedPhase.set(this.seedAnswerId, 'loading');
      this.streamIds = [this.seedAnswerId];
    }
    this.dataSource.replaceAll(rows);
    this.refreshStatus();
  }

  private bodyRowsFor(answerId: string): Array<ContinuousRow> {
    const record = this.scheduler?.record(answerId);
    const phase = record?.phase ?? 'pending';
    const divider = continuousDividerRow(answerId);
    if (phase === 'ready' && record?.answer !== undefined) {
      const answer = record.answer;
      const scoped = this.scopedBlocks(answerId, parseZhihuHtml(answer.contentHtml));
      this.answerBlocks.set(answerId, scoped);
      this.loadLinkCardMetas(scoped);
      const rows: Array<ContinuousRow> = continuousBlockRows(answerId, scoped);
      this.indexReferenceRows(answerId, rows);
      rows.push(continuousDateRow(answerId, answerDateLine(answer)));
      rows.push(continuousActionsRow(answerId));
      rows.push(divider);
      return rows;
    }
    if (phase === 'error') {
      return [continuousErrorBodyRow(answerId, record?.errorMessage ?? '回答加载失败'), divider];
    }
    if (phase === 'evicted') {
      return [continuousReleasedBodyRow(answerId, record?.measuredHeightVp ?? 0), divider];
    }
    const loadingRow = continuousLoadingBodyRow(answerId);
    const author = this.authorOf(answerId);
    if (author.name.length > 0) {
      const withAuthor: ContinuousRow = {
        key: loadingRow.key,
        answerId: loadingRow.answerId,
        kind: loadingRow.kind,
        estimatedHeightVp: loadingRow.estimatedHeightVp,
        label: `正在加载 ${author.name} 的回答…`
      };
      return [withAuthor, divider];
    }
    return [loadingRow, divider];
  }

  /** 正文块 id 加回答作用域（parseZhihuHtml 的 block-N 在多回答间会重号）。 */
  private scopedBlocks(answerId: string, blocks: Array<ReaderBlock>): Array<ReaderBlock> {
    const scoped: Array<ReaderBlock> = [];
    blocks.forEach((block: ReaderBlock): void => {
      const next: ReaderBlock = {
        id: `${answerId}-${block.id}`,
        kind: block.kind,
        text: block.text,
        sourceUrl: block.sourceUrl,
        quoteDepth: block.quoteDepth,
        coverUrl: block.coverUrl,
        displayUrl: block.displayUrl,
        targetId: block.targetId,
        pid: block.pid,
        reference: block.reference,
        inlineRuns: block.inlineRuns
      };
      scoped.push(next);
    });
    return scoped;
  }

  private indexReferenceRows(answerId: string, rows: Array<ContinuousRow>): void {
    const mapping: Map<number, string> = new Map();
    rows.forEach((row: ContinuousRow): void => {
      if (row.kind === ContinuousRowKind.BLOCK && row.block !== undefined &&
        row.block.kind === ReaderBlockKind.REFERENCE && row.block.reference !== undefined) {
        mapping.set(row.block.reference.numero, row.key);
      }
    });
    if (mapping.size > 0) {
      this.referenceRowKeys.set(answerId, mapping);
    }
  }

  // ---------- 状态同步 ----------

  private onFeedState(state: QuestionAnswersViewState): void {
    if (this.disposed) {
      return;
    }
    state.items.forEach((item: ChannelContentItem): void => {
      this.summaries.set(item.feedItem.target.id, item);
    });
    this.feedErrorLine = state.errorMessage;
    const ids: Array<string> = [];
    state.items.forEach((item: ChannelContentItem): void => {
      const id = item.feedItem.target.id;
      if (!ids.includes(id)) {
        ids.push(id);
      }
    });
    if (!this.streamBuilt) {
      this.syncStreamSeed(ids, state);
      return;
    }
    this.appendFeedDelta(ids, state);
    this.ensureWindow();
    this.refreshStatus();
  }

  private syncStreamSeed(ids: Array<string>, state: QuestionAnswersViewState): void {
    const seedIndex = ids.indexOf(this.seedAnswerId);
    if (seedIndex >= 0) {
      this.buildStream(ids, false);
      return;
    }
    if (!state.canLoadMore || this.seedSearchPages >= SEED_SEARCH_EXTRA_PAGES) {
      // 种子不在已加载列表：种子置顶作为起点，其余按默认排序追加并去重（计划 §2.2）。
      this.buildStream(ids, true);
      return;
    }
    this.seedSearchPages += 1;
    void this.feedController?.loadMore();
  }

  private buildStream(feedIds: Array<string>, seedFirst: boolean): void {
    const ordered: Array<string> = [];
    const pushUnique = (answerId: string): void => {
      if (answerId.length > 0 && !ordered.includes(answerId)) {
        ordered.push(answerId);
      }
    };
    if (seedFirst && this.seedAnswerId.length > 0) {
      pushUnique(this.seedAnswerId);
    }
    feedIds.forEach(pushUnique);
    if (!seedFirst && this.seedAnswerId.length > 0 && !ordered.includes(this.seedAnswerId)) {
      pushUnique(this.seedAnswerId);
    }
    this.streamIds = ordered;
    const rows: Array<ContinuousRow> = [];
    ordered.forEach((answerId: string): void => {
      rows.push(continuousHeaderRow(answerId));
      const knownPhase = this.materializedPhase.get(answerId);
      if (knownPhase === undefined) {
        this.materializedPhase.set(answerId, 'pending');
      }
      this.appendAll(rows, this.bodyRowsFor(answerId));
    });
    rows.push(continuousStreamEndRow(this.endRowLabel(false)));
    this.dataSource.replaceAll(rows);
    this.streamBuilt = true;
    const target = this.seedAnswerId.length > 0 ? this.seedAnswerId : (ordered.length > 0 ? ordered[0] : '');
    if (target.length > 0) {
      setTimeout((): void => {
        if (this.disposed) {
          return;
        }
        const index = this.dataSource.indexOfRowKey(continuousHeaderRowKey(target));
        if (index >= 0) {
          this.scroller.scrollToIndex(index, false, ScrollAlign.START);
        }
      }, 120);
    }
    this.ensureWindow();
    this.refreshStatus();
  }

  private appendAll(target: Array<ContinuousRow>, items: Array<ContinuousRow>): void {
    items.forEach((item: ContinuousRow): void => {
      target.push(item);
    });
  }

  private appendFeedDelta(feedIds: Array<string>, state: QuestionAnswersViewState): void {
    const fresh: Array<ContinuousRow> = [];
    feedIds.forEach((answerId: string): void => {
      if (this.streamIds.includes(answerId)) {
        return;
      }
      this.streamIds.push(answerId);
      this.materializedPhase.set(answerId, 'pending');
      fresh.push(continuousHeaderRow(answerId));
      fresh.push(continuousLoadingBodyRow(answerId));
      fresh.push(continuousDividerRow(answerId));
    });
    const endIndex = this.dataSource.indexOfRowKey('stream-end:end');
    if (fresh.length > 0 && endIndex >= 0) {
      // 插到结尾行之前（结尾行索引随插入平移，fresh 按序落在其前）。
      for (let i = 0; i < fresh.length; i++) {
        this.dataSource.insertRowAt(endIndex + i, fresh[i]);
      }
    } else if (fresh.length > 0) {
      this.dataSource.appendRows(fresh);
    }
    this.refreshEndRow(state);
  }

  private refreshEndRow(state: QuestionAnswersViewState): void {
    this.dataSource.updateRow('stream-end:end', continuousStreamEndRow(this.endRowLabel(!state.canLoadMore)));
  }

  private retryFeed(): void {
    this.feedErrorLine = '';
    if (this.streamBuilt) {
      void this.feedController?.loadMore();
    } else {
      void this.feedController?.refresh();
    }
  }

  private endRowLabel(isEnd: boolean): string {
    if (this.feedErrorLine.length > 0) {
      return `加载更多回答失败：${this.feedErrorLine}`;
    }
    return isEnd
      ? `已经到底了 · 共 ${this.streamIds.length} 篇回答`
      : `上滑加载更多回答 · 已加载 ${this.streamIds.length} 篇`;
  }

  private onFullText(snapshot: Array<ContinuousFullTextRecord>): void {
    if (this.disposed) {
      return;
    }
    snapshot.forEach((record: ContinuousFullTextRecord): void => {
      const materialized = this.materializedPhase.get(record.answerId);
      if (materialized === record.phase) {
        return;
      }
      if (!this.streamBuilt && record.answerId !== this.seedAnswerId) {
        return;
      }
      this.materializedPhase.set(record.answerId, record.phase);
      if (this.dataSource.indexOfRowKey(continuousHeaderRowKey(record.answerId)) >= 0) {
        this.applyBodyMutation(record.answerId, this.bodyRowsFor(record.answerId));
        this.refreshAnswerRow(continuousHeaderRowKey(record.answerId));
      }
      // 种子答就绪后按共享位置记录恢复段落锚点（单篇→连续交接）。
      if (record.answerId === this.seedAnswerId && record.phase === 'ready') {
        this.restoreSeedPosition(record.answerId);
      }
    });
    this.refreshStatus();
  }

  // ---------- 懒加载 / 淘汰 / 锚点（沿用 P0 验证结构） ----------

  private ensureWindow(): void {
    const scheduler = this.scheduler;
    if (scheduler === undefined) {
      return;
    }
    const windowIds: Array<string> = [];
    for (let i = this.activeAnswerIndex - 1; i <= this.activeAnswerIndex + 2; i++) {
      const answerId = this.streamIds[i];
      if (answerId !== undefined && !windowIds.includes(answerId)) {
        windowIds.push(answerId);
      }
    }
    if (this.seedAnswerId.length > 0 && !windowIds.includes(this.seedAnswerId)) {
      windowIds.push(this.seedAnswerId);
    }
    if (windowIds.length > 0) {
      scheduler.ensure(windowIds);
    }
  }

  private applyEvictionPolicy(): void {
    const scheduler = this.scheduler;
    if (scheduler === undefined || this.activeAnswerIndex < 0) {
      return;
    }
    for (let i = 0; i < this.streamIds.length; i++) {
      const answerId = this.streamIds[i];
      const record = scheduler.record(answerId);
      if (record === undefined) {
        continue;
      }
      const near = i >= this.activeAnswerIndex - 1 && i <= this.activeAnswerIndex + 2;
      if (!near && record.phase === 'ready') {
        scheduler.evict(answerId, this.measuredBodyHeightVp.get(answerId) ?? 0);
        this.answerBlocks.delete(answerId);
        // 淘汰后回看会重新拉取全文，划线缓存一并作废，避免旧回包的划线被复用。
        this.segmentInfosCache.delete(answerId);
      } else if (near && record.phase === 'evicted') {
        scheduler.restore(answerId);
      }
    }
  }

  private applyBodyMutation(answerId: string, nextRows: Array<ContinuousRow>): void {
    const headerIndex = this.dataSource.indexOfRowKey(continuousHeaderRowKey(answerId));
    const touchesViewport = headerIndex >= 0 && headerIndex + 1 <= this.lastVisibleIndex;
    if (touchesViewport) {
      this.captureAnchor();
      this.clearRowMeasurements(answerId);
    }
    const startIndex = this.dataSource.replaceBodyRows(answerId, nextRows);
    if (touchesViewport && startIndex >= 0) {
      this.scheduleAnchorRestore();
    }
  }

  private clearRowMeasurements(answerId: string): void {
    const staleKeys: Array<string> = [];
    this.measuredRowHeightVp.forEach((_height: number, key: string): void => {
      if (key.startsWith(`${answerId}:`)) {
        staleKeys.push(key);
      }
    });
    staleKeys.forEach((key: string): void => {
      this.measuredRowHeightVp.delete(key);
    });
    this.measuredBodyHeightVp.delete(answerId);
  }

  private captureAnchor(): void {
    this.anchorKey = '';
    this.anchorFraction = 0;
    if (this.viewportHeightVp <= 0) {
      return;
    }
    const referenceY = this.viewportHeightVp * ACTIVE_REFERENCE_FRACTION;
    const total = this.dataSource.totalCount();
    for (let i = this.firstVisibleIndex; i <= Math.min(this.lastVisibleIndex, total - 1); i++) {
      const rect = this.scroller.getItemRect(i);
      if (rect.height <= 0) {
        continue;
      }
      if (rect.y + rect.height > referenceY + 2) {
        this.anchorKey = this.dataSource.rowAt(i).key;
        const fraction = (referenceY - rect.y) / rect.height;
        this.anchorFraction = Math.min(1, Math.max(0, fraction));
        return;
      }
    }
  }

  private scheduleAnchorRestore(): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreAttempt = 0;
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      this.restoreAnchorOnce();
    }, 60);
  }

  private restoreAnchorOnce(): void {
    if (this.anchorKey.length === 0) {
      return;
    }
    const index = this.dataSource.indexOfRowKey(this.anchorKey);
    if (index < 0) {
      this.anchorKey = '';
      return;
    }
    const rect = this.scroller.getItemRect(index);
    if (rect.height <= 0) {
      this.restoreAttempt += 1;
      if (this.restoreAttempt < ANCHOR_RESTORE_MAX_ATTEMPTS) {
        this.restoreTimer = setTimeout((): void => {
          this.restoreTimer = -1;
          this.restoreAnchorOnce();
        }, 60);
      } else {
        this.anchorKey = '';
      }
      return;
    }
    const referenceY = this.viewportHeightVp * ACTIVE_REFERENCE_FRACTION;
    const targetY = referenceY - this.anchorFraction * rect.height;
    const delta = rect.y - targetY;
    if (Math.abs(delta) > 1) {
      this.scroller.scrollBy(0, delta);
    }
    this.anchorKey = '';
  }

  private reportRowHeight(row: ContinuousRow, newHeight: number): void {
    if (!(newHeight > 0)) {
      return;
    }
    const previous = this.measuredRowHeightVp.get(row.key);
    this.measuredRowHeightVp.set(row.key, newHeight);
    if (row.kind === ContinuousRowKind.BLOCK) {
      const sum = (this.measuredBodyHeightVp.get(row.answerId) ?? 0) +
        (previous === undefined ? newHeight : newHeight - previous);
      this.measuredBodyHeightVp.set(row.answerId, Math.max(0, sum));
    }
    if (previous === undefined || Math.abs(newHeight - previous) < 1) {
      return;
    }
    const delta = newHeight - previous;
    const index = this.dataSource.indexOfRowKey(row.key);
    if (index < 0 || this.viewportHeightVp <= 0) {
      return;
    }
    const rect = this.scroller.getItemRect(index);
    if (rect.height <= 0) {
      return;
    }
    const referenceY = this.viewportHeightVp * ACTIVE_REFERENCE_FRACTION;
    if (rect.y + Math.min(previous, newHeight) <= referenceY) {
      this.scroller.scrollBy(0, delta);
    }
  }

  private updateActiveAnswer(): void {
    if (this.viewportHeightVp <= 0) {
      return;
    }
    const referenceY = this.viewportHeightVp * ACTIVE_REFERENCE_FRACTION;
    const total = this.dataSource.totalCount();
    let referenceIndex = -1;
    for (let i = this.firstVisibleIndex; i <= Math.min(this.lastVisibleIndex, total - 1); i++) {
      const rect = this.scroller.getItemRect(i);
      if (rect.height <= 0) {
        continue;
      }
      if (rect.y + rect.height > referenceY + 2) {
        referenceIndex = i;
        break;
      }
    }
    if (referenceIndex < 0) {
      return;
    }
    const row = this.dataSource.rowAt(referenceIndex);
    if (row.kind === ContinuousRowKind.DIVIDER_BAND || row.kind === ContinuousRowKind.STREAM_END) {
      return;
    }
    const candidate = this.streamIds.indexOf(row.answerId);
    if (candidate < 0 || candidate === this.activeAnswerIndex) {
      return;
    }
    const headerIndex = this.dataSource.indexOfRowKey(continuousHeaderRowKey(row.answerId));
    if (headerIndex >= 0) {
      const headerRect = this.scroller.getItemRect(headerIndex);
      if (headerRect.height > 0 && referenceY - headerRect.y < ACTIVE_ANSWER_HYSTERESIS_VP) {
        return;
      }
    }
    this.activeAnswerIndex = candidate;
    this.refreshStatus();
    this.applyEvictionPolicy();
    this.ensureWindow();
    this.scheduleDwellConfirm();
  }

  private refreshStatus(): void {
    let ready = 0;
    let evicted = 0;
    let errored = 0;
    this.materializedPhase.forEach((phase: string): void => {
      if (phase === 'ready') {
        ready += 1;
      } else if (phase === 'evicted') {
        evicted += 1;
      } else if (phase === 'error') {
        errored += 1;
      }
    });
    const active = this.activeAnswerIndex >= 0 && this.activeAnswerIndex < this.streamIds.length
      ? `回答 ${this.activeAnswerIndex + 1}/${this.streamIds.length}` : '回答 -';
    this.statusLine = `${active} · 已加载 ${this.streamIds.length} · 就绪 ${ready} · 已释放 ${evicted} · 失败 ${errored}`;
  }

  // ---------- 阅读记录与逐答位置（计划 §4.4） ----------

  /** 活动回答停留 800ms 确认后才写历史；预取/划过不写。 */
  private scheduleDwellConfirm(): void {
    if (this.dwellTimer >= 0) {
      clearTimeout(this.dwellTimer);
      this.dwellTimer = -1;
    }
    const answerId = this.activeAnswerIndex >= 0 && this.activeAnswerIndex < this.streamIds.length
      ? this.streamIds[this.activeAnswerIndex] : '';
    this.dwellAnswerId = answerId;
    if (answerId.length === 0 || this.recordedAnswers.has(answerId)) {
      return;
    }
    const record = this.scheduler?.record(answerId);
    if (record === undefined || record.phase !== 'ready') {
      return;
    }
    this.dwellTimer = setTimeout((): void => {
      this.dwellTimer = -1;
      if (this.disposed || this.dwellAnswerId !== answerId) {
        return;
      }
      this.confirmAnswerRead(answerId);
    }, 800);
  }

  private confirmAnswerRead(answerId: string): void {
    if (this.recordedAnswers.has(answerId)) {
      return;
    }
    const answer = this.scheduler?.record(answerId)?.answer;
    if (answer === undefined) {
      return;
    }
    this.recordedAnswers.add(answerId);
    const store = this.openedContentStore;
    if (store !== undefined) {
      const detail: LoadedContentDetail = { kind: ContentDetailKind.ANSWER, value: answer };
      void recordContentOpen(store, this.historyUploader, detail);
    }
    this.saveAnswerPosition(answerId, false);
  }

  /** 活动回答的逐答位置：参考线（正文顶部）所在正文块 + 块内比例，存共享 ReaderPosition 仓库。 */
  private captureAnswerPosition(answerId: string): ReaderPosition | undefined {
    const blocks = this.answerBlocks.get(answerId);
    if (blocks === undefined || blocks.length === 0 || this.viewportHeightVp <= 0) {
      return undefined;
    }
    const readingLine = CONTINUOUS_TOP_INSET_VP;
    const total = this.dataSource.totalCount();
    for (let i = this.firstVisibleIndex; i <= Math.min(this.lastVisibleIndex, total - 1); i++) {
      const row = this.dataSource.rowAt(i);
      const block = row.block;
      if (row.answerId !== answerId || row.kind !== ContinuousRowKind.BLOCK || block === undefined) {
        continue;
      }
      const rect = this.scroller.getItemRect(i);
      if (rect.height <= 0) {
        continue;
      }
      if (rect.y + rect.height > readingLine + 2) {
        const blockIndex = blocks.findIndex((item: ReaderBlock): boolean => item.id === block.id);
        if (blockIndex < 0) {
          return undefined;
        }
        const position: ReaderPosition = {
          version: 1,
          blockId: blocks[blockIndex].id,
          signature: readerBlockSignature(blocks[blockIndex]),
          blockIndex: blockIndex,
          fraction: readerPositionFraction(rect.y, rect.height, readingLine),
          atEnd: false
        };
        return position;
      }
    }
    return undefined;
  }

  private saveAnswerPosition(answerId: string, synchronous: boolean): void {
    const store = this.positionStore;
    const key = readerPositionKey('answer', answerId);
    if (store === undefined || key.length === 0) {
      return;
    }
    const position = this.captureAnswerPosition(answerId);
    if (position !== undefined) {
      try {
        store.save(key, position, synchronous);
      } catch (_error) {
        // 位置保存失败不影响阅读与历史。
      }
    }
  }

  /** 种子答就绪后按共享位置记录恢复段落锚点（单篇页保存的同格式，跨模式交接）。 */
  private restoreSeedPosition(answerId: string): void {
    if (this.seedRestored || this.positionStore === undefined) {
      return;
    }
    const key = readerPositionKey('answer', answerId);
    if (key.length === 0) {
      return;
    }
    let position: ReaderPosition | undefined = undefined;
    try {
      position = this.positionStore.load(key);
    } catch (_error) {
      return;
    }
    if (position === undefined || (position.blockIndex === -1 && position.fraction === 0)) {
      this.seedRestored = true;
      return;
    }
    const blocks = this.answerBlocks.get(answerId);
    if (blocks === undefined) {
      this.seedRestored = true;
      return;
    }
    const blockIndex = readerPositionBlockIndex(position, blocks);
    if (blockIndex < 0) {
      this.seedRestored = true;
      return;
    }
    const rowKey = `${answerId}:block:${blocks[blockIndex].id}`;
    const rowIndex = this.dataSource.indexOfRowKey(rowKey);
    if (rowIndex < 0) {
      this.seedRestored = true;
      return;
    }
    this.seedRestored = true;
    const fraction = position.fraction;
    setTimeout((): void => {
      if (this.disposed) {
        return;
      }
      this.scroller.scrollToIndex(rowIndex, false, ScrollAlign.START);
      setTimeout((): void => {
        if (this.disposed) {
          return;
        }
        const rect = this.scroller.getItemRect(rowIndex);
        if (rect.height <= 0) {
          return;
        }
        const delta = rect.y - readerPositionTargetY(fraction, rect.height, CONTINUOUS_TOP_INSET_VP);
        if (Math.abs(delta) > 1) {
          this.scroller.scrollBy(0, delta);
        }
      }, 80);
    }, 60);
  }

  // ---------- 逐答互动 ----------

  private authorOf(answerId: string): AuthorInfo {
    const record = this.scheduler?.record(answerId);
    if (record?.answer !== undefined) {
      return authorOfAnswer(record.answer);
    }
    const summary = this.summaries.get(answerId);
    if (summary !== undefined) {
      return authorOfSummary(summary);
    }
    return { id: '', name: '知乎用户', urlToken: '', headline: '', avatarUrl: '', isFollowing: false };
  }

  private voteSnapshot(answerId: string): AnswerVoteSnapshot {
    const cached = this.votes.get(answerId);
    if (cached !== undefined) {
      return cached;
    }
    const answer = this.scheduler?.record(answerId)?.answer;
    const summary = this.summaries.get(answerId);
    const voteupCount = answer?.voteupCount ?? summary?.feedItem.target.voteupCount ?? 0;
    const commentCount = answer?.commentCount ?? summary?.feedItem.target.commentCount ?? 0;
    const snapshot: AnswerVoteSnapshot = {
      voteState: answer?.voteState,
      voteupCount: voteupCount,
      commentCount: commentCount
    };
    this.votes.set(answerId, snapshot);
    return snapshot;
  }

  private vote(answerId: string, target: ContentVoteState): void {
    const repository = this.voteRepository;
    if (repository === undefined) {
      return;
    }
    // 明确的逐答操作立即确认已读（计划 §4.4），不等停留时长。
    this.confirmAnswerRead(answerId);
    const current = this.voteSnapshot(answerId);
    const previous = current.voteState ?? ContentVoteState.NEUTRAL;
    const next = previous === target ? ContentVoteState.NEUTRAL : target;
    let delta = 0;
    if (previous === ContentVoteState.UP && next !== ContentVoteState.UP) {
      delta -= 1;
    }
    if (previous === ContentVoteState.DOWN && next !== ContentVoteState.DOWN) {
      delta += 1;
    }
    if (next === ContentVoteState.UP && previous !== ContentVoteState.UP) {
      delta += 1;
    }
    if (next === ContentVoteState.DOWN && previous !== ContentVoteState.DOWN) {
      delta -= 1;
    }
    const optimistic: AnswerVoteSnapshot = {
      voteState: next,
      voteupCount: Math.max(0, current.voteupCount + delta),
      commentCount: current.commentCount
    };
    this.votes.set(answerId, optimistic);
    this.refreshAnswerRows(answerId);
    repository.voteAnswer(answerId, next).then((result: ContentVoteResult): void => {
      if (this.disposed) {
        return;
      }
      this.votes.set(answerId, {
        voteState: next,
        voteupCount: result.voteupCount ?? optimistic.voteupCount,
        commentCount: optimistic.commentCount
      });
      this.refreshAnswerRows(answerId);
    }).catch((error: Object): void => {
      if (this.disposed) {
        return;
      }
      this.votes.set(answerId, current);
      this.refreshAnswerRows(answerId);
      this.toast(contentDetailErrorMessage(error));
    });
  }

  private toggleFollow(answerId: string): void {
    const repository = this.followRepository;
    const author = this.authorOf(answerId);
    if (repository === undefined || author.id.length === 0 || author.urlToken.length === 0) {
      this.toast('暂时无法关注该作者');
      return;
    }
    const current = this.followStates.get(author.id) ?? author.isFollowing;
    const next = !current;
    this.followStates.set(author.id, next);
    this.refreshFollowRows(author.id);
    repository.followUser(author.urlToken, next).then((_result: Object): void => {
      this.toast(next ? `已关注 ${author.name}` : `已取消关注 ${author.name}`);
    }).catch((error: Object): void => {
      if (this.disposed) {
        return;
      }
      this.followStates.set(author.id, current);
      this.refreshFollowRows(author.id);
      this.toast(contentDetailErrorMessage(error));
    });
  }

  /** 同作者多答的报名头一起刷新（计划 §4.3：关注状态按作者共享）。 */
  private refreshFollowRows(authorId: string): void {
    this.streamIds.forEach((answerId: string): void => {
      if (this.authorOf(answerId).id === authorId) {
        this.refreshAnswerRow(continuousHeaderRowKey(answerId));
      }
    });
  }

  private refreshAnswerRows(answerId: string): void {
    this.refreshAnswerRow(continuousHeaderRowKey(answerId));
    this.refreshAnswerRow(`${answerId}:actions`);
  }

  /** 行内容取自页面缓存（投票/关注），行对象本身不变：delete+add 强制重渲染。 */
  private refreshAnswerRow(key: string): void {
    const index = this.dataSource.indexOfRowKey(key);
    if (index < 0) {
      return;
    }
    this.dataSource.replaceRowAt(key, this.dataSource.rowAt(index));
  }

  private answerUrl(answerId: string): string {
    const answer = this.scheduler?.record(answerId)?.answer;
    if (answer !== undefined && answer.url.length > 0) {
      return answer.url;
    }
    return `https://www.zhihu.com/question/${this.questionId}/answer/${answerId}`;
  }

  private copyAnswerLink(answerId: string): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.answerUrl(answerId));
      pasteboard.getSystemPasteboard().setData(pasteData).then((): void => {
        this.toast('已复制链接');
      }).catch((_error: Error): void => {
        this.toast('复制失败，请重试');
      });
    } catch (_error) {
      this.toast('复制失败，请重试');
    }
  }

  private shareAnswer(answerId: string): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.toast('暂时无法打开分享面板');
      return;
    }
    const author = this.authorOf(answerId);
    const payload: ShareTextPayload = {
      kind: SharePayloadKind.TEXT,
      title: `${author.name}的回答`,
      summary: '',
      contentUrl: this.answerUrl(answerId)
    };
    createSystemShareService(context).share(payload).then((outcome: ShareOutcome): void => {
      if (outcome !== ShareOutcome.CANCELLED) {
        this.toast('已打开系统分享面板');
      }
    }).catch((): void => {
      this.toast('暂时无法打开分享面板');
    });
  }

  private switchToSingleAnswer(answerId: string): void {
    // 模式交接：先落盘当前段落位置，单篇页按同格式恢复（计划 §4.4）。
    this.saveAnswerPosition(answerId, true);
    const context = getAbilityContext();
    if (context !== undefined) {
      void new AppPreferencesStore(context).saveAnswerReadingMode('single')
        .catch((_error: Error): void => {});
    }
    AppStorage.setOrCreate('answerReadingMode', 'single');
    this.navigate({ name: AppDestinationName.ANSWER, id: answerId });
  }

  private toast(message: string): void {
    if (message.length === 0) {
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  private onContentLinkClick(url: string): void {
    const destination = resolveZhihuLink(url);
    if (destination !== undefined) {
      this.navigate(toAppDestination(destination));
      return;
    }
    const context = getAbilityContext();
    if (context === undefined || !url.startsWith('https://')) {
      return;
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    context.startAbility(want).catch((_error: Error): void => {
      this.toast('暂时无法打开链接');
    });
  }

  private onImagePreviewChanged(): void {
    // 图片预览经 AppStorage 广播（AppShell 控制顶栏隐藏与返回键），无需本地状态。
  }

  private onImmersiveExitTick(): void {
    // 返回键退出沉浸（AppShell 分支发 tick，语义同回答/文章页）。
    AppStorage.setOrCreate('detailImmersiveActive', false);
  }

  private onRouteVisibleChanged(): void {
    if (this.disposed) {
      return;
    }
    // 离页（评论/作者页/切后台路由被覆盖）停止预取与分页，回页恢复。
    if (this.routeVisible) {
      this.scheduler?.activate();
      this.feedController?.activate();
      this.scheduleDwellConfirm();
    } else {
      this.scheduler?.deactivate();
      this.feedController?.deactivate();
      if (this.dwellTimer >= 0) {
        clearTimeout(this.dwellTimer);
        this.dwellTimer = -1;
      }
    }
  }

  // ---------- 渲染 ----------

  private blockSpacingVp(): number {
    return readerBlockSpacing(this.blockSpacingPercent, this.typographyPreset);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        List({ space: this.blockSpacingVp(), scroller: this.scroller }) {
          LazyForEach(this.dataSource, (row: ContinuousRow) => {
            ListItem() {
              this.streamRow(row)
            }
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              this.reportRowHeight(row, Number(newArea.height));
            })
          }, (row: ContinuousRow): string => row.key)
        }
        .id('continuous_answer_list')
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .cachedCount(6)
        .edgeEffect(EdgeEffect.Spring)
        // 沉浸式标题栏是覆盖层：顶部让出状态栏+标题行高度（P0 结论），正文不穿顶栏；
        // 沉浸阅读隐藏标题栏后只保留状态栏让位。
        .padding({ left: 16, right: 16, top: this.detailImmersiveActive ? 56 : 116 })
        .onScrollIndex((start: number, end: number): void => {
          this.firstVisibleIndex = start;
          this.lastVisibleIndex = end;
          this.updateActiveAnswer();
        })
        .onScrollStop((): void => {
          this.updateActiveAnswer();
          this.ensureWindow();
          this.applyEvictionPolicy();
          this.scheduleDwellConfirm();
        })
        .onReachEnd((): void => {
          if (this.feedErrorLine.length === 0) {
            void this.feedController?.loadMore();
          }
        })
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const height = Number(newArea.height);
          if (height > 0) {
            this.viewportHeightVp = height;
          }
        })
      }
      .width('100%')
      .height('100%')

      // 划线面板与双击动作询问面板：独立空节点挂 bindSheet（对齐单篇详情页多弹层模式）。
      Column()
        .bindSheet(this.segmentSheetShown, this.segmentSheet(), {
          preferType: SheetType.CENTER,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onWillDismiss: (action: DismissSheetAction): void => this.guardSegmentSheetDismiss(action),
          onDisappear: (): void => {
            if (this.segmentSheetShown) {
              this.segmentSheetShown = false;
              this.segmentSheetAnswerId = '';
              this.segmentSheetPid = '';
              this.segmentSheetMarkIndex = -1;
            }
          }
        })
      Column()
        .bindSheet(this.doubleTapAskSheetShown, this.doubleTapAskSheet(), {
          preferType: SheetType.CENTER,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.doubleTapAskSheetShown) {
              this.doubleTapAskSheetShown = false;
            }
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .bindSheet(this.collectionAnswerId.length > 0, this.collectionSheet(), {
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      preferType: SheetType.BOTTOM,
      dragBar: true,
      showClose: false,
      maskColor: '#99000000',
      backgroundColor: $r('app.color.surface_background'),
      onDisappear: (): void => {
        if (this.collectionAnswerId.length > 0) {
          this.collectionAnswerId = '';
        }
      }
    })
  }

  @Builder
  private collectionSheet() {
    CollectionDialogComponent({
      contentType: 'answer',
      contentId: this.collectionAnswerId,
      repository: this.collectionRepository,
      session: this.session,
      navigate: this.navigate,
      onDismiss: (): void => {
        this.collectionAnswerId = '';
      }
    })
  }

  /** 他人划线面板：引用文本 + 点赞/评论胶囊 + 复制（对齐单篇详情页 segmentActionSheet）。 */
  @Builder
  private segmentSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Text('划线片段')
        .id('segment_sheet_title')
        .fontSize($r('app.float.segment_sheet_title_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Text(`“${this.currentSegmentQuote()}”`)
        .id('segment_sheet_quote')
        .fontSize($r('app.float.segment_quote_font_size'))
        .lineHeight($r('app.float.segment_quote_line_height'))
        .fontColor($r('app.color.primary_text'))
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
      if (this.currentSegmentMeta() !== undefined) {
        Row({ space: $r('app.float.spacing_small') }) {
          SegmentPill({
            icon: this.currentSegmentMeta()!.isLike
              ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup'),
            count: `${this.currentSegmentMeta()!.likeCount}`,
            active: this.currentSegmentMeta()!.isLike,
            iconAccent: false,
            testId: 'segment_sheet_like',
            label: this.currentSegmentMeta()!.isLike ? '取消点赞该划线' : '点赞该划线',
            onTap: (): void => { void this.onSegmentLike(); }
          })
          SegmentPill({
            icon: $r('sys.symbol.text_bubble_left_2'),
            count: `${this.currentSegmentMeta()!.commentCount}`,
            active: false,
            iconAccent: true,
            testId: 'segment_sheet_comment',
            label: '查看该划线的评论',
            onTap: (): void => {
              this.openSegmentComments();
            }
          })
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
              .fontSize(20)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id('segment_sheet_copy')
          .width($r('app.float.segment_action_button_height'))
          .height($r('app.float.segment_action_button_height'))
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('复制划线内容')
          .onClick((): void => {
            const quote = this.currentSegmentQuote();
            if (quote.length === 0) {
              return;
            }
            try {
              const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, quote);
              pasteboard.getSystemPasteboard().setData(pasteData).then((): void => {
                this.toast('已复制划线内容');
              }).catch((_error: Error): void => {
                this.toast('复制失败，请重试');
              });
            } catch (_error) {
              this.toast('复制失败，请重试');
            }
          })
        }
        .width('100%')
      }
    }
    .id('segment_action_sheet')
    .width('100%')
    .padding({ top: 16, bottom: 24, left: 20, right: 20 })
  }

  /** 双击动作询问面板（对齐单篇详情页 doubleTapAskSheet）：选择后记住并立即执行。 */
  @Builder
  private doubleTapAskSheet() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('设置双击正文动作')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('选择以后双击正文时默认执行的动作。选择后会立即保存到设置，你也可以稍后在设置中修改。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Button('设为无操作', { type: ButtonType.Normal, stateEffect: true })
        .id('answer_double_tap_none')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveDoubleTapAction(AnswerDoubleTapAction.NONE);
        })
      Button('设为点赞', { type: ButtonType.Normal, stateEffect: true })
        .id('answer_double_tap_vote_up')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveDoubleTapAction(AnswerDoubleTapAction.VOTE_UP);
          performConfirmHaptic();
          const answerId = this.doubleTapAskAnswerId;
          if (answerId.length > 0 && this.voteSnapshot(answerId).voteState !== ContentVoteState.UP) {
            this.vote(answerId, ContentVoteState.UP);
          }
        })
      Button('设为打开评论区', { type: ButtonType.Normal, stateEffect: true })
        .id('answer_double_tap_open_comments')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveDoubleTapAction(AnswerDoubleTapAction.OPEN_COMMENTS);
          performConfirmHaptic();
          const answerId = this.doubleTapAskAnswerId;
          if (answerId.length > 0) {
            this.confirmAnswerRead(answerId);
            this.navigate({ name: AppDestinationName.COMMENT, contentType: 'answer', contentId: answerId });
          }
        })
      Button('设为开关沉浸式', { type: ButtonType.Normal, stateEffect: true })
        .id('answer_double_tap_toggle_immersive')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.card_radius'))
        .onClick((): void => {
          this.doubleTapAskSheetShown = false;
          this.saveDoubleTapAction(AnswerDoubleTapAction.TOGGLE_IMMERSIVE);
          AppStorage.setOrCreate('detailImmersiveActive', !this.detailImmersiveActive);
        })
    }
    .id('answer_double_tap_sheet')
    .width('100%')
    .padding($r('app.float.spacing_medium'))
  }

  @Builder
  private streamRow(row: ContinuousRow) {
    if (row.kind === ContinuousRowKind.ANSWER_HEADER) {
      this.answerHeader(row)
    } else if (row.kind === ContinuousRowKind.BLOCK) {
      this.streamBlock(row)
    } else if (row.kind === ContinuousRowKind.DATE_ROW) {
      Text(row.label)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .padding({ top: 8 })
    } else if (row.kind === ContinuousRowKind.ACTIONS_ROW) {
      this.answerActions(row)
    } else if (row.kind === ContinuousRowKind.DIVIDER_BAND) {
      Column() {
        Divider().color($r('app.color.divider_color')).strokeWidth(1)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
    } else if (row.kind === ContinuousRowKind.BODY_LOADING) {
      this.loadingPlaceholder(row)
    } else if (row.kind === ContinuousRowKind.BODY_RELEASED) {
      this.releasedPlaceholder(row)
    } else if (row.kind === ContinuousRowKind.BODY_ERROR) {
      this.errorPlaceholder(row)
    } else {
      this.streamEndRow(row)
    }
  }

  @Builder
  private streamEndRow(row: ContinuousRow) {
    Column({ space: 8 }) {
      Text(row.label)
        .id('continuous_answer_stream_end')
        .fontSize(13)
        .fontColor(this.feedErrorLine.length > 0 ? this.resolvedThemeColor : $r('app.color.secondary_text'))
        .width('100%')
        .textAlign(TextAlign.Center)
      if (this.feedErrorLine.length > 0) {
        Button('重试加载更多')
          .id('continuous_answer_retry_more')
          .height(32)
          .fontSize(13)
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .onClick((): void => this.retryFeed())
      }
    }
    .width('100%')
    .padding({ top: 24, bottom: 32 })
  }

  @Builder
  private answerHeader(row: ContinuousRow) {
    Row({ space: 12 }) {
      if (this.authorAvatarUrl(row.answerId).length > 0 && !this.failedAvatarIds.has(row.answerId)) {
        Image(this.authorAvatarUrl(row.answerId))
          .id(`cont_avatar_${row.answerId}`)
          .width(40)
          .height(40)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
          .onError((): void => {
            this.failedAvatarIds.add(row.answerId);
            this.refreshAnswerRow(continuousHeaderRowKey(row.answerId));
          })
      } else {
        Text(this.authorNameOf(row.answerId).substring(0, 1))
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
          .fontSize(18)
      }
      Column({ space: 2 }) {
        Text(this.authorNameOf(row.answerId))
          .id(`cont_author_${row.answerId}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
        if (this.authorHeadlineOf(row.answerId).length > 0) {
          Text(this.authorHeadlineOf(row.answerId))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(this.voteLineOf(row.answerId))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button(this.isFollowingAuthor(row.answerId) ? '已关注' : '关注')
        .id(`cont_follow_${row.answerId}`)
        .height(32)
        .fontSize(13)
        .backgroundColor(this.isFollowingAuthor(row.answerId) ? $r('app.color.control_background') : this.resolvedThemeColor)
        .fontColor(this.isFollowingAuthor(row.answerId) ? $r('app.color.secondary_text') : onThemeColor(this.resolvedThemeColor))
        .onClick((): void => this.toggleFollow(row.answerId))
    }
    .id(`cont_header_${row.answerId}`)
    .width('100%')
    .padding({ top: 12, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  private authorNameOf(answerId: string): string {
    return this.authorOf(answerId).name;
  }

  private authorHeadlineOf(answerId: string): string {
    return this.authorOf(answerId).headline;
  }

  private authorAvatarUrl(answerId: string): string {
    return this.authorOf(answerId).avatarUrl;
  }

  private isFollowingAuthor(answerId: string): boolean {
    const author = this.authorOf(answerId);
    if (author.id.length === 0) {
      return false;
    }
    return this.followStates.get(author.id) ?? author.isFollowing;
  }

  private voteLineOf(answerId: string): string {
    const snapshot = this.voteSnapshot(answerId);
    return `${formatVoteCount(snapshot.voteupCount)} · ${formatVoteCount(snapshot.commentCount)} 条评论`;
  }

  @Builder
  private streamBlock(row: ContinuousRow) {
    if (row.block !== undefined) {
      ReaderBlockView({
        item: row.block,
        previousBlock: this.previousBlockOf(row.answerId, row.block),
        segmentInfos: this.segmentInfosOf(row.answerId),
        linkCardMeta: this.linkCardMetas.get(row.block.sourceUrl),
        onLinkClick: (url: string): void => this.onContentLinkClick(url),
        onReferenceClick: (numero: number): void => this.scrollToReference(row.answerId, numero),
        onReferenceBack: (numero: number): void => this.scrollBackToReference(row.answerId, numero),
        onVideoOpen: (videoId: string): void => {
          if (videoId.length > 0) {
            this.navigate({ name: AppDestinationName.VIDEO, id: videoId });
          }
        },
        onSegmentClick: (paragraph: SegmentInfoParagraph, markIndex: number): void =>
          this.openSegmentSheet(row.answerId, paragraph, markIndex),
        onBodyDoubleTap: (): void => this.onBodyDoubleTapAction(row.answerId),
        onBodySelectionActive: (_active: boolean): void => {
          // 连续页没有单篇的过滑切答手势，选区信号无需挂起手势；保留通道与单篇对齐。
        }
      })
    }
  }

  /** 同一回答中上一个正文块：ReaderBlockView 据此计算标题/图片/引用的段前留白。 */
  private previousBlockOf(answerId: string, block: ReaderBlock): ReaderBlock | undefined {
    const blocks = this.answerBlocks.get(answerId);
    if (blocks === undefined) {
      return undefined;
    }
    const index = blocks.findIndex((item: ReaderBlock): boolean => item.id === block.id);
    if (index <= 0) {
      return undefined;
    }
    return blocks[index - 1];
  }

  /** 逐答他人划线（合并同区间 mark）：按回答懒加载缓存，供划线叠加与面板读取。 */
  private segmentInfosOf(answerId: string): SegmentInfoParagraph[] {
    const cached = this.segmentInfosCache.get(answerId);
    if (cached !== undefined) {
      return cached;
    }
    const answer = this.scheduler?.record(answerId)?.answer;
    const infos = answer === undefined ? [] : mergeSameRangeMarks(answer.segmentInfos ?? []);
    this.segmentInfosCache.set(answerId, infos);
    return infos;
  }

  /**
   * 推荐阅读卡片元数据拉取（串行与去重在 LinkCardMetaLoader 内）：失败或非站内资源
   * 静默跳过，卡片保持展示链接地址的回退形态。
   */
  private loadLinkCardMetas(blocks: Array<ReaderBlock>): void {
    const loader = this.linkCardMetaLoader;
    if (loader === undefined) {
      return;
    }
    const urls: Array<string> = [];
    blocks.forEach((block: ReaderBlock): void => {
      if (block.kind === ReaderBlockKind.LINK_CARD && block.sourceUrl.length > 0 &&
        !urls.includes(block.sourceUrl)) {
        urls.push(block.sourceUrl);
      }
    });
    if (urls.length > 0) {
      loader.load(urls);
    }
  }

  /** 元数据回填：更新状态并对引用该 url 的卡片行 delete+add 强制重建（惰性行不随状态重渲染）。 */
  private applyLinkCardMeta(url: string, meta: LinkCardMeta): void {
    const updated: Map<string, LinkCardMeta> = new Map();
    this.linkCardMetas.forEach((existing: LinkCardMeta, key: string): void => {
      updated.set(key, existing);
    });
    updated.set(url, meta);
    this.linkCardMetas = updated;
    const total = this.dataSource.totalCount();
    for (let i = 0; i < total; i++) {
      const row = this.dataSource.rowAt(i);
      if (row.kind === ContinuousRowKind.BLOCK && row.block !== undefined &&
        row.block.kind === ReaderBlockKind.LINK_CARD && row.block.sourceUrl === url) {
        this.dataSource.replaceRowAt(row.key, row);
      }
    }
  }

  // ---------- 他人划线互动（对齐单篇详情页面板） ----------

  private openSegmentSheet(answerId: string, paragraph: SegmentInfoParagraph, markIndex: number): void {
    const mark = paragraph.marks[markIndex];
    if (mark === undefined || effectiveSegmentMeta(mark) === undefined) {
      return;
    }
    this.segmentSheetAnswerId = answerId;
    this.segmentSheetPid = paragraph.pid;
    this.segmentSheetMarkIndex = markIndex;
    this.segmentSheetOpenedAt = Date.now();
    this.segmentSheetInfos = this.segmentInfosOf(answerId);
    this.segmentSheetShown = true;
  }

  /** 面板打开后极短时间内的关闭一律拦截：双击划线句的第二击会落在刚弹出的面板遮罩上。 */
  private guardSegmentSheetDismiss(action: DismissSheetAction): void {
    if (Date.now() - this.segmentSheetOpenedAt < 400) {
      return;
    }
    action.dismiss();
  }

  private currentSegmentMeta(): SegmentInfoMeta | undefined {
    const paragraph = this.segmentSheetInfos.find((p: SegmentInfoParagraph): boolean =>
      p.pid === this.segmentSheetPid);
    if (paragraph === undefined) {
      return undefined;
    }
    const mark = paragraph.marks[this.segmentSheetMarkIndex];
    return mark === undefined ? undefined : effectiveSegmentMeta(mark);
  }

  private currentSegmentQuote(): string {
    const paragraph = this.segmentSheetInfos.find((p: SegmentInfoParagraph): boolean =>
      p.pid === this.segmentSheetPid);
    if (paragraph === undefined) {
      return '';
    }
    const mark = paragraph.marks[this.segmentSheetMarkIndex];
    if (mark === undefined) {
      return '';
    }
    const start = Math.max(0, Math.min(paragraph.text.length, mark.startIndex));
    const end = Math.max(0, Math.min(paragraph.text.length, mark.endIndex));
    return end > start ? paragraph.text.substring(start, end) : '';
  }

  /** 乐观更新某条划线的元信息（点赞数/是否已赞）：同时刷新面板与缓存。 */
  private applySegmentMeta(answerId: string, pid: string, markIndex: number, meta: SegmentInfoMeta): void {
    const applyTo = (paragraphs: SegmentInfoParagraph[]): SegmentInfoParagraph[] => {
      const next: Array<SegmentInfoParagraph> = [];
      paragraphs.forEach((p: SegmentInfoParagraph): void => {
        if (p.pid !== pid) {
          next.push(p);
          return;
        }
        const marks: Array<SegmentInfoMark> = [];
        p.marks.forEach((m: SegmentInfoMark, index: number): void => {
          if (index !== markIndex) {
            marks.push(m);
            return;
          }
          const updated: SegmentInfoMark = {
            startIndex: m.startIndex,
            endIndex: m.endIndex,
            segInfo: m.segInfo !== undefined ? meta : m.segInfo,
            masterSegInfo: m.masterSegInfo !== undefined ? meta : m.masterSegInfo
          };
          marks.push(updated);
        });
        next.push({ pid: p.pid, text: p.text, marks: marks });
      });
      return next;
    };
    const cached = this.segmentInfosCache.get(answerId);
    if (cached !== undefined) {
      this.segmentInfosCache.set(answerId, applyTo(cached));
    }
    if (this.segmentSheetAnswerId === answerId) {
      this.segmentSheetInfos = applyTo(this.segmentSheetInfos);
    }
  }

  /**
   * 切换划线点赞（乐观更新 + 真实请求，失败回滚）。结构约束（对齐单篇详情页）：
   * busy 翻转与回滚必须无条件执行（finally）；失败分支里可能抛错的 toast 自带 try 兜底，
   * 否则一次异常会让 busy 永久为 true，后续点赞全被守卫挡掉且毫无反馈。
   */
  private async onSegmentLike(): Promise<void> {
    if (this.segmentLikeBusy || this.segmentReactionRepository === undefined ||
      this.session === undefined || this.segmentSheetMarkIndex < 0) {
      return;
    }
    const answerId = this.segmentSheetAnswerId;
    const pid = this.segmentSheetPid;
    const markIndex = this.segmentSheetMarkIndex;
    const paragraph = this.segmentSheetInfos.find((p: SegmentInfoParagraph): boolean => p.pid === pid);
    if (paragraph === undefined) {
      return;
    }
    const mark = paragraph.marks[markIndex];
    const before = mark === undefined ? undefined : effectiveSegmentMeta(mark);
    if (before === undefined) {
      return;
    }
    const optimistic: SegmentInfoMeta = {
      segIds: before.segIds,
      isLike: !before.isLike,
      likeCount: before.isLike ? Math.max(0, before.likeCount - 1) : before.likeCount + 1,
      commentCount: before.commentCount,
      myCommentCount: before.myCommentCount,
      isSpan: before.isSpan
    };
    this.segmentLikeBusy = true;
    try {
      this.applySegmentMeta(answerId, pid, markIndex, optimistic);
      const result = await this.segmentReactionRepository
        .toggleSegmentLike('answer', answerId, paragraph, markIndex);
      this.applySegmentMeta(answerId, pid, markIndex, result);
    } catch (_error) {
      this.applySegmentMeta(answerId, pid, markIndex, before);
      try {
        this.toast('操作失败，请稍后重试');
      } catch (_toastError) {
        // toast 抛错不得吞掉回滚与 busy 释放（已先行完成）。
      }
    } finally {
      this.segmentLikeBusy = false;
    }
  }

  private openSegmentComments(): void {
    const meta = this.currentSegmentMeta();
    if (meta === undefined) {
      return;
    }
    const paragraph = this.segmentSheetInfos.find((p: SegmentInfoParagraph): boolean =>
      p.pid === this.segmentSheetPid);
    const mark = paragraph === undefined ? undefined : paragraph.marks[this.segmentSheetMarkIndex];
    this.segmentSheetShown = false;
    this.navigate({
      name: AppDestinationName.COMMENT,
      contentType: 'answer',
      contentId: this.segmentSheetAnswerId,
      segmentId: meta.segIds.join(','),
      segmentContent: this.currentSegmentQuote(),
      segmentParagraphId: this.segmentSheetPid,
      segmentStartOffset: mark === undefined ? 0 : mark.startIndex,
      segmentEndOffset: mark === undefined ? 0 : mark.endIndex
    });
  }

  // ---------- 双击正文动作（对齐单篇详情页分发） ----------

  private onBodyDoubleTapAction(answerId: string): void {
    const action = this.answerDoubleTapAction;
    if (action === AnswerDoubleTapAction.NONE) {
      return;
    }
    if (action === AnswerDoubleTapAction.OPEN_COMMENTS) {
      performConfirmHaptic();
      this.confirmAnswerRead(answerId);
      this.navigate({ name: AppDestinationName.COMMENT, contentType: 'answer', contentId: answerId });
      return;
    }
    if (action === AnswerDoubleTapAction.TOGGLE_IMMERSIVE) {
      AppStorage.setOrCreate('detailImmersiveActive', !this.detailImmersiveActive);
      return;
    }
    if (action === AnswerDoubleTapAction.VOTE_UP) {
      performConfirmHaptic();
      // 对齐上游 voteUpFromDoubleTap：已赞保持原状，不因双击取消点赞。
      if (this.voteSnapshot(answerId).voteState !== ContentVoteState.UP) {
        this.vote(answerId, ContentVoteState.UP);
      }
      return;
    }
    this.doubleTapAskAnswerId = answerId;
    this.doubleTapAskSheetShown = true;
  }

  /** 保存双击动作（询问面板选择）：先广播 AppStorage 再落盘，与单篇详情页同键。 */
  private saveDoubleTapAction(action: AnswerDoubleTapAction): void {
    AppStorage.setOrCreate('answerDoubleTapAction', action);
    const context = getAbilityContext();
    if (context !== undefined) {
      void new AppPreferencesStore(context).saveAnswerDoubleTapAction(action).catch((_error: Error): void => {
      });
    }
  }

  private scrollToReference(answerId: string, numero: number): void {
    const mapping = this.referenceRowKeys.get(answerId);
    const rowKey = mapping?.get(numero);
    if (rowKey === undefined) {
      return;
    }
    this.referenceReturnOffsets.set(`${answerId}:${numero}`, this.scroller.currentOffset().yOffset);
    const index = this.dataSource.indexOfRowKey(rowKey);
    if (index >= 0) {
      this.scroller.scrollToIndex(index, true, ScrollAlign.START);
    }
  }

  private scrollBackToReference(answerId: string, numero: number): void {
    const remembered = this.referenceReturnOffsets.get(`${answerId}:${numero}`);
    if (remembered !== undefined) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: remembered, animation: true });
      return;
    }
    // 未点过标记：回退到正文首个引用该序号的段落（近似定位）。
    const rows: Array<string> = [];
    const total = this.dataSource.totalCount();
    for (let i = 0; i < total; i++) {
      const row = this.dataSource.rowAt(i);
      if (row.answerId === answerId && row.kind === ContinuousRowKind.BLOCK && row.block !== undefined &&
        row.block.inlineRuns.some((run: ReaderInlineRun): boolean => run.referenceNumero === numero)) {
        rows.push(row.key);
        break;
      }
    }
    if (rows.length > 0) {
      const index = this.dataSource.indexOfRowKey(rows[0]);
      if (index >= 0) {
        this.scroller.scrollToIndex(index, true, ScrollAlign.START);
      }
    }
  }

  @Builder
  private answerActions(row: ContinuousRow) {
    Row({ space: 8 }) {
      Text(`赞同 ${formatVoteCount(this.voteSnapshot(row.answerId).voteupCount)}`)
        .id(`cont_vote_up_${row.answerId}`)
        .fontSize(13)
        .fontColor(this.voteSnapshot(row.answerId).voteState === ContentVoteState.UP
          ? onThemeColor(this.resolvedThemeColor) : $r('app.color.primary_text'))
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor(this.voteSnapshot(row.answerId).voteState === ContentVoteState.UP
          ? this.resolvedThemeColor : $r('app.color.surface_background'))
        .onClick((): void => this.vote(row.answerId, ContentVoteState.UP))
      Text('反对')
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor(this.voteSnapshot(row.answerId).voteState === ContentVoteState.DOWN
          ? this.resolvedThemeColor : $r('app.color.surface_background'))
        .onClick((): void => this.vote(row.answerId, ContentVoteState.DOWN))
      Text('收藏')
        .id(`cont_favorite_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_background'))
        .onClick((): void => {
          if (this.collectionRepository !== undefined && this.session !== undefined) {
            this.confirmAnswerRead(row.answerId);
            this.collectionAnswerId = row.answerId;
          } else {
            this.toast('收藏功能需要登录');
          }
        })
      Text(`评论 ${formatVoteCount(this.voteSnapshot(row.answerId).commentCount)}`)
        .id(`cont_comment_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_background'))
        .onClick((): void => {
          this.confirmAnswerRead(row.answerId);
          this.navigate({
            name: AppDestinationName.COMMENT,
            contentType: 'answer',
            contentId: row.answerId
          });
        })
      Blank()
      Text('···')
        .id(`cont_more_${row.answerId}`)
        .fontSize(16)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_background'))
        .bindMenu([
          {
            value: '沉浸阅读',
            action: (): void => {
              AppStorage.setOrCreate('detailImmersiveActive', !this.detailImmersiveActive);
              this.toast(this.detailImmersiveActive ? '已进入沉浸式，按返回键即可退出' : '已退出沉浸式');
            }
          },
          {
            value: '复制链接',
            action: (): void => {
              this.copyAnswerLink(row.answerId);
            }
          },
          {
            value: '分享',
            action: (): void => {
              this.shareAnswer(row.answerId);
            }
          },
          {
            value: '切换到单篇阅读',
            action: (): void => {
              this.switchToSingleAnswer(row.answerId);
            }
          }
        ])
    }
    .id(`cont_actions_${row.answerId}`)
    .width('100%')
    .padding({ top: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private loadingPlaceholder(row: ContinuousRow) {
    Column({ space: 10 }) {
      Text(row.label)
        .id(`cont_loading_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row().height(14).borderRadius(4).backgroundColor($r('app.color.divider_color')).width('92%')
      Row().height(14).borderRadius(4).backgroundColor($r('app.color.divider_color')).width('78%')
      Row().height(14).borderRadius(4).backgroundColor($r('app.color.divider_color')).width('64%')
    }
    .width('100%')
    .height(row.estimatedHeightVp > 0 ? row.estimatedHeightVp : 220)
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private releasedPlaceholder(row: ContinuousRow) {
    Column({ space: 8 }) {
      Text('正文已释放，回看将重新加载')
        .id(`cont_released_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
      Text(`占位高度 ${Math.round(row.estimatedHeightVp)} vp`)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height(row.estimatedHeightVp > 0 ? row.estimatedHeightVp : 220)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_background'))
    .opacity(0.7)
  }

  @Builder
  private errorPlaceholder(row: ContinuousRow) {
    Column({ space: 10 }) {
      Text(row.label)
        .id(`cont_error_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row({ space: 12 }) {
        Button('重试')
          .id(`cont_error_retry_${row.answerId}`)
          .height(32)
          .fontSize(13)
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .onClick((): void => {
            this.scheduler?.retry(row.answerId);
          })
        Button('去登录')
          .id(`cont_error_login_${row.answerId}`)
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => {
            this.navigate({ name: AppDestinationName.LOGIN });
          })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_background'))
  }
}
