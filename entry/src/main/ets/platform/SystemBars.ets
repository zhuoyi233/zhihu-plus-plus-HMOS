import { window } from '@kit.ArkUI';
import { SystemBarVisibility, SystemBarVisibilityPort } from './SystemBarVisibility';
import { resourceManager } from '@kit.LocalizationKit';
import { AppThemeMode } from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/** 状态栏内容色（时间/电量）：深色背景用白字，浅色背景用黑字。 */
function statusBarContentColor(isDark: boolean): string {
  return isDark ? '#FFFFFF' : '#000000';
}

/**
 * 按当前主题应用状态栏内容色，并把结果广播到 AppStorage。
 *
 * HdsNavigation/NavDestination 的 systemBarStyle 读同一份广播值：导航转场时由系统按
 * 栈顶页面统一应用并还原，不会再出现详情页退出后图标色停留在白色的问题。窗口级写入
 * 只负责首帧与主题切换，两边取值同一来源，避免互相覆盖。
 */
export function updateStatusBarAppearance(systemIsDark?: boolean): void {
  const context = getAbilityContext();
  const mode = AppStorage.get<AppThemeMode>('appThemeMode') ?? AppThemeMode.SYSTEM;
  let configDark = false;
  try {
    configDark = context?.resourceManager.getConfigurationSync().colorMode ===
      resourceManager.ColorMode.DARK;
  } catch (_error) {
  }
  const isDark = mode === AppThemeMode.DARK || (mode === AppThemeMode.SYSTEM &&
    (systemIsDark ?? configDark));
  AppStorage.setOrCreate('systemBarContentColor', statusBarContentColor(isDark));
  if (context === undefined) {
    return;
  }
  try {
    const mainWindow = systemBarWindow;
    if (mainWindow === undefined) {
      return;
    }
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      // 新老字段同时给：部分系统版本只认 isStatusBarLightIcon（true=白色图标）。
      isStatusBarLightIcon: isDark,
      statusBarContentColor: statusBarContentColor(isDark)
    }).catch((_error: Object): void => {
    });
  } catch (_error) {
  }
}

/** 窗口由 Ability 生命周期显式绑定，异步回调不再重新获取另一个窗口。 */
let systemBarWindow: window.Window | undefined = undefined;
let windowGeneration: number = 0;
let appearanceTimer: number = -1;
const visibility = new SystemBarVisibility((): void => {
  updateStatusBarAppearance();
  const generation = windowGeneration;
  if (appearanceTimer >= 0) { clearTimeout(appearanceTimer); }
  appearanceTimer = setTimeout((): void => {
    appearanceTimer = -1;
    if (generation === windowGeneration && visibility.isShown()) { updateStatusBarAppearance(); }
  }, 150);
});

class WindowSystemBarVisibilityPort implements SystemBarVisibilityPort {
  private readonly target: window.Window;
  constructor(target: window.Window) { this.target = target; }
  apply(hidden: boolean): Promise<void> {
    return this.target.setWindowSystemBarEnable(hidden ? ['navigation'] : ['status', 'navigation']);
  }
}

export function bindSystemBarWindow(target: window.Window): void {
  windowGeneration += 1;
  systemBarWindow = target;
  if (appearanceTimer >= 0) { clearTimeout(appearanceTimer); appearanceTimer = -1; }
  visibility.bind(new WindowSystemBarVisibilityPort(target));
  updateStatusBarAppearance();
}

export function detachSystemBarWindow(): void {
  windowGeneration += 1;
  systemBarWindow = undefined;
  if (appearanceTimer >= 0) { clearTimeout(appearanceTimer); appearanceTimer = -1; }
  visibility.detach();
}

/** 目标与成功状态分离：失败可重试，串行应用，窗口更换后重新应用。 */
export function setStatusBarHidden(hidden: boolean): void { visibility.request(hidden); }

/** 窗口回到前台时允许重试上次失败的目标。 */
export function retryStatusBarVisibility(): void { visibility.retry(); }
