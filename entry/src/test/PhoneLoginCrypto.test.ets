import { describe, expect, it } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import {
  defaultPhoneLoginDeviceInfo,
  encryptZhihuMessageBody,
  hmacSha1Hex,
  PhoneLoginError
} from 'data';

/**
 * host 侧 UnitTestArkTS 运行时（hvigor test 的本地 JS 引擎）里 @kit.ArkTS 的
 * Base64Helper 是空桩（encodeToStringSync 返回空串），无法执行真实加密。这里先
 * 探测能力，不可用时跳过加密器断言；HMAC-SHA1 是纯 ArkTS 实现，任何环境都可跑。
 */
function hostBase64Capable(): boolean {
  try {
    return new util.Base64Helper().encodeToStringSync(new Uint8Array([1, 2, 3])) === 'AQID';
  } catch (_error) {
    return false;
  }
}

export default function phoneLoginCryptoTest(): void {
  describe('phoneLoginCryptoTest', () => {
    it('hmacSha1MatchesKnownVector', 0, () => {
      expect(hmacSha1Hex('key', 'The quick brown fox jumps over the lazy dog'))
        .assertEqual('de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9');
    });

    it('hmacSha1MatchesEmptyAndRfcVectors', 0, () => {
      // RFC 2202 附录 A 用例（key 长于 64 字节会先做 SHA1 压缩）。
      expect(hmacSha1Hex('', '')).assertEqual('fbdb1d1b18aa6c08324b7d64b71fb76370690e1d');
      expect(hmacSha1Hex('Jefe', 'what do ya want for nothing?')).assertEqual(
        'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79');
    });

    it('hmacSha1HandlesUnicodeAndLongKeys', 0, () => {
      expect(hmacSha1Hex('secret', '知乎').length).assertEqual(40);
      expect(hmacSha1Hex('x'.repeat(80), 'message').length).assertEqual(40);
    });

    it('encryptsFormBodyToDeterministicBase64', 0, () => {
      if (!hostBase64Capable()) {
        return;
      }
      const form = 'username=%2B8613800138000&client_id=8d5227e0aaaa4797a763ac64e0c3b8';
      const first = encryptZhihuMessageBody(form);
      const second = encryptZhihuMessageBody(form);
      expect(first).assertEqual(second);
      // 输入按 16 字节块补齐后 base64 编码：密文非空且长度为 4 的倍数。
      expect(first.length > 0).assertTrue();
      expect(first.length % 4).assertEqual(0);
    });

    it('producesDifferentCiphertextForDifferentInputs', 0, () => {
      if (!hostBase64Capable()) {
        return;
      }
      const a = encryptZhihuMessageBody('username=13800138000');
      const b = encryptZhihuMessageBody('username=13800138001');
      expect(a === b).assertFalse();
    });

    it('padsEmptyInputToOneFullBlock', 0, () => {
      if (!hostBase64Capable()) {
        return;
      }
      // 空输入补齐到 16 字节 → base64 24 字符。
      expect(encryptZhihuMessageBody('').length).assertEqual(24);
    });

    it('providesSaneDeviceInfoDefaultsAndTypedErrors', 0, () => {
      const info = defaultPhoneLoginDeviceInfo();
      expect(info.timezoneOffsetSeconds).assertEqual(-new Date().getTimezoneOffset() * 60);
      expect(info.cpuCount > 0).assertTrue();
      expect(info.totalMemoryMegabytes > 0).assertTrue();
      expect(info.phoneModel.length > 0).assertTrue();
      const error = new PhoneLoginError('验证码无效', 'captcha');
      expect(error.message).assertEqual('验证码无效');
      expect(error.kind).assertEqual('captcha');
      expect(error instanceof Error).assertTrue();
    });
  });
}
