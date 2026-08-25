import {
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  parseStrictJson
} from 'core';
import { hmacSha1Base64 } from '../network/ZhihuHmacSha1';
import { ZhihuHttpMethod } from '../network/ZhihuHttpClient';

/** P4-2 图片选择与上传的纯函数合同；这里绝不读取 URI、文件或网络。 */
export const IMAGE_UPLOAD_TEMPORARY_DIRECTORY: string = 'p4-images';
export const MAX_IMAGE_SELECTION_COUNT: number = 9;
export const MAX_IMAGE_SINGLE_BYTES: number = 20 * 1024 * 1024;
export const MAX_IMAGE_BATCH_BYTES: number = 50 * 1024 * 1024;
export const MAX_IMAGE_DIMENSION: number = 8192;
export const MAX_IMAGE_PIXELS: number = 30000000;
export const MAX_IMAGE_DECODE_MEMORY_BYTES: number = 128 * 1024 * 1024;
export const GIF_UPLOAD_PART_BYTES: number = 1024 * 1024;
export const IMAGE_STATUS_POLL_INTERVAL_MILLIS: number = 2000;
export const MAX_IMAGE_STATUS_POLL_ATTEMPTS: number = 10;
export const IMAGE_TEMPORARY_MAX_AGE_MILLIS: number = 24 * 60 * 60 * 1000;
export const OSS_UPLOAD_HOST: string = 'zhihu-pics-upload.zhimg.com';
export const OSS_USER_AGENT: string = 'aliyun-sdk-js/6.8.0 Chrome 99.0.4844.84 on Windows 10 64-bit';

export enum PickedImageFormat {
  JPEG = 'jpeg',
  PNG = 'png',
  WEBP = 'webp',
  GIF = 'gif'
}

export enum ImageUploadSource {
  ANSWER = 'article',
  PIN = 'pin'
}

export enum ImageUploadProgress {
  SELECTED = 'selected',
  PROCESSING = 'processing',
  UPLOADING = 'uploading',
  COMPLETED = 'completed',
  RETRYABLE_FAILURE = 'retryable_failure',
  CANCELLED = 'cancelled'
}

export enum ImageTemporaryState {
  SELECTED = 'selected',
  PROCESSING = 'processing',
  READY = 'ready',
  UPLOADING = 'uploading',
  UPLOADED = 'uploaded',
  CANCELLED = 'cancelled',
  RELEASED = 'released'
}

export enum ImageUploadFailureKind {
  INVALID_INPUT = 'invalid_input',
  UNSUPPORTED_FORMAT = 'unsupported_format',
  LIMIT_EXCEEDED = 'limit_exceeded',
  INVALID_RESPONSE = 'invalid_response',
  MISSING_ETAG = 'missing_etag',
  POLL_TIMEOUT = 'poll_timeout',
  CANCELLED = 'cancelled',
  AUTHENTICATION = 'authentication',
  FORBIDDEN = 'forbidden',
  RATE_LIMITED = 'rate_limited',
  NETWORK = 'network',
  TIMEOUT = 'timeout',
  SERVER = 'server'
}

export class ImageUploadFailure extends Error {
  readonly kind: ImageUploadFailureKind;
  readonly retryable: boolean;

  constructor(kind: ImageUploadFailureKind) {
    super(imageUploadFailureMessage(kind));
    this.name = 'ImageUploadFailure';
    this.kind = kind;
    this.retryable = kind === ImageUploadFailureKind.RATE_LIMITED || kind === ImageUploadFailureKind.NETWORK ||
      kind === ImageUploadFailureKind.TIMEOUT || kind === ImageUploadFailureKind.SERVER ||
      kind === ImageUploadFailureKind.POLL_TIMEOUT;
  }
}

export interface ImageBinaryDescriptor {
  readonly format: PickedImageFormat;
  readonly mimeType: string;
  readonly extension: string;
  readonly width: number;
  readonly height: number;
  readonly animated: boolean;
}

/** 平台适配层读取的有限头部与文件长度，绝不把整张原图放进草稿模型。 */
export interface PickedImageInspection {
  readonly sourceUri: string;
  readonly byteLength: number;
  readonly headerBytes: Array<number>;
}

export interface ValidatedPickedImage {
  readonly sourceUri: string;
  readonly byteLength: number;
  readonly descriptor: ImageBinaryDescriptor;
}

export interface ImageSelectionLimits {
  readonly maxCount: number;
  readonly maxSingleBytes: number;
  readonly maxBatchBytes: number;
  readonly maxDimension: number;
  readonly maxPixels: number;
  readonly maxDecodeMemoryBytes: number;
}

export interface ImageTemporaryFile {
  /** cacheDir/p4-images 下由应用生成的唯一文件名；不是用户可控 URI。 */
  readonly path: string;
  readonly mimeType: string;
  readonly byteLength: number;
  readonly createdAtMillis: number;
}

export interface ImageTemporaryLifecycle {
  readonly file: ImageTemporaryFile;
  readonly state: ImageTemporaryState;
  readonly uploadedImageId?: string;
  readonly cleanupAfterMillis: number;
}

export interface ImageResourceReleasePlan {
  readonly releasePixelMap: boolean;
  readonly closeFileHandles: boolean;
  readonly deleteTemporaryFile: boolean;
}

export interface ImageUploadHttpContract {
  readonly url: string;
  readonly method: ZhihuHttpMethod;
  readonly body?: string;
  readonly contentType?: string;
  /** API 段复用认证会话；OSS 段只能使用临时授权，绝不附 Cookie。 */
  readonly useSession: boolean;
  readonly signWithZse: boolean;
  readonly includeXsrfToken: boolean;
  readonly maxRedirects: 0;
  /** 仅 OSS 单次对象临时持有，不能落盘、展示或写入日志。 */
  readonly headers?: OssRequestHeaders;
}

export interface OssTemporaryCredential {
  readonly accessId: string;
  readonly accessKey: string;
  readonly securityToken: string;
}

export interface OssRequestHeaders {
  readonly authorization: string;
  readonly ossDate: string;
  readonly ossUserAgent: string;
  readonly ossSecurityToken: string;
}

export interface ImageUploadApplyResult {
  readonly imageId: string;
  /** 2 代表必须执行 OSS 上传；其他已知完成态仅走状态轮询。 */
  readonly requiresUpload: boolean;
  readonly credential?: OssTemporaryCredential;
}

export interface ImageStatusResult {
  readonly completed: boolean;
  readonly imageId: string;
  readonly url?: string;
  readonly originalUrl?: string;
  readonly watermarkUrl?: string;
  readonly watermark?: 'watermark' | 'original';
}

export interface GifUploadPart {
  readonly partNumber: number;
  readonly offset: number;
  readonly length: number;
}

export interface ImageStatusPollPlan {
  readonly attempt: number;
  readonly delayMillis: number;
  readonly shouldContinue: boolean;
}

export function defaultImageSelectionLimits(): ImageSelectionLimits {
  return {
    maxCount: MAX_IMAGE_SELECTION_COUNT,
    maxSingleBytes: MAX_IMAGE_SINGLE_BYTES,
    maxBatchBytes: MAX_IMAGE_BATCH_BYTES,
    maxDimension: MAX_IMAGE_DIMENSION,
    maxPixels: MAX_IMAGE_PIXELS,
    maxDecodeMemoryBytes: MAX_IMAGE_DECODE_MEMORY_BYTES
  };
}

export function inspectPickedImage(input: PickedImageInspection, limits: ImageSelectionLimits = defaultImageSelectionLimits()): ValidatedPickedImage {
  validateSelectionLimits(limits);
  if (!isSafePickedImageUri(input.sourceUri) || !isSafeByteLength(input.byteLength) ||
    input.byteLength > limits.maxSingleBytes || input.headerBytes.length > 65536) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const descriptor = sniffImageBinary(input.headerBytes);
  validateDescriptor(descriptor, limits);
  return { sourceUri: input.sourceUri, byteLength: input.byteLength, descriptor: descriptor };
}

export function validatePickedImageBatch(
  inputs: Array<PickedImageInspection>,
  limits: ImageSelectionLimits = defaultImageSelectionLimits()
): Array<ValidatedPickedImage> {
  validateSelectionLimits(limits);
  if (inputs.length === 0 || inputs.length > limits.maxCount) {
    throw new ImageUploadFailure(ImageUploadFailureKind.LIMIT_EXCEEDED);
  }
  let totalBytes = 0;
  const result: Array<ValidatedPickedImage> = [];
  inputs.forEach((input: PickedImageInspection): void => {
    if (!isSafeByteLength(input.byteLength) || input.byteLength > limits.maxSingleBytes) {
      throw new ImageUploadFailure(ImageUploadFailureKind.LIMIT_EXCEEDED);
    }
    totalBytes += input.byteLength;
    if (totalBytes > limits.maxBatchBytes) {
      throw new ImageUploadFailure(ImageUploadFailureKind.LIMIT_EXCEEDED);
    }
    result.push(inspectPickedImage(input, limits));
  });
  return result;
}

/** 只根据 magic bytes 和格式头解析，调用方声明的 MIME 或扩展名不参与判定。 */
export function sniffImageBinary(bytes: Array<number>): ImageBinaryDescriptor {
  if (isPng(bytes)) {
    return pngDescriptor(bytes);
  }
  if (isJpeg(bytes)) {
    return jpegDescriptor(bytes);
  }
  if (isGif(bytes)) {
    return gifDescriptor(bytes);
  }
  if (isWebp(bytes)) {
    return webpDescriptor(bytes);
  }
  throw new ImageUploadFailure(ImageUploadFailureKind.UNSUPPORTED_FORMAT);
}

export function createImageTemporaryLifecycle(file: ImageTemporaryFile, cacheDir: string): ImageTemporaryLifecycle {
  validateTemporaryFile(file, cacheDir);
  return {
    file: file,
    state: ImageTemporaryState.SELECTED,
    cleanupAfterMillis: file.createdAtMillis + IMAGE_TEMPORARY_MAX_AGE_MILLIS
  };
}

export function transitionImageTemporaryLifecycle(
  lifecycle: ImageTemporaryLifecycle,
  target: ImageTemporaryState,
  imageId?: string
): ImageTemporaryLifecycle {
  if (!isAllowedTemporaryTransition(lifecycle.state, target) ||
    ((target === ImageTemporaryState.UPLOADED) !== (imageId !== undefined)) ||
    (imageId !== undefined && !isSafeDecimalId(imageId))) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return {
    file: lifecycle.file,
    state: target,
    uploadedImageId: imageId,
    cleanupAfterMillis: lifecycle.cleanupAfterMillis
  };
}

export function imageTemporaryReleasePlan(lifecycle: ImageTemporaryLifecycle, nowMillis: number): ImageResourceReleasePlan {
  if (!isFiniteTimestamp(nowMillis)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const deleteTemporaryFile = lifecycle.state === ImageTemporaryState.UPLOADED ||
    lifecycle.state === ImageTemporaryState.CANCELLED || lifecycle.state === ImageTemporaryState.RELEASED ||
    nowMillis >= lifecycle.cleanupAfterMillis;
  return {
    releasePixelMap: lifecycle.state !== ImageTemporaryState.UPLOADING || deleteTemporaryFile,
    closeFileHandles: lifecycle.state !== ImageTemporaryState.UPLOADING || deleteTemporaryFile,
    deleteTemporaryFile: deleteTemporaryFile
  };
}

export function buildImageApplyRequest(imageHash: string, source: ImageUploadSource): ImageUploadHttpContract {
  requireImageHash(imageHash);
  return {
    url: 'https://api.zhihu.com/images',
    method: ZhihuHttpMethod.POST,
    body: '{"image_hash":' + JSON.stringify(imageHash) + ',"source":' + JSON.stringify(source) + '}',
    contentType: 'application/json',
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    maxRedirects: 0
  };
}

export function parseImageApplyResult(body: string): ImageUploadApplyResult {
  const root = parseObject(body);
  const uploadFile = readObject(root, 'upload_file') ?? readObject(root, 'uploadFile');
  if (uploadFile === undefined) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  const imageId = readText(uploadFile, 'image_id') ?? readText(uploadFile, 'imageId');
  const state = readInteger(uploadFile, 'state');
  if (imageId === undefined || !isSafeDecimalId(imageId) || state === undefined || state < 0 || state > 10) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  if (state !== 2) {
    return { imageId: imageId, requiresUpload: false };
  }
  const token = readObject(root, 'upload_token') ?? readObject(root, 'uploadToken');
  if (token === undefined) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  const credential = readTemporaryCredential(token);
  return { imageId: imageId, requiresUpload: true, credential: credential };
}

export function buildOssSinglePutRequest(
  imageHash: string,
  mimeType: string,
  date: string,
  credential: OssTemporaryCredential
): ImageUploadHttpContract {
  requireImageHash(imageHash);
  requireImageMime(mimeType);
  return buildOssRequest(ZhihuHttpMethod.PUT, imageHash, '', mimeType, date, credential);
}

export function buildGifMultipartInitRequest(
  imageHash: string,
  date: string,
  credential: OssTemporaryCredential
): ImageUploadHttpContract {
  return buildOssRequest(ZhihuHttpMethod.POST, imageHash, 'uploads', '', date, credential);
}

export function buildGifMultipartPartRequest(
  imageHash: string,
  uploadId: string,
  part: GifUploadPart,
  date: string,
  credential: OssTemporaryCredential
): ImageUploadHttpContract {
  if (!isSafeUploadId(uploadId) || !isSafePart(part)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return buildOssRequest(
    ZhihuHttpMethod.PUT,
    imageHash,
    `partNumber=${part.partNumber}&uploadId=${encodeURIComponent(uploadId)}`,
    'application/octet-stream',
    date,
    credential
  );
}

export function buildGifMultipartCompleteRequest(
  imageHash: string,
  uploadId: string,
  etags: Array<string>,
  date: string,
  credential: OssTemporaryCredential
): ImageUploadHttpContract {
  if (!isSafeUploadId(uploadId) || etags.length === 0 || etags.length > 100 ||
    !etags.every((etag: string): boolean => isSafeOssEtag(etag))) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  let parts = '';
  for (let index = 0; index < etags.length; index += 1) {
    parts += '<Part><PartNumber>' + (index + 1) + '</PartNumber><ETag>' + etags[index] + '</ETag></Part>';
  }
  const request = buildOssRequest(
    ZhihuHttpMethod.POST,
    imageHash,
    `uploadId=${encodeURIComponent(uploadId)}`,
    'application/xml',
    date,
    credential
  );
  return {
    url: request.url,
    method: request.method,
    body: '<CompleteMultipartUpload>' + parts + '</CompleteMultipartUpload>',
    contentType: request.contentType,
    useSession: false,
    signWithZse: false,
    includeXsrfToken: false,
    maxRedirects: 0,
    headers: request.headers
  };
}

export function buildImageUploadingStatusRequest(imageId: string): ImageUploadHttpContract {
  if (!isSafeDecimalId(imageId)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return {
    url: `https://api.zhihu.com/images/${imageId}/uploading_status`,
    method: ZhihuHttpMethod.PUT,
    body: '{"upload_result":"success"}',
    contentType: 'application/json',
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    maxRedirects: 0
  };
}

export function buildImageStatusRequest(imageId: string): ImageUploadHttpContract {
  if (!isSafeDecimalId(imageId)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return {
    url: `https://api.zhihu.com/images/${imageId}`,
    method: ZhihuHttpMethod.GET,
    useSession: true,
    signWithZse: true,
    includeXsrfToken: false,
    maxRedirects: 0
  };
}

export function createGifUploadParts(byteLength: number): Array<GifUploadPart> {
  if (!isSafeByteLength(byteLength) || byteLength > MAX_IMAGE_SINGLE_BYTES) {
    throw new ImageUploadFailure(ImageUploadFailureKind.LIMIT_EXCEEDED);
  }
  const result: Array<GifUploadPart> = [];
  let offset = 0;
  while (offset < byteLength) {
    const length = Math.min(GIF_UPLOAD_PART_BYTES, byteLength - offset);
    result.push({ partNumber: result.length + 1, offset: offset, length: length });
    offset += length;
  }
  return result;
}

export function parseOssMultipartUploadId(xml: string): string {
  const match = /<UploadId>([A-Za-z0-9._-]{1,512})<\/UploadId>/.exec(xml);
  if (match === null || match[1] === undefined || !isSafeUploadId(match[1])) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  return match[1];
}

export function requireOssEtag(value: string | undefined): string {
  if (value === undefined || !isSafeOssEtag(value)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.MISSING_ETAG);
  }
  return value;
}

export function parseImageStatusResult(body: string, imageId: string): ImageStatusResult {
  if (!isSafeDecimalId(imageId)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const root = parseObject(body);
  const status = readText(root, 'status');
  if (status !== 'success') {
    return { completed: false, imageId: imageId };
  }
  const src = readText(root, 'src');
  const original = readText(root, 'original_src') ?? readText(root, 'originalSrc');
  const watermark = readText(root, 'watermark_src') ?? readText(root, 'watermarkSrc');
  const url = firstTrustedImageUrl(src, watermark, original);
  if (url === undefined) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  const originalUrl = firstTrustedImageUrl(original, src, watermark) ?? url;
  const watermarkUrl = watermark !== undefined && isTrustedZhihuImageUrl(watermark) ? watermark : undefined;
  const watermarkMode = readText(root, 'watermark');
  return {
    completed: true,
    imageId: imageId,
    url: url,
    originalUrl: originalUrl,
    watermarkUrl: watermarkUrl,
    watermark: watermarkMode === 'watermark' || watermarkMode === 'true' || watermarkMode === '1'
      ? 'watermark'
      : watermarkMode === 'original' || watermarkMode === 'false' || watermarkMode === '0' ? 'original' : undefined
  };
}

export function nextImageStatusPoll(attempt: number, completed: boolean): ImageStatusPollPlan {
  if (!Number.isSafeInteger(attempt) || attempt < 0 || attempt > MAX_IMAGE_STATUS_POLL_ATTEMPTS) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return {
    attempt: attempt,
    delayMillis: completed ? 0 : IMAGE_STATUS_POLL_INTERVAL_MILLIS,
    shouldContinue: !completed && attempt < MAX_IMAGE_STATUS_POLL_ATTEMPTS
  };
}

export function isTrustedZhihuImageUrl(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 4096 &&
    /^https:\/\/(?:pic|pica|picx|pic[0-9]+)\.zhimg\.com\/[A-Za-z0-9%&=._~!$'()*+,;:@/?-]+$/.test(value) &&
    !value.includes('..') && !value.includes('@') && !/[\r\n\t ]/.test(value);
}

function buildOssRequest(
  method: ZhihuHttpMethod,
  imageHash: string,
  subResource: string,
  contentType: string,
  date: string,
  credential: OssTemporaryCredential
): ImageUploadHttpContract {
  requireImageHash(imageHash);
  if (!isSafeOssDate(date) || !isSafeCredential(credential) ||
    (contentType.length > 0 && contentType !== 'application/octet-stream' && contentType !== 'application/xml' &&
      !isAllowedImageMime(contentType))) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const resourcePath = `/zhihu-pics/v2-${imageHash}`;
  const canonicalResource = subResource.length === 0 ? resourcePath : resourcePath + '?' + subResource;
  const signatureText = method + '\n\n' + contentType + '\n' + date + '\n' +
    'x-oss-date:' + date + '\n' +
    'x-oss-security-token:' + credential.securityToken + '\n' +
    'x-oss-user-agent:' + OSS_USER_AGENT + '\n' + canonicalResource;
  const authorization = 'OSS ' + credential.accessId + ':' + hmacSha1Base64(credential.accessKey, signatureText);
  const headers: OssRequestHeaders = {
    authorization: authorization,
    ossDate: date,
    ossUserAgent: OSS_USER_AGENT,
    ossSecurityToken: credential.securityToken
  };
  return {
    url: `https://${OSS_UPLOAD_HOST}/v2-${imageHash}` + (subResource.length === 0 ? '' : '?' + subResource),
    method: method,
    contentType: contentType.length === 0 ? undefined : contentType,
    useSession: false,
    signWithZse: false,
    includeXsrfToken: false,
    maxRedirects: 0,
    headers: headers
  };
}

function pngDescriptor(bytes: Array<number>): ImageBinaryDescriptor {
  if (bytes.length < 24 || !hasAscii(bytes, 12, 'IHDR')) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return descriptor(PickedImageFormat.PNG, readUint32Be(bytes, 16), readUint32Be(bytes, 20), false);
}

function jpegDescriptor(bytes: Array<number>): ImageBinaryDescriptor {
  let offset = 2;
  while (offset + 3 < bytes.length) {
    if (byteAt(bytes, offset) !== 0xff) {
      offset += 1;
      continue;
    }
    while (offset < bytes.length && byteAt(bytes, offset) === 0xff) {
      offset += 1;
    }
    if (offset >= bytes.length) {
      break;
    }
    const marker = byteAt(bytes, offset);
    offset += 1;
    if (marker === 0xd9 || marker === 0xda) {
      break;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    if (offset + 1 >= bytes.length) {
      break;
    }
    const length = readUint16Be(bytes, offset);
    if (length < 2 || offset + length > bytes.length) {
      break;
    }
    if (isJpegStartOfFrame(marker)) {
      if (offset + 6 >= bytes.length) {
        break;
      }
      return descriptor(PickedImageFormat.JPEG, readUint16Be(bytes, offset + 5), readUint16Be(bytes, offset + 3), false);
    }
    offset += length;
  }
  throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
}

function gifDescriptor(bytes: Array<number>): ImageBinaryDescriptor {
  if (bytes.length < 10) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return descriptor(PickedImageFormat.GIF, readUint16Le(bytes, 6), readUint16Le(bytes, 8), true);
}

function webpDescriptor(bytes: Array<number>): ImageBinaryDescriptor {
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const type = ascii(bytes, offset, 4);
    const chunkLength = readUint32Le(bytes, offset + 4);
    const dataOffset = offset + 8;
    if (chunkLength < 0 || dataOffset + chunkLength > bytes.length) {
      break;
    }
    if (type === 'VP8X' && chunkLength >= 10) {
      return descriptor(PickedImageFormat.WEBP, readUint24Le(bytes, dataOffset + 4) + 1, readUint24Le(bytes, dataOffset + 7) + 1, false);
    }
    if (type === 'VP8L' && chunkLength >= 5 && byteAt(bytes, dataOffset) === 0x2f) {
      const bits = readUint32Le(bytes, dataOffset + 1);
      return descriptor(PickedImageFormat.WEBP, (bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1, false);
    }
    if (type === 'VP8 ' && chunkLength >= 10 && byteAt(bytes, dataOffset + 3) === 0x9d &&
      byteAt(bytes, dataOffset + 4) === 0x01 && byteAt(bytes, dataOffset + 5) === 0x2a) {
      return descriptor(PickedImageFormat.WEBP, readUint16Le(bytes, dataOffset + 6) & 0x3fff, readUint16Le(bytes, dataOffset + 8) & 0x3fff, false);
    }
    offset = dataOffset + chunkLength + (chunkLength & 1);
  }
  throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
}

function descriptor(format: PickedImageFormat, width: number, height: number, animated: boolean): ImageBinaryDescriptor {
  return {
    format: format,
    mimeType: mimeForFormat(format),
    extension: extensionForFormat(format),
    width: width,
    height: height,
    animated: animated
  };
}

function validateDescriptor(descriptor: ImageBinaryDescriptor, limits: ImageSelectionLimits): void {
  if (!Number.isSafeInteger(descriptor.width) || !Number.isSafeInteger(descriptor.height) || descriptor.width <= 0 ||
    descriptor.height <= 0 || descriptor.width > limits.maxDimension || descriptor.height > limits.maxDimension ||
    descriptor.width * descriptor.height > limits.maxPixels || descriptor.width * descriptor.height * 4 > limits.maxDecodeMemoryBytes) {
    throw new ImageUploadFailure(ImageUploadFailureKind.LIMIT_EXCEEDED);
  }
}

function validateSelectionLimits(limits: ImageSelectionLimits): void {
  if (!Number.isSafeInteger(limits.maxCount) || limits.maxCount < 1 || limits.maxCount > MAX_IMAGE_SELECTION_COUNT ||
    !isSafeByteLength(limits.maxSingleBytes) || !isSafeByteLength(limits.maxBatchBytes) ||
    limits.maxBatchBytes < limits.maxSingleBytes || !Number.isSafeInteger(limits.maxDimension) || limits.maxDimension < 1 ||
    !Number.isSafeInteger(limits.maxPixels) || limits.maxPixels < 1 || !isSafeByteLength(limits.maxDecodeMemoryBytes)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function validateTemporaryFile(file: ImageTemporaryFile, cacheDir: string): void {
  const normalizedCache = normalizeCacheDir(cacheDir);
  const prefix = normalizedCache + '/' + IMAGE_UPLOAD_TEMPORARY_DIRECTORY + '/';
  if (!isFiniteTimestamp(file.createdAtMillis) || !isSafeByteLength(file.byteLength) || !isAllowedImageMime(file.mimeType) ||
    !file.path.startsWith(prefix) || !/^[a-f0-9]{32}\.(?:jpg|png|webp|gif)$/.test(file.path.substring(prefix.length))) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function isAllowedTemporaryTransition(from: ImageTemporaryState, to: ImageTemporaryState): boolean {
  if (to === ImageTemporaryState.CANCELLED || to === ImageTemporaryState.RELEASED) {
    return from !== ImageTemporaryState.RELEASED;
  }
  if (from === ImageTemporaryState.SELECTED) {
    return to === ImageTemporaryState.PROCESSING;
  }
  if (from === ImageTemporaryState.PROCESSING) {
    return to === ImageTemporaryState.READY;
  }
  if (from === ImageTemporaryState.READY) {
    return to === ImageTemporaryState.UPLOADING;
  }
  return from === ImageTemporaryState.UPLOADING && to === ImageTemporaryState.UPLOADED;
}

function parseObject(body: string): JsonObjectValue {
  try {
    const value = parseStrictJson(body);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (_error) {
  }
  throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
}

function readObject(object: JsonObjectValue, key: string): JsonObjectValue | undefined {
  const value = object.get(key);
  return value instanceof JsonObjectValue ? value : undefined;
}

function readText(object: JsonObjectValue, key: string): string | undefined {
  const value = object.get(key);
  return value instanceof JsonStringValue ? value.value : undefined;
}

function readInteger(object: JsonObjectValue, key: string): number | undefined {
  const value = object.get(key);
  if (value instanceof JsonNumberValue && /^-?[0-9]+$/.test(value.literal)) {
    const parsed = Number(value.literal);
    return Number.isSafeInteger(parsed) ? parsed : undefined;
  }
  return undefined;
}

function readTemporaryCredential(token: JsonObjectValue): OssTemporaryCredential {
  const accessId = readText(token, 'access_id') ?? readText(token, 'accessId');
  const accessKey = readText(token, 'access_key') ?? readText(token, 'accessKey');
  const securityToken = readText(token, 'access_token') ?? readText(token, 'accessToken');
  const credential: OssTemporaryCredential = {
    accessId: accessId ?? '', accessKey: accessKey ?? '', securityToken: securityToken ?? ''
  };
  if (!isSafeCredential(credential)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_RESPONSE);
  }
  return credential;
}

function firstTrustedImageUrl(...values: Array<string | undefined>): string | undefined {
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value !== undefined && isTrustedZhihuImageUrl(value)) {
      return value;
    }
  }
  return undefined;
}

function isPng(bytes: Array<number>): boolean {
  return bytes.length >= 8 && byteAt(bytes, 0) === 0x89 && hasAscii(bytes, 1, 'PNG') &&
    byteAt(bytes, 4) === 0x0d && byteAt(bytes, 5) === 0x0a && byteAt(bytes, 6) === 0x1a && byteAt(bytes, 7) === 0x0a;
}

function isJpeg(bytes: Array<number>): boolean {
  return bytes.length >= 3 && byteAt(bytes, 0) === 0xff && byteAt(bytes, 1) === 0xd8 && byteAt(bytes, 2) === 0xff;
}

function isGif(bytes: Array<number>): boolean {
  return bytes.length >= 6 && (hasAscii(bytes, 0, 'GIF87a') || hasAscii(bytes, 0, 'GIF89a'));
}

function isWebp(bytes: Array<number>): boolean {
  return bytes.length >= 12 && hasAscii(bytes, 0, 'RIFF') && hasAscii(bytes, 8, 'WEBP');
}

function isJpegStartOfFrame(marker: number): boolean {
  return marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
}

function mimeForFormat(format: PickedImageFormat): string {
  if (format === PickedImageFormat.JPEG) return 'image/jpeg';
  if (format === PickedImageFormat.PNG) return 'image/png';
  if (format === PickedImageFormat.WEBP) return 'image/webp';
  return 'image/gif';
}

function extensionForFormat(format: PickedImageFormat): string {
  if (format === PickedImageFormat.JPEG) return 'jpg';
  if (format === PickedImageFormat.PNG) return 'png';
  if (format === PickedImageFormat.WEBP) return 'webp';
  return 'gif';
}

function requireImageHash(value: string): void {
  if (!/^[a-f0-9]{32}$/.test(value)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function requireImageMime(value: string): void {
  if (!isAllowedImageMime(value)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
}

function isAllowedImageMime(value: string): boolean {
  return value === 'image/jpeg' || value === 'image/png' || value === 'image/webp' || value === 'image/gif';
}

function isSafePickedImageUri(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 4096 &&
    /^file:\/\/(?:media|com\.ohos\.filemanager\.dir)\/[A-Za-z0-9._~%/-]+$/.test(value) &&
    !value.includes('..') && !/[\r\n\t ]/.test(value);
}

function isSafeByteLength(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}

function isFiniteTimestamp(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

function isSafeDecimalId(value: string): boolean {
  return /^[1-9][0-9]{0,29}$/.test(value);
}

function isSafeUploadId(value: string): boolean {
  return /^[A-Za-z0-9._-]{1,512}$/.test(value);
}

function isSafeOssEtag(value: string): boolean {
  return /^"?[A-Fa-f0-9]{16,128}"?$/.test(value);
}

function isSafeOssDate(value: string): boolean {
  return /^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), [0-3][0-9] (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} [0-2][0-9]:[0-5][0-9]:[0-5][0-9] GMT$/.test(value);
}

function isSafeCredential(value: OssTemporaryCredential): boolean {
  return /^[A-Za-z0-9._/-]{1,256}$/.test(value.accessId) && /^[A-Za-z0-9+/=_-]{16,512}$/.test(value.accessKey) &&
    /^[A-Za-z0-9+/=_.-]{16,2048}$/.test(value.securityToken);
}

function isSafePart(value: GifUploadPart): boolean {
  return Number.isSafeInteger(value.partNumber) && value.partNumber >= 1 && value.partNumber <= 100 &&
    Number.isSafeInteger(value.offset) && value.offset >= 0 && Number.isSafeInteger(value.length) &&
    value.length > 0 && value.length <= GIF_UPLOAD_PART_BYTES;
}

function normalizeCacheDir(value: string): string {
  const normalized = value.replace(/\\/g, '/').replace(/\/+$/g, '');
  if (!/^\/[A-Za-z0-9._/-]+$/.test(normalized) || normalized.includes('..')) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return normalized;
}

function byteAt(bytes: Array<number>, offset: number): number {
  const value = bytes[offset];
  return value === undefined ? -1 : value & 0xff;
}

function hasAscii(bytes: Array<number>, offset: number, text: string): boolean {
  if (offset + text.length > bytes.length) return false;
  for (let index = 0; index < text.length; index += 1) {
    if (byteAt(bytes, offset + index) !== text.charCodeAt(index)) return false;
  }
  return true;
}

function ascii(bytes: Array<number>, offset: number, length: number): string {
  let value = '';
  for (let index = 0; index < length; index += 1) value += String.fromCharCode(byteAt(bytes, offset + index));
  return value;
}

function readUint16Be(bytes: Array<number>, offset: number): number {
  return (byteAt(bytes, offset) << 8) | byteAt(bytes, offset + 1);
}

function readUint16Le(bytes: Array<number>, offset: number): number {
  return byteAt(bytes, offset) | (byteAt(bytes, offset + 1) << 8);
}

function readUint24Le(bytes: Array<number>, offset: number): number {
  return byteAt(bytes, offset) | (byteAt(bytes, offset + 1) << 8) | (byteAt(bytes, offset + 2) << 16);
}

function readUint32Be(bytes: Array<number>, offset: number): number {
  return byteAt(bytes, offset) * 0x1000000 + (byteAt(bytes, offset + 1) << 16) +
    (byteAt(bytes, offset + 2) << 8) + byteAt(bytes, offset + 3);
}

function readUint32Le(bytes: Array<number>, offset: number): number {
  return byteAt(bytes, offset) + byteAt(bytes, offset + 1) * 0x100 +
    byteAt(bytes, offset + 2) * 0x10000 + byteAt(bytes, offset + 3) * 0x1000000;
}

function imageUploadFailureMessage(kind: ImageUploadFailureKind): string {
  if (kind === ImageUploadFailureKind.UNSUPPORTED_FORMAT) return '无法识别图片格式';
  if (kind === ImageUploadFailureKind.LIMIT_EXCEEDED) return '图片数量、尺寸或大小超出限制';
  if (kind === ImageUploadFailureKind.MISSING_ETAG) return '图片分片上传未返回 ETag';
  if (kind === ImageUploadFailureKind.POLL_TIMEOUT) return '图片处理超时，可稍后重试';
  if (kind === ImageUploadFailureKind.CANCELLED) return '已取消图片上传';
  if (kind === ImageUploadFailureKind.AUTHENTICATION) return '登录已失效，请重新登录后上传图片';
  if (kind === ImageUploadFailureKind.FORBIDDEN) return '图片上传被拒绝或需要完成安全验证';
  if (kind === ImageUploadFailureKind.RATE_LIMITED) return '图片上传请求过于频繁，请稍后重试';
  if (kind === ImageUploadFailureKind.TIMEOUT) return '图片上传请求超时，请稍后重试';
  if (kind === ImageUploadFailureKind.SERVER) return '图片服务暂时不可用，请稍后重试';
  if (kind === ImageUploadFailureKind.NETWORK) return '网络不可用，请检查连接后重试';
  if (kind === ImageUploadFailureKind.INVALID_RESPONSE) return '图片服务返回无效结果';
  return '图片输入无效';
}
