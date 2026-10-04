import { describe, expect, it } from '@ohos/hypium';
import {
  buildReadHistoryAddBody,
  DefaultReadHistoryUploadRepository,
  PreparedZhihuHttpRequest,
  READ_HISTORY_ADD_URL,
  readHistoryAddPairOf,
  readHistoryProfilePairOf,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpMethod,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class UploadCookieProvider implements SessionCookieProvider {
  private readonly cookies: Array<SessionCookie>;

  constructor(cookies: Array<SessionCookie>) {
    this.cookies = cookies;
  }

  getCookies(): Array<SessionCookie> {
    return this.cookies;
  }
}

class UploadTransport implements ZhihuHttpTransport {
  private readonly response: ZhihuHttpResponse;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(response: ZhihuHttpResponse) {
    this.response = response;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    return Promise.resolve(this.response);
  }

  destroy(): void {
  }
}

class UploadTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: UploadTransport;

  constructor(response: ZhihuHttpResponse) {
    this.transport = new UploadTransport(response);
  }

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

const OK_RESPONSE: ZhihuHttpResponse = { statusCode: 200, body: '' };

export default function readHistoryUploadRepositoryTest(): void {
  describe('readHistoryUploadRepositoryTest', () => {
    it('parsesValidContentKeysAndRejectsOthers', 0, () => {
      expect(readHistoryAddPairOf('answer:200001').contentType).assertEqual('answer');
      expect(readHistoryAddPairOf('answer:200001').contentToken).assertEqual('200001');
      expect(readHistoryAddPairOf('question:100001').contentType).assertEqual('question');
      expect(readHistoryAddPairOf('article:300001').contentType).assertEqual('article');
      expect(readHistoryAddPairOf('pin:400001').contentType).assertEqual('pin');

      const invalid: Array<string> = ['', ':', 'answer:', ':200001', 'profile:600001',
        'video:700001', 'answer:0', 'answer:00', 'answer:abc', 'answer:-1',
        'answer:1:2', 'answer:200001 '];
      invalid.forEach((key: string): void => {
        let failed = false;
        try {
          readHistoryAddPairOf(key);
        } catch (_error) {
          failed = true;
        }
        expect(failed).assertTrue();
      });
    });

    it('buildsAddBodyWithTokenAndType', 0, () => {
      expect(buildReadHistoryAddBody({ contentToken: '200001', contentType: 'answer' }))
        .assertEqual('{"content_token":"200001","content_type":"answer"}');
    });

    it('postsSignedAddRequestForValidKey', 0, async () => {
      const provider = new UploadCookieProvider([
        { name: 'z_c0', value: 'login' },
        { name: 'd_c0', value: 'device' }
      ]);
      const factory = new UploadTransportFactory(OK_RESPONSE);
      const repository = new DefaultReadHistoryUploadRepository(
        new ZhihuHttpClient(provider, factory), provider);
      await repository.add('answer:200001');
      expect(factory.transport.requests.length).assertEqual(1);
      const request = factory.transport.requests[0];
      expect(request.url).assertEqual(READ_HISTORY_ADD_URL);
      expect(request.method).assertEqual(ZhihuHttpMethod.POST);
      expect(request.body).assertEqual('{"content_token":"200001","content_type":"answer"}');
      const serializedHeaders = JSON.stringify(request.headers);
      expect(serializedHeaders.includes('"x-zse-93":"101_3_3.0"')).assertTrue();
      expect(serializedHeaders.includes('"x-zse-96":"2.0_')).assertTrue();
      expect(serializedHeaders.includes('"Content-Type":"application/json"')).assertTrue();
      expect(request.headers.Cookie !== undefined).assertTrue();
    });

    it('skipsSilentlyWithoutDeviceCookie', 0, async () => {
      const provider = new UploadCookieProvider([{ name: 'z_c0', value: 'login' }]);
      const factory = new UploadTransportFactory(OK_RESPONSE);
      const repository = new DefaultReadHistoryUploadRepository(
        new ZhihuHttpClient(provider, factory), provider);
      await repository.add('answer:200001');
      expect(factory.transport.requests.length).assertEqual(0);
    });

    it('propagatesHttpFailuresToCaller', 0, async () => {
      const provider = new UploadCookieProvider([{ name: 'd_c0', value: 'device' }]);
      const factory = new UploadTransportFactory({ statusCode: 401, body: '' });
      const repository = new DefaultReadHistoryUploadRepository(
        new ZhihuHttpClient(provider, factory), provider);
      let failed = false;
      try {
        await repository.add('article:300001');
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect(factory.transport.requests.length).assertEqual(1);
    });

    it('parsesProfileIdsAndPostsProfileType', 0, async () => {
      expect(readHistoryProfilePairOf('600001').contentType).assertEqual('profile');
      expect(readHistoryProfilePairOf('600001').contentToken).assertEqual('600001');
      const invalid: Array<string> = ['', 'abc', '0', '007', '-1', '1:2'];
      invalid.forEach((id: string): void => {
        let failed = false;
        try {
          readHistoryProfilePairOf(id);
        } catch (_error) {
          failed = true;
        }
        expect(failed).assertTrue();
      });

      const provider = new UploadCookieProvider([
        { name: 'z_c0', value: 'login' },
        { name: 'd_c0', value: 'device' }
      ]);
      const factory = new UploadTransportFactory(OK_RESPONSE);
      const repository = new DefaultReadHistoryUploadRepository(
        new ZhihuHttpClient(provider, factory), provider);
      await repository.addProfile('600001');
      expect(factory.transport.requests.length).assertEqual(1);
      const request = factory.transport.requests[0];
      expect(request.url).assertEqual(READ_HISTORY_ADD_URL);
      expect(request.body).assertEqual('{"content_token":"600001","content_type":"profile"}');
    });
  });
}
