import { describe, expect, it } from '@ohos/hypium';
import {
  isConfirmedQrDesktopLoginUrl,
  shouldBlockQrDesktopLoginNavigation
} from '../main/ets/scan/QrDesktopLoginConfirmationPolicy';

const CONFIRMED_URL: string = 'https://www.zhihu.com/account/scan/login/confirmed-token';

export default function qrDesktopLoginConfirmationPolicyTest(): void {
  describe('qrDesktopLoginConfirmationPolicyTest', () => {
    it('requiresTheCoreVerifiedExactDesktopLoginUrl', 0, () => {
      expect(isConfirmedQrDesktopLoginUrl(CONFIRMED_URL)).assertTrue();
      expect(isConfirmedQrDesktopLoginUrl(' https://www.zhihu.com/account/scan/login/confirmed-token')).assertFalse();
      expect(isConfirmedQrDesktopLoginUrl('https://www.zhihu.com/account/scan/login/confirmed-token#fragment'))
        .assertFalse();
      expect(isConfirmedQrDesktopLoginUrl('https://www.zhihu.com/account/scan/login/confirmed-token/extra'))
        .assertFalse();
    });

    it('allowsOnlyTheConfirmedEntryAndTrustedZhihuMainFrameNavigation', 0, () => {
      expect(shouldBlockQrDesktopLoginNavigation(CONFIRMED_URL, true, CONFIRMED_URL)).assertFalse();
      expect(shouldBlockQrDesktopLoginNavigation('https://www.zhihu.com/', true, CONFIRMED_URL)).assertFalse();
      expect(shouldBlockQrDesktopLoginNavigation('https://static.zhihu.com/asset.js', false, CONFIRMED_URL)).assertFalse();
    });

    it('blocksExternalSchemesAndUntrustedMainFrameNavigation', 0, () => {
      expect(shouldBlockQrDesktopLoginNavigation('https://evil.example/', true, CONFIRMED_URL)).assertTrue();
      expect(shouldBlockQrDesktopLoginNavigation('http://www.zhihu.com/', true, CONFIRMED_URL)).assertTrue();
      expect(shouldBlockQrDesktopLoginNavigation('zhihu://open', true, CONFIRMED_URL)).assertTrue();
      expect(shouldBlockQrDesktopLoginNavigation('https://user@www.zhihu.com/', true, CONFIRMED_URL)).assertTrue();
      expect(shouldBlockQrDesktopLoginNavigation('https://www.zhihu.com:443/', true, CONFIRMED_URL)).assertTrue();
    });

    it('blocksAllMainFrameNavigationAfterTheEntryIsCleared', 0, () => {
      expect(shouldBlockQrDesktopLoginNavigation(CONFIRMED_URL, true, undefined)).assertTrue();
    });
  });
}
