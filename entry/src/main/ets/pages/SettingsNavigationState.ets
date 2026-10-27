/**
 * 设置宿主的内部导航模型。
 *
 * “内容屏蔽”“屏蔽记录”“开发者选项”不再以根路由整页打开，而是设置容器内部的 pane；
 * 目录选中、返回层级、搜索入口解析与开发者可见性门禁都由这里的纯函数决定，
 * 页面只负责渲染，避免继续在各处散落条件判断（设计依据见 docs/account-settings-redesign.md §11）。
 *
 * 所有函数都不依赖 UI 状态，宿主与 Hypium 共同使用同一套判定。
 */
import { SettingsEntryId } from './SettingsSearchIndex';

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

/** 子页的直接父级；分类根页与目录返回 NONE。 */
export function paneParent(pane: SettingsPaneId): SettingsPaneId {
  switch (pane) {
    case SettingsPaneId.THEME_COLOR:
      return SettingsPaneId.APPEARANCE;
    case SettingsPaneId.BLOCKING_RULES:
    case SettingsPaneId.BLOCKED_HISTORY:
      return SettingsPaneId.FILTER;
    default:
      return SettingsPaneId.NONE;
  }
}

/** 从直接父级到根的祖先链，用于目录选中态与“当前在哪一级”的判断。 */
export function paneAncestors(pane: SettingsPaneId): Array<SettingsPaneId> {
  const ancestors: Array<SettingsPaneId> = [];
  let current: SettingsPaneId = paneParent(pane);
  let guard: number = 0;
  while (current !== SettingsPaneId.NONE && guard < 8) {
    ancestors.push(current);
    current = paneParent(current);
    guard += 1;
  }
  return ancestors;
}

/**
 * 目录分类是否处于选中态：当前页等于该分类，或该分类是当前页的祖先。
 * 规则／记录页不会让“推荐系统与内容过滤”失去选中。
 */
export function isPaneHighlighted(selected: SettingsPaneId, category: SettingsPaneId): boolean {
  if (selected === category) {
    return true;
  }
  return paneAncestors(selected).includes(category);
}

/** 当前页在设置内部的完整路径（由分类根到当前页），用于面包屑与测试断言。 */
export function panePath(pane: SettingsPaneId): Array<SettingsPaneId> {
  const path: Array<SettingsPaneId> = [pane];
  let current: SettingsPaneId = paneParent(pane);
  let guard: number = 0;
  while (current !== SettingsPaneId.NONE && guard < 8) {
    path.unshift(current);
    current = paneParent(current);
    guard += 1;
  }
  return path;
}

/** 详情标题；宿主只画一次。 */
export function paneTitle(pane: SettingsPaneId): string {
  switch (pane) {
    case SettingsPaneId.IDENTITY:
      return '身份管理';
    case SettingsPaneId.APPEARANCE:
      return '外观与阅读体验';
    case SettingsPaneId.THEME_COLOR:
      return '主题颜色';
    case SettingsPaneId.READING:
      return '朗读与播放';
    case SettingsPaneId.FILTER:
      return '推荐系统与内容过滤';
    case SettingsPaneId.BLOCKING_RULES:
      return '内容屏蔽';
    case SettingsPaneId.BLOCKED_HISTORY:
      return '屏蔽记录';
    case SettingsPaneId.NOTIFICATION:
      return '通知设置';
    case SettingsPaneId.SYSTEM_UPDATE:
      return '系统与更新';
    case SettingsPaneId.ABOUT:
      return '关于应用';
    case SettingsPaneId.DEVELOPER:
      return '开发者选项';
    default:
      return '设置';
  }
}

/**
 * 目录行／搜索命中项 → 设置内部目的地。
 * 返回 NONE 表示该项属于设置之外（登录、身份管理等根路由），由调用方走 navigate。
 */
export function paneForEntry(id: SettingsEntryId): SettingsPaneId {
  switch (id) {
    case SettingsEntryId.IDENTITY:
      return SettingsPaneId.IDENTITY;
    case SettingsEntryId.APPEARANCE:
      return SettingsPaneId.APPEARANCE;
    case SettingsEntryId.THEME_COLOR:
      return SettingsPaneId.THEME_COLOR;
    case SettingsEntryId.READING:
      return SettingsPaneId.READING;
    case SettingsEntryId.FILTER:
      return SettingsPaneId.FILTER;
    case SettingsEntryId.BLOCKING_RULES:
      return SettingsPaneId.BLOCKING_RULES;
    case SettingsEntryId.BLOCKED_HISTORY:
      return SettingsPaneId.BLOCKED_HISTORY;
    case SettingsEntryId.NOTIFICATION:
      return SettingsPaneId.NOTIFICATION;
    case SettingsEntryId.SYSTEM_UPDATE:
      return SettingsPaneId.SYSTEM_UPDATE;
    case SettingsEntryId.ABOUT:
    case SettingsEntryId.ABOUT_VERSION:
    case SettingsEntryId.ABOUT_GITHUB:
    case SettingsEntryId.ABOUT_LICENSE:
    case SettingsEntryId.ABOUT_OPEN_SOURCE:
      return SettingsPaneId.ABOUT;
    case SettingsEntryId.DEVELOPER:
      return SettingsPaneId.DEVELOPER;
    default:
      return SettingsPaneId.NONE;
  }
}

/**
 * 返回键是否由设置容器内部消化。
 * 双栏下分类根页返回即退出设置（交回导航栈），只有子页在右栏内逐级返回；窄栏一律先回目录。
 */
export function hasInternalBack(pane: SettingsPaneId, split: boolean): boolean {
  if (pane === SettingsPaneId.NONE) {
    return false;
  }
  if (!split) {
    return true;
  }
  return paneParent(pane) !== SettingsPaneId.NONE;
}

/** 关闭开发者模式后应当停留的 pane：宽窄窗都回设置目录，不再无条件弹设置首页。 */
export function paneAfterDeveloperModeDisabled(pane: SettingsPaneId): SettingsPaneId {
  if (pane === SettingsPaneId.DEVELOPER) {
    return SettingsPaneId.NONE;
  }
  return pane;
}

/**
 * 开发者页的全局门禁：目录、搜索与正文使用同一判定。
 * 关闭模式后浏览器返回、旧搜索结果或恢复路径都不得重新显示开发者页。
 */
export function isPaneAvailable(pane: SettingsPaneId, developerModeEnabled: boolean): boolean {
  if (pane === SettingsPaneId.DEVELOPER) {
    return developerModeEnabled;
  }
  return true;
}
