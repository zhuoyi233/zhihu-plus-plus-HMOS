import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import {
  DefaultImageUploadRepository,
  ImageBinaryDescriptor,
  ImageTemporaryFile,
  ImageUploadBinary,
  ImageUploadBinaryReader,
  ImageUploadFailure,
  ImageUploadFailureKind,
  ImageUploadInput,
  ImageUploadRepository,
  ImageUploadSource,
  isControlledImageUploadInput,
  LocalDraftImageReference,
  OssImageUploadRequest,
  OssImageUploadResponse,
  OssImageUploadTransport,
  PickedImageFormat,
  SessionCookieProvider,
  sniffImageBinary,
  UploadedZhihuImage,
  ZhihuHttpClient,
  ZhihuHttpMethod
} from 'data';
import { buildControlledImageTemporaryPath } from './SystemPickedImageFileStore';

const HEADER_BYTES: number = 65536;
const DIGEST_READ_CHUNK_BYTES: number = 1024 * 1024;
const OSS_CONNECT_TIMEOUT_MS: number = 10000;
const OSS_READ_TIMEOUT_MS: number = 30000;
const OSS_RESPONSE_LIMIT_BYTES: number = 64 * 1024;
const CONTROLLED_OSS_URL: RegExp = /^https:\/\/zhihu-pics-upload\.zhimg\.com\/v2-[a-f0-9]{32}(?:\?.*)?$/;

/** 页面只依赖此窄接口；任何上传都必须由最终确认动作显式触发。 */
export interface ImageAttachmentUploader {
  upload(references: Array<LocalDraftImageReference>): Promise<Array<UploadedZhihuImage>>;
  cancel(): void;
}

export interface ImageAttachmentUploaderFactory {
  create(source: ImageUploadSource): ImageAttachmentUploader;
}

/**
 * 生产上传唯一的本地文件入口。它从已验证的随机缓存名重建 file:// URI，外部调用者无法传入
 * Photo Picker 原始 URI、任意路径或图片字节。
 */
export function createControlledImageUploadInput(cacheDir: string,
  reference: LocalDraftImageReference): ImageUploadInput {
  const file: ImageTemporaryFile = {
    path: buildControlledImageTemporaryPath(cacheDir, reference.fileName),
    mimeType: reference.mimeType,
    byteLength: reference.byteLength,
    createdAtMillis: reference.createdAtMillis
  };
  let sourceUri: string;
  try {
    sourceUri = fileUri.getUriFromPath(file.path);
  } catch (_error) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const input: ImageUploadInput = {
    sourceUri: sourceUri,
    mimeType: file.mimeType,
    byteLength: file.byteLength
  };
  if (!isControlledImageUploadInput(input)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return input;
}

/** 只允许 DefaultImageUploadRepository 打开前述受控 input；读取器不接受其他 file:// URI。 */
export class ControlledImageUploadBinaryReader implements ImageUploadBinaryReader {
  private generation: number = 0;
  private active?: ControlledImageUploadBinary;

  async open(input: ImageUploadInput): Promise<ImageUploadBinary> {
    if (!isControlledImageUploadInput(input)) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const generation = this.generation;
    let fd: number = -1;
    try {
      const opened = await fileIo.open(input.sourceUri, fileIo.OpenMode.READ_ONLY);
      fd = opened.fd;
      const stat = await fileIo.stat(fd);
      if (!stat.isFile() || stat.size !== input.byteLength) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }
      const headerLength = Math.min(stat.size, HEADER_BYTES);
      const header = new ArrayBuffer(headerLength);
      const read = await fileIo.read(fd, header, { offset: 0, length: headerLength });
      if (read !== headerLength) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }
      const descriptor = sniffDescriptor(header, read);
      if (descriptor.mimeType !== input.mimeType) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }
      const binary = new ControlledImageUploadBinary(fd, input, descriptor, generation,
        (): number => this.generation, (): void => this.clearActive());
      fd = -1;
      this.active?.close().catch((): void => {});
      this.active = binary;
      return binary;
    } catch (error) {
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    } finally {
      if (fd >= 0) {
        try {
          await fileIo.close(fd);
        } catch (_error) {
        }
      }
    }
  }

  cancel(): void {
    this.generation += 1;
    const active = this.active;
    this.active = undefined;
    if (active !== undefined) {
      void active.close();
    }
  }

  private clearActive(): void {
    this.active = undefined;
  }
}

class ControlledImageUploadBinary implements ImageUploadBinary {
  readonly mimeType: string;
  readonly byteLength: number;
  readonly format: PickedImageFormat;
  readonly width: number;
  readonly height: number;
  private fd: number;
  private readonly sourceUri: string;
  private readonly generation: number;
  private readonly generationProvider: () => number;
  private readonly onClosed: () => void;

  constructor(fd: number, input: ImageUploadInput, descriptor: ImageBinaryDescriptor, generation: number,
    generationProvider: () => number, onClosed: () => void) {
    this.fd = fd;
    this.sourceUri = input.sourceUri;
    this.mimeType = input.mimeType;
    this.byteLength = input.byteLength;
    this.format = descriptor.format;
    this.width = descriptor.width;
    this.height = descriptor.height;
    this.generation = generation;
    this.generationProvider = generationProvider;
    this.onClosed = onClosed;
  }

  async digestMd5(): Promise<string> {
    this.assertOpen();
    let digest: cryptoFramework.Md | undefined = undefined;
    try {
      digest = cryptoFramework.createMd('MD5');
      let offset = 0;
      while (offset < this.byteLength) {
        const length = Math.min(DIGEST_READ_CHUNK_BYTES, this.byteLength - offset);
        const chunk = await this.readPart(offset, length);
        await digest.update({ data: new Uint8Array(chunk) });
        offset += length;
      }
      const result = await digest.digest();
      return hexDigest(result.data);
    } catch (error) {
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }

  async readPart(offset: number, length: number): Promise<ArrayBuffer> {
    this.assertOpen();
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length < 1 ||
      offset + length > this.byteLength) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const data = new ArrayBuffer(length);
    try {
      const read = await fileIo.read(this.fd, data, { offset: offset, length: length });
      this.assertOpen();
      if (read !== length) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }
      return data;
    } catch (error) {
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }

  async close(): Promise<void> {
    const fd = this.fd;
    this.fd = -1;
    this.onClosed();
    if (fd < 0) {
      return;
    }
    try {
      await fileIo.close(fd);
    } catch (_error) {
    }
  }

  private assertOpen(): void {
    if (this.fd < 0 || this.generation !== this.generationProvider() || !isControlledImageUploadInput({
      sourceUri: this.sourceUri,
      mimeType: this.mimeType,
      byteLength: this.byteLength
    })) {
      throw new ImageUploadFailure(ImageUploadFailureKind.CANCELLED);
    }
  }
}

/** OSS 传输不持有 Cookie、会话、ZSE 或任意外部 URL 能力。 */
export class SystemOssImageUploadTransport implements OssImageUploadTransport {
  private request?: http.HttpRequest;

  async execute(request: OssImageUploadRequest): Promise<OssImageUploadResponse> {
    if (!CONTROLLED_OSS_URL.test(request.url) || request.maxRedirects !== 0) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const client = http.createHttp();
    this.request = client;
    try {
      const options: http.HttpRequestOptions = {
        method: toSystemMethod(request.method),
        header: ossHeaders(request),
        extraData: request.body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: OSS_CONNECT_TIMEOUT_MS,
        readTimeout: OSS_READ_TIMEOUT_MS,
        maxRedirects: 0,
        maxLimit: OSS_RESPONSE_LIMIT_BYTES,
        usingCache: false
      };
      const response = await client.request(request.url, options);
      return {
        statusCode: Number(response.responseCode),
        body: typeof response.result === 'string' ? response.result : undefined,
        etag: responseHeader(response.header, 'etag')
      };
    } catch (_error) {
      throw new ImageUploadFailure(ImageUploadFailureKind.NETWORK);
    } finally {
      if (this.request === client) {
        this.request = undefined;
      }
      try {
        client.destroy();
      } catch (_error) {
      }
    }
  }

  cancel(): void {
    const client = this.request;
    this.request = undefined;
    try {
      client?.destroy();
    } catch (_error) {
    }
  }
}

/** 页面仅在用户点击最终确认后调用 upload；保存草稿和选择/取消路径均不触网。 */
export class ProductionImageAttachmentUploader implements ImageAttachmentUploader {
  private readonly cacheDir: string;
  private readonly repository: ImageUploadRepository;

  constructor(cacheDir: string, repository: ImageUploadRepository) {
    this.cacheDir = cacheDir;
    this.repository = repository;
  }

  async upload(references: Array<LocalDraftImageReference>): Promise<Array<UploadedZhihuImage>> {
    const result: Array<UploadedZhihuImage> = [];
    for (let index = 0; index < references.length; index += 1) {
      const input = createControlledImageUploadInput(this.cacheDir, references[index]);
      result.push(await this.repository.upload(input));
    }
    return result;
  }

  cancel(): void {
    this.repository.cancel();
  }
}

/** 组合根按创作类型创建独立 HTTP/文件/OSS 生命周期，避免离页取消影响其他页面。 */
export class ProductionImageAttachmentUploaderFactory implements ImageAttachmentUploaderFactory {
  private readonly cacheDir: string;
  private readonly cookies: SessionCookieProvider;

  constructor(cacheDir: string, cookies: SessionCookieProvider) {
    this.cacheDir = cacheDir;
    this.cookies = cookies;
  }

  create(source: ImageUploadSource): ImageAttachmentUploader {
    const repository = new DefaultImageUploadRepository(new ZhihuHttpClient(this.cookies),
      new ControlledImageUploadBinaryReader(), new SystemOssImageUploadTransport(), source);
    return new ProductionImageAttachmentUploader(this.cacheDir, repository);
  }
}

function sniffDescriptor(buffer: ArrayBuffer, count: number): ImageBinaryDescriptor {
  const bytes: Array<number> = [];
  const view = new Uint8Array(buffer);
  for (let index = 0; index < count; index += 1) {
    bytes.push(view[index]);
  }
  return sniffImageBinary(bytes);
}

function hexDigest(data: Uint8Array): string {
  let result = '';
  for (let index = 0; index < data.length; index += 1) {
    result += data[index].toString(16).padStart(2, '0');
  }
  return result;
}

function toSystemMethod(method: ZhihuHttpMethod): http.RequestMethod {
  if (method === ZhihuHttpMethod.POST) return http.RequestMethod.POST;
  if (method === ZhihuHttpMethod.PUT) return http.RequestMethod.PUT;
  throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
}

function ossHeaders(request: OssImageUploadRequest): Record<string, string> {
  const headers: Record<string, string> = {
    'Authorization': request.headers.authorization,
    'x-oss-date': request.headers.ossDate,
    'x-oss-user-agent': request.headers.ossUserAgent,
    'x-oss-security-token': request.headers.ossSecurityToken
  };
  if (request.contentType !== undefined) {
    headers['Content-Type'] = request.contentType;
  }
  return headers;
}

function responseHeader(headers: Object, expectedName: string): string | undefined {
  const source = headers as Record<string, Object>;
  const names = Object.keys(source);
  for (let index = 0; index < names.length; index += 1) {
    if (names[index].toLowerCase() === expectedName) {
      const value = source[names[index]];
      return typeof value === 'string' ? value : undefined;
    }
  }
  return undefined;
}
