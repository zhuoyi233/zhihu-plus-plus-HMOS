import { uiMaterial } from '@kit.ArkUI';
import { HarmonyOSCapabilities } from '../platform/HarmonyOSCapabilities';

/**
 * 顶部控件的系统材质（`uiMaterial`，API 26 专属）：模块级创建一次并缓存，
 * 页面与共享按钮共用同一个材质对象，不在 build 中反复构造或查询能力。
 *
 * 兼容线仍是 API 23：静态导入本身在低版本不崩，但 `new uiMaterial.ImmersiveMaterial(...)`
 * 会抛异常（实测 API 24 模拟器抛错但不崩），因此必须版本门禁 + try/catch；
 * 取不到时返回 undefined，调用方按 TopBarMaterial.ets 的互斥策略退回普通模糊。
 */
function createTopBarGlassMaterial(): uiMaterial.Material | undefined {
  if (!HarmonyOSCapabilities.supportsSystemMaterial()) {
    return undefined;
  }
  try {
    // interactive: 顶部圆按钮/胶囊需要设置页同款跟手形变（计划 §3.4），不动画、不改布局。
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true
    });
  } catch (_error) {
    return undefined;
  }
}

export const TOP_BAR_GLASS_MATERIAL: uiMaterial.Material | undefined = createTopBarGlassMaterial();
