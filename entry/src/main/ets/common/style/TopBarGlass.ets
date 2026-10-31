import { uiMaterial } from '@kit.ArkUI';
import { HarmonyOSCapabilities } from '../platform/HarmonyOSCapabilities';

/**
 * 顶栏自定义动作按钮的系统材质（`uiMaterial`，API 26 专属）。
 *
 * 与 main 设置页 `createTitleBarGlassMaterial()` 完全相同：先过版本门禁，再在 try/catch 内
 * 以 ULTRA_THIN 参数构造，失败返回 undefined；模块级只创建一次并在页面与共享按钮间复用。
 * 兼容线仍是 API 23：静态导入本身不崩，但 `new uiMaterial.ImmersiveMaterial(...)` 会抛异常，
 * 因此必须有门禁与兜底——取不到时调用方退回 `backgroundBlurStyle(COMPONENT_ULTRA_THIN)`。
 *
 * 不启用 `interactive`／`lightEffect`（feature 分支曾加的形变与光感不属于基线）。
 */
function createTitleBarGlassMaterial(): uiMaterial.Material | undefined {
  if (!HarmonyOSCapabilities.supportsSystemMaterial()) {
    return undefined;
  }
  try {
    return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN });
  } catch (_error) {
    return undefined;
  }
}

export const TOP_BAR_GLASS_MATERIAL: uiMaterial.Material | undefined = createTitleBarGlassMaterial();
