import { uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HarmonyOSCapabilities } from '../platform/HarmonyOSCapabilities';

const TOP_BAR_GLASS_LOG_DOMAIN: number = 0x0000;
const TOP_BAR_GLASS_LOG_TAG: string = 'TopBarGlass';

/**
 * 顶栏系统材质（`uiMaterial`，API 26 专属）：模块级创建并缓存，不在 build 中反复构造。
 *
 * 兼容线仍是 API 23：静态导入本身不崩，但 `new uiMaterial.ImmersiveMaterial(...)` 会抛异常，
 * 因此必须先过版本门禁再 try/catch；取不到时返回 undefined，调用方退回
 * `backgroundBlurStyle(COMPONENT_ULTRA_THIN)`。
 *
 * 这里区分两份材质，因为「按压时是否形变」只对可点击的圆按钮成立：
 * - `TOP_BAR_ACTION_GLASS_MATERIAL`：顶栏动作圆按钮，开 `interactive: true`，按下时与
 *   HDS 原生返回键呈现同一套交互形变与跟手反馈（plan §3.4 修订口径）；
 * - `TOP_BAR_GLASS_MATERIAL`：搜索胶囊、输入胶囊、页签切换组等输入型/组合型容器，
 *   保持默认（不形变），避免输入过程中控件跟着手指缩放。
 *
 * 两者都不启用 `lightEffect`：光感是独立的触点反馈参数，本轮不引入。
 *
 * 创建结果只打印一次日志：材质是否存在决定按压反馈路径（材质形变 / stateEffect 兜底），
 * 设备回归时先看这条日志，避免把「设备不支持」误判成「代码没生效」。
 */
function createMaterial(interactive: boolean): uiMaterial.Material | undefined {
  if (!HarmonyOSCapabilities.supportsSystemMaterial()) {
    hilog.info(TOP_BAR_GLASS_LOG_DOMAIN, TOP_BAR_GLASS_LOG_TAG,
      'system material skipped (api < 26), interactive=%{public}s', `${interactive}`);
    return undefined;
  }
  try {
    const material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: interactive
    });
    hilog.info(TOP_BAR_GLASS_LOG_DOMAIN, TOP_BAR_GLASS_LOG_TAG,
      'system material created, interactive=%{public}s', `${interactive}`);
    return material;
  } catch (error) {
    const message: string = error instanceof Error ? error.message : `${error}`;
    hilog.warn(TOP_BAR_GLASS_LOG_DOMAIN, TOP_BAR_GLASS_LOG_TAG,
      'system material creation failed, interactive=%{public}s, error=%{public}s',
      `${interactive}`, message);
    // 含 interactive 参数不被当前系统接受的情况：整体退回模糊兜底，不做半套材质。
    return undefined;
  }
}

/** 顶栏动作圆按钮：与 HDS 原生返回键一致的按压形变与跟手反馈。 */
export const TOP_BAR_ACTION_GLASS_MATERIAL: uiMaterial.Material | undefined = createMaterial(true);

/** 顶栏输入型/组合型容器（搜索胶囊、关注页签切换组）：不参与按压形变。 */
export const TOP_BAR_GLASS_MATERIAL: uiMaterial.Material | undefined = createMaterial(false);
