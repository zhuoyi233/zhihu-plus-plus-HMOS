/**
 * 设置搜索目标的中立类型定义。
 *
 * 索引（SettingsSearchIndex）、导航（SettingsNavigationState）与定位运行时
 * 都从这里取类型，避免“索引 → 导航 → 索引”的循环依赖。
 * SettingsPaneId 原先定义在 SettingsNavigationState，现迁移到这里并由其重新导出，
 * 既有 `import { SettingsPaneId } from './SettingsNavigationState'` 写法继续有效。
 */

/** 设置容器内部的详情 pane。NONE 表示目录（无详情）。 */
export enum SettingsPaneId {
  NONE = 'none',
  IDENTITY = 'identity',
  APPEARANCE = 'appearance',
  THEME_COLOR = 'theme_color',
  READING = 'reading',
  FILTER = 'filter',
  BLOCKING_RULES = 'blocking_rules',
  BLOCKED_HISTORY = 'blocked_history',
  NOTIFICATION = 'notification',
  SYSTEM_UPDATE = 'system_update',
  ABOUT = 'about',
  DEVELOPER = 'developer'
}

/** 搜索结果的目标种类：具体设置项、分类入口或外部导航入口。 */
export enum SettingsTargetKind {
  SETTING_ITEM = 'setting_item',
  CATEGORY = 'category',
  EXTERNAL = 'external'
}

/**
 * 搜索定位请求快照：经 AppStorage 广播，接收端由 tick 触发后整体读取，
 * 避免读取到部分写入的数据。
 * `anchorId` 为空表示不滚动（分类落点）；`highlightGroupId` 为空表示不闪烁；
 * `fallbackAnchorId` 为空表示无回退落点（条件隐藏且无合理落点时应隐藏结果）。
 */
export interface SettingsSearchLocationRequest {
  readonly sessionId: number;
  readonly requestId: number;
  readonly entryId: string;
  readonly paneId: SettingsPaneId;
  readonly anchorId: string;
  readonly highlightGroupId: string;
  readonly fallbackAnchorId: string;
}

/** 滚动落定后发布给提醒卡片组的高亮信号；groupId 为空表示取消残留动画。 */
export interface SettingsSearchHighlightSignal {
  readonly requestId: number;
  readonly highlightGroupId: string;
  readonly cancelled: boolean;
}

/** AppStorage 键名集中管理，宿主与各设置页共用同一套字面量。 */
export class SettingsSearchLocationKeys {
  static readonly REQUEST: string = 'settingsSearchLocationRequest';
  static readonly REQUEST_TICK: string = 'settingsSearchLocationTick';
  static readonly HIGHLIGHT: string = 'settingsSearchLocationHighlight';
  static readonly HIGHLIGHT_TICK: string = 'settingsSearchLocationHighlightTick';
  /** 已开始消费的最大 requestId，防止陈旧请求在下次进入时重放。 */
  static readonly CONSUMED_REQUEST_ID: string = 'settingsSearchLocationConsumedRequestId';
}

export function readLocationRequest(): SettingsSearchLocationRequest | undefined {
  return AppStorage.get<SettingsSearchLocationRequest>(SettingsSearchLocationKeys.REQUEST);
}

export function readHighlightSignal(): SettingsSearchHighlightSignal | undefined {
  return AppStorage.get<SettingsSearchHighlightSignal>(SettingsSearchLocationKeys.HIGHLIGHT);
}

/** 发布高亮信号（含取消），接收端依赖 tick 触发后读取快照。 */
export function publishHighlightSignal(signal: SettingsSearchHighlightSignal): void {
  AppStorage.setOrCreate(SettingsSearchLocationKeys.HIGHLIGHT, signal);
  const tick: number = AppStorage.get<number>(SettingsSearchLocationKeys.HIGHLIGHT_TICK) ?? 0;
  AppStorage.setOrCreate(SettingsSearchLocationKeys.HIGHLIGHT_TICK, tick + 1);
}
