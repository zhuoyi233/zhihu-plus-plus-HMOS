import { window } from '@kit.ArkUI';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

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
