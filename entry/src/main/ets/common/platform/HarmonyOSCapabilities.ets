import { deviceInfo } from '@kit.BasicServicesKit';

export class HarmonyOSCapabilities {
  static supportsImmersiveMaterial(): boolean {
    return deviceInfo.apiAvailable('26.0.0');
  }
}
