import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  BlockingPreferences,
  BlockingPreferencesGateway,
  defaultBlockingPreferences,
  normalizeBlockingPreferences
} from '../data/BlockingRuleStore';
import {
  defaultNotificationPreferences,
  NotificationKind,
  NotificationPreferences,
  NotificationSettingsGateway,
  normalizeNotificationPreferences
} from '../domain/NotificationModels';
import { JsonArrayValue, JsonStringValue, parseStrictJson } from 'core';
import {
  decodeQualityFilterMode,
  decodeRecommendationMode,
  defaultRecommendationFilterPreferences,
  HomeFeedStartupCacheGateway,
  normalizeRecommendationFilterPreferences,
  RecommendationFilterPreferences,
  RecommendationFilterPreferencesGateway,
  RecommendationMode
} from './RecommendationFilterPreferences';
import {
  defaultSpeechPreferences,
  normalizeSpeechPreferences,
  SpeechPreferences
} from './SpeechPreferences';

const PREFERENCES_NAME = 'app_preferences';
const THEME_MODE_KEY = 'theme_mode';
const KEYWORD_BLOCKING_KEY = 'enableKeywordBlocking';
const USER_BLOCKING_KEY = 'enableUserBlocking';
const TOPIC_BLOCKING_KEY = 'enableTopicBlocking';
const TOPIC_BLOCKING_THRESHOLD_KEY = 'topicBlockingThreshold';
const LEGACY_KEYWORD_BLOCKING_KEY = 'enable_keyword_blocking';
const LEGACY_USER_BLOCKING_KEY = 'enable_user_blocking';
const LEGACY_TOPIC_BLOCKING_KEY = 'enable_topic_blocking';
const LEGACY_TOPIC_BLOCKING_THRESHOLD_KEY = 'topic_blocking_threshold';
const NOTIFICATION_DISPLAY_PREFIX = 'notification_display_in_app_';
const NOTIFICATION_AUTO_MARK_READ_KEY = 'notification_auto_mark_as_read';
const NOTIFICATION_UNREAD_BADGE_KEY = 'notification_unread_badge';
// 键与存储值对齐上游 answerDoubleTapAction 偏好（"none"/"ask"/"voteUp"/"openComments"/"toggleImmersive"）。
const ANSWER_DOUBLE_TAP_ACTION_KEY = 'answerDoubleTapAction';
// 键与容量对齐上游搜索历史（searchHistoryQueries，最多 20 条）。
const SEARCH_HISTORY_KEY = 'searchHistoryQueries';
export const SEARCH_HISTORY_MAX_SIZE = 20;
// 键与语义对齐上游 UpdateManager.PREF_LAST_UPDATE_CHECK（自动检查更新节流时间戳，毫秒）。
const LAST_UPDATE_CHECK_KEY = 'lastUpdateCheck';
// 键与语义对齐上游 AppearanceSettingsScreen 的排版偏好（"阅读"分组，存 Int 百分比）。
const CONTENT_FONT_SIZE_KEY = 'contentFontSize';
const CONTENT_LINE_HEIGHT_KEY = 'contentLineHeight';
const CONTENT_BLOCK_SPACING_KEY = 'contentBlockSpacing';
const FAB_OPACITY_KEY = 'fabOpacity';
const SHOW_FEED_THUMBNAIL_KEY = 'showFeedThumbnail';
const SHOW_REFRESH_FAB_KEY = 'showRefreshFab';
const FEED_CARD_STYLE_KEY = 'feedCardStyle';
const DEVELOPER_MODE_KEY = 'developer';
const SPEECH_SPEED_KEY = 'readingSpeechSpeed';
const SPEECH_PITCH_KEY = 'readingSpeechPitch';
const SPEECH_PERSON_KEY = 'readingSpeechPerson';

export const DEFAULT_CONTENT_FONT_SIZE = 100;
export const DEFAULT_CONTENT_LINE_HEIGHT = 160;
export const DEFAULT_CONTENT_BLOCK_SPACING = 100;
/** 行高/段间距滑块边界与步进（对齐上游 Slider valueRange 与 steps）。 */
export const CONTENT_LINE_HEIGHT_MIN = 100;
export const CONTENT_LINE_HEIGHT_MAX = 300;
export const CONTENT_BLOCK_SPACING_MIN = 0;
export const CONTENT_BLOCK_SPACING_MAX = 300;
export const CONTENT_TYPOGRAPHY_STEP = 10;
export const DEFAULT_FAB_OPACITY = 100;

export enum FeedCardStyle {
  CARD = 'card',
  DIVIDER = 'divider'
}

export interface AppearancePreferences {
  fabOpacity: number;
  showFeedThumbnail: boolean;
  showRefreshFab: boolean;
  feedCardStyle: FeedCardStyle;
}

/** 可拖动悬浮按钮的位置，坐标以按钮左上角相对页面可视域的 vp 值保存。 */
export interface FabPosition {
  x: number;
  y: number;
}

export enum AnswerSwitchMode {
  OFF = 'off',
  VERTICAL = 'vertical',
  HORIZONTAL = 'horizontal'
}

export enum ShareActionMode {
  ASK = 'ask',
  COPY = 'copy',
  SHARE = 'share'
}

/** 上游外观页中不属于主题/排版/信息流的跨平台设置。 */
export interface ExperiencePreferences {
  titleAutoHide: boolean;
  autoHideArticleBottomBar: boolean;
  buttonSkipAnswer: boolean;
  autoHideSkipAnswerButton: boolean;
  pinAnswerDate: boolean;
  answerSwitchMode: AnswerSwitchMode;
  answerSwitchSensitivity: number;
  startDestination: string;
  bottomBarItems: string;
  tapToRefresh: boolean;
  autoHideBottomBar: boolean;
  volumeKeyPageTurn: boolean;
  pageTurnSwitchAnswer: boolean;
  showPageTurnFab: boolean;
  pageTurnPercent: number;
  showPageTurnGuide: boolean;
  showContentEndMarker: boolean;
  shareActionMode: ShareActionMode;
  showSearchHotSearch: boolean;
  showSearchHistory: boolean;
}

export function defaultExperiencePreferences(): ExperiencePreferences {
  return {
    titleAutoHide: false,
    autoHideArticleBottomBar: false,
    buttonSkipAnswer: true,
    autoHideSkipAnswerButton: true,
    pinAnswerDate: false,
    answerSwitchMode: AnswerSwitchMode.VERTICAL,
    answerSwitchSensitivity: 1,
    startDestination: 'Home',
    bottomBarItems: 'Home,Following,Hot,Daily,Settings',
    tapToRefresh: true,
    autoHideBottomBar: false,
    volumeKeyPageTurn: false,
    pageTurnSwitchAnswer: true,
    showPageTurnFab: false,
    pageTurnPercent: 90,
    showPageTurnGuide: false,
    showContentEndMarker: false,
    shareActionMode: ShareActionMode.ASK,
    showSearchHotSearch: true,
    showSearchHistory: true
  };
}

export function normalizeExperiencePreferences(value: ExperiencePreferences): ExperiencePreferences {
  const defaults = defaultExperiencePreferences();
  const answerSwitchMode = value.answerSwitchMode === AnswerSwitchMode.OFF ||
    value.answerSwitchMode === AnswerSwitchMode.HORIZONTAL ? value.answerSwitchMode : AnswerSwitchMode.VERTICAL;
  const shareActionMode = value.shareActionMode === ShareActionMode.COPY || value.shareActionMode === ShareActionMode.SHARE
    ? value.shareActionMode : ShareActionMode.ASK;
  const allowedDestinations = ['Home', 'Following', 'Hot', 'Daily', 'ReadHistory', 'Collections', 'Settings'];
  const normalizedBottomBarItems = normalizeBottomBarItems(value.bottomBarItems);
  return {
    titleAutoHide: value.titleAutoHide,
    autoHideArticleBottomBar: value.autoHideArticleBottomBar,
    buttonSkipAnswer: value.buttonSkipAnswer,
    autoHideSkipAnswerButton: value.autoHideSkipAnswerButton,
    pinAnswerDate: value.pinAnswerDate,
    answerSwitchMode: answerSwitchMode,
    answerSwitchSensitivity: Math.min(3, Math.max(0.5, Math.round(value.answerSwitchSensitivity * 10) / 10)),
    startDestination: allowedDestinations.includes(value.startDestination) &&
      normalizedBottomBarItems.split(',').includes(value.startDestination) ? value.startDestination : normalizedBottomBarItems.split(',')[0],
    bottomBarItems: normalizedBottomBarItems,
    tapToRefresh: value.tapToRefresh,
    autoHideBottomBar: value.autoHideBottomBar,
    volumeKeyPageTurn: value.volumeKeyPageTurn,
    pageTurnSwitchAnswer: value.pageTurnSwitchAnswer,
    showPageTurnFab: value.showPageTurnFab,
    pageTurnPercent: Math.min(100, Math.max(50, Math.round(value.pageTurnPercent / 5) * 5)),
    showPageTurnGuide: value.showPageTurnGuide,
    showContentEndMarker: value.showContentEndMarker,
    shareActionMode: shareActionMode,
    showSearchHotSearch: value.showSearchHotSearch,
    showSearchHistory: value.showSearchHistory
  };
}

export function normalizeBottomBarItems(value: string): string {
  const allowed = ['Home', 'Following', 'Hot', 'Daily', 'ReadHistory', 'Collections', 'Settings'];
  const result: string[] = [];
  value.split(',').forEach((key: string): void => {
    if (allowed.includes(key) && !result.includes(key) && result.length < 5) {
      result.push(key);
    }
  });
  if (!result.includes('Settings')) {
    if (result.length >= 5) result.pop();
    result.push('Settings');
  }
  const fill = ['Home', 'Following', 'Daily', 'Hot', 'ReadHistory', 'Collections'];
  fill.forEach((key: string): void => {
    if (result.length < 3 && !result.includes(key)) result.splice(Math.max(0, result.length - 1), 0, key);
  });
  return result.join(',');
}

export function defaultAppearancePreferences(): AppearancePreferences {
  return {
    fabOpacity: DEFAULT_FAB_OPACITY,
    showFeedThumbnail: true,
    showRefreshFab: true,
    feedCardStyle: FeedCardStyle.DIVIDER
  };
}

export function decodeFabOpacity(value: preferences.ValueType): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_FAB_OPACITY;
  }
  return Math.min(100, Math.max(10, Math.round(value / 5) * 5));
}

export function decodeFeedCardStyle(value: preferences.ValueType): FeedCardStyle {
  return value === FeedCardStyle.CARD ? FeedCardStyle.CARD : FeedCardStyle.DIVIDER;
}

export function normalizeAppearancePreferences(value: AppearancePreferences): AppearancePreferences {
  return {
    fabOpacity: decodeFabOpacity(value.fabOpacity),
    showFeedThumbnail: value.showFeedThumbnail,
    showRefreshFab: value.showRefreshFab,
    feedCardStyle: decodeFeedCardStyle(value.feedCardStyle)
  };
}

function notificationDisplayKey(kind: NotificationKind): string {
  if (kind === NotificationKind.LIKE_COMMENT) {
    return `${NOTIFICATION_DISPLAY_PREFIX}like_comment`;
  }
  if (kind === NotificationKind.REPLY_COMMENT) {
    return `${NOTIFICATION_DISPLAY_PREFIX}reply_comment`;
  }
  if (kind === NotificationKind.INVITE_ANSWER) {
    return `${NOTIFICATION_DISPLAY_PREFIX}invite_answer`;
  }
  return `${NOTIFICATION_DISPLAY_PREFIX}like_answer`;
}

export enum AppThemeMode {
  SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

export function decodeAppThemeMode(value: preferences.ValueType): AppThemeMode {
  if (value === AppThemeMode.LIGHT) {
    return AppThemeMode.LIGHT;
  }
  if (value === AppThemeMode.DARK) {
    return AppThemeMode.DARK;
  }
  return AppThemeMode.SYSTEM;
}

/** 回答页双击正文动作（对齐上游 AnswerDoubleTapAction），默认询问并记住。 */
export enum AnswerDoubleTapAction {
  NONE = 0,
  ASK = 1,
  VOTE_UP = 2,
  OPEN_COMMENTS = 3,
  TOGGLE_IMMERSIVE = 4
}

export function answerDoubleTapActionPreferenceValue(action: AnswerDoubleTapAction): string {
  switch (action) {
    case AnswerDoubleTapAction.NONE:
      return 'none';
    case AnswerDoubleTapAction.VOTE_UP:
      return 'voteUp';
    case AnswerDoubleTapAction.OPEN_COMMENTS:
      return 'openComments';
    case AnswerDoubleTapAction.TOGGLE_IMMERSIVE:
      return 'toggleImmersive';
    default:
      return 'ask';
  }
}

export function answerDoubleTapActionLabel(action: AnswerDoubleTapAction): string {
  switch (action) {
    case AnswerDoubleTapAction.NONE:
      return '无操作';
    case AnswerDoubleTapAction.ASK:
      return '询问并记住';
    case AnswerDoubleTapAction.VOTE_UP:
      return '点赞';
    case AnswerDoubleTapAction.OPEN_COMMENTS:
      return '打开评论区';
    case AnswerDoubleTapAction.TOGGLE_IMMERSIVE:
      return '开关沉浸式';
    default:
      return '询问并记住';
  }
}

/** 未知/缺失值一律回退 Ask（对齐上游 fromPreference）。 */
export function decodeAnswerDoubleTapAction(value: preferences.ValueType): AnswerDoubleTapAction {
  if (typeof value === 'string') {
    if (value === 'none') {
      return AnswerDoubleTapAction.NONE;
    }
    if (value === 'voteUp') {
      return AnswerDoubleTapAction.VOTE_UP;
    }
    if (value === 'openComments') {
      return AnswerDoubleTapAction.OPEN_COMMENTS;
    }
    if (value === 'toggleImmersive') {
      return AnswerDoubleTapAction.TOGGLE_IMMERSIVE;
    }
  }
  return AnswerDoubleTapAction.ASK;
}

export function allAnswerDoubleTapActions(): AnswerDoubleTapAction[] {
  return [
    AnswerDoubleTapAction.NONE,
    AnswerDoubleTapAction.ASK,
    AnswerDoubleTapAction.VOTE_UP,
    AnswerDoubleTapAction.OPEN_COMMENTS,
    AnswerDoubleTapAction.TOGGLE_IMMERSIVE
  ];
}

/** 正文排版偏好（三个 Int 百分比，语义与键名对齐上游 AppearanceSettingsScreen）。 */
export interface ReaderTypography {
  /** 字号百分比，档位见 contentFontSizeLevels()，默认 100。 */
  fontSize: number;
  /** 行高百分比，100..300 step 10，默认 160。 */
  lineHeight: number;
  /** 段间距百分比，0..300 step 10，默认 100。 */
  blockSpacing: number;
}

/**
 * 字号档位：`50..120 step 5` + `130..200 step 10`（无 125），共 23 档，
 * 对齐上游 `contentFontSizeLevels`。
 */
const CONTENT_FONT_SIZE_LEVELS: Array<number> = buildContentFontSizeLevels();

function buildContentFontSizeLevels(): Array<number> {
  const levels: Array<number> = [];
  let value = 50;
  while (value <= 120) {
    levels.push(value);
    value += 5;
  }
  value = 130;
  while (value <= 200) {
    levels.push(value);
    value += 10;
  }
  return levels;
}

export function contentFontSizeLevels(): Array<number> {
  return CONTENT_FONT_SIZE_LEVELS.slice();
}

export function defaultReaderTypography(): ReaderTypography {
  return {
    fontSize: DEFAULT_CONTENT_FONT_SIZE,
    lineHeight: DEFAULT_CONTENT_LINE_HEIGHT,
    blockSpacing: DEFAULT_CONTENT_BLOCK_SPACING
  };
}

/** 吸附到最近档位；距离相同时取较小档（对齐上游 `minBy { abs(it - value) }` 的首个最小项）。 */
function nearestContentFontSizeLevel(value: number): number {
  const lastIndex = CONTENT_FONT_SIZE_LEVELS.length - 1;
  const bounded = Math.min(CONTENT_FONT_SIZE_LEVELS[lastIndex],
    Math.max(CONTENT_FONT_SIZE_LEVELS[0], value));
  let best = CONTENT_FONT_SIZE_LEVELS[0];
  let bestDistance = Math.abs(bounded - best);
  for (let index = 1; index <= lastIndex; index += 1) {
    const distance = Math.abs(bounded - CONTENT_FONT_SIZE_LEVELS[index]);
    if (distance < bestDistance) {
      best = CONTENT_FONT_SIZE_LEVELS[index];
      bestDistance = distance;
    }
  }
  return best;
}

function snapToStep(value: number, min: number, max: number, step: number): number {
  return Math.min(max, Math.max(min, Math.round(value / step) * step));
}

/** 非数字 → 100；否则 clamp 到档位区间后吸附最近档（对齐上游"读取即吸附并回写"）。 */
export function decodeContentFontSize(value: preferences.ValueType): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_CONTENT_FONT_SIZE;
  }
  return nearestContentFontSizeLevel(value);
}

/** 非数字 → 160；否则按 10 一档吸附并 clamp 到 100..300。 */
export function decodeContentLineHeight(value: preferences.ValueType): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_CONTENT_LINE_HEIGHT;
  }
  return snapToStep(value, CONTENT_LINE_HEIGHT_MIN, CONTENT_LINE_HEIGHT_MAX, CONTENT_TYPOGRAPHY_STEP);
}

/** 非数字 → 100；否则按 10 一档吸附并 clamp 到 0..300。 */
export function decodeContentBlockSpacing(value: preferences.ValueType): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_CONTENT_BLOCK_SPACING;
  }
  return snapToStep(value, CONTENT_BLOCK_SPACING_MIN, CONTENT_BLOCK_SPACING_MAX, CONTENT_TYPOGRAPHY_STEP);
}

/** 三值分别按各自语义吸附/回退；落盘与 AppStorage 广播前统一走这里。 */
export function normalizeReaderTypography(value: ReaderTypography): ReaderTypography {
  return {
    fontSize: decodeContentFontSize(value.fontSize),
    lineHeight: decodeContentLineHeight(value.lineHeight),
    blockSpacing: decodeContentBlockSpacing(value.blockSpacing)
  };
}

export function appPreferencesFailureMessage(operation: string, error: Object | null | undefined): string {
  if (error instanceof Error) {
    if (error.message.trim().length > 0) {
      return `${operation} failed: ${error.message}`;
    }
  }
  return `${operation} failed`;
}

/** 解析历史 JSON（字符串数组）；损坏内容静默丢弃，最多保留 SEARCH_HISTORY_MAX_SIZE 条。 */
function decodeSearchHistory(value: string): Array<string> {
  let parsed: Object;
  try {
    parsed = parseStrictJson(value);
  } catch (_error) {
    return [];
  }
  if (!(parsed instanceof JsonArrayValue)) {
    return [];
  }
  const items: Array<string> = [];
  parsed.items.forEach((item: Object): void => {
    if (item instanceof JsonStringValue) {
      const text = item.value.trim();
      if (text.length > 0 && !items.includes(text)) {
        items.push(text);
      }
    }
  });
  return items.slice(0, SEARCH_HISTORY_MAX_SIZE);
}

function normalizeSearchHistory(history: Array<string>): Array<string> {
  const items: Array<string> = [];
  history.forEach((item: string): void => {
    const text = item.trim();
    if (text.length > 0 && text.length <= 200 && !items.includes(text)) {
      items.push(text);
    }
  });
  return items.slice(0, SEARCH_HISTORY_MAX_SIZE);
}

export class AppPreferencesStore implements BlockingPreferencesGateway, NotificationSettingsGateway,
  RecommendationFilterPreferencesGateway, HomeFeedStartupCacheGateway {
  private readonly context: common.Context;
  private saveQueue: Promise<void> = Promise.resolve();

  constructor(context: common.Context) {
    this.context = context;
  }

  async loadDeveloperMode(): Promise<boolean> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const value = await store.get(DEVELOPER_MODE_KEY, false);
      return typeof value === 'boolean' ? value : false;
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Developer mode load', detail));
    }
  }

  saveDeveloperMode(enabled: boolean): Promise<void> {
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeDeveloperMode(enabled),
      (): Promise<void> => this.writeDeveloperMode(enabled)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeDeveloperMode(enabled: boolean): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(DEVELOPER_MODE_KEY, enabled);
      await store.flush();
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Developer mode save', detail));
    }
  }

  async loadSpeechPreferences(): Promise<SpeechPreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultSpeechPreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const speed = await store.get(SPEECH_SPEED_KEY, defaults.speed);
      const pitch = await store.get(SPEECH_PITCH_KEY, defaults.pitch);
      const person = await store.get(SPEECH_PERSON_KEY, defaults.person);
      return normalizeSpeechPreferences({
        speed: typeof speed === 'number' ? speed : defaults.speed,
        pitch: typeof pitch === 'number' ? pitch : defaults.pitch,
        person: typeof person === 'number' ? person : defaults.person
      });
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Speech preferences load', detail));
    }
  }

  saveSpeechPreferences(value: SpeechPreferences): Promise<void> {
    const normalized = normalizeSpeechPreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeSpeechPreferences(normalized),
      (): Promise<void> => this.writeSpeechPreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeSpeechPreferences(value: SpeechPreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(SPEECH_SPEED_KEY, value.speed);
      await store.put(SPEECH_PITCH_KEY, value.pitch);
      await store.put(SPEECH_PERSON_KEY, value.person);
      await store.flush();
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Speech preferences save', detail));
    }
  }

  async loadThemeMode(): Promise<AppThemeMode> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      return decodeAppThemeMode(await store.get(THEME_MODE_KEY, AppThemeMode.SYSTEM));
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Theme mode load', error));
      }
      throw new Error(appPreferencesFailureMessage('Theme mode load', undefined));
    }
  }

  saveThemeMode(mode: AppThemeMode): Promise<void> {
    const normalizedMode = decodeAppThemeMode(mode);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeThemeMode(normalizedMode),
      (): Promise<void> => this.writeThemeMode(normalizedMode)
    );
    this.saveQueue = operation.then(
      (): void => {},
      (): void => {}
    );
    return operation;
  }

  async loadAnswerDoubleTapAction(): Promise<AnswerDoubleTapAction> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      return decodeAnswerDoubleTapAction(await store.get(ANSWER_DOUBLE_TAP_ACTION_KEY,
        answerDoubleTapActionPreferenceValue(AnswerDoubleTapAction.ASK)));
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Answer double tap action load', error));
      }
      throw new Error(appPreferencesFailureMessage('Answer double tap action load', undefined));
    }
  }

  saveAnswerDoubleTapAction(action: AnswerDoubleTapAction): Promise<void> {
    const normalizedAction = decodeAnswerDoubleTapAction(answerDoubleTapActionPreferenceValue(action));
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeAnswerDoubleTapAction(normalizedAction),
      (): Promise<void> => this.writeAnswerDoubleTapAction(normalizedAction)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async loadSearchHistory(): Promise<Array<string>> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const value = await store.get(SEARCH_HISTORY_KEY, '[]');
      if (typeof value !== 'string') {
        return [];
      }
      return decodeSearchHistory(value);
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Search history load', error));
      }
      throw new Error(appPreferencesFailureMessage('Search history load', undefined));
    }
  }

  saveSearchHistory(history: Array<string>): Promise<void> {
    const normalized = normalizeSearchHistory(history);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeSearchHistory(normalized),
      (): Promise<void> => this.writeSearchHistory(normalized)
    );
    this.saveQueue = operation.then((): void => {
    }, (): void => {
    });
    return operation;
  }

  private async writeSearchHistory(history: Array<string>): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(SEARCH_HISTORY_KEY, JSON.stringify(history));
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Search history save', error));
      }
      throw new Error(appPreferencesFailureMessage('Search history save', undefined));
    }
  }

  async loadLastUpdateCheckAt(): Promise<number> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const value = await store.get(LAST_UPDATE_CHECK_KEY, 0);
      return typeof value === 'number' ? value : 0;
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Last update check load', error));
      }
      throw new Error(appPreferencesFailureMessage('Last update check load', undefined));
    }
  }

  saveLastUpdateCheckAt(tick: number): Promise<void> {
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeLastUpdateCheckAt(tick),
      (): Promise<void> => this.writeLastUpdateCheckAt(tick)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeLastUpdateCheckAt(tick: number): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(LAST_UPDATE_CHECK_KEY, tick);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Last update check save', error));
      }
      throw new Error(appPreferencesFailureMessage('Last update check save', undefined));
    }
  }

  async loadBlockingPreferences(): Promise<BlockingPreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultBlockingPreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const legacyKeyword = await store.get(LEGACY_KEYWORD_BLOCKING_KEY, defaults.keywordBlockingEnabled);
      const legacyUser = await store.get(LEGACY_USER_BLOCKING_KEY, defaults.userBlockingEnabled);
      const legacyTopic = await store.get(LEGACY_TOPIC_BLOCKING_KEY, defaults.topicBlockingEnabled);
      const legacyThreshold = await store.get(LEGACY_TOPIC_BLOCKING_THRESHOLD_KEY, defaults.topicBlockingThreshold);
      const keywordEnabled = await store.get(KEYWORD_BLOCKING_KEY, legacyKeyword);
      const userEnabled = await store.get(USER_BLOCKING_KEY, legacyUser);
      const topicEnabled = await store.get(TOPIC_BLOCKING_KEY, legacyTopic);
      const threshold = await store.get(TOPIC_BLOCKING_THRESHOLD_KEY, legacyThreshold);
      return normalizeBlockingPreferences({
        keywordBlockingEnabled: typeof keywordEnabled === 'boolean' ? keywordEnabled : true,
        userBlockingEnabled: typeof userEnabled === 'boolean' ? userEnabled : true,
        topicBlockingEnabled: typeof topicEnabled === 'boolean' ? topicEnabled : true,
        topicBlockingThreshold: typeof threshold === 'number' ? threshold : 1
      });
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Blocking preferences load', error));
      }
      throw new Error(appPreferencesFailureMessage('Blocking preferences load', undefined));
    }
  }

  saveBlockingPreferences(value: BlockingPreferences): Promise<void> {
    const normalized = normalizeBlockingPreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeBlockingPreferences(normalized),
      (): Promise<void> => this.writeBlockingPreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async loadRecommendationFilterPreferences(): Promise<RecommendationFilterPreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultRecommendationFilterPreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const readBoolean = async (key: string, fallback: boolean): Promise<boolean> => {
        const value = await store.get(key, fallback);
        return typeof value === 'boolean' ? value : fallback;
      };
      const readNumber = async (key: string, fallback: number): Promise<number> => {
        const value = await store.get(key, fallback);
        return typeof value === 'number' ? value : fallback;
      };
      const recommendationMode = await store.get('recommendationMode', defaults.recommendationMode);
      const qualityFilterMode = await store.get('qualityFilterMode', defaults.qualityFilterMode);
      return normalizeRecommendationFilterPreferences({
        recommendationMode: decodeRecommendationMode(typeof recommendationMode === 'string' ? recommendationMode : ''),
        loginForRecommendation: await readBoolean('loginForRecommendation', defaults.loginForRecommendation),
        autoRefreshHomeOnStartup: await readBoolean('autoRefreshHomeOnStartup', defaults.autoRefreshHomeOnStartup),
        qualityFilterMode: decodeQualityFilterMode(typeof qualityFilterMode === 'string' ? qualityFilterMode : ''),
        answerVoteupThreshold: await readNumber('answerVoteupThreshold', defaults.answerVoteupThreshold),
        articleVoteupThreshold: await readNumber('articleVoteupThreshold', defaults.articleVoteupThreshold),
        articleFollowersThreshold: await readNumber('articleFollowersThreshold', defaults.articleFollowersThreshold),
        videoVoteThreshold: await readNumber('videoVoteThreshold', defaults.videoVoteThreshold),
        videoFollowersThreshold: await readNumber('videoFollowersThreshold', defaults.videoFollowersThreshold),
        questionAnswerThreshold: await readNumber('questionAnswerThreshold', defaults.questionAnswerThreshold),
        questionFollowersThreshold: await readNumber('questionFollowersThreshold', defaults.questionFollowersThreshold),
        enableContentFilter: await readBoolean('enableContentFilter', defaults.enableContentFilter),
        filterFollowedUserContent: await readBoolean('filterFollowedUserContent', defaults.filterFollowedUserContent),
        blockZhihuAdPlatform: await readBoolean('blockZhihuAdPlatform', defaults.blockZhihuAdPlatform),
        blockZhihuSchool: await readBoolean('blockZhihuSchool', defaults.blockZhihuSchool),
        blockWeChatOfficialAccount: await readBoolean('blockWeChatOfficialAccount', defaults.blockWeChatOfficialAccount),
        blockPaidContent: await readBoolean('blockPaidContent', defaults.blockPaidContent),
        reverseBlock: await readBoolean('reverseBlock', defaults.reverseBlock)
      });
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Recommendation filter preferences load', detail));
    }
  }

  saveRecommendationFilterPreferences(value: RecommendationFilterPreferences): Promise<void> {
    const normalized = normalizeRecommendationFilterPreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeRecommendationFilterPreferences(normalized),
      (): Promise<void> => this.writeRecommendationFilterPreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async loadHomeFeedStartupResponse(mode: RecommendationMode): Promise<string | undefined> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const value = await store.get(`homeFeedStartupCache_${mode}`, '');
      return typeof value === 'string' && value.length > 0 ? value : undefined;
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Home feed startup cache load', detail));
    }
  }

  saveHomeFeedStartupResponse(mode: RecommendationMode, response: string): Promise<void> {
    const operation = this.saveQueue.then(async (): Promise<void> => {
      try {
        const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
        await store.put(`homeFeedStartupCache_${mode}`, response);
        await store.flush();
      } catch (error) {
        const detail = error instanceof Error ? error : undefined;
        throw new Error(appPreferencesFailureMessage('Home feed startup cache save', detail));
      }
    });
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeThemeMode(mode: AppThemeMode): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(THEME_MODE_KEY, mode);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Theme mode save', error));
      }
      throw new Error(appPreferencesFailureMessage('Theme mode save', undefined));
    }
  }

  private async writeAnswerDoubleTapAction(action: AnswerDoubleTapAction): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(ANSWER_DOUBLE_TAP_ACTION_KEY, answerDoubleTapActionPreferenceValue(action));
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Answer double tap action save', error));
      }
      throw new Error(appPreferencesFailureMessage('Answer double tap action save', undefined));
    }
  }

  /** 一次读三个排版偏好，减少 getPreferences 往返；损坏/缺失值按各自默认值回退。 */
  async loadReaderTypography(): Promise<ReaderTypography> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const fontSize = await store.get(CONTENT_FONT_SIZE_KEY, DEFAULT_CONTENT_FONT_SIZE);
      const lineHeight = await store.get(CONTENT_LINE_HEIGHT_KEY, DEFAULT_CONTENT_LINE_HEIGHT);
      const blockSpacing = await store.get(CONTENT_BLOCK_SPACING_KEY, DEFAULT_CONTENT_BLOCK_SPACING);
      return normalizeReaderTypography({
        fontSize: decodeContentFontSize(fontSize),
        lineHeight: decodeContentLineHeight(lineHeight),
        blockSpacing: decodeContentBlockSpacing(blockSpacing)
      });
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Reader typography load', error));
      }
      throw new Error(appPreferencesFailureMessage('Reader typography load', undefined));
    }
  }

  saveReaderTypography(value: ReaderTypography): Promise<void> {
    const normalized = normalizeReaderTypography(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeReaderTypography(normalized),
      (): Promise<void> => this.writeReaderTypography(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeReaderTypography(value: ReaderTypography): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(CONTENT_FONT_SIZE_KEY, value.fontSize);
      await store.put(CONTENT_LINE_HEIGHT_KEY, value.lineHeight);
      await store.put(CONTENT_BLOCK_SPACING_KEY, value.blockSpacing);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Reader typography save', error));
      }
      throw new Error(appPreferencesFailureMessage('Reader typography save', undefined));
    }
  }

  async loadAppearancePreferences(): Promise<AppearancePreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultAppearancePreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const fabOpacity = await store.get(FAB_OPACITY_KEY, defaults.fabOpacity);
      const showFeedThumbnail = await store.get(SHOW_FEED_THUMBNAIL_KEY, defaults.showFeedThumbnail);
      const showRefreshFab = await store.get(SHOW_REFRESH_FAB_KEY, defaults.showRefreshFab);
      const feedCardStyle = await store.get(FEED_CARD_STYLE_KEY, defaults.feedCardStyle);
      return normalizeAppearancePreferences({
        fabOpacity: decodeFabOpacity(fabOpacity),
        showFeedThumbnail: typeof showFeedThumbnail === 'boolean' ? showFeedThumbnail : defaults.showFeedThumbnail,
        showRefreshFab: typeof showRefreshFab === 'boolean' ? showRefreshFab : defaults.showRefreshFab,
        feedCardStyle: decodeFeedCardStyle(feedCardStyle)
      });
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Appearance preferences load', error));
      }
      throw new Error(appPreferencesFailureMessage('Appearance preferences load', undefined));
    }
  }

  saveAppearancePreferences(value: AppearancePreferences): Promise<void> {
    const normalized = normalizeAppearancePreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeAppearancePreferences(normalized),
      (): Promise<void> => this.writeAppearancePreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  /** 读取与上游 DraggableRefreshButton 相同的 `<name>-x/y` 位置键。 */
  async loadFabPosition(preferenceName: string): Promise<FabPosition | undefined> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const x = await store.get(`${preferenceName}-x`, Number.NaN);
      const y = await store.get(`${preferenceName}-y`, Number.NaN);
      if (typeof x !== 'number' || !Number.isFinite(x) || typeof y !== 'number' || !Number.isFinite(y)) {
        return undefined;
      }
      const position: FabPosition = { x: x, y: y };
      return position;
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('FAB position load', error));
      }
      throw new Error(appPreferencesFailureMessage('FAB position load', undefined));
    }
  }

  saveFabPosition(preferenceName: string, value: FabPosition): Promise<void> {
    const position: FabPosition = { x: value.x, y: value.y };
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeFabPosition(preferenceName, position),
      (): Promise<void> => this.writeFabPosition(preferenceName, position)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeFabPosition(preferenceName: string, value: FabPosition): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(`${preferenceName}-x`, value.x);
      await store.put(`${preferenceName}-y`, value.y);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('FAB position save', error));
      }
      throw new Error(appPreferencesFailureMessage('FAB position save', undefined));
    }
  }

  private async writeAppearancePreferences(value: AppearancePreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(FAB_OPACITY_KEY, value.fabOpacity);
      await store.put(SHOW_FEED_THUMBNAIL_KEY, value.showFeedThumbnail);
      await store.put(SHOW_REFRESH_FAB_KEY, value.showRefreshFab);
      await store.put(FEED_CARD_STYLE_KEY, value.feedCardStyle);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Appearance preferences save', error));
      }
      throw new Error(appPreferencesFailureMessage('Appearance preferences save', undefined));
    }
  }

  async loadExperiencePreferences(): Promise<ExperiencePreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultExperiencePreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const readBoolean = async (key: string, fallback: boolean): Promise<boolean> => {
        const value = await store.get(key, fallback);
        return typeof value === 'boolean' ? value : fallback;
      };
      const readNumber = async (key: string, fallback: number): Promise<number> => {
        const value = await store.get(key, fallback);
        return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
      };
      const readString = async (key: string, fallback: string): Promise<string> => {
        const value = await store.get(key, fallback);
        return typeof value === 'string' ? value : fallback;
      };
      return normalizeExperiencePreferences({
        titleAutoHide: await readBoolean('titleAutoHide', defaults.titleAutoHide),
        autoHideArticleBottomBar: await readBoolean('autoHideArticleBottomBar', defaults.autoHideArticleBottomBar),
        buttonSkipAnswer: await readBoolean('buttonSkipAnswer', defaults.buttonSkipAnswer),
        autoHideSkipAnswerButton: await readBoolean('autoHideSkipAnswerButton', defaults.autoHideSkipAnswerButton),
        pinAnswerDate: await readBoolean('pinAnswerDate', defaults.pinAnswerDate),
        answerSwitchMode: await readString('answerSwitchMode', defaults.answerSwitchMode) as AnswerSwitchMode,
        answerSwitchSensitivity: await readNumber('answerSwitchSensitivity', defaults.answerSwitchSensitivity),
        startDestination: await readString('startDestination', defaults.startDestination),
        bottomBarItems: await readString('bottom_bar_item_order', defaults.bottomBarItems),
        tapToRefresh: await readBoolean('tapToRefresh', defaults.tapToRefresh),
        autoHideBottomBar: await readBoolean('autoHideBottomBar', defaults.autoHideBottomBar),
        volumeKeyPageTurn: await readBoolean('volumeKeyPageTurn', defaults.volumeKeyPageTurn),
        pageTurnSwitchAnswer: await readBoolean('pageTurnSwitchAnswer', defaults.pageTurnSwitchAnswer),
        showPageTurnFab: await readBoolean('showPageTurnFab', defaults.showPageTurnFab),
        pageTurnPercent: await readNumber('pageTurnPercent', defaults.pageTurnPercent),
        showPageTurnGuide: await readBoolean('showPageTurnGuide', defaults.showPageTurnGuide),
        showContentEndMarker: await readBoolean('showContentEndMarker', defaults.showContentEndMarker),
        shareActionMode: await readString('shareActionMode', defaults.shareActionMode) as ShareActionMode,
        showSearchHotSearch: await readBoolean('showSearchHotSearch', defaults.showSearchHotSearch),
        showSearchHistory: await readBoolean('showSearchHistory', defaults.showSearchHistory)
      });
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Experience preferences load', error));
      }
      throw new Error(appPreferencesFailureMessage('Experience preferences load', undefined));
    }
  }

  saveExperiencePreferences(value: ExperiencePreferences): Promise<void> {
    const normalized = normalizeExperiencePreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeExperiencePreferences(normalized),
      (): Promise<void> => this.writeExperiencePreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeExperiencePreferences(value: ExperiencePreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put('titleAutoHide', value.titleAutoHide);
      await store.put('autoHideArticleBottomBar', value.autoHideArticleBottomBar);
      await store.put('buttonSkipAnswer', value.buttonSkipAnswer);
      await store.put('autoHideSkipAnswerButton', value.autoHideSkipAnswerButton);
      await store.put('pinAnswerDate', value.pinAnswerDate);
      await store.put('answerSwitchMode', value.answerSwitchMode);
      await store.put('answerSwitchSensitivity', value.answerSwitchSensitivity);
      await store.put('startDestination', value.startDestination);
      await store.put('bottom_bar_item_order', value.bottomBarItems);
      await store.put('tapToRefresh', value.tapToRefresh);
      await store.put('autoHideBottomBar', value.autoHideBottomBar);
      await store.put('volumeKeyPageTurn', value.volumeKeyPageTurn);
      await store.put('pageTurnSwitchAnswer', value.pageTurnSwitchAnswer);
      await store.put('showPageTurnFab', value.showPageTurnFab);
      await store.put('pageTurnPercent', value.pageTurnPercent);
      await store.put('showPageTurnGuide', value.showPageTurnGuide);
      await store.put('showContentEndMarker', value.showContentEndMarker);
      await store.put('shareActionMode', value.shareActionMode);
      await store.put('showSearchHotSearch', value.showSearchHotSearch);
      await store.put('showSearchHistory', value.showSearchHistory);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Experience preferences save', error));
      }
      throw new Error(appPreferencesFailureMessage('Experience preferences save', undefined));
    }
  }

  private async writeBlockingPreferences(value: BlockingPreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(KEYWORD_BLOCKING_KEY, value.keywordBlockingEnabled);
      await store.put(USER_BLOCKING_KEY, value.userBlockingEnabled);
      await store.put(TOPIC_BLOCKING_KEY, value.topicBlockingEnabled);
      await store.put(TOPIC_BLOCKING_THRESHOLD_KEY, value.topicBlockingThreshold);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Blocking preferences save', error));
      }
      throw new Error(appPreferencesFailureMessage('Blocking preferences save', undefined));
    }
  }

  private async writeRecommendationFilterPreferences(value: RecommendationFilterPreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put('recommendationMode', value.recommendationMode);
      await store.put('loginForRecommendation', value.loginForRecommendation);
      await store.put('autoRefreshHomeOnStartup', value.autoRefreshHomeOnStartup);
      await store.put('qualityFilterMode', value.qualityFilterMode);
      await store.put('answerVoteupThreshold', value.answerVoteupThreshold);
      await store.put('articleVoteupThreshold', value.articleVoteupThreshold);
      await store.put('articleFollowersThreshold', value.articleFollowersThreshold);
      await store.put('videoVoteThreshold', value.videoVoteThreshold);
      await store.put('videoFollowersThreshold', value.videoFollowersThreshold);
      await store.put('questionAnswerThreshold', value.questionAnswerThreshold);
      await store.put('questionFollowersThreshold', value.questionFollowersThreshold);
      await store.put('enableContentFilter', value.enableContentFilter);
      await store.put('filterFollowedUserContent', value.filterFollowedUserContent);
      await store.put('blockZhihuAdPlatform', value.blockZhihuAdPlatform);
      await store.put('blockZhihuSchool', value.blockZhihuSchool);
      await store.put('blockWeChatOfficialAccount', value.blockWeChatOfficialAccount);
      await store.put('blockPaidContent', value.blockPaidContent);
      await store.put('reverseBlock', value.reverseBlock);
      await store.flush();
    } catch (error) {
      const detail = error instanceof Error ? error : undefined;
      throw new Error(appPreferencesFailureMessage('Recommendation filter preferences save', detail));
    }
  }

  async loadNotificationPreferences(): Promise<NotificationPreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultNotificationPreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const readBoolean = async (key: string, fallback: boolean): Promise<boolean> => {
        const value = await store.get(key, fallback);
        return typeof value === 'boolean' ? value : fallback;
      };
      const raw: NotificationPreferences = {
        likeAnswerDisplay: await readBoolean(notificationDisplayKey(NotificationKind.LIKE_ANSWER),
          defaults.likeAnswerDisplay),
        likeCommentDisplay: await readBoolean(notificationDisplayKey(NotificationKind.LIKE_COMMENT),
          defaults.likeCommentDisplay),
        replyCommentDisplay: await readBoolean(notificationDisplayKey(NotificationKind.REPLY_COMMENT),
          defaults.replyCommentDisplay),
        inviteAnswerDisplay: await readBoolean(notificationDisplayKey(NotificationKind.INVITE_ANSWER),
          defaults.inviteAnswerDisplay),
        autoMarkAsRead: await readBoolean(NOTIFICATION_AUTO_MARK_READ_KEY, defaults.autoMarkAsRead),
        unreadBadge: await readBoolean(NOTIFICATION_UNREAD_BADGE_KEY, defaults.unreadBadge)
      };
      return normalizeNotificationPreferences(raw);
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Notification preferences load', error));
      }
      throw new Error(appPreferencesFailureMessage('Notification preferences load', undefined));
    }
  }

  saveNotificationPreferences(value: NotificationPreferences): Promise<void> {
    const normalized = normalizeNotificationPreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeNotificationPreferences(normalized),
      (): Promise<void> => this.writeNotificationPreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeNotificationPreferences(value: NotificationPreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(notificationDisplayKey(NotificationKind.LIKE_ANSWER), value.likeAnswerDisplay);
      await store.put(notificationDisplayKey(NotificationKind.LIKE_COMMENT), value.likeCommentDisplay);
      await store.put(notificationDisplayKey(NotificationKind.REPLY_COMMENT), value.replyCommentDisplay);
      await store.put(notificationDisplayKey(NotificationKind.INVITE_ANSWER), value.inviteAnswerDisplay);
      await store.put(NOTIFICATION_AUTO_MARK_READ_KEY, value.autoMarkAsRead);
      await store.put(NOTIFICATION_UNREAD_BADGE_KEY, value.unreadBadge);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Notification preferences save', error));
      }
      throw new Error(appPreferencesFailureMessage('Notification preferences save', undefined));
    }
  }
}
