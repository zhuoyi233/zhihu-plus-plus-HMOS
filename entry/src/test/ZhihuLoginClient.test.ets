import { describe, expect, it } from '@ohos/hypium';
import {
  classifyLoginResponse,
  classifyLoginFailure,
  classifyLoginTransportError,
  hasRequiredLoginCookies,
  HttpFailure,
  HttpFailureKind,
  LoginVerificationStatus,
  parseZhihuProfile,
  PreparedZhihuHttpRequest,
  SessionCookie,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory,
  ZhihuLoginClient
} from 'data';

class LoginTransport implements ZhihuHttpTransport {
  requestValue?: PreparedZhihuHttpRequest;
  destroyCount: number = 0;

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requestValue = request;
    const response: ZhihuHttpResponse = {
      statusCode: 200,
      body: '{"id":"test-id","name":"测试账号"}'
    };
    return Promise.resolve(response);
  }

  destroy(): void {
    this.destroyCount += 1;
  }
}

class LoginTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: LoginTransport = new LoginTransport();
  createCount: number = 0;

  create(): ZhihuHttpTransport {
    this.createCount += 1;
    return this.transport;
  }
}

class PendingLoginTransport implements ZhihuHttpTransport {
  destroyCount: number = 0;
  private rejectRequest?: (reason: Error) => void;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, reject: (reason: Error) => void) => {
      this.rejectRequest = reject;
    });
  }

  destroy(): void {
    this.destroyCount += 1;
    this.rejectRequest?.(new Error('test cancellation'));
  }
}

class PendingLoginTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingLoginTransport = new PendingLoginTransport();
  createCount: number = 0;

  create(): ZhihuHttpTransport {
    this.createCount += 1;
    return this.transport;
  }
}

function testLoginCookies(): Array<SessionCookie> {
  return [
    { name: 'z_c0', value: 'test-login' },
    { name: 'd_c0', value: 'test-device' }
  ];
}

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
      const unauthorized = classifyLoginResponse(401, '');
      const forbidden = classifyLoginResponse(403, '');
      expect(unauthorized.status).assertEqual(LoginVerificationStatus.REJECTED);
      expect(unauthorized.rejectionStatus).assertEqual(401);
      expect(unauthorized.message).assertEqual('Cookie 已失效或被知乎拒绝');
      expect(forbidden.status).assertEqual(LoginVerificationStatus.REJECTED);
      expect(forbidden.rejectionStatus).assertEqual(403);
      expect(forbidden.message).assertEqual('知乎拒绝了本次验证请求，可能需要稍后重试或完成风控');
      expect(forbidden.message.includes('Cookie 已失效')).assertFalse();
      expect(classifyLoginResponse(429, '').status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
      expect(classifyLoginResponse(503, '').status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
    });

    it('classifiesTimeoutAndNetworkFailures', 0, () => {
      const timeout = classifyLoginTransportError(2300028);
      expect(timeout.status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
      expect(timeout.message).assertEqual('网络请求超时，请稍后重试');
      expect(classifyLoginTransportError(2300007).message).assertEqual('网络连接失败，请稍后重试');
      const forbidden = classifyLoginFailure(new HttpFailure(HttpFailureKind.AUTHENTICATION, 403));
      expect(forbidden.status).assertEqual(LoginVerificationStatus.REJECTED);
      expect(forbidden.message).assertEqual('知乎拒绝了本次验证请求，可能需要稍后重试或完成风控');
    });

    it('rejectsInvalidSuccessfulResponse', 0, () => {
      expect(classifyLoginResponse(200, '{}').status).assertEqual(LoginVerificationStatus.INVALID_RESPONSE);
    });

    it('verifiesThroughUnifiedSignedTransport', 0, async () => {
      const factory = new LoginTransportFactory();
      const result = await new ZhihuLoginClient(factory).verify(testLoginCookies());
      expect(result.status).assertEqual(LoginVerificationStatus.AUTHENTICATED);
      expect(factory.createCount).assertEqual(1);
      const headers = JSON.stringify(factory.transport.requestValue?.headers);
      expect(headers.includes('"Cookie":"z_c0=test-login; d_c0=test-device"')).assertTrue();
      expect(headers.includes('"x-zse-96":"2.0_')).assertTrue();
      expect(factory.transport.requestValue?.maxRedirects).assertEqual(0);
      expect(factory.transport.destroyCount).assertEqual(1);
    });

    it('preventsConcurrentVerificationAndSupportsCancellation', 0, async () => {
      const factory = new PendingLoginTransportFactory();
      const client = new ZhihuLoginClient(factory);
      const first = client.verify(testLoginCookies());
      const concurrent = await client.verify(testLoginCookies());
      expect(concurrent.status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
      expect(factory.createCount).assertEqual(1);
      client.cancel();
      const cancelled = await first;
      expect(cancelled.status).assertEqual(LoginVerificationStatus.TEMPORARY_FAILURE);
      expect(cancelled.message).assertEqual('登录验证已取消');
      expect(factory.transport.destroyCount).assertEqual(1);
    });
  });
}
