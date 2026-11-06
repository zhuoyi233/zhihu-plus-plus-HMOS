import { KeyboardAvoidMode, UIContext } from '@kit.ArkUI';

/**
 * 登录页键盘避让：进入时切到「压缩（RESIZE）」，离开时还原。
 * 默认的上抬（OFFSET）会把整页顶起，键盘遮挡协议勾选与登录按钮；压缩只挤压内容区。
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
