import { describe, expect, it } from '@ohos/hypium';
import { assessQrScanValue, QrScanDecision } from 'core';

export default function qrLoginScanPolicyTest(): void {
  describe('qrLoginScanPolicyTest', () => {
    it('acceptsZhihuDesktopLoginQrUrl', 0, () => {
      const assessment = assessQrScanValue(
        'https://www.zhihu.com/account/scan/login/p0-test-token?source=web'
      );

      expect(assessment.decision).assertEqual(QrScanDecision.ZHIHU_DESKTOP_LOGIN);
    });

    it('rejectsLookalikeHostsAndInsecureSchemes', 0, () => {
      const lookalike = assessQrScanValue(
        'https://www.zhihu.com.evil.example/account/scan/login/token'
      );
      const insecure = assessQrScanValue(
        'http://www.zhihu.com/account/scan/login/token'
      );
      const nonStandardPort = assessQrScanValue(
        'https://www.zhihu.com:8443/account/scan/login/token'
      );
      const credentials = assessQrScanValue(
        'https://user@www.zhihu.com/account/scan/login/token'
      );
      const duplicateSeparator = assessQrScanValue(
        'https://www.zhihu.com/account//scan/login/token'
      );
      const trailingSeparator = assessQrScanValue(
        'https://www.zhihu.com/account/scan/login/token/'
      );

      expect(lookalike.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(insecure.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(nonStandardPort.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(credentials.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(duplicateSeparator.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(trailingSeparator.decision).assertEqual(QrScanDecision.UNSUPPORTED);
    });

    it('rejectsNonLoginAndMalformedValues', 0, () => {
      const ordinaryLink = assessQrScanValue('https://www.zhihu.com/question/631983014');
      const malformed = assessQrScanValue('not a URL');
      const empty = assessQrScanValue('   ');

      expect(ordinaryLink.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(malformed.decision).assertEqual(QrScanDecision.UNSUPPORTED);
      expect(empty.decision).assertEqual(QrScanDecision.INVALID);
    });

    it('doesNotExposeLoginTokenInAssessmentMessage', 0, () => {
      const token = 'sensitive-p0-token';
      const assessment = assessQrScanValue(`https://www.zhihu.com/account/scan/login/${token}`);

      expect(assessment.message.includes(token)).assertFalse();
    });
  });
}
