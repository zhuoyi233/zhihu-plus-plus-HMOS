import { describe, expect, it } from '@ohos/hypium';
import {
  buildLastReadTouchMultipart,
  buildLastReadTouchPayload,
  DefaultLastReadTouchRepository,
  LASTREAD_TOUCH_URL,
  lastReadTouchContentTypeOf,
  LastReadTouchEntry,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class TouchCookieProvider implements SessionCookieProvider {
  private readonly cookies: Array<SessionCookie>;

  constructor(cookies: Array<SessionCookie>) {
    this.cookies = cookies;
  }

  getCookies(): Array<SessionCookie> {
    return this.cookies;
  }
}

class TouchTransport implements ZhihuHttpTransport {
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

class TouchTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: TouchTransport;

  constructor(response: ZhihuHttpResponse) {
    this.transport = new TouchTransport(response);
  }

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

const OK_RESPONSE: ZhihuHttpResponse = { statusCode: 200, body: '' };

function entry(kind: string, id: string, action: string): LastReadTouchEntry {
  return { kind: kind, id: id, action: action };
}

export default function lastReadTouchRepositoryTest(): void {
  describe('lastReadTouchRepositoryTest', () => {
    it('buildsTuplePayloadAndRejectsInvalidEntries', 0, () => {
      expect(buildLastReadTouchPayload([entry('answer', '123', 'read')]))
        .assertEqual('[["answer","123","read"]]');
      expect(buildLastReadTouchPayload([entry('article', '1', 'touch'), entry('pin', '2', 'read')]))
        .assertEqual('[["article","1","touch"],["pin","2","read"]]');

      const invalid: Array<LastReadTouchEntry> = [
        entry('question', '1', 'read'),
        entry('video', '1', 'touch'),
        entry('answer', '0', 'read'),
        entry('answer', 'abc', 'read'),
        entry('answer', '1', 'hover'),
        entry('answer', '', 'read')
      ];
      invalid.forEach((candidate: LastReadTouchEntry): void => {
        let failed = false;
        try {
          buildLastReadTouchPayload([candidate]);
        } catch (_error) {
          failed = true;
        }
        expect(failed).assertTrue();
      });
    });

    it('buildsMultipartBodyAndContentType', 0, () => {
      const boundary = '0123456789abcdef';
      const body = buildLastReadTouchMultipart([entry('answer', '123', 'read')], boundary);
      const expected = '--0123456789abcdef\r\n' +
        'Content-Disposition: form-data; name="items"\r\n' +
        '\r\n' +
        '[["answer","123","read"]]\r\n' +
        '--0123456789abcdef--\r\n';
      expect(body).assertEqual(expected);
      expect(lastReadTouchContentTypeOf(boundary))
        .assertEqual('multipart/form-data; boundary=0123456789abcdef');

      let failed = false;
      try {
        buildLastReadTouchMultipart([entry('answer', '123', 'read')], 'SHORT');
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });

    it('postsSignedMultipartTouchRequest', 0, async () => {
      const provider = new TouchCookieProvider([
        { name: 'z_c0', value: 'login' },
        { name: 'd_c0', value: 'device' }
      ]);
      const factory = new TouchTransportFactory(OK_RESPONSE);
      const repository = new DefaultLastReadTouchRepository(new ZhihuHttpClient(provider, factory), provider);
      await repository.report([entry('answer', '123', 'touch'), entry('article', '456', 'touch')]);
      expect(factory.transport.requests.length).assertEqual(1);
      const request = factory.transport.requests[0];
      expect(request.url).assertEqual(LASTREAD_TOUCH_URL);
      expect(request.method).assertEqual('POST');
      const serializedHeaders = JSON.stringify(request.headers);
      const boundaryMarker = '"Content-Type":"multipart/form-data; boundary=';
      const markerStart = serializedHeaders.indexOf(boundaryMarker);
      expect(markerStart >= 0).assertTrue();
      const boundary = markerStart >= 0
        ? serializedHeaders.substring(markerStart + boundaryMarker.length,
          markerStart + boundaryMarker.length + 16)
        : '';
      expect(boundary.length).assertEqual(16);
      const expectedBody = `--${boundary}\r\n` +
        'Content-Disposition: form-data; name="items"\r\n' +
        '\r\n' +
        '[["answer","123","touch"],["article","456","touch"]]\r\n' +
        `--${boundary}--\r\n`;
      expect(request.body).assertEqual(expectedBody);
      expect(serializedHeaders.includes('"x-zse-93":"101_3_3.0"')).assertTrue();
      expect(serializedHeaders.includes('"x-zse-96":"2.0_')).assertTrue();
    });

    it('skipsEmptyEntriesAndGuestSession', 0, async () => {
      const guestProvider = new TouchCookieProvider([{ name: 'z_c0', value: 'login' }]);
      const guestFactory = new TouchTransportFactory(OK_RESPONSE);
      const guestRepository = new DefaultLastReadTouchRepository(
        new ZhihuHttpClient(guestProvider, guestFactory), guestProvider);
      await guestRepository.report([entry('answer', '123', 'read')]);
      expect(guestFactory.transport.requests.length).assertEqual(0);

      const provider = new TouchCookieProvider([
        { name: 'z_c0', value: 'login' },
        { name: 'd_c0', value: 'device' }
      ]);
      const factory = new TouchTransportFactory(OK_RESPONSE);
      const repository = new DefaultLastReadTouchRepository(new ZhihuHttpClient(provider, factory), provider);
      await repository.report([]);
      expect(factory.transport.requests.length).assertEqual(0);
    });
  });
}
