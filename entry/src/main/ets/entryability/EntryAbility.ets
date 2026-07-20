import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resolveZhihuLink } from '../navigation/DeepLinkResolver';

const DOMAIN = 0xD001;
const TAG = 'ZhihuPlusPlusP0';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility created');
    this.logIncomingLink(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.logIncomingLink(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load P0 page: %{public}s', JSON.stringify(error));
        return;
      }
      hilog.info(DOMAIN, TAG, 'P0 page loaded');
    });
  }

  private logIncomingLink(want: Want): void {
    if (want.uri === undefined || want.uri.length === 0) {
      return;
    }
    const destination = resolveZhihuLink(want.uri);
    const result = destination === undefined ? 'unsupported' : destination.type;
    hilog.info(DOMAIN, TAG, 'Incoming deep link resolved as %{public}s', result);
  }
}
