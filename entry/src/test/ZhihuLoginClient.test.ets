import { describe, expect, it } from '@ohos/hypium';
import {
  classifyLoginResponse,
  classifyLoginTransportError,
  hasRequiredLoginCookies,
  LoginVerificationStatus,
  parseZhihuProfile
} from '../main/ets/network/ZhihuLoginClient';

export default function zhihuLoginClientTest(): void {
  describe('zhihuLoginClientTest', () => {
    it('requiresBothAuthenticationCookies', 0, () => {
      expect(hasRequiredLoginCookies([{ name: 'z_c0', value: 'token' }])).assertFalse();
      expect(hasRequiredLoginCookies([
        { name: 'z_c0', value: 'token' },
        { name: 'd_c0', value: 'device' }
      ])).assertTrue();
    });

    it('parsesVerifiedProfile', 0, () => {
      const profile = parseZhihuProfile(
        '{"id":"people-id","name":"测试用户","url_token":"tester","user_type":"people"}'
      );
      expect(profile?.id).assertEqual('people-id');
      expect(profile?.name).assertEqual('测试用户');
      expect(profile?.urlToken).assertEqual('tester');
    });

    it('rejectsIncompleteOrMalformedProfile', 0, () => {
      expect(parseZhihuProfile('{"id":"people-id"}')).assertUndefined();
      expect(parseZhihuProfile('not-json')).assertUndefined();
    });

    it('classifiesAuthenticationResponse', 0, () => {
      const result = classifyLoginResponse(200, '{"id":"people-id","name":"测试用户"}');
      expect(result.status).assertEqual(LoginVerificationStatus.AUTHENTICATED);
      expect(result.profile?.name).assertEqual('测试用户');
    });

    it('classifiesRejectedAndTemporaryResponses', 0, () => {
      expect(classifyLoginResponse(401, '').status).assertEqual(LoginVerificationStatus.REJECTED);
      expect(classifyLoginResponse(403, '').status).assertEqual(LoginVerificationStatus.REJECTED);
      expect(classifyLoginResponse(429, '').status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
      expect(classifyLoginResponse(503, '').status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
    });

    it('classifiesTimeoutAndNetworkFailures', 0, () => {
      const timeout = classifyLoginTransportError(2300028);
      expect(timeout.status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
      expect(timeout.message).assertEqual('网络请求超时，请稍后重试');
      expect(classifyLoginTransportError(2300007).message).assertEqual('网络连接失败，请稍后重试');
    });

    it('rejectsInvalidSuccessfulResponse', 0, () => {
      expect(classifyLoginResponse(200, '{}').status).assertEqual(LoginVerificationStatus.INVALID_RESPONSE);
    });
  });
}
