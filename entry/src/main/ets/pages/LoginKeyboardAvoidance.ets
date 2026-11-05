import { KeyboardAvoidMode, UIContext } from '@kit.ArkUI';

/**
 * 登录页的键盘避让：临时把页面切成「压缩（RESIZE）」，离开时还原。
 *
 * 默认的上抬（OFFSET）模式会把整页顶起：手机号卡片里的协议勾选与登录按钮被键盘盖住，
 * 上方的登录方式页签被顶出屏幕。压缩模式只挤压内容区高度，配合页面内的 Scroll，输入框
 * 获得焦点时系统会把光标滚进可视区，用户在键盘上方就能继续勾选协议、点登录。
 *
 * 弹层（国家/地区选择）不受影响，仍走各自的 SheetKeyboardAvoidMode。
 * 返回的旧模式供 `restoreKeyboardAvoidMode` 还原，避免带到其他页面。
 */
export function applyLoginKeyboardResize(uiContext: UIContext): KeyboardAvoidMode | undefined {
  try {
    const previous: KeyboardAvoidMode = uiContext.getKeyboardAvoidMode();
    uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    return previous;
  } catch (_error) {
    // 低版本或非 UI 上下文拿不到避让模式时保持系统默认，不影响登录流程本身。
    return undefined;
  }
}

export function restoreKeyboardAvoidMode(uiContext: UIContext, previous: KeyboardAvoidMode | undefined): void {
  if (previous === undefined) {
    return;
  }
  try {
    uiContext.setKeyboardAvoidMode(previous);
  } catch (_error) {
    // 页面销毁阶段还原失败无需处理：窗口销毁时避让模式随之失效。
  }
}
