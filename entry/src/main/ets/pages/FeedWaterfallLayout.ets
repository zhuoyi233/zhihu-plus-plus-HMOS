/** 旧双列断点，保留供兼容判断；列数策略统一走 resolveFeedColumnSpec。 */
export const FEED_TWO_COLUMN_MIN_WIDTH: number = 600;
/**
 * 三列、四列断点，对齐官方横向断点体系（HarmonyOS 响应式布局指南）：
 * sm [320,600)、md [600,840)、lg [840,1440)、xl [1440,∞)。
 * 600/840/1440 分别是双列/三列/四列候选起点；实际列数仍受最小卡宽保护
 * （如 840~895vp 因容不下 3×280vp 卡仍为双列）。
 */
export const FEED_THREE_COLUMN_MIN_WIDTH: number = 840;
export const FEED_FOUR_COLUMN_MIN_WIDTH: number = 1440;

/** 信息流最大列数。 */
export const FEED_MAX_COLUMNS: number = 4;
/** 页面左右外边距（app.float.page_padding，12vp），供无资源环境兜底。 */
export const FEED_PAGE_HORIZONTAL_PADDING_VP: number = 12;
/** 信息流列间距（app.float.spacing_medium，14vp），供无资源环境兜底。 */
export const FEED_COLUMN_GAP_VP: number = 14;
/** 常规字号下的最小卡片宽度起点；字号放大按 feedMinCardWidthVp 比例提高。 */
export const FEED_BASE_MIN_CARD_WIDTH_VP: number = 280;
/** 日报 4×1 实验布局的目标列数与专属最小卡宽（竖排小卡可比信息流卡更窄）。 */
export const FEED_DAILY_COLUMN_TARGET: number = 4;
export const FEED_DAILY_BASE_MIN_CARD_WIDTH_VP: number = 240;
/** 首屏容量估算用的单行卡高（较短卡片的经验值，仅服务预取，不决定实际布局）。 */
export const FEED_ESTIMATED_CARD_HEIGHT_VP: number = 112;

/** 按页面宽度给出候选列数（断点未含最小卡宽保护）。 */
export function feedColumnCandidates(pageWidthVp: number): number {
  if (pageWidthVp < FEED_TWO_COLUMN_MIN_WIDTH) {
    return 1;
  }
  if (pageWidthVp < FEED_THREE_COLUMN_MIN_WIDTH) {
    return 2;
  }
  if (pageWidthVp < FEED_FOUR_COLUMN_MIN_WIDTH) {
    return 3;
  }
  return FEED_MAX_COLUMNS;
}

/**
 * 常规字号以 280vp 为最小卡宽起点；系统字号放大时按比例提高，
 * 使可用宽度不足以容纳原列数时自动减列（映射以设备验收为准，上限 2 倍防极端）。
 */
export function feedMinCardWidthVp(fontScale: number): number {
  const scale: number = Number.isFinite(fontScale) && fontScale >= 1 ? Math.min(2, fontScale) : 1;
  return Math.round(FEED_BASE_MIN_CARD_WIDTH_VP * scale);
}

/** 日报 4×1 实验布局的最小卡宽；同样随系统字号缩放提高，上限 2 倍。 */
export function feedDailyMinCardWidthVp(fontScale: number): number {
  const scale: number = Number.isFinite(fontScale) && fontScale >= 1 ? Math.min(2, fontScale) : 1;
  return Math.round(FEED_DAILY_BASE_MIN_CARD_WIDTH_VP * scale);
}

export interface FeedColumnSpec {
  /** 最终列数（1～4）：断点候选、用户期望与最小卡宽保护共同决定。 */
  columns: number;
  /** 多列下均分后的卡片宽度；单列为可用内容宽度（允许不足最小卡宽，占满可用空间）。 */
  cardWidth: number;
  /** 页面宽度扣除左右外边距后的内容宽度。 */
  contentWidth: number;
}

export interface FeedColumnSpecOptions {
  /** 信息流列间距（vp），缺省用 FEED_COLUMN_GAP_VP。 */
  columnGapVp?: number;
  /** 最小卡片宽度（vp），缺省用 FEED_BASE_MIN_CARD_WIDTH_VP。 */
  minCardWidthVp?: number;
  /** 用户期望列数（列数偏好）；缺省或 ≤0 表示自动断点，实际列数仍受宽度保护。 */
  requestedColumns?: number;
}

/**
 * 统一布局计算：页面只消费结果（列数、卡宽），不再各自复制断点判断。
 * 页面宽度必须来自实际页面容器的 vp 宽度（onAreaChange），不用物理 display 尺寸。
 */
export function resolveFeedColumnSpec(pageWidthVp: number, options?: FeedColumnSpecOptions): FeedColumnSpec {
  const gap: number = options?.columnGapVp !== undefined && options.columnGapVp >= 0
    ? options.columnGapVp : FEED_COLUMN_GAP_VP;
  const minCard: number = options?.minCardWidthVp !== undefined && options.minCardWidthVp > 0
    ? options.minCardWidthVp : FEED_BASE_MIN_CARD_WIDTH_VP;
  const contentWidth: number = Math.max(0, pageWidthVp - FEED_PAGE_HORIZONTAL_PADDING_VP * 2);
  const requested: number = options?.requestedColumns ?? 0;
  const wanted: number = requested > 0
    ? Math.min(FEED_MAX_COLUMNS, Math.floor(requested))
    : feedColumnCandidates(pageWidthVp);
  let columns: number = Math.max(1, Math.min(FEED_MAX_COLUMNS, wanted));
  // 可容纳列数 = floor((内容宽度 + 列间距) / (最小卡宽 + 列间距))；容不下最小卡宽时保持单列占满。
  const fit: number = Math.floor((contentWidth + gap) / (minCard + gap));
  columns = fit >= 1 ? Math.min(columns, fit) : 1;
  const cardWidth: number = columns > 1 ? (contentWidth - (columns - 1) * gap) / columns : contentWidth;
  return { columns: columns, cardWidth: Math.max(0, cardWidth), contentWidth: contentWidth };
}

/** 按较短卡片估算首屏容量并预留两行；列数随宽度变化，单列默认首页一屏即足够（无需补页）。 */
export function homeFeedInitialItemTarget(width: number, height: number, topOffset: number,
  minCardWidthVp?: number): number {
  if (height <= 0) {
    return 1;
  }
  const columns: number = resolveFeedColumnSpec(width, { minCardWidthVp: minCardWidthVp }).columns;
  if (columns <= 1) {
    return 1;
  }
  const rows: number = Math.ceil(Math.max(0, height - topOffset) / FEED_ESTIMATED_CARD_HEIGHT_VP) + 2;
  return Math.min(60, Math.max(12, rows * columns));
}

export interface FeedFlowEntry {
  key: string;
  itemIndex: number;
  date: string;
}

export interface FeedFlowLayout {
  entries: Array<FeedFlowEntry>;
  sections: Array<SectionOptions>;
  leadingCount: number;
  /** 分组间距，供签名比较使用（sections.margin 是联合类型，不便直接读取）。 */
  gap: number;
}

/** Full-width chrome and date headings are separate one-column sections. */
export function buildFeedFlowLayout(keys: Array<string>, dates: Array<string>, columns: number,
  leadingCount: number, loadingMore: boolean, gap: number): FeedFlowLayout {
  const entries: Array<FeedFlowEntry> = [];
  const groups: Array<SectionOptions> = [];
  if (leadingCount > 0) {
    groups.push({ itemsCount: leadingCount, crossCount: 1, rowsGap: gap });
  }
  let contentCount: number = 0;
  for (let index = 0; index < keys.length; index += 1) {
    const date: string = dates[index] ?? '';
    if (date.length > 0 && (index === 0 || date !== dates[index - 1])) {
      if (contentCount > 0) {
        groups.push({ itemsCount: contentCount, crossCount: columns, columnsGap: gap, rowsGap: gap });
        contentCount = 0;
      }
      entries.push({ key: `date:${date}`, itemIndex: index, date: date });
      groups.push({ itemsCount: 1, crossCount: 1 });
    }
    entries.push({ key: keys[index], itemIndex: index, date: '' });
    contentCount += 1;
  }
  if (contentCount > 0) {
    groups.push({ itemsCount: contentCount, crossCount: columns, columnsGap: gap, rowsGap: gap });
  }
  if (loadingMore) {
    groups.push({ itemsCount: 1, crossCount: 1 });
  }
  for (let index = 0; index < groups.length; index += 1) {
    // 首组不加顶部 margin：顶部让位改由真实的让位条目（第 0 个 FlowItem）承担，
    // 否则「按条目对齐」的回顶实现（系统点状态栏回顶、scrollToIndex）会跳过 margin，
    // 把首行卡片顶到屏幕最上沿、盖住标题栏。
    groups[index].margin = { top: index === 0 ? 0 : gap };
  }
  return { entries: entries, sections: groups, leadingCount: leadingCount, gap: gap };
}

/**
 * sections 变更签名：分组计数、列数或行列间距任一变化才需要 splice；
 * 仅宽度变化、布局未变时让框架自然重排，避免重复替换 sections。
 */
export function feedSectionSignature(layout: FeedFlowLayout): string {
  let signature: string = `gap:${layout.gap};`;
  for (let index = 0; index < layout.sections.length; index += 1) {
    const section: SectionOptions = layout.sections[index];
    signature += `${section.itemsCount}:${section.crossCount ?? 1}:${section.columnsGap ?? 0}:` +
      `${section.rowsGap ?? 0};`;
  }
  return signature;
}

/** Translate a visible FlowItem to its source index, excluding banners and footer. */
export function feedFlowItemIndex(layout: FeedFlowLayout, flowIndex: number): number {
  const index: number = flowIndex - layout.leadingCount;
  if (index < 0 || layout.entries.length === 0) {
    return -1;
  }
  return layout.entries[Math.min(index, layout.entries.length - 1)].itemIndex;
}

/**
 * 换列保位：把锚点内容索引映射回新布局的 FlowItem 索引。
 * 优先选锚点及其后最近的内容项（含紧邻的日期标题，使标题与内容同屏）；
 * 锚点被过滤或删除时自然落在相邻内容，列表为空时返回 -1（调用方回顶）。
 */
export function feedAnchorFlowIndex(layout: FeedFlowLayout, anchorItemIndex: number): number {
  if (anchorItemIndex < 0 || layout.entries.length === 0) {
    return -1;
  }
  let entryIndex: number = -1;
  for (let index = 0; index < layout.entries.length; index += 1) {
    if (layout.entries[index].itemIndex >= anchorItemIndex) {
      entryIndex = index;
      break;
    }
  }
  if (entryIndex < 0) {
    entryIndex = layout.entries.length - 1;
  }
  return entryIndex + layout.leadingCount;
}
