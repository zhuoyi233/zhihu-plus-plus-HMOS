import { HttpFailure, HttpFailureKind, httpFailureFromStatus } from '../network/HttpFailure';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import {
  ImageUploadInput,
  ImageUploadRepository,
  UploadedZhihuImage
} from './CreationPublishRepository';
import {
  buildGifMultipartCompleteRequest,
  buildGifMultipartInitRequest,
  buildGifMultipartPartRequest,
  buildImageApplyRequest,
  buildImageStatusRequest,
  buildImageUploadingStatusRequest,
  buildOssSinglePutRequest,
  createGifUploadParts,
  ImageStatusResult,
  ImageUploadFailure,
  ImageUploadFailureKind,
  ImageUploadHttpContract,
  ImageUploadSource,
  OssRequestHeaders,
  OssTemporaryCredential,
  nextImageStatusPoll,
  parseImageApplyResult,
  parseImageStatusResult,
  parseOssMultipartUploadId,
  PickedImageFormat,
  requireOssEtag
} from './ImageUploadContracts';

const CONTROLLED_IMAGE_FILE_URI: RegExp =
  /^file:\/\/(?:\/[A-Za-z0-9._~-]+)+\/p4-images\/[a-f0-9]{32}\.(?:jpg|png|webp|gif)$/;
const SAFE_IMAGE_HASH: RegExp = /^[a-f0-9]{32}$/;
const SAFE_OSS_UPLOAD_URL: RegExp =
  /^https:\/\/zhihu-pics-upload\.zhimg\.com\/v2-[a-f0-9]{32}(?:\?(?:uploads|uploadId=[A-Za-z0-9._~%=-]+|partNumber=[1-9][0-9]*&uploadId=[A-Za-z0-9._~%=-]+))?$/;
const MAX_UPLOAD_BYTES: number = 20 * 1024 * 1024;

/**
 * 已经通过 Photo Picker 和受控缓存门禁的二进制读取句柄。读取器不得将原图、哈希或路径写入日志，
 * 也不得为草稿、Preferences 或数据库保存任何字节。仓储只在本次 upload 调用中临时持有该句柄。
 */
export interface ImageUploadBinary {
  readonly mimeType: string;
  readonly byteLength: number;
  readonly format: PickedImageFormat;
  readonly width: number;
  readonly height: number;
  digestMd5(): Promise<string>;
  readPart(offset: number, length: number): Promise<ArrayBuffer>;
  close(): Promise<void>;
}

/** 组合根只可从 cache/p4-images 的应用生成 file:// URI 打开图片。 */
export interface ImageUploadBinaryReader {
  open(input: ImageUploadInput): Promise<ImageUploadBinary>;
  cancel(): void;
}

/**
 * OSS 边界故意不复用 ZhihuHttpClient：它没有 Cookie、ZSE、_xsrf 或通用外部 URL 能力，
 * 且临时凭证仅存于单次 request.headers 对象中。
 */
export interface OssImageUploadRequest {
  readonly url: string;
  readonly method: ZhihuHttpMethod;
  readonly body?: string | ArrayBuffer;
  readonly contentType?: string;
  readonly headers: OssRequestHeaders;
  readonly maxRedirects: 0;
}

/** 传输实现只返回协议所需状态、XML 和 ETag；不得保存或记录 Authorization、Token 或图片字节。 */
export interface OssImageUploadResponse {
  readonly statusCode: number;
  readonly body?: string;
  readonly etag?: string;
}

export interface OssImageUploadTransport {
  execute(request: OssImageUploadRequest): Promise<OssImageUploadResponse>;
  cancel(): void;
}

/** 将轮询等待封装为可替换边界，测试不会真的等待两秒。 */
export interface ImageUploadPollDelay {
  wait(delayMillis: number): Promise<void>;
}

class SystemImageUploadPollDelay implements ImageUploadPollDelay {
  wait(delayMillis: number): Promise<void> {
    return new Promise<void>((resolve): void => {
      setTimeout(resolve, delayMillis);
    });
  }
}

/**
 * 知乎图片上传的生产仓储。申请和状态请求严格委托给已认证 ZhihuHttpClient；
 * OSS 请求仅通过窄传输器发出，先验证精确 URL、禁重定向且不会附带会话数据。
 */
export class DefaultImageUploadRepository implements ImageUploadRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly binaryReader: ImageUploadBinaryReader;
  private readonly ossTransport: OssImageUploadTransport;
  private readonly source: ImageUploadSource;
  private readonly pollDelay: ImageUploadPollDelay;
  private generation: number = 0;

  constructor(
    httpClient: ZhihuHttpClient,
    binaryReader: ImageUploadBinaryReader,
    ossTransport: OssImageUploadTransport,
    source: ImageUploadSource,
    pollDelay: ImageUploadPollDelay = new SystemImageUploadPollDelay()
  ) {
    if (source !== ImageUploadSource.ANSWER && source !== ImageUploadSource.PIN) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    this.httpClient = httpClient;
    this.binaryReader = binaryReader;
    this.ossTransport = ossTransport;
    this.source = source;
    this.pollDelay = pollDelay;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
    this.binaryReader.cancel();
    this.ossTransport.cancel();
  }

  async upload(input: ImageUploadInput): Promise<UploadedZhihuImage> {
    validateImageUploadInput(input);
    const requestGeneration = this.generation;
    let binary: ImageUploadBinary | undefined = undefined;
    try {
      binary = await this.binaryReader.open(input);
      this.assertCurrent(requestGeneration);
      validateOpenedBinary(input, binary);
      const imageHash = await binary.digestMd5();
      this.assertCurrent(requestGeneration);
      if (!SAFE_IMAGE_HASH.test(imageHash)) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }

      const applyResponse = await this.executeZhihuApi(
        buildImageApplyRequest(imageHash, this.source),
        requestGeneration
      );
      const apply = parseImageApplyResult(applyResponse.body);
      this.assertCurrent(requestGeneration);
      if (apply.requiresUpload) {
        if (apply.credential === undefined) {
          throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
        }
        if (binary.format === PickedImageFormat.GIF) {
          await this.uploadGif(binary, imageHash, apply.credential, requestGeneration);
        } else {
          await this.uploadSingle(binary, imageHash, apply.credential, requestGeneration);
        }
        await this.executeZhihuApi(buildImageUploadingStatusRequest(apply.imageId), requestGeneration);
      }
      const status = await this.pollStatus(apply.imageId, requestGeneration);
      return toUploadedImage(status, binary);
    } catch (error) {
      throw toImageUploadFailure(error);
    } finally {
      if (binary !== undefined) {
        try {
          await binary.close();
        } catch (_error) {
          // 读取器的资源回收失败不能泄漏任何文件、字节或平台异常；缓存过期回收会再次处理。
        }
      }
    }
  }

  private async uploadSingle(
    binary: ImageUploadBinary,
    imageHash: string,
    credential: OssTemporaryCredential,
    requestGeneration: number
  ): Promise<void> {
    const body = await binary.readPart(0, binary.byteLength);
    this.assertCurrent(requestGeneration);
    requireExactPart(body, binary.byteLength);
    await this.executeOss(
      buildOssSinglePutRequest(imageHash, binary.mimeType, currentOssDate(), credential),
      body,
      requestGeneration
    );
  }

  private async uploadGif(
    binary: ImageUploadBinary,
    imageHash: string,
    credential: OssTemporaryCredential,
    requestGeneration: number
  ): Promise<void> {
    const init = await this.executeOss(
      buildGifMultipartInitRequest(imageHash, currentOssDate(), credential),
      undefined,
      requestGeneration
    );
    const uploadId = parseOssMultipartUploadId(init.body ?? '');
    const parts = createGifUploadParts(binary.byteLength);
    const etags: Array<string> = [];
    for (let index = 0; index < parts.length; index += 1) {
      const part = parts[index];
      const body = await binary.readPart(part.offset, part.length);
      this.assertCurrent(requestGeneration);
      requireExactPart(body, part.length);
      const response = await this.executeOss(
        buildGifMultipartPartRequest(imageHash, uploadId, part, currentOssDate(), credential),
        body,
        requestGeneration
      );
      etags.push(requireOssEtag(response.etag));
    }
    const complete = buildGifMultipartCompleteRequest(imageHash, uploadId, etags, currentOssDate(), credential);
    await this.executeOss(complete, complete.body, requestGeneration);
  }

  private async pollStatus(imageId: string, requestGeneration: number): Promise<ImageStatusResult> {
    for (let attempt = 0; ; attempt += 1) {
      const response = await this.executeZhihuApi(buildImageStatusRequest(imageId), requestGeneration);
      const status = parseImageStatusResult(response.body, imageId);
      if (status.completed) {
        return status;
      }
      const next = nextImageStatusPoll(attempt, false);
      if (!next.shouldContinue) {
        throw new ImageUploadFailure(ImageUploadFailureKind.POLL_TIMEOUT);
      }
      await this.pollDelay.wait(next.delayMillis);
      this.assertCurrent(requestGeneration);
    }
  }

  private async executeZhihuApi(
    contract: ImageUploadHttpContract,
    requestGeneration: number
  ): Promise<ZhihuHttpResponse> {
    if (!contract.useSession || !contract.signWithZse || contract.headers !== undefined || contract.maxRedirects !== 0) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const response = await this.httpClient.execute({
      url: contract.url,
      method: contract.method,
      body: contract.body,
      contentType: contract.contentType,
      accept: 'application/json',
      useSession: true,
      signWithZse: true,
      includeXsrfToken: contract.includeXsrfToken
    });
    this.assertCurrent(requestGeneration);
    return response;
  }

  private async executeOss(
    contract: ImageUploadHttpContract,
    body: string | ArrayBuffer | undefined,
    requestGeneration: number
  ): Promise<OssImageUploadResponse> {
    if (contract.useSession || contract.signWithZse || contract.includeXsrfToken || contract.maxRedirects !== 0 ||
      contract.headers === undefined || !SAFE_OSS_UPLOAD_URL.test(contract.url)) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const response = await this.ossTransport.execute({
      url: contract.url,
      method: contract.method,
      body: body,
      contentType: contract.contentType,
      headers: contract.headers,
      maxRedirects: 0
    });
    this.assertCurrent(requestGeneration);
    throwIfOssStatusFailed(response.statusCode);
    return response;
  }

  private assertCurrent(requestGeneration: number): void {
    if (requestGeneration !== this.generation) {
      throw new ImageUploadFailure(ImageUploadFailureKind.CANCELLED);
    }
  }
}

export function isControlledImageUploadInput(input: ImageUploadInput): boolean {
  return typeof input.sourceUri === 'string' && input.sourceUri.length <= 4096 &&
    CONTROLLED_IMAGE_FILE_URI.test(input.sourceUri) && !input.sourceUri.includes('..') &&
    input.mimeType === mimeTypeForUri(input.sourceUri) && Number.isSafeInteger(input.byteLength) &&
    input.byteLength > 0 && input.byteLength <= MAX_UPLOAD_BYTES;
}

/** 将 HTTP/传输失败压缩为稳定、无响应原文的图片上传错误。 */
export function toImageUploadFailure(error: Object): ImageUploadFailure {
  if (error instanceof ImageUploadFailure) {
    return error;
  }
  if (!(error instanceof HttpFailure)) {
    return new ImageUploadFailure(ImageUploadFailureKind.NETWORK);
  }
  if (error.kind === HttpFailureKind.AUTHENTICATION) {
    return new ImageUploadFailure(error.status === 403
      ? ImageUploadFailureKind.FORBIDDEN
      : ImageUploadFailureKind.AUTHENTICATION);
  }
  if (error.kind === HttpFailureKind.RATE_LIMITED) return new ImageUploadFailure(ImageUploadFailureKind.RATE_LIMITED);
  if (error.kind === HttpFailureKind.TIMEOUT) return new ImageUploadFailure(ImageUploadFailureKind.TIMEOUT);
  if (error.kind === HttpFailureKind.SERVER) return new ImageUploadFailure(ImageUploadFailureKind.SERVER);
  if (error.kind === HttpFailureKind.CANCELLED) return new ImageUploadFailure(ImageUploadFailureKind.CANCELLED);
  if (error.kind === HttpFailureKind.CLIENT) return new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  return new ImageUploadFailure(ImageUploadFailureKind.NETWORK);
}

function validateImageUploadInput(input: ImageUploadInput): void {
  if (!isControlledImageUploadInput(input)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function validateOpenedBinary(input: ImageUploadInput, binary: ImageUploadBinary): void {
  if (binary.mimeType !== input.mimeType || binary.byteLength !== input.byteLength ||
    !Number.isSafeInteger(binary.width) || !Number.isSafeInteger(binary.height) || binary.width < 1 || binary.height < 1 ||
    binary.width > 8192 || binary.height > 8192 || binary.width * binary.height > 30000000 ||
    !matchesBinaryFormat(binary.format, binary.mimeType)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function matchesBinaryFormat(format: PickedImageFormat, mimeType: string): boolean {
  return (format === PickedImageFormat.JPEG && mimeType === 'image/jpeg') ||
    (format === PickedImageFormat.PNG && mimeType === 'image/png') ||
    (format === PickedImageFormat.WEBP && mimeType === 'image/webp') ||
    (format === PickedImageFormat.GIF && mimeType === 'image/gif');
}

function mimeTypeForUri(uri: string): string | undefined {
  if (uri.endsWith('.jpg')) return 'image/jpeg';
  if (uri.endsWith('.png')) return 'image/png';
  if (uri.endsWith('.webp')) return 'image/webp';
  if (uri.endsWith('.gif')) return 'image/gif';
  return undefined;
}

function requireExactPart(buffer: ArrayBuffer, expectedLength: number): void {
  if (buffer.byteLength !== expectedLength) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function currentOssDate(): string {
  const value = new Date().toUTCString();
  if (!/^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$/.test(value)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return value;
}

function throwIfOssStatusFailed(statusCode: number): void {
  if (Number.isSafeInteger(statusCode) && statusCode >= 200 && statusCode < 300) {
    return;
  }
  if (!Number.isSafeInteger(statusCode) || statusCode < 100 || statusCode > 599) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  const failure = httpFailureFromStatus(statusCode);
  throw toImageUploadFailure(failure ?? new HttpFailure(HttpFailureKind.SERVER, statusCode));
}

function toUploadedImage(status: ImageStatusResult, binary: ImageUploadBinary): UploadedZhihuImage {
  if (!status.completed || status.url === undefined || status.originalUrl === undefined) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  return {
    imageId: status.imageId,
    url: status.url,
    originalUrl: status.originalUrl,
    width: binary.width,
    height: binary.height,
    watermark: status.watermark,
    watermarkUrl: status.watermarkUrl
  };
}
