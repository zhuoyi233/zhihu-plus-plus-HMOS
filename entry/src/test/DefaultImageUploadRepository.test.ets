import { describe, expect, it } from '@ohos/hypium';
import {
  DefaultImageUploadRepository,
  HttpFailure,
  HttpFailureKind,
  ImageUploadBinary,
  ImageUploadBinaryReader,
  ImageUploadFailure,
  ImageUploadFailureKind,
  ImageUploadInput,
  ImageUploadPollDelay,
  ImageUploadSource,
  OssImageUploadRequest,
  OssImageUploadResponse,
  OssImageUploadTransport,
  PickedImageFormat,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  toImageUploadFailure,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

const HASH: string = '900150983cd24fb0d6963f7d28e17f72';
const CONTROLLED_PNG_URI: string =
  'file:///data/storage/el2/base/cache/p4-images/0123456789abcdef0123456789abcdef.png';
const CONTROLLED_GIF_URI: string =
  'file:///data/storage/el2/base/cache/p4-images/0123456789abcdef0123456789abcdef.gif';
const APPLY_RESPONSE: string =
  '{"upload_file":{"image_id":"123","state":2},"upload_token":' +
  '{"access_id":"TESTACCESSID123456","access_key":"test-access-key-0123456789abcdef",' +
  '"access_token":"test-security-token-0123456789abcdef"}}';
const COMPLETE_STATUS: string =
  '{"status":"success","src":"https://picx.zhimg.com/v2-safe.png",' +
  '"original_src":"https://picx.zhimg.com/v2-original.png","watermark":"original"}';

class UploadSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'test-login-token' },
      { name: 'd_c0', value: 'test-device-token' },
      { name: '_xsrf', value: 'test-xsrf-token' }
    ];
  }
}

class SequenceZhihuTransport implements ZhihuHttpTransport {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest>;
  readonly events: Array<string>;

  constructor(responses: Array<ZhihuHttpResponse>, requests: Array<PreparedZhihuHttpRequest>, events: Array<string>) {
    this.responses = responses;
    this.requests = requests;
    this.events = events;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    this.events.push('api:' + request.url);
    const response = this.responses[this.index];
    this.index += 1;
    if (response === undefined) {
      return Promise.reject(new Error('unexpected test API request'));
    }
    return Promise.resolve(response);
  }

  destroy(): void {
  }
}

class SequenceZhihuTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private readonly requests: Array<PreparedZhihuHttpRequest>;
  private readonly events: Array<string>;
  private index: number = 0;

  constructor(responses: Array<ZhihuHttpResponse>, requests: Array<PreparedZhihuHttpRequest>, events: Array<string>) {
    this.responses = responses;
    this.requests = requests;
    this.events = events;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new SequenceZhihuTransport([response], this.requests, this.events);
  }
}

class TestBinary implements ImageUploadBinary {
  readonly mimeType: string;
  readonly byteLength: number;
  readonly format: PickedImageFormat;
  readonly width: number;
  readonly height: number;
  readonly readRanges: Array<string> = [];
  closeCount: number = 0;

  constructor(mimeType: string, byteLength: number, format: PickedImageFormat, width: number, height: number) {
    this.mimeType = mimeType;
    this.byteLength = byteLength;
    this.format = format;
    this.width = width;
    this.height = height;
  }

  digestMd5(): Promise<string> {
    return Promise.resolve(HASH);
  }

  readPart(offset: number, length: number): Promise<ArrayBuffer> {
    this.readRanges.push(offset + ':' + length);
    return Promise.resolve(new ArrayBuffer(length));
  }

  close(): Promise<void> {
    this.closeCount += 1;
    return Promise.resolve();
  }
}

class TestBinaryReader implements ImageUploadBinaryReader {
  readonly binary: ImageUploadBinary;
  readonly openedInputs: Array<ImageUploadInput> = [];
  cancelCount: number = 0;

  constructor(binary: ImageUploadBinary) {
    this.binary = binary;
  }

  open(input: ImageUploadInput): Promise<ImageUploadBinary> {
    this.openedInputs.push(input);
    return Promise.resolve(this.binary);
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class PendingBinaryReader implements ImageUploadBinaryReader {
  private resolveOpen?: (binary: ImageUploadBinary) => void;
  cancelCount: number = 0;

  open(_input: ImageUploadInput): Promise<ImageUploadBinary> {
    return new Promise<ImageUploadBinary>((resolve: (binary: ImageUploadBinary) => void): void => {
      this.resolveOpen = resolve;
    });
  }

  resolve(binary: ImageUploadBinary): void {
    this.resolveOpen?.(binary);
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class RecordingOssTransport implements OssImageUploadTransport {
  private readonly responses: Array<OssImageUploadResponse>;
  private index: number = 0;
  readonly requests: Array<OssImageUploadRequest> = [];
  readonly events: Array<string>;
  cancelCount: number = 0;

  constructor(responses: Array<OssImageUploadResponse>, events: Array<string>) {
    this.responses = responses;
    this.events = events;
  }

  execute(request: OssImageUploadRequest): Promise<OssImageUploadResponse> {
    this.requests.push(request);
    this.events.push('oss:' + request.method);
    const response = this.responses[this.index];
    this.index += 1;
    if (response === undefined) {
      return Promise.reject(new Error('unexpected test OSS request'));
    }
    return Promise.resolve(response);
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class RecordingPollDelay implements ImageUploadPollDelay {
  readonly delays: Array<number> = [];

  wait(delayMillis: number): Promise<void> {
    this.delays.push(delayMillis);
    return Promise.resolve();
  }
}

function pngInput(): ImageUploadInput {
  return { sourceUri: CONTROLLED_PNG_URI, mimeType: 'image/png', byteLength: 4 };
}

function gifInput(byteLength: number): ImageUploadInput {
  return { sourceUri: CONTROLLED_GIF_URI, mimeType: 'image/gif', byteLength: byteLength };
}

function apiClient(
  responses: Array<ZhihuHttpResponse>,
  requests: Array<PreparedZhihuHttpRequest>,
  events: Array<string>
): ZhihuHttpClient {
  return new ZhihuHttpClient(new UploadSessionProvider(), new SequenceZhihuTransportFactory(responses, requests, events));
}

export default function defaultImageUploadRepositoryTest(): void {
  describe('defaultImageUploadRepositoryTest', () => {
    it('uploadsSingleImageInFixedApiOssNotifyAndPollOrderWithoutSessionLeak', 0, async () => {
      const apiRequests: Array<PreparedZhihuHttpRequest> = [];
      const events: Array<string> = [];
      const binary = new TestBinary('image/png', 4, PickedImageFormat.PNG, 3, 2);
      const reader = new TestBinaryReader(binary);
      const oss = new RecordingOssTransport([{ statusCode: 200 }], events);
      const delay = new RecordingPollDelay();
      const repository = new DefaultImageUploadRepository(
        apiClient([
          { statusCode: 200, body: APPLY_RESPONSE },
          { statusCode: 200, body: '{}' },
          { statusCode: 200, body: '{"status":"processing"}' },
          { statusCode: 200, body: COMPLETE_STATUS }
        ], apiRequests, events),
        reader,
        oss,
        ImageUploadSource.PIN,
        delay
      );

      const uploaded = await repository.upload(pngInput());

      expect(uploaded.imageId).assertEqual('123');
      expect(uploaded.url).assertEqual('https://picx.zhimg.com/v2-safe.png');
      expect(uploaded.originalUrl).assertEqual('https://picx.zhimg.com/v2-original.png');
      expect(uploaded.width).assertEqual(3);
      expect(uploaded.height).assertEqual(2);
      expect(uploaded.watermark).assertEqual('original');
      expect(reader.openedInputs.length).assertEqual(1);
      expect(binary.readRanges[0]).assertEqual('0:4');
      expect(binary.closeCount).assertEqual(1);
      expect(apiRequests.length).assertEqual(4);
      expect(apiRequests[0].url).assertEqual('https://api.zhihu.com/images');
      expect(apiRequests[1].url).assertEqual('https://api.zhihu.com/images/123/uploading_status');
      expect(apiRequests[2].url).assertEqual('https://api.zhihu.com/images/123');
      expect(apiRequests[0].headers.Cookie === undefined).assertFalse();
      expect(JSON.stringify(apiRequests[0].headers).includes('x-zse-96')).assertTrue();
      expect(oss.requests.length).assertEqual(1);
      expect(oss.requests[0].url).assertEqual('https://zhihu-pics-upload.zhimg.com/v2-' + HASH);
      expect(oss.requests[0].maxRedirects).assertEqual(0);
      expect(JSON.stringify(oss.requests[0]).includes('Cookie')).assertFalse();
      expect(JSON.stringify(oss.requests[0]).includes('x-zse-')).assertFalse();
      expect(events[0]).assertEqual('api:https://api.zhihu.com/images');
      expect(events[1]).assertEqual('oss:PUT');
      expect(events[2]).assertEqual('api:https://api.zhihu.com/images/123/uploading_status');
      expect(delay.delays.length).assertEqual(1);
      expect(delay.delays[0]).assertEqual(2000);
    });

    it('uploadsGifAsBoundedMultipartAndRequiresEveryEtag', 0, async () => {
      const apiRequests: Array<PreparedZhihuHttpRequest> = [];
      const events: Array<string> = [];
      const byteLength: number = 1024 * 1024 + 7;
      const binary = new TestBinary('image/gif', byteLength, PickedImageFormat.GIF, 4, 3);
      const oss = new RecordingOssTransport([
        { statusCode: 200, body: '<UploadId>upload-123</UploadId>' },
        { statusCode: 200, etag: '"abcdef0123456789"' },
        { statusCode: 200, etag: 'abcdef0123456789' },
        { statusCode: 200 }
      ], events);
      const repository = new DefaultImageUploadRepository(
        apiClient([
          { statusCode: 200, body: APPLY_RESPONSE },
          { statusCode: 200, body: '{}' },
          { statusCode: 200, body: COMPLETE_STATUS }
        ], apiRequests, events),
        new TestBinaryReader(binary),
        oss,
        ImageUploadSource.PIN,
        new RecordingPollDelay()
      );

      const uploaded = await repository.upload(gifInput(byteLength));

      expect(uploaded.imageId).assertEqual('123');
      expect(binary.readRanges.length).assertEqual(2);
      expect(binary.readRanges[0]).assertEqual('0:1048576');
      expect(binary.readRanges[1]).assertEqual('1048576:7');
      expect(oss.requests.length).assertEqual(4);
      expect(oss.requests[0].url.endsWith('?uploads')).assertTrue();
      expect(oss.requests[1].url.includes('partNumber=1&uploadId=upload-123')).assertTrue();
      expect(oss.requests[3].body instanceof ArrayBuffer).assertFalse();
      expect(binary.closeCount).assertEqual(1);
      expect(apiRequests.length).assertEqual(3);
    });

    it('mapsApiAndOssFailuresWithoutExposingUpstreamOrCredentialData', 0, async () => {
      const apiRequests: Array<PreparedZhihuHttpRequest> = [];
      const events: Array<string> = [];
      const repository = new DefaultImageUploadRepository(
        apiClient([{ statusCode: 200, body: APPLY_RESPONSE }], apiRequests, events),
        new TestBinaryReader(new TestBinary('image/png', 4, PickedImageFormat.PNG, 1, 1)),
        new RecordingOssTransport([{ statusCode: 403, body: 'token=test-security-token-must-not-leak' }], events),
        ImageUploadSource.ANSWER,
        new RecordingPollDelay()
      );
      let failure: ImageUploadFailure | undefined = undefined;
      try {
        await repository.upload(pngInput());
      } catch (error) {
        if (error instanceof ImageUploadFailure) {
          failure = error;
        }
      }

      expect(failure?.kind).assertEqual(ImageUploadFailureKind.FORBIDDEN);
      expect(failure?.message.includes('test-security-token')).assertFalse();
      expect(apiRequests[0].body?.includes('"source":"article"')).assertTrue();
      expect(toImageUploadFailure(new HttpFailure(HttpFailureKind.RATE_LIMITED, 429)).kind)
        .assertEqual(ImageUploadFailureKind.RATE_LIMITED);
      expect(toImageUploadFailure(new HttpFailure(HttpFailureKind.TIMEOUT, 504)).kind)
        .assertEqual(ImageUploadFailureKind.TIMEOUT);
      expect(toImageUploadFailure(new HttpFailure(HttpFailureKind.SERVER, 503)).retryable).assertTrue();
      expect(toImageUploadFailure(new HttpFailure(HttpFailureKind.AUTHENTICATION, 401)).kind)
        .assertEqual(ImageUploadFailureKind.AUTHENTICATION);
    });

    it('cancelsPendingOpenBeforeAnyApiOrOssWriteAndClosesLateBinary', 0, async () => {
      const apiRequests: Array<PreparedZhihuHttpRequest> = [];
      const events: Array<string> = [];
      const reader = new PendingBinaryReader();
      const oss = new RecordingOssTransport([], events);
      const repository = new DefaultImageUploadRepository(
        apiClient([], apiRequests, events),
        reader,
        oss,
        ImageUploadSource.PIN,
        new RecordingPollDelay()
      );
      const pending = repository.upload(pngInput());
      repository.cancel();
      const binary = new TestBinary('image/png', 4, PickedImageFormat.PNG, 1, 1);
      reader.resolve(binary);
      let failure: ImageUploadFailure | undefined = undefined;
      try {
        await pending;
      } catch (error) {
        if (error instanceof ImageUploadFailure) {
          failure = error;
        }
      }

      expect(failure?.kind).assertEqual(ImageUploadFailureKind.CANCELLED);
      expect(reader.cancelCount).assertEqual(1);
      expect(oss.cancelCount).assertEqual(1);
      expect(apiRequests.length).assertEqual(0);
      expect(oss.requests.length).assertEqual(0);
      expect(binary.closeCount).assertEqual(1);
    });

    it('rejectsNonControlledUriOrMismatchedOpenedMetadataBeforeNetwork', 0, async () => {
      const apiRequests: Array<PreparedZhihuHttpRequest> = [];
      const events: Array<string> = [];
      const reader = new TestBinaryReader(new TestBinary('image/jpeg', 4, PickedImageFormat.JPEG, 1, 1));
      const oss = new RecordingOssTransport([], events);
      const repository = new DefaultImageUploadRepository(
        apiClient([], apiRequests, events),
        reader,
        oss,
        ImageUploadSource.PIN,
        new RecordingPollDelay()
      );
      let unsafeFailure: ImageUploadFailure | undefined = undefined;
      let mismatchFailure: ImageUploadFailure | undefined = undefined;
      try {
        await repository.upload({ sourceUri: 'https://evil.example/image.png', mimeType: 'image/png', byteLength: 4 });
      } catch (error) {
        if (error instanceof ImageUploadFailure) {
          unsafeFailure = error;
        }
      }
      try {
        await repository.upload(pngInput());
      } catch (error) {
        if (error instanceof ImageUploadFailure) {
          mismatchFailure = error;
        }
      }

      expect(unsafeFailure?.kind).assertEqual(ImageUploadFailureKind.INVALID_INPUT);
      expect(mismatchFailure?.kind).assertEqual(ImageUploadFailureKind.INVALID_INPUT);
      expect(reader.openedInputs.length).assertEqual(1);
      expect(apiRequests.length).assertEqual(0);
      expect(oss.requests.length).assertEqual(0);
    });
  });
}
