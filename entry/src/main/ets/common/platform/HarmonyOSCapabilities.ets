import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';

export class HarmonyOSCapabilities {
  /**
   * 沉浸材质能力检测：hdsMaterial 自 6.1.0(23) 起可用，按设备实际能力判定。
   * 勿改用 deviceInfo.apiAvailable('26.0.0') 之类的版本判断——该 API 本身是
   * API 26 专属，在 API 23 设备上函数不存在，调用即崩。
   *
   * 供 HdsTabs 浮动玻璃画布（底栏/返回键胶囊）使用：23 真机材质渲染正常。
   */
  static supportsImmersiveMaterial(): boolean {
    try {
      return hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_error) {
      return false;
    }
  }

  /**
   * 沉浸式标题栏样式（HdsNavigation titleBar 的 systemMaterialEffect +
   * IMMERSIVE_GRADIENT_BLUR 滚动效果）仅在 API 26 真机验证过渲染正常；
   * API 23 真机上会渲染为不透明白色遮挡条盖住滚动正文（材质层降级为
   * 不透明白底的已知问题族），故按版本门禁，勿改回材质能力判断。
   */
  static supportsImmersiveTitleBarStyle(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }
}
