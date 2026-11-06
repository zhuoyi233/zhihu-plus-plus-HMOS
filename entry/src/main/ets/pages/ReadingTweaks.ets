/**
 * 阅读体验相关纯逻辑：滚动手感、切答过渡参数、新增设置项的选项与下标换算。
 * 不依赖 UI，可直接单测。
 */

import {
  AnswerSwitchStyle,
  decodeAnswerSwitchStyle,
  decodeHomeSearchBarStyle,
  decodePreloadCacheBudget,
  decodePreloadOptimization,
  decodeScrollFeelPreset,
  HomeSearchBarStyle,
  HOT_COMMENT_PREVIEW_DEFAULT,
  HOT_COMMENT_PREVIEW_MAX,
  HOT_COMMENT_PREVIEW_MIN,
  PreloadCacheBudget,
  PreloadOptimizationMode,
  ScrollFeelPreset
} from 'data';
/**
 * 正文滚动手感：把「跟手拖动」从系统默认的 1:1 位移，改为按手指速度渐变的比例。
 *
 * 系统默认滑动是线性的：无论快慢，手指移动多少正文就跟着移动多少，长正文里快速下滑容易
 * 一下滑过头、慢速微调又显得迟钝。这里给 List 的 onScrollFrameBegin 装一条缓出曲线：
 * 慢速拖动增益接近 1（保留精确控制），速度上来后增益升到该档位的上限（少滑几下就能翻过
 * 长段落）；每个档位同时给一个惯性摩擦系数，让松手后的滑行距离与档位名称一致。
 *
 * 只影响手指按住时的滚动量，松手后的惯性滚动仍由 List 自身的摩擦系数决定，避免在
 * onScrollFrameBegin 里二次放大惯性导致滑行失控。
 */

/** 手感档位参数。 */
export interface ScrollFeelProfile {
  /** List 惯性摩擦系数；0 表示沿用系统默认（文档约定 <=0 按默认处理）。 */
  readonly friction: number;
  /** 慢速拖动时的增益下限。 */
  readonly minGain: number;
  /** 快速拖动时的增益上限。 */
  readonly maxGain: number;
}

/** 速度参考值（vp/帧）：单帧位移到这个量级时增益到达上限。 */
export const SCROLL_FEEL_SPEED_REFERENCE_VP = 12;

const SYSTEM_PROFILE: ScrollFeelProfile = { friction: 0, minGain: 1, maxGain: 1 };
const MILD_PROFILE: ScrollFeelProfile = { friction: 0.72, minGain: 1, maxGain: 1.08 };
/** 标准 = 原「顺滑」参数：作为本版本基准手感。 */
const STANDARD_PROFILE: ScrollFeelProfile = { friction: 0.6, minGain: 1, maxGain: 1.18 };
const SWIFT_PROFILE: ScrollFeelProfile = { friction: 0.45, minGain: 1.05, maxGain: 1.4 };
const STEADY_PROFILE: ScrollFeelProfile = { friction: 1.05, minGain: 0.85, maxGain: 1.02 };
const EXTREME_PROFILE: ScrollFeelProfile = { friction: 0.35, minGain: 1.1, maxGain: 1.6 };

export function scrollFeelProfile(preset: ScrollFeelPreset): ScrollFeelProfile {
  switch (preset) {
    case ScrollFeelPreset.SYSTEM:
      return SYSTEM_PROFILE;
    case ScrollFeelPreset.MILD:
      return MILD_PROFILE;
    case ScrollFeelPreset.SWIFT:
      return SWIFT_PROFILE;
    case ScrollFeelPreset.EXTREME:
      return EXTREME_PROFILE;
    case ScrollFeelPreset.STEADY:
      return STEADY_PROFILE;
    default:
      return STANDARD_PROFILE;
  }
}

/** 缓出曲线：低速段变化平缓（微调不跳），速度过半后迅速贴近上限（快速滑动更跟手）。 */
function scrollFeelGainRatio(magnitudeVp: number): number {
  const ratio = Math.min(1, Math.max(0, magnitudeVp) / SCROLL_FEEL_SPEED_REFERENCE_VP);
  return ratio * (2 - ratio);
}

/**
 * 按档位把本帧位移换成实际位移：方向不变，只改幅度。
 *
 * @param profile 当前档位参数
 * @param offset 框架给出的本帧位移（vp，负值表示内容向下滚）
 */
export function scrollFeelAdjustedOffset(profile: ScrollFeelProfile, offset: number): number {
  if (offset === 0 || !Number.isFinite(offset)) {
    return offset;
  }
  const gain = profile.minGain + (profile.maxGain - profile.minGain) * scrollFeelGainRatio(Math.abs(offset));
  return offset * gain;
}

export function allScrollFeelPresets(): Array<ScrollFeelPreset> {
  return [ScrollFeelPreset.SYSTEM, ScrollFeelPreset.MILD, ScrollFeelPreset.SMOOTH, ScrollFeelPreset.SWIFT,
    ScrollFeelPreset.EXTREME, ScrollFeelPreset.STEADY];
}

export function scrollFeelPresetLabel(preset: ScrollFeelPreset): string {
  switch (preset) {
    case ScrollFeelPreset.SYSTEM:
      return '跟随系统';
    case ScrollFeelPreset.MILD:
      return '柔和';
    case ScrollFeelPreset.SWIFT:
      return '迅捷';
    case ScrollFeelPreset.EXTREME:
      return '极速';
    case ScrollFeelPreset.STEADY:
      return '沉稳';
    default:
      return '标准';
  }
}

export function scrollFeelPresetDescription(preset: ScrollFeelPreset): string {
  switch (preset) {
    case ScrollFeelPreset.SYSTEM:
      return '手指移动多少正文就滚动多少，松手后按系统默认惯性滑行';
    case ScrollFeelPreset.MILD:
      return '比标准更克制：跟手放大幅度小、惯性更短，适合习惯原生手感又要一点点加速度';
    case ScrollFeelPreset.SWIFT:
      return '快速下滑走得更远、惯性更长，适合长回答快速略读；慢速拖动仍保留控制力';
    case ScrollFeelPreset.EXTREME:
      return '比迅捷更激进：快速滑动最多放大到 1.6 倍、惯性最长，适合长文快速扫读';
    case ScrollFeelPreset.STEADY:
      return '整体收窄跟手比例、加快停下，适合长按选词与逐段精读';
    default:
      return '本版本的基准手感：慢速拖动更精细，快速滑动更跟手，松手后滑行距离略短于系统默认';
  }
}

export function scrollFeelPresetIndex(preset: ScrollFeelPreset): number {
  const presets = allScrollFeelPresets();
  for (let index = 0; index < presets.length; index++) {
    if (presets[index] === preset) {
      return index;
    }
  }
  return 2;
}


/**
 * 回答整页切换的过渡参数（纯函数，方便单测与复用）。
 *
 * 三种样式只改「位移比例 / 透明度 / 缩放 / 时长」，跟手判定、过阈值提交等交互逻辑仍在页面里：
 * - `slide`（默认）：整页按手指位移平移，与上游原有行为一致；
 * - `fade`：只保留 12% 位移，靠透明度交接，适合横向切换；
 * - `stack`：预览页从 0.92 放大到 1 并盖上当前页，当前页轻微后退。
 */

/** 位移跟手的过渡时长（ms）：与上游原有切答动画一致。 */
export const ANSWER_SWITCH_SLIDE_DURATION: number = 220;

/** 淡入淡出略短（不靠位移，观感更快）。 */
export const ANSWER_SWITCH_FADE_DURATION: number = 200;

/** 盖卡片略长（多了缩放，需要一点余量）。 */
export const ANSWER_SWITCH_STACK_DURATION: number = 260;

const FADE_TRAVEL_RATIO: number = 0.12;
const STACK_TRAVEL_RATIO: number = 0.55;

export function answerSwitchStyleValue(raw: string): AnswerSwitchStyle {
  return decodeAnswerSwitchStyle(raw);
}

export function answerSwitchDurationMs(style: AnswerSwitchStyle): number {
  if (style === AnswerSwitchStyle.STACK) {
    return ANSWER_SWITCH_STACK_DURATION;
  }
  return style === AnswerSwitchStyle.FADE ? ANSWER_SWITCH_FADE_DURATION : ANSWER_SWITCH_SLIDE_DURATION;
}

/** 预览页沿切换轴的实际位移：淡入淡出几乎不动，盖卡片只走一半多。 */
export function answerSwitchTranslate(style: AnswerSwitchStyle, horizontal: boolean, delta: number): TranslateOptions {
  const factor: number = style === AnswerSwitchStyle.FADE
    ? FADE_TRAVEL_RATIO
    : (style === AnswerSwitchStyle.STACK ? STACK_TRAVEL_RATIO : 1);
  const scaled: number = delta * factor;
  return horizontal ? { x: scaled, y: 0 } : { x: 0, y: scaled };
}

/** 跟手进度（0~1）：已过滑距离 / 一页跨度；跨度非法时按 0 处理。 */
export function answerSwitchProgressRatio(overscrollOffset: number, extent: number): number {
  const span: number = Math.max(1, extent);
  return Math.min(1, Math.abs(overscrollOffset) / span);
}

/** 盖卡片：当前页随进度轻微后退，预览页从 0.92 放大到 1。 */
export function answerSwitchPaneScale(style: AnswerSwitchStyle, displayed: boolean, progress: number): number {
  if (style !== AnswerSwitchStyle.STACK) {
    return 1;
  }
  return displayed ? 1 - 0.03 * progress : 0.92 + 0.08 * progress;
}

/** 淡入淡出：两页按进度交接透明度；非淡入淡出样式沿用「可见即 1」。 */
export function answerSwitchPaneOpacity(style: AnswerSwitchStyle, visible: boolean, displayed: boolean,
  progress: number): number {
  if (!visible) {
    return 0;
  }
  if (style !== AnswerSwitchStyle.FADE) {
    return 1;
  }
  return displayed ? Math.max(0.1, 1 - 0.9 * progress) : Math.min(1, 0.1 + 0.9 * progress);
}


/**
 * 新增阅读体验设置的「选项 / 文案 / 下标」纯映射。
 *
 * 设置页只负责摆放行（`selectSetting` 是页面内的 @Builder），文案与下标换算集中在这里：
 * 取值方向（raw → 展示）与写回方向（下标 → raw）成对出现，避免两边漂移。
 */

export const PRELOAD_OPTIMIZATION_DESCRIPTION: string =
  '开启后主页/热榜/回答/评论逐级预加载，当前答 ±1 及其评论常驻，返回上级不丢缓存；关闭则完全使用原有加载机制';

export const PRELOAD_CACHE_BUDGET_DESCRIPTION: string =
  '预加载内存缓存的上限；调小会立即按新配额回收，调大后随浏览逐步填充';

export const HOT_COMMENT_COUNT_DESCRIPTION: string =
  '回答底部展示的最高赞评论条数；点击热评标题或评论可进入完整评论';

export const ANSWER_SWITCH_STYLE_DESCRIPTION: string =
  '上下/左右切换回答时的整页过渡：位移跟手 / 淡入淡出 / 新页盖上并轻微缩放';

export const HOME_SEARCH_BAR_DESCRIPTION: string =
  '蓝细边白底对齐知乎官方首页；玻璃胶囊跟随顶部沉浸材质；深蓝实底为纯色条';

// ---- 正文滚动手感 ----

export function scrollFeelSelectDescription(raw: string): string {
  return scrollFeelPresetDescription(decodeScrollFeelPreset(raw));
}

export function scrollFeelSelectLabel(raw: string): string {
  return scrollFeelPresetLabel(decodeScrollFeelPreset(raw));
}

export function scrollFeelSelectOptions(): SelectOption[] {
  const presets: Array<ScrollFeelPreset> = allScrollFeelPresets();
  const options: SelectOption[] = [];
  for (let index = 0; index < presets.length; index += 1) {
    options.push({ value: scrollFeelPresetLabel(presets[index]) });
  }
  return options;
}

export function scrollFeelSelectIndex(raw: string): number {
  return scrollFeelPresetIndex(decodeScrollFeelPreset(raw));
}

export function scrollFeelPresetFromIndex(index: number): ScrollFeelPreset {
  const presets: Array<ScrollFeelPreset> = allScrollFeelPresets();
  return index >= 0 && index < presets.length ? presets[index] : ScrollFeelPreset.SMOOTH;
}

// ---- 热评条数 ----

export function hotCommentCountOptions(): SelectOption[] {
  const options: SelectOption[] = [];
  for (let count = HOT_COMMENT_PREVIEW_MIN; count <= HOT_COMMENT_PREVIEW_MAX; count += 1) {
    options.push({ value: `${count} 条` });
  }
  return options;
}

export function hotCommentCountLabel(count: number): string {
  return `${count} 条`;
}

export function hotCommentCountIndex(count: number): number {
  return Math.min(HOT_COMMENT_PREVIEW_MAX, Math.max(HOT_COMMENT_PREVIEW_MIN, count)) - HOT_COMMENT_PREVIEW_MIN;
}

export function hotCommentCountFromIndex(index: number): number {
  const count: number = HOT_COMMENT_PREVIEW_MIN + index;
  return Math.min(HOT_COMMENT_PREVIEW_MAX, Math.max(HOT_COMMENT_PREVIEW_MIN, count));
}

// ---- 切答动画样式 ----

const ANSWER_SWITCH_STYLES: Array<AnswerSwitchStyle> = [
  AnswerSwitchStyle.SLIDE, AnswerSwitchStyle.FADE, AnswerSwitchStyle.STACK
];

function answerSwitchStyleText(style: AnswerSwitchStyle): string {
  if (style === AnswerSwitchStyle.FADE) {
    return '淡入淡出';
  }
  return style === AnswerSwitchStyle.STACK ? '新页盖上' : '位移跟手';
}

export function answerSwitchStyleOptions(): SelectOption[] {
  return [{ value: answerSwitchStyleText(AnswerSwitchStyle.SLIDE) },
    { value: answerSwitchStyleText(AnswerSwitchStyle.FADE) },
    { value: answerSwitchStyleText(AnswerSwitchStyle.STACK) }];
}

export function answerSwitchStyleLabel(raw: string): string {
  return answerSwitchStyleText(decodeAnswerSwitchStyle(raw));
}

export function answerSwitchStyleIndex(raw: string): number {
  const style: AnswerSwitchStyle = decodeAnswerSwitchStyle(raw);
  const index: number = ANSWER_SWITCH_STYLES.indexOf(style);
  return index >= 0 ? index : 0;
}

export function answerSwitchStyleFromIndex(index: number): AnswerSwitchStyle {
  return index >= 0 && index < ANSWER_SWITCH_STYLES.length ? ANSWER_SWITCH_STYLES[index] : AnswerSwitchStyle.SLIDE;
}

// ---- 首页搜索栏样式 ----

const HOME_SEARCH_BAR_STYLES: Array<HomeSearchBarStyle> = [
  HomeSearchBarStyle.OUTLINED, HomeSearchBarStyle.GLASS, HomeSearchBarStyle.FILLED
];

function homeSearchBarStyleText(style: HomeSearchBarStyle): string {
  if (style === HomeSearchBarStyle.FILLED) {
    return '深蓝实底';
  }
  return style === HomeSearchBarStyle.GLASS ? '玻璃胶囊' : '蓝细边白底';
}

export function homeSearchBarStyleOptions(): SelectOption[] {
  return [{ value: homeSearchBarStyleText(HomeSearchBarStyle.OUTLINED) },
    { value: homeSearchBarStyleText(HomeSearchBarStyle.GLASS) },
    { value: homeSearchBarStyleText(HomeSearchBarStyle.FILLED) }];
}

export function homeSearchBarStyleLabel(raw: string): string {
  return homeSearchBarStyleText(decodeHomeSearchBarStyle(raw));
}

export function homeSearchBarStyleIndex(raw: string): number {
  const style: HomeSearchBarStyle = decodeHomeSearchBarStyle(raw);
  const index: number = HOME_SEARCH_BAR_STYLES.indexOf(style);
  return index >= 0 ? index : 0;
}

export function homeSearchBarStyleFromIndex(index: number): HomeSearchBarStyle {
  return index >= 0 && index < HOME_SEARCH_BAR_STYLES.length
    ? HOME_SEARCH_BAR_STYLES[index] : HomeSearchBarStyle.OUTLINED;
}

// ---- 预加载优化（两态） ----

export function preloadOptimizationOptions(): SelectOption[] {
  return [{ value: '关闭' }, { value: '开启' }];
}

export function preloadOptimizationLabel(raw: string): string {
  return decodePreloadOptimization(raw) === PreloadOptimizationMode.ON ? '开启' : '关闭';
}

export function preloadOptimizationIndex(raw: string): number {
  return decodePreloadOptimization(raw) === PreloadOptimizationMode.ON ? 1 : 0;
}

export function preloadOptimizationFromIndex(index: number): PreloadOptimizationMode {
  return index === 1 ? PreloadOptimizationMode.ON : PreloadOptimizationMode.OFF;
}

// ---- 预加载缓存预算（三档） ----

const PRELOAD_CACHE_BUDGETS: Array<PreloadCacheBudget> = [
  PreloadCacheBudget.SMALL, PreloadCacheBudget.MEDIUM, PreloadCacheBudget.LARGE
];

function preloadCacheBudgetText(budget: PreloadCacheBudget): string {
  if (budget === PreloadCacheBudget.MEDIUM) {
    return '2GB';
  }
  return budget === PreloadCacheBudget.LARGE ? '4GB' : '512MB';
}

export function preloadCacheBudgetOptions(): SelectOption[] {
  return [{ value: preloadCacheBudgetText(PreloadCacheBudget.SMALL) },
    { value: preloadCacheBudgetText(PreloadCacheBudget.MEDIUM) },
    { value: preloadCacheBudgetText(PreloadCacheBudget.LARGE) }];
}

export function preloadCacheBudgetLabel(raw: string): string {
  return preloadCacheBudgetText(decodePreloadCacheBudget(raw));
}

export function preloadCacheBudgetIndex(raw: string): number {
  const budget: PreloadCacheBudget = decodePreloadCacheBudget(raw);
  const index: number = PRELOAD_CACHE_BUDGETS.indexOf(budget);
  return index >= 0 ? index : 0;
}

export function preloadCacheBudgetFromIndex(index: number): PreloadCacheBudget {
  return index >= 0 && index < PRELOAD_CACHE_BUDGETS.length
    ? PRELOAD_CACHE_BUDGETS[index] : PreloadCacheBudget.SMALL;
}

