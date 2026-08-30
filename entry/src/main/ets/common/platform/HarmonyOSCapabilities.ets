import { hdsMaterial } from '@kit.UIDesignKit';

export class HarmonyOSCapabilities {
  /**
   * 沉浸材质能力检测：hdsMaterial 自 6.1.0(23) 起可用，按设备实际能力判定。
   * 勿改用 deviceInfo.apiAvailable('26.0.0') 之类的版本判断——该 API 本身是
   * API 26 专属，在 API 23 设备上函数不存在，调用即崩。
   */
  static supportsImmersiveMaterial(): boolean {
    try {
      return hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_error) {
      return false;
    }
  }
}
