import {
  clearFormulaByteCache,
  ReaderBlock,
  ReaderBlockKind,
  ReaderImageBlock,
  ReaderInlineKind,
  ReaderInlineRun
} from 'reader';
import { ContentBlockFormula, ContentInlineFormula } from './NativeContentDocument';
import { DEFAULT_THEME_COLOR, onThemeColor } from 'data';
import {
  readerBlockSpacing,
  readerBodyFontSize,
  readerBodyLineHeight,
  readerHeadingFontSize
} from './ReaderTypography';
import {
  ContinuousRow,
  ContinuousRowKind,
  ContinuousStreamDataSource,
  continuousActionsRow,
  continuousBlockRows,
  continuousDateRow,
  continuousDividerRow,
  continuousHeaderRow,
  continuousHeaderRowKey,
  continuousLoadingBodyRow,
  continuousReleasedBodyRow,
  continuousStreamEndRow
} from './ContinuousStreamDataSource';

/** 夹具回答数：P0 内存趋势按 10/20/30 三个检查点采样。 */
const PROTOTYPE_ANSWER_COUNT = 30;

/** 模拟网络回包延迟（ms）：让加载占位与原位展开肉眼可辨。 */
const SIMULATED_FETCH_DELAY_MS = 450;

/** 活动回答判定滞回（vp）：参考线越过下一答信息头该距离才切换，防边界抖动。 */
const ACTIVE_ANSWER_HYSTERESIS_VP = 120;

/** 视口参考线位置：有效视口顶部下方 1/3（docs §4.3 初值）。 */
const ACTIVE_REFERENCE_FRACTION = 1 / 3;

/** 锚点恢复重试次数上限：惰性块/图片排版稳定通常一两帧内完成。 */
const ANCHOR_RESTORE_MAX_ATTEMPTS = 10;

/** 增高试验追加文本：模拟图片迟到加载把上方行撑高。 */
const GROWTH_SUFFIX = '【增高试验】这段文字在点击「上方增高」按钮后追加到参考线上方的段落，' +
  '用于验证上方行高度变化时的锚点补偿：若补偿生效，当前视口内的阅读位置不应跳动。';

const PROTOTYPE_IMAGE_URL = 'https://picx.zhimg.com/v2-7f36f391170ca2319d6b61239694e0ef_1440w.jpg';
const PROTOTYPE_GIF_URL = 'https://pic2.zhimg.com/v2-5e25b72ea793eb39f3709e89e56b2513_1440w.gif';

/** 夹具回答形态，按序循环铺满 30 篇。 */
enum PrototypeAnswerKind {
  SHORT,
  LONG,
  IMAGE,
  FORMULA,
  MIXED
}

interface PrototypeAnswer {
  readonly id: string;
  readonly no: number;
  readonly authorName: string;
  readonly authorBio: string;
  readonly voteLabel: string;
  readonly commentLabel: string;
  readonly dateLine: string;
  readonly blocks: Array<ReaderBlock>;
}

function kindLabel(kind: PrototypeAnswerKind): string {
  if (kind === PrototypeAnswerKind.SHORT) {
    return '短回答';
  }
  if (kind === PrototypeAnswerKind.LONG) {
    return '长回答';
  }
  if (kind === PrototypeAnswerKind.IMAGE) {
    return '图片回答';
  }
  if (kind === PrototypeAnswerKind.FORMULA) {
    return '公式回答';
  }
  return '混合回答';
}

function equationUrl(tex: string): string {
  return `https://www.zhihu.com/equation?tex=${encodeURIComponent(tex)}`;
}

function paragraphBlock(id: string, text: string): ReaderBlock {
  return { id: id, kind: ReaderBlockKind.PARAGRAPH, text: text, sourceUrl: '', inlineRuns: [] };
}

function headingBlock(id: string, text: string): ReaderBlock {
  return { id: id, kind: ReaderBlockKind.HEADING, text: text, sourceUrl: '', inlineRuns: [] };
}

function imageBlock(id: string, url: string, caption: string): ReaderBlock {
  return { id: id, kind: ReaderBlockKind.IMAGE, text: caption, sourceUrl: url, inlineRuns: [] };
}

function formulaBlock(id: string, tex: string): ReaderBlock {
  return { id: id, kind: ReaderBlockKind.FORMULA, text: tex, sourceUrl: equationUrl(tex), inlineRuns: [] };
}

function listItemBlock(id: string, text: string): ReaderBlock {
  return { id: id, kind: ReaderBlockKind.LIST_ITEM, text: text, sourceUrl: '', inlineRuns: [] };
}

function dividerBlock(id: string): ReaderBlock {
  return { id: id, kind: ReaderBlockKind.DIVIDER, text: '', sourceUrl: '', inlineRuns: [] };
}

function inlineFormulaParagraph(id: string, lead: string, tail: string): ReaderBlock {
  const runs: Array<ReaderInlineRun> = [
    { id: `${id}-r0`, kind: ReaderInlineKind.TEXT, text: lead, sourceUrl: '' },
    {
      id: `${id}-r1`,
      kind: ReaderInlineKind.FORMULA,
      text: 'E=mc^2',
      sourceUrl: equationUrl('E=mc^2')
    },
    { id: `${id}-r2`, kind: ReaderInlineKind.TEXT, text: tail, sourceUrl: '' }
  ];
  return {
    id: id,
    kind: ReaderBlockKind.PARAGRAPH,
    text: `${lead}「E=mc^2」${tail}`,
    sourceUrl: '',
    inlineRuns: runs
  };
}

function fixtureParagraphs(answerNo: number, startIndex: number, count: number): Array<ReaderBlock> {
  const blocks: Array<ReaderBlock> = [];
  for (let i = 0; i < count; i++) {
    const index = startIndex + i;
    const line = `这是第 ${answerNo} 号回答的第 ${index} 段，用于验证连续阅读流的滚动、懒加载与行身份稳定。` +
      `内容按固定模板生成，便于在截图中核对段落归属；长回答通过成倍段落拉高整体高度。`;
    const text = index % 3 === 0 ? `${line}${line}` : line;
    blocks.push(paragraphBlock(`a${answerNo}-b${index}`, text));
  }
  return blocks;
}

function buildFixtureBlocks(answerNo: number, kind: PrototypeAnswerKind): Array<ReaderBlock> {
  const aid = `a${answerNo}`;
  const blocks: Array<ReaderBlock> = [headingBlock(`${aid}-b0`, `回答 ${answerNo}：${kindLabel(kind)}`)];
  if (kind === PrototypeAnswerKind.SHORT) {
    blocks.push(paragraphBlock(`${aid}-b1`,
      `短回答：全篇只有两段，验证跨过短回答边界时活动回答判定与滞回是否稳定。`));
    blocks.push(paragraphBlock(`${aid}-b2`,
      `第二段到此结束，下一答的信息头应能在同一屏内露出。`));
    return blocks;
  }
  if (kind === PrototypeAnswerKind.LONG) {
    appendAll(blocks, fixtureParagraphs(answerNo, 1, 14));
    blocks.push(headingBlock(`${aid}-b15`, `第二节：继续铺量`));
    appendAll(blocks, fixtureParagraphs(answerNo, 16, 14));
    for (let i = 0; i < 6; i++) {
      blocks.push(listItemBlock(`${aid}-li${i}`, `要点 ${i + 1}：列表项参与行身份隔离，跨回答的同序号列表项互不影响。`));
    }
    blocks.push(dividerBlock(`${aid}-hr0`));
    appendAll(blocks, fixtureParagraphs(answerNo, 31, 14));
    return blocks;
  }
  if (kind === PrototypeAnswerKind.IMAGE) {
    blocks.push(paragraphBlock(`${aid}-b1`, `图片回答：图片加载完成前按 4:3 占位，加载后按源图比例与屏占比定宽，` +
      `高度变化经上方行增高补偿路径维持阅读位置。`));
    blocks.push(imageBlock(`${aid}-img0`, PROTOTYPE_IMAGE_URL, `静态图片：1440w 静图`));
    blocks.push(paragraphBlock(`${aid}-b2`, `图片之后继续一段正文，保证图片下方仍有可读内容用于观察补偿效果。`));
    blocks.push(imageBlock(`${aid}-img1`, PROTOTYPE_GIF_URL, `GIF 动图：逐帧解码`));
    blocks.push(paragraphBlock(`${aid}-b3`, `图片回答收尾段。`));
    return blocks;
  }
  if (kind === PrototypeAnswerKind.FORMULA) {
    blocks.push(paragraphBlock(`${aid}-b1`, `公式回答：块级公式与行内公式各若干，验证公式组件在连续流内按回答作用域加载。`));
    blocks.push(formulaBlock(`${aid}-eq0`, 'E=mc^2'));
    blocks.push(inlineFormulaParagraph(`${aid}-b2`, '质能方程 ', ' 是物理学中最著名的公式之一。'));
    blocks.push(formulaBlock(`${aid}-eq1`, '\\int_0^1 x^2\\,dx=\\frac{1}{3}'));
    blocks.push(paragraphBlock(`${aid}-b3`, `公式回答收尾段：公式解码失败时回退为 TeX 文本，不影响滚动结构。`));
    return blocks;
  }
  blocks.push(paragraphBlock(`${aid}-b1`, `混合回答：段落、列表、图片与分隔线组合，覆盖逐答操作栏前的常见块序列。`));
  for (let i = 0; i < 3; i++) {
    blocks.push(listItemBlock(`${aid}-li${i}`, `混合要点 ${i + 1}：同回答内列表项顺序展示。`));
  }
  blocks.push(imageBlock(`${aid}-img0`, PROTOTYPE_IMAGE_URL, `混合回答配图`));
  blocks.push(dividerBlock(`${aid}-hr0`));
  appendAll(blocks, fixtureParagraphs(answerNo, 2, 4));
  return blocks;
}

function appendAll(target: Array<ReaderBlock>, items: Array<ReaderBlock>): void {
  items.forEach((item: ReaderBlock): void => {
    target.push(item);
  });
}

const FIXTURE_AUTHORS: Array<[string, string]> = [
  ['临江仙客', '历史爱好者'],
  ['山野樵夫', '地质工程师'],
  ['量子小径', '理论物理博士生'],
  ['城南旧事', '纪录片导演'],
  ['白露为霜', '植物学答主'],
  ['陆吾', '专栏作者']
];

function buildPrototypeAnswers(count: number): Array<PrototypeAnswer> {
  const kinds: Array<PrototypeAnswerKind> = [
    PrototypeAnswerKind.LONG,
    PrototypeAnswerKind.SHORT,
    PrototypeAnswerKind.IMAGE,
    PrototypeAnswerKind.FORMULA,
    PrototypeAnswerKind.MIXED,
    PrototypeAnswerKind.SHORT
  ];
  const answers: Array<PrototypeAnswer> = [];
  for (let i = 0; i < count; i++) {
    const no = i + 1;
    const noIndex = i % FIXTURE_AUTHORS.length;
    const author = FIXTURE_AUTHORS[noIndex];
    const kind = kinds[i % kinds.length];
    const voteLabel = no % 3 === 0 ? `赞同 ${(no * 137) % 900 + 100}` : `赞同 ${(no * 2417) % 90}k`;
    answers.push({
      id: `a${no}`,
      no: no,
      authorName: author[0],
      authorBio: `${author[1]} · ${kindLabel(kind)}`,
      voteLabel: voteLabel,
      commentLabel: `${(no * 53) % 800 + 12}`,
      dateLine: `发布于 2026-10-${(no % 28 + 1).toString().padStart(2, '0')} · IP 属地北京 · 编辑于 2026-10-23`,
      blocks: buildFixtureBlocks(no, kind)
    });
  }
  return answers;
}

/**
 * P0 技术原型：同一问题下回答连续阅读的滚动结构验证（docs/continuous-answer-reading-plan.md 批次 P0）。
 * 本地夹具不接网络；验证目标：单 List 展平多回答、跨答懒加载、锚点补偿、远处正文释放。
 * 夹具文本/图片地址来自仓库既有探针页；公式走知乎 equation 端点（失败回退 TeX 文本）。
 */
@Component
export struct ContinuousReadingPrototype {
  onBack: () => void = () => {};
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('contentFontSize') private fontSizePercent: number = 100;
  @StorageProp('contentLineHeight') private lineHeightPercent: number = 160;
  @StorageProp('contentBlockSpacing') private blockSpacingPercent: number = 100;
  @StorageProp('contentTypographyPreset') private typographyPreset: string = 'comfortable';

  private readonly answers: Array<PrototypeAnswer> = buildPrototypeAnswers(PROTOTYPE_ANSWER_COUNT);
  private readonly answerById: Map<string, PrototypeAnswer> = new Map();
  private readonly dataSource: ContinuousStreamDataSource = new ContinuousStreamDataSource();
  private readonly scroller: Scroller = new Scroller();

  /** 回答正文状态：pending → loading → ready ⇄ released（淘汰）。 */
  private readonly bodyState: Map<string, string> = new Map();
  /** BLOCK 行实测高度（vp，行 key → 高度）：淘汰占位高度与上方行增高补偿都依赖它。 */
  private readonly measuredRowHeightVp: Map<string, number> = new Map();
  /** 每回答 BLOCK 行实测高度累计（vp，answerId → 高度）：淘汰占位按它预留。 */
  private readonly measuredBodyHeightVp: Map<string, number> = new Map();
  private readonly loadTimers: Map<string, number> = new Map();

  private activeAnswerIndex: number = -1;
  private restoreTimer: number = -1;
  private restoreAttempt: number = 0;
  private anchorKey: string = '';
  private anchorFraction: number = 0;
  private firstVisibleIndex: number = 0;
  private lastVisibleIndex: number = 0;
  private viewportHeightVp: number = 0;
  private lastScrollFrameTs: number = 0;
  private readonly scrollFrameGaps: Array<number> = [];
  private longFrameGaps: number = 0;
  private compensationCount: number = 0;
  private lastCompensationDeltaVp: number = 0;
  private fetchCount: number = 0;

  @State private statusLine: string = '初始化…';
  @State private evictionEnabled: boolean = true;
  @State private previewUrl: string = '';

  aboutToAppear(): void {
    this.answers.forEach((answer: PrototypeAnswer): void => {
      this.answerById.set(answer.id, answer);
      this.bodyState.set(answer.id, 'pending');
    });
    const rows: Array<ContinuousRow> = [];
    this.answers.forEach((answer: PrototypeAnswer): void => {
      rows.push(continuousHeaderRow(answer.id));
      rows.push(continuousLoadingBodyRow(answer.id));
      rows.push(continuousDividerRow(answer.id));
    });
    rows.push(continuousStreamEndRow(`已经到底了 · 共 ${this.answers.length} 个回答（本地夹具，无网络分页）`));
    this.dataSource.replaceAll(rows);
    console.info(`[ContProto] stream built answers=${this.answers.length} rows=${this.dataSource.totalCount()}`);
    this.activeAnswerIndex = 0;
    // 初始并发上限 2（docs §4.2）：一个当前需要 + 一个预取。
    this.requestBody(0);
    this.requestBody(1);
    this.refreshStatus();
  }

  aboutToDisappear(): void {
    this.loadTimers.forEach((timerId: number): void => {
      clearTimeout(timerId);
    });
    this.loadTimers.clear();
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    clearFormulaByteCache();
  }

  private refreshStatus(): void {
    let ready = 0;
    let released = 0;
    let loading = 0;
    this.bodyState.forEach((state: string): void => {
      if (state === 'ready') {
        ready += 1;
      } else if (state === 'released') {
        released += 1;
      } else if (state === 'loading') {
        loading += 1;
      }
    });
    const active = this.activeAnswerIndex >= 0 && this.activeAnswerIndex < this.answers.length
      ? `回答${this.answers[this.activeAnswerIndex].no}` : '回答-';
    this.statusLine = `活动 ${active} · 就绪 ${ready}/${this.answers.length} · 加载中 ${loading} · 已释放 ${released} · ` +
      `取文 ${this.fetchCount} · 补偿 ${this.compensationCount} 次 Δ${this.lastCompensationDeltaVp}vp`;
  }

  // ---------- 懒加载与淘汰 ----------

  /** 请求某回答正文（pending/released → loading → ready）；loading/ready 时幂等。 */
  private requestBody(index: number): void {
    if (index < 0 || index >= this.answers.length) {
      return;
    }
    const answer = this.answers[index];
    const state = this.bodyState.get(answer.id) ?? 'pending';
    if (state === 'loading' || state === 'ready') {
      return;
    }
    this.bodyState.set(answer.id, 'loading');
    this.fetchCount += 1;
    this.applyBodyMutation(answer.id, [
      continuousLoadingBodyRow(answer.id),
      continuousDividerRow(answer.id)
    ]);
    const timerId = setTimeout((): void => {
      this.loadTimers.delete(answer.id);
      // 模拟网络回包：仅当仍在 loading（未被淘汰流程改写）时落数据。
      if ((this.bodyState.get(answer.id) ?? '') !== 'loading') {
        return;
      }
      this.bodyState.set(answer.id, 'ready');
      this.applyBodyMutation(answer.id, this.readyBodyRows(answer));
      this.refreshStatus();
    }, SIMULATED_FETCH_DELAY_MS);
    this.loadTimers.set(answer.id, timerId);
    this.refreshStatus();
  }

  private readyBodyRows(answer: PrototypeAnswer): Array<ContinuousRow> {
    const rows: Array<ContinuousRow> = continuousBlockRows(answer.id, answer.blocks);
    rows.push(continuousDateRow(answer.id, answer.dateLine));
    rows.push(continuousActionsRow(answer.id));
    rows.push(continuousDividerRow(answer.id));
    return rows;
  }

  /** 预取：当前答兜底就绪；下一答信息头进入两屏内才触发（docs §4.2 初值）。 */
  private prefetchNearby(): void {
    if (this.activeAnswerIndex >= 0) {
      this.requestBody(this.activeAnswerIndex);
    }
    const next = this.activeAnswerIndex + 1;
    if (next < 0 || next >= this.answers.length) {
      return;
    }
    const nextAnswer = this.answers[next];
    const state = this.bodyState.get(nextAnswer.id) ?? 'pending';
    if (state === 'loading' || state === 'ready') {
      return;
    }
    const headerIndex = this.dataSource.indexOfRowKey(continuousHeaderRowKey(nextAnswer.id));
    if (headerIndex < 0) {
      return;
    }
    const rect = this.scroller.getItemRect(headerIndex);
    const withinTwoScreens = rect.height <= 0 || (rect.y - this.viewportHeightVp) <= this.viewportHeightVp * 2;
    if (withinTwoScreens) {
      this.requestBody(next);
    }
  }

  /** 淘汰策略（docs §4.5 初值窗口）：仅保留 active-1 .. active+2 区间内的正文。 */
  private applyEvictionPolicy(): void {
    if (!this.evictionEnabled || this.activeAnswerIndex < 0) {
      return;
    }
    for (let i = 0; i < this.answers.length; i++) {
      const answer = this.answers[i];
      const state = this.bodyState.get(answer.id) ?? 'pending';
      const near = i >= this.activeAnswerIndex - 1 && i <= this.activeAnswerIndex + 2;
      if (!near && state === 'ready') {
        this.evictAnswer(i);
      } else if (near && state === 'released') {
        this.requestBody(i);
      }
    }
  }

  private evictAnswer(index: number): void {
    const answer = this.answers[index];
    const measured = this.measuredBodyHeightVp.get(answer.id) ?? 0;
    this.bodyState.set(answer.id, 'released');
    // 淘汰释放正文行；夹具字符串留在 answers 中（真实实现在此处释放全文与重资源）。
    this.applyBodyMutation(answer.id, [
      continuousReleasedBodyRow(answer.id, measured),
      continuousDividerRow(answer.id)
    ]);
    console.info(`[ContProto] evict answer=${answer.id} measuredHeight=${measured.toFixed(0)}vp`);
    this.refreshStatus();
  }

  // ---------- 锚点补偿 ----------

  /** 带锚点保护地原位替换回答正文：替换区间触及视口时先捕获锚点、替换后校正。 */
  private applyBodyMutation(answerId: string, nextRows: Array<ContinuousRow>): void {
    const headerIndex = this.dataSource.indexOfRowKey(continuousHeaderRowKey(answerId));
    const touchesViewport = headerIndex >= 0 && headerIndex + 1 <= this.lastVisibleIndex;
    if (touchesViewport) {
      this.captureAnchor();
      // 被替换行的旧实测高度不再可信：清掉，避免重建行的新测量被误判为"上方行增高"二次补偿。
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

  /** 记录参考线所在内容点（行 key + 行内比例），供替换后的视口校正。 */
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

  /** 把锚点行内容点校正回参考线；行尚未布局（rect 为空）时按帧重试。 */
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
        console.warn(`[ContProto] anchorRestoreGiveUp key=${this.anchorKey}`);
        this.anchorKey = '';
      }
      return;
    }
    const referenceY = this.viewportHeightVp * ACTIVE_REFERENCE_FRACTION;
    const targetY = referenceY - this.anchorFraction * rect.height;
    const delta = rect.y - targetY;
    if (Math.abs(delta) > 1) {
      this.scroller.scrollBy(0, delta);
      this.lastCompensationDeltaVp = Math.round(Math.abs(delta));
      this.compensationCount += 1;
      console.info(`[ContProto] anchorCompensate key=${this.anchorKey} delta=${delta.toFixed(1)}vp`);
    }
    this.anchorKey = '';
    this.refreshStatus();
  }

  // ---------- 滚动监测 ----------

  /** 行实测高度回报：维护淘汰占位高度；上方行高度变化（图片迟到/增高试验）即时补偿。 */
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
    // 该行整行位于参考线上方时，其增高会把视口内容向下推：等量回滚维持阅读位置。
    if (rect.y + Math.min(previous, newHeight) <= referenceY) {
      this.scroller.scrollBy(0, delta);
      this.lastCompensationDeltaVp = Math.round(Math.abs(delta));
      this.compensationCount += 1;
      console.info(`[ContProto] aboveRowGrow key=${row.key} delta=${delta.toFixed(1)}vp`);
      this.refreshStatus();
    }
  }

  /** 参考线行所属回答即活动回答；分隔带/结尾行保持原活动回答（边界滞回之一）。 */
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
    const candidate = this.answers.findIndex((answer: PrototypeAnswer): boolean => answer.id === row.answerId);
    if (candidate < 0 || candidate === this.activeAnswerIndex) {
      return;
    }
    // 越过新回答信息头 120vp 才切换：两短答相邻时参考线贴边不至于来回抖动。
    const headerIndex = this.dataSource.indexOfRowKey(continuousHeaderRowKey(row.answerId));
    if (headerIndex >= 0) {
      const headerRect = this.scroller.getItemRect(headerIndex);
      if (headerRect.height > 0 && referenceY - headerRect.y < ACTIVE_ANSWER_HYSTERESIS_VP) {
        return;
      }
    }
    console.info(`[ContProto] activeAnswer ${this.activeAnswerIndex} -> ${candidate}`);
    this.activeAnswerIndex = candidate;
    this.refreshStatus();
    this.applyEvictionPolicy();
    this.prefetchNearby();
  }

  private recordScrollFrame(): void {
    const now = Date.now();
    if (this.lastScrollFrameTs > 0) {
      const gap = now - this.lastScrollFrameTs;
      this.scrollFrameGaps.push(gap);
      if (this.scrollFrameGaps.length > 600) {
        this.scrollFrameGaps.shift();
      }
      if (gap > 100) {
        this.longFrameGaps += 1;
        console.warn(`[ContProto] longScrollGap ${gap}ms`);
      }
    }
    this.lastScrollFrameTs = now;
  }

  /**
   * 滚动帧间隔统计：onDidScroll 回调节奏近似帧节奏（ فلing 期间逐帧回调），
   * 以 P95 间隔与 >100ms 停顿计数作为滚动流畅度基线（docs §7.2 P0 目标的代理指标）。
   */
  private logFrameStats(reason: string): void {
    if (this.scrollFrameGaps.length < 10) {
      return;
    }
    const sorted = this.scrollFrameGaps.slice().sort((a: number, b: number): number => a - b);
    const p50 = sorted[Math.floor(sorted.length * 0.5)];
    const p95 = sorted[Math.floor(sorted.length * 0.95)];
    const max = sorted[sorted.length - 1];
    console.info(`[ContProto] scrollGapStats(${reason}) n=${sorted.length} p50=${p50}ms p95=${p95}ms ` +
      `max=${max}ms longGaps=${this.longFrameGaps}`);
  }

  private onScrollStopped(): void {
    this.lastScrollFrameTs = 0;
    this.logFrameStats('stop');
    this.updateActiveAnswer();
    this.prefetchNearby();
    this.applyEvictionPolicy();
  }

  // ---------- 控制按钮 ----------

  private scrollToTop(): void {
    this.scroller.scrollToIndex(0, true);
  }

  private jumpToNextAnswer(): void {
    const next = this.activeAnswerIndex + 1;
    if (next < 0 || next >= this.answers.length) {
      return;
    }
    const headerIndex = this.dataSource.indexOfRowKey(continuousHeaderRowKey(this.answers[next].id));
    if (headerIndex >= 0) {
      // 定位下一答信息头（docs §2.1「长回答跳过」语义），不增加返回栈。
      this.scroller.scrollToIndex(headerIndex, true, ScrollAlign.START);
    }
  }

  /** 增高试验：参考线上方最近的段落追加文本，复用"上方行增高"补偿路径。 */
  private growAboveParagraph(): void {
    const referenceY = this.viewportHeightVp * ACTIVE_REFERENCE_FRACTION;
    const total = this.dataSource.totalCount();
    for (let i = Math.min(this.lastVisibleIndex, total - 1); i >= this.firstVisibleIndex; i--) {
      const row = this.dataSource.rowAt(i);
      const rect = this.scroller.getItemRect(i);
      if (row.kind !== ContinuousRowKind.BLOCK || row.block === undefined ||
        row.block.kind !== ReaderBlockKind.PARAGRAPH) {
        continue;
      }
      if (rect.height > 0 && rect.y + rect.height <= referenceY) {
        const block: ReaderBlock = row.block;
        const grown: ReaderBlock = {
          id: block.id,
          kind: block.kind,
          text: `${block.text}${GROWTH_SUFFIX}`,
          sourceUrl: block.sourceUrl,
          quoteDepth: block.quoteDepth,
          pid: block.pid,
          inlineRuns: block.inlineRuns
        };
        const nextRow: ContinuousRow = {
          key: row.key,
          answerId: row.answerId,
          kind: row.kind,
          block: grown,
          estimatedHeightVp: row.estimatedHeightVp,
          label: row.label
        };
        // 同位 delete+add 强制重建该行（onDataChange 对按值传参的嵌套 @Builder 不刷新）。
        this.dataSource.replaceRowAt(row.key, nextRow);
        console.info(`[ContProto] growBlock key=${row.key}`);
        return;
      }
    }
    this.statusLine = '参考线上方没有可增高的段落（先向下滚动一段）';
  }

  private toggleEviction(): void {
    this.evictionEnabled = !this.evictionEnabled;
    if (this.evictionEnabled) {
      this.applyEvictionPolicy();
    }
    this.refreshStatus();
  }

  // ---------- 渲染 ----------

  private bodyFontFp(): number {
    return readerBodyFontSize(this.fontSizePercent, this.typographyPreset);
  }

  private bodyLineHeightFp(): number {
    return readerBodyLineHeight(this.fontSizePercent, this.lineHeightPercent, this.typographyPreset);
  }

  private blockSpacingVp(): number {
    return readerBlockSpacing(this.blockSpacingPercent, this.typographyPreset);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        this.controlBar()
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
        .id('cont_proto_list')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .cachedCount(6)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ left: 16, right: 16 })
        .onScrollIndex((start: number, end: number): void => {
          this.firstVisibleIndex = start;
          this.lastVisibleIndex = end;
          this.updateActiveAnswer();
        })
        .onDidScroll((): void => {
          this.recordScrollFrame();
        })
        .onScrollStop((): void => {
          this.onScrollStopped();
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

      if (this.previewUrl.length > 0) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.previewUrl)
            .id('cont_proto_preview')
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
          Button('关闭预览')
            .id('cont_proto_preview_close')
            .margin(20)
            .backgroundColor($r('app.color.control_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick((): void => {
              this.previewUrl = '';
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#EE000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private controlBar() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Button('返回')
          .id('cont_btn_back')
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => this.onBack())
        Button('回顶')
          .id('cont_btn_top')
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.surface_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => this.scrollToTop())
        Button('下一答')
          .id('cont_btn_next')
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.surface_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => this.jumpToNextAnswer())
        Button('上方增高')
          .id('cont_btn_grow')
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.surface_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => this.growAboveParagraph())
        Button(this.evictionEnabled ? '淘汰:开' : '淘汰:关')
          .id('cont_btn_evict')
          .height(32)
          .fontSize(13)
          .backgroundColor(this.evictionEnabled ? this.resolvedThemeColor : $r('app.color.surface_background'))
          .fontColor(this.evictionEnabled ? onThemeColor(this.resolvedThemeColor) : $r('app.color.primary_text'))
          .onClick((): void => this.toggleEviction())
      }
      .width('100%')
      Text(this.statusLine)
        .id('cont_proto_status')
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .maxLines(2)
    }
    .width('100%')
    // 沉浸式标题栏（含聊天样式）都是覆盖层，内容不自动避让（whats-new 页先例）：
    // 原型页给控制栏让出标题栏高度（API 23 模拟器实测 ≈72vp，含状态栏区让位）。
    .padding({ left: 16, right: 16, top: 80, bottom: 4 })
  }

  @Builder
  private streamRow(row: ContinuousRow) {
    if (row.kind === ContinuousRowKind.ANSWER_HEADER) {
      this.answerHeader(row)
    } else if (row.kind === ContinuousRowKind.BLOCK) {
      this.streamBlock(row)
    } else if (row.kind === ContinuousRowKind.DATE_ROW) {
      Text(row.label)
        .id(`cont_date_${row.answerId}`)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .padding({ top: 8 })
    } else if (row.kind === ContinuousRowKind.ACTIONS_ROW) {
      this.answerActions(row)
    } else if (row.kind === ContinuousRowKind.DIVIDER_BAND) {
      Column() {
        Divider()
          .color($r('app.color.divider_color'))
          .strokeWidth(1)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
    } else if (row.kind === ContinuousRowKind.BODY_LOADING) {
      this.loadingPlaceholder(row)
    } else if (row.kind === ContinuousRowKind.BODY_RELEASED) {
      this.releasedPlaceholder(row)
    } else {
      Text(row.label)
        .id('cont_proto_stream_end')
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 24, bottom: 32 })
    }
  }

  /** @Builder 体内只能调用方法取值：夹具行必有归属回答，缺省返回空串。 */
  private fixtureAuthorName(answerId: string): string {
    const answer = this.answerById.get(answerId);
    return answer === undefined ? '' : answer.authorName;
  }

  private fixtureAuthorBio(answerId: string): string {
    const answer = this.answerById.get(answerId);
    return answer === undefined ? '' : answer.authorBio;
  }

  private fixtureVoteLine(answerId: string): string {
    const answer = this.answerById.get(answerId);
    return answer === undefined ? '' : `${answer.voteLabel} · ${answer.commentLabel} 条评论`;
  }

  private fixtureVoteLabel(answerId: string): string {
    const answer = this.answerById.get(answerId);
    return answer === undefined ? '' : answer.voteLabel;
  }

  private fixtureCommentLabel(answerId: string): string {
    const answer = this.answerById.get(answerId);
    return answer === undefined ? '' : answer.commentLabel;
  }

  @Builder
  private answerHeader(row: ContinuousRow) {
    if (this.answerById.has(row.answerId)) {
      Row({ space: 12 }) {
        Text(this.fixtureAuthorName(row.answerId).substring(0, 1))
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .textAlign(TextAlign.Center)
          .fontSize(18)
        Column({ space: 2 }) {
          Text(this.fixtureAuthorName(row.answerId))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
          Text(this.fixtureAuthorBio(row.answerId))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.fixtureVoteLine(row.answerId))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('关注')
          .id(`cont_follow_${row.answerId}`)
          .height(32)
          .fontSize(13)
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
      }
      .id(`cont_header_${row.answerId}`)
      .width('100%')
      .padding({ top: 12, bottom: 4 })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private streamBlock(row: ContinuousRow) {
    Column() {
      if (row.block !== undefined) {
        this.blockContent(row.block)
      }
    }
    .width('100%')
  }

  @Builder
  private blockContent(block: ReaderBlock) {
    if (block.kind === ReaderBlockKind.HEADING) {
      Text(block.text)
        .id(`cont_heading_${block.id}`)
        .fontSize(readerHeadingFontSize(this.fontSizePercent))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    } else if (block.kind === ReaderBlockKind.DIVIDER) {
      Divider().margin({ top: 8, bottom: 8 })
    } else if (block.kind === ReaderBlockKind.FORMULA) {
      ContentBlockFormula({ item: block })
    } else if (block.kind === ReaderBlockKind.IMAGE) {
      ReaderImageBlock({
        item: block,
        secondaryTextColor: $r('app.color.secondary_text'),
        onPreview: (url: string): void => {
          this.previewUrl = url;
        }
      })
    } else if (block.inlineRuns.length > 0) {
      ContentInlineFormula({ item: block })
    } else if (block.kind === ReaderBlockKind.LIST_ITEM) {
      Text(`• ${block.text}`)
        .id(`cont_block_${block.id}`)
        .fontSize(this.bodyFontFp())
        .lineHeight(this.bodyLineHeightFp())
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    } else {
      Text(block.text)
        .id(`cont_block_${block.id}`)
        .fontSize(this.bodyFontFp())
        .lineHeight(this.bodyLineHeightFp())
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    }
  }

  @Builder
  private answerActions(row: ContinuousRow) {
    if (this.answerById.has(row.answerId)) {
      Row({ space: 8 }) {
        Text(this.fixtureVoteLabel(row.answerId))
          .fontSize(13)
          .fontColor(this.resolvedThemeColor)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.surface_background'))
        Text('反对')
          .fontSize(13)
          .fontColor($r('app.color.primary_text'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.surface_background'))
        Text('收藏')
          .fontSize(13)
          .fontColor($r('app.color.primary_text'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.surface_background'))
        Text(`评论 ${this.fixtureCommentLabel(row.answerId)}`)
          .fontSize(13)
          .fontColor($r('app.color.primary_text'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.surface_background'))
        Blank()
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(18)
        }
        .id(`cont_jump_next_${row.answerId}`)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.surface_background'))
        .accessibilityText('定位下一个回答')
        .onClick((): void => this.jumpToNextAnswer())
      }
      .id(`cont_actions_${row.answerId}`)
      .width('100%')
      .padding({ top: 8 })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private skeletonBar(widthPercent: string) {
    Row()
      .height(14)
      .borderRadius(4)
      .backgroundColor($r('app.color.divider_color'))
      .width(widthPercent)
  }

  @Builder
  private loadingPlaceholder(row: ContinuousRow) {
    Column({ space: 10 }) {
      Text(row.label)
        .id(`cont_loading_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      this.skeletonBar('92%')
      this.skeletonBar('78%')
      this.skeletonBar('64%')
      this.skeletonBar('86%')
    }
    .width('100%')
    .height(row.estimatedHeightVp > 0 ? row.estimatedHeightVp : 320)
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private releasedPlaceholder(row: ContinuousRow) {
    Column({ space: 8 }) {
      Text(row.label)
        .id(`cont_released_${row.answerId}`)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
      Text(`占位高度 ${Math.round(row.estimatedHeightVp)} vp（淘汰前实测）`)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height(row.estimatedHeightVp > 0 ? row.estimatedHeightVp : 320)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_background'))
    .opacity(0.7)
  }
}
