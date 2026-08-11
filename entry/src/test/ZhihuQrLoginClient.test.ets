import { describe, expect, it } from '@ohos/hypium';
import {
  isTrustedQrLoginUrl,
  isTrustedQrChallengeLink,
  normalizeQrDeadline,
  QrLoginRequest,
  QrLoginResponse,
  QrLoginStatus,
  QrLoginTransport,
  QrLoginTransportFactory,
  SessionCookie,
  ZHIHU_QR_CAPTCHA_URL,
  ZHIHU_QR_CODE_URL,
  ZHIHU_QR_SIGNIN_URL,
  ZHIHU_QR_UDID_URL,
  ZhihuQrLoginClient
} from 'data';

class ScriptedQrTransport implements QrLoginTransport {
  private readonly factory: ScriptedQrTransportFactory;

  constructor(factory: ScriptedQrTransportFactory) {
    this.factory = factory;
  }

  request(request: QrLoginRequest): Promise<QrLoginResponse> {
    this.factory.requests.push(request);
    const response = this.factory.responses.shift();
    if (response === undefined) {
      if (this.factory.pendingWhenEmpty) {
        return new Promise<QrLoginResponse>((resolve: (value: QrLoginResponse) => void) => {
          this.factory.pendingResolver = resolve;
        });
      }
      return Promise.reject(new Error('missing scripted response'));
    }
    return Promise.resolve(response);
  }

  destroy(): void {
    this.factory.destroyCount += 1;
    if (this.factory.throwOnDestroy) {
      throw new Error('cleanup detail must not escape');
    }
  }
}

class ScriptedQrTransportFactory implements QrLoginTransportFactory {
  readonly responses: Array<QrLoginResponse> = [];
  readonly requests: Array<QrLoginRequest> = [];
  destroyCount: number = 0;
  throwOnDestroy: boolean = false;
  pendingWhenEmpty: boolean = false;
  pendingResolver?: (value: QrLoginResponse) => void;

  create(): QrLoginTransport {
    return new ScriptedQrTransport(this);
  }

  resolvePending(value: QrLoginResponse): void {
    this.pendingResolver?.(value);
    this.pendingResolver = undefined;
  }
}

function response(statusCode: number, body: string, cookies: Array<SessionCookie> = []): QrLoginResponse {
  return { statusCode: statusCode, body: body, cookies: cookies };
}

function queueSuccessfulStart(factory: ScriptedQrTransportFactory): void {
  factory.responses.push(response(200, '', [{ name: '_xsrf', value: 'xsrf-token' }]));
  factory.responses.push(response(200, '{}', [{ name: 'd_c0', value: 'device-token' }]));
  factory.responses.push(response(200, '{}'));
  factory.responses.push(response(200,
    '{"expires_at":600,"link":"https://www.zhihu.com/account/scan/login/test-token","token":"test-token"}'));
}

export default function zhihuQrLoginClientTest(): void {
  describe('zhihuQrLoginClientTest', () => {
    it('usesAndroidLiteProtocolOrderAndKeepsRedirectsOutOfTheContract', 0, async () => {
      const factory = new ScriptedQrTransportFactory();
      factory.throwOnDestroy = true;
      queueSuccessfulStart(factory);
      const client = new ZhihuQrLoginClient(factory);

      const state = await client.start([], 1000000);

      expect(state.status).assertEqual(QrLoginStatus.READY);
      expect(factory.requests.length).assertEqual(4);
      expect(factory.requests[0].url).assertEqual(ZHIHU_QR_SIGNIN_URL);
      expect(factory.requests[1].url).assertEqual(ZHIHU_QR_UDID_URL);
      expect(factory.requests[2].url).assertEqual(ZHIHU_QR_CAPTCHA_URL);
      expect(factory.requests[3].url).assertEqual(ZHIHU_QR_CODE_URL);
      const udidHeaders = JSON.stringify(factory.requests[1].headers);
      expect(udidHeaders.includes('"x-xsrftoken":"xsrf-token"')).assertTrue();
      expect(factory.requests[3].headers.Cookie?.includes('d_c0=device-token')).assertTrue();
      expect(factory.destroyCount).assertEqual(4);
      expect(JSON.stringify(state).includes('device-token')).assertFalse();
    });

    it('requiresZC0BeforePublishingCandidateCredentials', 0, async () => {
      const factory = new ScriptedQrTransportFactory();
      queueSuccessfulStart(factory);
      factory.responses.push(response(200, '{"status":1,"success":true}'));
      factory.responses.push(response(200, '{"status":0,"z_c0":"login-token"}'));
      const client = new ZhihuQrLoginClient(factory);
      await client.start([], 1000000);

      const scanned = await client.pollOnce(1000500);
      expect(scanned.status).assertEqual(QrLoginStatus.WAITING_CONFIRMATION);
      expect(client.getCandidateCookies().length).assertEqual(0);

      const ready = await client.pollOnce(1001000);
      expect(ready.status).assertEqual(QrLoginStatus.CREDENTIAL_READY);
      const candidates = client.getCandidateCookies();
      expect(candidates.some((cookie: SessionCookie) => cookie.name === 'z_c0')).assertTrue();
      expect(candidates.some((cookie: SessionCookie) => cookie.name === 'd_c0')).assertTrue();
      expect(factory.requests[4].url).assertEqual(`${ZHIHU_QR_CODE_URL}/test-token/scan_info`);
      expect(JSON.stringify(factory.requests[4].headers).includes('"x-zse-93":"101_3_3.0"')).assertTrue();
      const requestCount = factory.requests.length;
      const terminal = await client.pollOnce(1001500);
      expect(terminal.status).assertEqual(QrLoginStatus.CREDENTIAL_READY);
      expect(factory.requests.length).assertEqual(requestCount);
    });

    it('classifiesExpiryAndRiskControlWithoutExposingResponseBody', 0, async () => {
      const expiredFactory = new ScriptedQrTransportFactory();
      queueSuccessfulStart(expiredFactory);
      expiredFactory.responses.push(response(200, '{"status":2}'));
      const expiredClient = new ZhihuQrLoginClient(expiredFactory);
      await expiredClient.start([], 1000000);
      expect((await expiredClient.pollOnce(1000500)).status).assertEqual(QrLoginStatus.EXPIRED);

      const riskFactory = new ScriptedQrTransportFactory();
      queueSuccessfulStart(riskFactory);
      riskFactory.responses.push(response(403,
        '{"error":{"code":40352,"need_login":true,"redirect":"https://evil.example/risk","message":"secret"}}'));
      const riskClient = new ZhihuQrLoginClient(riskFactory);
      await riskClient.start([], 1000000);
      const risk = await riskClient.pollOnce(1000500);
      expect(risk.status).assertEqual(QrLoginStatus.RISK_CONTROL);
      expect(risk.riskControlUrl).assertEqual('https://www.zhihu.com/account/risk_control/');
      expect(JSON.stringify(risk).includes('secret')).assertFalse();

      const serverFactory = new ScriptedQrTransportFactory();
      queueSuccessfulStart(serverFactory);
      serverFactory.responses.push(response(500, '{}', [{ name: 'z_c0', value: 'must-not-publish' }]));
      const serverClient = new ZhihuQrLoginClient(serverFactory);
      await serverClient.start([], 1000000);
      const serverFailure = await serverClient.pollOnce(1000500);
      expect(serverFailure.status).assertEqual(QrLoginStatus.TEMPORARY_FAILURE);
      expect(serverClient.getCandidateCookies().length).assertEqual(0);
      serverFactory.responses.push(response(200, '{"status":0}'));
      const recoveredPoll = await serverClient.pollOnce(1001000);
      expect(recoveredPoll.status).assertEqual(QrLoginStatus.READY);
      expect(serverClient.getCandidateCookies().length).assertEqual(0);
      expect(JSON.stringify(serverFactory.requests[5].headers).includes('must-not-publish')).assertFalse();
    });

    it('normalizesTtlAndAbsoluteDeadlines', 0, () => {
      expect(normalizeQrDeadline(undefined, 1000000)).assertEqual(1120000);
      expect(normalizeQrDeadline(600, 2000000000000)).assertEqual(2000000600000);
      expect(normalizeQrDeadline(600000, 2000000000000)).assertEqual(2000000600000);
      expect(normalizeQrDeadline(2000000600, 2000000000000)).assertEqual(2000000600000);
      expect(normalizeQrDeadline(2000000600000, 2000000000000)).assertEqual(2000000600000);
      expect(normalizeQrDeadline(Number.NaN, 1000000)).assertEqual(1120000);
      expect(normalizeQrDeadline(Number.POSITIVE_INFINITY, 1000000)).assertEqual(1120000);
      expect(normalizeQrDeadline(999999999999999, 1000000)).assertEqual(1120000);
    });

    it('boundsInvalidRuntimeExpiryInsteadOfCreatingLongLivedQr', 0, async () => {
      const factory = new ScriptedQrTransportFactory();
      factory.responses.push(response(200, ''));
      factory.responses.push(response(200, '{}'));
      factory.responses.push(response(200, '{}'));
      factory.responses.push(response(200,
        '{"expires_at":"999999999999","link":"https://www.zhihu.com/account/scan/login/token",' +
          '"token":"token"}'));

      const state = await new ZhihuQrLoginClient(factory).start([], 1000000);

      expect(state.status).assertEqual(QrLoginStatus.READY);
      expect(state.expiresAt).assertEqual(1120000);
    });

    it('rejectsOverlappingStartAndPollThenCancelsWithoutTransportSettlement', 0, async () => {
      const factory = new ScriptedQrTransportFactory();
      factory.pendingWhenEmpty = true;
      const client = new ZhihuQrLoginClient(factory);

      const starting = client.start([], 1000000);
      const overlappingStart = await client.start([], 1000000);
      const overlappingPoll = await client.pollOnce(1000000);
      expect(overlappingStart.status).assertEqual(QrLoginStatus.BUSY);
      expect(overlappingPoll.status).assertEqual(QrLoginStatus.BUSY);
      expect(factory.requests.length).assertEqual(1);

      client.cancel();
      const cancelled = await starting;
      expect(cancelled.status).assertEqual(QrLoginStatus.CANCELLED);
      expect(factory.destroyCount).assertEqual(1);

      factory.resolvePending(response(200,
        '{"link":"https://www.zhihu.com/account/scan/login/old","token":"old"}',
        [{ name: 'z_c0', value: 'old-login' }]));
      await Promise.resolve();
      expect(client.getState().status).assertEqual(QrLoginStatus.CANCELLED);
      expect(client.getCandidateCookies().length).assertEqual(0);
    });

    it('keepsOverlappingPollBusyAndBlocksCancelledOldResponseWriteback', 0, async () => {
      const factory = new ScriptedQrTransportFactory();
      queueSuccessfulStart(factory);
      const client = new ZhihuQrLoginClient(factory);
      await client.start([], 1000000);
      factory.pendingWhenEmpty = true;

      const polling = client.pollOnce(1000500);
      const overlapping = await client.pollOnce(1000500);
      expect(overlapping.status).assertEqual(QrLoginStatus.BUSY);
      client.cancel();
      const cancelled = await polling;
      expect(cancelled.status).assertEqual(QrLoginStatus.CANCELLED);

      factory.resolvePending(response(200, '{"status":0,"z_c0":"old-login"}'));
      await Promise.resolve();
      expect(client.getState().status).assertEqual(QrLoginStatus.CANCELLED);
      expect(client.getCandidateCookies().length).assertEqual(0);
    });

    it('rejectsMalformedOrUntrustedQrChallenge', 0, async () => {
      expect(isTrustedQrLoginUrl('https://www.zhihu.com/account/scan/login/token')).assertTrue();
      expect(isTrustedQrLoginUrl('https://api.zhihu.com/account/scan/login/token')).assertFalse();
      expect(isTrustedQrLoginUrl('https://www.zhihu.com.evil.example/account/scan/login/token')).assertFalse();
      expect(isTrustedQrLoginUrl('https://user@www.zhihu.com/account/scan/login/token')).assertFalse();
      expect(isTrustedQrLoginUrl('https://www.zhihu.com:443/account/scan/login/token')).assertFalse();
      const factory = new ScriptedQrTransportFactory();
      factory.responses.push(response(200, ''));
      factory.responses.push(response(200, '{}'));
      factory.responses.push(response(200, '{}'));
      factory.responses.push(response(200,
        '{"link":"https://evil.example/account/scan/login/token","token":"token"}'));
      const state = await new ZhihuQrLoginClient(factory).start();

      expect(state.status).assertEqual(QrLoginStatus.TEMPORARY_FAILURE);
      expect(state.message.includes('evil.example')).assertFalse();
    });

    it('requiresExactBoundedChallengePathForTheReturnedToken', 0, async () => {
      expect(isTrustedQrChallengeLink(
        'https://www.zhihu.com/account/scan/login/exact-token', 'exact-token')).assertTrue();
      expect(isTrustedQrChallengeLink(
        'https://www.zhihu.com/account/scan/login/other-token', 'exact-token')).assertFalse();
      expect(isTrustedQrChallengeLink(
        'https://www.zhihu.com/account/risk_control/exact-token', 'exact-token')).assertFalse();

      const factory = new ScriptedQrTransportFactory();
      factory.responses.push(response(200, ''));
      factory.responses.push(response(200, '{}'));
      factory.responses.push(response(200, '{}'));
      factory.responses.push(response(200,
        '{"link":"https://www.zhihu.com/account/scan/login/wrong","token":"expected"}'));
      const state = await new ZhihuQrLoginClient(factory).start();
      expect(state.status).assertEqual(QrLoginStatus.TEMPORARY_FAILURE);
      expect(state.qrLink).assertUndefined();
    });
  });
}
