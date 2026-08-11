import { describe, expect, it } from '@ohos/hypium';
import {
  HttpFailure,
  HttpFailureKind,
  isTrustedZhihuRequestUrl,
  PreparedZhihuHttpRequest,
  prepareZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class FixedCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'login-token' },
      { name: 'd_c0', value: 'device-token' }
    ];
  }
}

class CountingCookieProvider implements SessionCookieProvider {
  readCount: number = 0;

  getCookies(): Array<SessionCookie> {
    this.readCount += 1;
    return [{ name: 'd_c0', value: 'test-device' }];
  }
}

class ThrowingCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    throw new Error('provider detail must not escape');
  }
}

class CapturingTransport implements ZhihuHttpTransport {
  requestValue?: PreparedZhihuHttpRequest;
  destroyCount: number = 0;
  response: ZhihuHttpResponse = { statusCode: 200, body: '{"ok":true}' };
  throwOnDestroy: boolean = false;

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requestValue = request;
    return Promise.resolve(this.response);
  }

  destroy(): void {
    this.destroyCount += 1;
    if (this.throwOnDestroy) {
      throw new Error('destroy failure must stay internal');
    }
  }
}

class CapturingTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: CapturingTransport = new CapturingTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

class ThrowingTransportFactory implements ZhihuHttpTransportFactory {
  create(): ZhihuHttpTransport {
    throw new Error('factory detail must not escape');
  }
}

class CancellingTransport implements ZhihuHttpTransport {
  destroyCount: number = 0;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, _reject) => {});
  }

  destroy(): void {
    this.destroyCount += 1;
  }
}

class CancellingTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: CancellingTransport = new CancellingTransport();
  readonly replacement: CapturingTransport = new CapturingTransport();
  createCount: number = 0;

  create(): ZhihuHttpTransport {
    this.createCount += 1;
    return this.createCount === 1 ? this.transport : this.replacement;
  }
}

export default function zhihuHttpClientTest(): void {
  describe('zhihuHttpClientTest', () => {
    it('keepsAnonymousRequestFreeOfSessionHeaders', 0, () => {
      const prepared = prepareZhihuHttpRequest({
        url: 'https://www.zhihu.com/api/v4/questions/1',
        accept: 'application/json'
      });
      expect(prepared.headers.Cookie).assertUndefined();
      expect(JSON.stringify(prepared.headers).includes('x-zse-93')).assertFalse();
      expect(prepared.connectTimeout).assertEqual(10000);
      expect(prepared.readTimeout).assertEqual(15000);
      expect(prepared.maxRedirects).assertEqual(0);
      expect(prepared.maxLimit).assertEqual(1024 * 1024);
    });

    it('rejectsUntrustedUrlsWithoutReadingSession', 0, async () => {
      const rejectedUrls: Array<string> = [
        'http://www.zhihu.com/api/v4/me',
        'https://www.zhihu.com.evil.example/api/v4/me',
        'https://www.zhihu.com@evil.example/api/v4/me',
        'https://user@www.zhihu.com/api/v4/me',
        'https://www.zhihu.com:443/api/v4/me',
        'https://api.zhihu.com/api/v4/me'
      ];
      for (let index = 0; index < rejectedUrls.length; index += 1) {
        expect(isTrustedZhihuRequestUrl(rejectedUrls[index])).assertFalse();
      }
      expect(isTrustedZhihuRequestUrl('https://www.zhihu.com/api/v4/me')).assertTrue();

      const provider = new CountingCookieProvider();
      let failure: HttpFailure | undefined = undefined;
      try {
        await new ZhihuHttpClient(provider).execute({
          url: rejectedUrls[1],
          useSession: true,
          signWithZse: true
        });
      } catch (error) {
        failure = error as HttpFailure;
      }
      expect(failure?.kind).assertEqual(HttpFailureKind.CLIENT);
      expect(failure?.retryable).assertFalse();
      expect(provider.readCount).assertEqual(0);
    });

    it('addsCookieAndZseOnlyForSignedSessionRequest', 0, () => {
      const prepared = prepareZhihuHttpRequest({
        url: 'https://www.zhihu.com/api/v4/me',
        useSession: true,
        signWithZse: true
      }, new FixedCookieProvider().getCookies(), 1);
      expect(prepared.headers.Cookie).assertEqual('z_c0=login-token; d_c0=device-token');
      const serializedHeaders = JSON.stringify(prepared.headers);
      expect(serializedHeaders.includes('"x-zse-93":"101_3_3.0"')).assertTrue();
      expect(serializedHeaders.includes('"x-zse-96":"2.0_')).assertTrue();
    });

    it('mapsProviderAndFactoryExceptionsToSafeStructuredFailure', 0, async () => {
      const failures: Array<HttpFailure> = [];
      try {
        await new ZhihuHttpClient(new ThrowingCookieProvider()).execute({
          url: 'https://www.zhihu.com/api/v4/me',
          useSession: true
        });
      } catch (error) {
        failures.push(error as HttpFailure);
      }
      try {
        await new ZhihuHttpClient(undefined, new ThrowingTransportFactory()).execute({
          url: 'https://www.zhihu.com/api/v4/test'
        });
      } catch (error) {
        failures.push(error as HttpFailure);
      }
      expect(failures.length).assertEqual(2);
      expect(failures[0].kind).assertEqual(HttpFailureKind.NETWORK);
      expect(failures[1].kind).assertEqual(HttpFailureKind.NETWORK);
      expect(failures[0].message.includes('provider detail')).assertFalse();
      expect(failures[1].message.includes('factory detail')).assertFalse();
    });

    it('usesOneExecutionPathAndDestroysTransportOnSuccess', 0, async () => {
      const factory = new CapturingTransportFactory();
      const response = await new ZhihuHttpClient(new FixedCookieProvider(), factory).execute({
        url: 'https://www.zhihu.com/api/v4/me',
        useSession: true,
        signWithZse: true
      });
      expect(response.statusCode).assertEqual(200);
      expect(factory.transport.requestValue?.headers.Cookie).assertEqual('z_c0=login-token; d_c0=device-token');
      expect(factory.transport.destroyCount).assertEqual(1);
    });

    it('doesNotLetDestroyFailureOverrideSuccessfulResponse', 0, async () => {
      const factory = new CapturingTransportFactory();
      factory.transport.throwOnDestroy = true;
      const response = await new ZhihuHttpClient(undefined, factory).execute({
        url: 'https://www.zhihu.com/api/v4/test'
      });
      expect(response.statusCode).assertEqual(200);
      expect(factory.transport.destroyCount).assertEqual(1);
    });

    it('turnsStatusIntoStructuredFailureAndDestroysTransport', 0, async () => {
      const factory = new CapturingTransportFactory();
      factory.transport.response = { statusCode: 503, body: 'upstream body must not leak' };
      let failure: HttpFailure | undefined = undefined;
      try {
        await new ZhihuHttpClient(undefined, factory).execute({ url: 'https://www.zhihu.com/api/v4/test' });
      } catch (error) {
        failure = error as HttpFailure;
      }
      expect(failure?.kind).assertEqual(HttpFailureKind.SERVER);
      expect(failure?.status).assertEqual(503);
      expect(failure?.retryable).assertTrue();
      expect((failure as HttpFailure).message.includes('upstream body')).assertFalse();
      expect(factory.transport.destroyCount).assertEqual(1);
    });

    it('rejectsRedirectResponseWithoutFollowingIt', 0, async () => {
      const factory = new CapturingTransportFactory();
      factory.transport.response = { statusCode: 302, body: 'redirect target is not exposed' };
      let failure: HttpFailure | undefined = undefined;
      try {
        await new ZhihuHttpClient(undefined, factory).execute({ url: 'https://www.zhihu.com/api/v4/test' });
      } catch (error) {
        failure = error as HttpFailure;
      }
      expect(factory.transport.requestValue?.maxRedirects).assertEqual(0);
      expect(failure?.kind).assertEqual(HttpFailureKind.CLIENT);
      expect(failure?.status).assertEqual(302);
      expect(failure?.retryable).assertFalse();
      expect(factory.transport.destroyCount).assertEqual(1);
    });

    it('cancelsNonSettlingTransportAndAllowsImmediateReplacement', 0, async () => {
      const factory = new CancellingTransportFactory();
      const client = new ZhihuHttpClient(undefined, factory);
      const pending = client.execute({ url: 'https://www.zhihu.com/api/v4/test' });
      client.cancel();
      const replacement = await client.execute({ url: 'https://www.zhihu.com/api/v4/replacement' });
      let failure: HttpFailure | undefined = undefined;
      try {
        await pending;
      } catch (error) {
        failure = error as HttpFailure;
      }
      expect(failure?.kind).assertEqual(HttpFailureKind.CANCELLED);
      expect(replacement.statusCode).assertEqual(200);
      expect(factory.transport.destroyCount).assertEqual(1);
      expect(factory.replacement.destroyCount).assertEqual(1);
    });
  });
}
