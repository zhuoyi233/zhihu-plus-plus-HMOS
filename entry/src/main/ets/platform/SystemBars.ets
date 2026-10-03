import { window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { AppThemeMode } from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/** 显式内容色优先于 isStatusBarLightIcon，统一按实际主题设置，避免深色背景上的黑色文字。 */
export function updateStatusBarAppearance(systemIsDark?: boolean): void {
  const context = getAbilityContext();
  try {
    const mainWindow = context?.windowStage?.getMainWindowSync();
    if (context === undefined || mainWindow === undefined) {
      return;
    }
    const mode = AppStorage.get<AppThemeMode>('appThemeMode') ?? AppThemeMode.SYSTEM;
    const isDark = mode === AppThemeMode.DARK || (mode === AppThemeMode.SYSTEM &&
      (systemIsDark ?? (context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK)));
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
    }).catch((_error: Object): void => {
    });
  } catch (_error) {
  }
}

/**
 * 隐藏/恢复状态栏（对齐上游 ArticleImmersiveModeEffect：沉浸式真全屏，只藏 statusBars）。
 * 隐藏后 TYPE_SYSTEM 避让区归零，avoidAreaChange 监听会把 statusBarHeight 刷成 0，
 * 页面顶部留空随之收起；恢复时反向还原。
 */
export function setStatusBarHidden(hidden: boolean): void {
  const context = getAbilityContext();
  try {
    const mainWindow = context?.windowStage?.getMainWindowSync();
    if (mainWindow === undefined) {
      return;
    }
    mainWindow.setWindowSystemBarEnable(hidden ? ['navigation'] : ['status', 'navigation'])
      .catch((_error: Object): void => {
      });
  } catch (_error) {
  }
}
