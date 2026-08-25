import { describe, expect, it } from '@ohos/hypium';
import {
  buildGifMultipartCompleteRequest,
  buildGifMultipartInitRequest,
  buildGifMultipartPartRequest,
  buildImageApplyRequest,
  buildImageStatusRequest,
  buildImageUploadingStatusRequest,
  buildOssSinglePutRequest,
  createGifUploadParts,
  createImageTemporaryLifecycle,
  createLocalDraftImageReference,
  defaultImageSelectionLimits,
  ImageResourceReleasePlan,
  ImageTemporaryFile,
  ImageTemporaryLifecycle,
  ImageTemporaryState,
  ImageUploadFailure,
  ImageUploadFailureKind,
  ImageUploadHttpContract,
  ImageUploadSource,
  inspectPickedImage,
  imageTemporaryReleasePlan,
  isTrustedZhihuImageUrl,
  nextImageStatusPoll,
  OssTemporaryCredential,
  parseImageApplyResult,
  parseImageStatusResult,
  parseLocalDraftImageReferences,
  parseOssMultipartUploadId,
  PickedImageFormat,
  PickedImageInspection,
  requireOssEtag,
  sniffImageBinary,
  transitionImageTemporaryLifecycle,
  serializeLocalDraftImageReferences,
  validatePickedImageBatch,
  ZhihuHttpMethod
} from 'data';

const CACHE_DIR: string = '/data/storage/el2/base/cache';
const JPEG_HEADER: Array<number> = [
  0xff, 0xd8, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x00, 0x02, 0x00, 0x03, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x03, 0x11,
  0x00, 0xff, 0xd9
];
const PNG_HEADER: Array<number> = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03, 0x00
];
const GIF_HEADER: Array<number> = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x80, 0x02, 0xe0, 0x01];
const WEBP_HEADER: Array<number> = [
  0x52, 0x49, 0x46, 0x46, 0x16, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
  0x56, 0x50, 0x38, 0x58, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0xff, 0x03, 0x00, 0xdf, 0x01, 0x00
];
const HASH: string = '900150983cd24fb0d6963f7d28e17f72';
const DATE: string = 'Tue, 20 Aug 2026 10:11:12 GMT';

class RecordingImageUploadTransport {
  readonly requests: Array<ImageUploadHttpContract> = [];

  execute(request: ImageUploadHttpContract): void {
    this.requests.push(request);
  }
}

function inspection(header: Array<number> = PNG_HEADER, byteLength: number = 4096): PickedImageInspection {
  const value: PickedImageInspection = {
    sourceUri: 'file://media/Photo/123', byteLength: byteLength, headerBytes: header
  };
  return value;
}

function credential(): OssTemporaryCredential {
  const value: OssTemporaryCredential = {
    accessId: 'TESTACCESSID123456',
    accessKey: 'test-access-key-0123456789abcdef',
    securityToken: 'test-security-token-0123456789abcdef'
  };
  return value;
}

function temporaryFile(): ImageTemporaryFile {
  const file: ImageTemporaryFile = {
    path: `${CACHE_DIR}/p4-images/0123456789abcdef0123456789abcdef.png`,
    mimeType: 'image/png',
    byteLength: 4096,
    createdAtMillis: 1770000000000
  };
  return file;
}

function lifecycleToReady(): ImageTemporaryLifecycle {
  const selected = createImageTemporaryLifecycle(temporaryFile(), CACHE_DIR);
  const processing = transitionImageTemporaryLifecycle(selected, ImageTemporaryState.PROCESSING);
  return transitionImageTemporaryLifecycle(processing, ImageTemporaryState.READY);
}

export default function imageUploadContractsTest(): void {
  describe('imageUploadContractsTest', () => {
    it('sniffsMagicBytesAndDimensionsWithoutTrustingMimeOrExtension', 0, () => {
      const jpeg = sniffImageBinary(JPEG_HEADER);
      const png = sniffImageBinary(PNG_HEADER);
      const gif = sniffImageBinary(GIF_HEADER);
      const webp = sniffImageBinary(WEBP_HEADER);

      expect(jpeg.format).assertEqual(PickedImageFormat.JPEG);
      expect(jpeg.width).assertEqual(3);
      expect(jpeg.height).assertEqual(2);
      expect(png.mimeType).assertEqual('image/png');
      expect(png.width).assertEqual(1024);
      expect(png.height).assertEqual(768);
      expect(gif.animated).assertTrue();
      expect(gif.width).assertEqual(640);
      expect(webp.format).assertEqual(PickedImageFormat.WEBP);
      expect(webp.width).assertEqual(1024);
      expect(webp.height).assertEqual(480);
    });

    it('rejectsUnknownTruncatedAndOversizedImageInputs', 0, () => {
      const limits = defaultImageSelectionLimits();
      const oversized = inspection(PNG_HEADER, limits.maxSingleBytes + 1);
      const truncatedPng: Array<number> = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

      expect((): void => { sniffImageBinary([0x52, 0x49, 0x46, 0x46]); }).assertThrowError('无法识别图片格式');
      expect((): void => { sniffImageBinary(truncatedPng); }).assertThrowError('图片输入无效');
      expect((): void => { inspectPickedImage(oversized); }).assertThrowError('图片输入无效');
      expect((): void => {
        inspectPickedImage({ sourceUri: 'https://evil.example/image.png', byteLength: 1, headerBytes: PNG_HEADER });
      }).assertThrowError('图片输入无效');
    });

    it('enforcesCountAndTotalBatchBoundariesBeforeAnyUpload', 0, () => {
      const limits = defaultImageSelectionLimits();
      const accepted = validatePickedImageBatch([inspection(PNG_HEADER, 1024), inspection(JPEG_HEADER, 2048)]);
      const tooMany: Array<PickedImageInspection> = [];
      for (let index = 0; index < limits.maxCount + 1; index += 1) tooMany.push(inspection());

      expect(accepted.length).assertEqual(2);
      expect((): void => { validatePickedImageBatch(tooMany); }).assertThrowError('图片数量、尺寸或大小超出限制');
      expect((): void => {
        validatePickedImageBatch([inspection(PNG_HEADER, limits.maxBatchBytes), inspection(JPEG_HEADER, 1)]);
      }).assertThrowError('图片数量、尺寸或大小超出限制');
    });

    it('modelsTemporaryResourceStateAndReleasesOnlyAtSafeBoundaries', 0, () => {
      const ready = lifecycleToReady();
      const uploading = transitionImageTemporaryLifecycle(ready, ImageTemporaryState.UPLOADING);
      const uploaded = transitionImageTemporaryLifecycle(uploading, ImageTemporaryState.UPLOADED, '123');
      const beforeUpload: ImageResourceReleasePlan = imageTemporaryReleasePlan(uploading, 1770000000001);
      const afterUpload: ImageResourceReleasePlan = imageTemporaryReleasePlan(uploaded, 1770000000001);
      const cancelled = transitionImageTemporaryLifecycle(ready, ImageTemporaryState.CANCELLED);

      expect(ready.state).assertEqual(ImageTemporaryState.READY);
      expect(beforeUpload.deleteTemporaryFile).assertFalse();
      expect(afterUpload.deleteTemporaryFile).assertTrue();
      expect(afterUpload.releasePixelMap).assertTrue();
      expect(imageTemporaryReleasePlan(cancelled, 1770000000001).closeFileHandles).assertTrue();
      const reference = createLocalDraftImageReference(temporaryFile(), sniffImageBinary(PNG_HEADER));
      const restored = parseLocalDraftImageReferences(serializeLocalDraftImageReferences([reference]));
      expect(restored.length).assertEqual(1);
      expect(restored[0].fileName).assertEqual('0123456789abcdef0123456789abcdef.png');
      expect(serializeLocalDraftImageReferences([reference]).includes('file://media')).assertFalse();
      expect(parseLocalDraftImageReferences('[{"fileName":"../../outside.png"}]').length).assertEqual(0);
      expect((): void => {
        transitionImageTemporaryLifecycle(uploaded, ImageTemporaryState.PROCESSING);
      }).assertThrowError('图片输入无效');
    });

    it('freezesApplySinglePutStatusAndPollingContractsWithFakeTransport', 0, () => {
      const transport = new RecordingImageUploadTransport();
      const apply = buildImageApplyRequest(HASH, ImageUploadSource.ANSWER);
      const upload = buildOssSinglePutRequest(HASH, 'image/png', DATE, credential());
      const notify = buildImageUploadingStatusRequest('123');
      const status = buildImageStatusRequest('123');
      transport.execute(apply);
      transport.execute(upload);
      transport.execute(notify);
      transport.execute(status);

      expect(transport.requests.length).assertEqual(4);
      expect(apply.url).assertEqual('https://api.zhihu.com/images');
      expect(apply.body).assertEqual('{"image_hash":"900150983cd24fb0d6963f7d28e17f72","source":"article"}');
      expect(apply.useSession).assertTrue();
      expect(upload.url).assertEqual('https://zhihu-pics-upload.zhimg.com/v2-900150983cd24fb0d6963f7d28e17f72');
      expect(upload.method).assertEqual(ZhihuHttpMethod.PUT);
      expect(upload.useSession).assertFalse();
      expect(upload.signWithZse).assertFalse();
      expect(upload.headers?.authorization.startsWith('OSS TESTACCESSID123456:')).assertTrue();
      expect(notify.method).assertEqual(ZhihuHttpMethod.PUT);
      expect(status.method).assertEqual(ZhihuHttpMethod.GET);
      expect(status.maxRedirects).assertEqual(0);
      expect(nextImageStatusPoll(0, false).delayMillis).assertEqual(2000);
      expect(nextImageStatusPoll(10, false).shouldContinue).assertFalse();
    });

    it('parsesApplyAndStatusResponsesWithoutLeakingTokensOrUntrustedUrls', 0, () => {
      const apply = parseImageApplyResult(
        '{"upload_file":{"image_id":"123","state":2},"upload_token":' +
          '{"access_id":"TESTACCESSID123456","access_key":"test-access-key-0123456789abcdef",' +
          '"access_token":"test-security-token-0123456789abcdef"}}'
      );
      const completed = parseImageStatusResult(
        '{"status":"success","src":"https://picx.zhimg.com/v2-safe.png",' +
          '"original_src":"https://picx.zhimg.com/v2-original.png","watermark":"original"}',
        '123'
      );
      const pending = parseImageStatusResult('{"status":"processing"}', '123');

      expect(apply.requiresUpload).assertTrue();
      expect(apply.imageId).assertEqual('123');
      expect(completed.completed).assertTrue();
      expect(completed.originalUrl).assertEqual('https://picx.zhimg.com/v2-original.png');
      expect(completed.watermark).assertEqual('original');
      expect(pending.completed).assertFalse();
      expect(isTrustedZhihuImageUrl('https://picx.zhimg.com.evil.example/v2-safe.png')).assertFalse();
      expect((): void => {
        parseImageStatusResult('{"status":"success","src":"https://evil.example/a.png"}', '123');
      }).assertThrowError('图片服务返回无效结果');
    });

    it('freezesGifMultipartRangesXmlEtagsAndUploadIds', 0, () => {
      const parts = createGifUploadParts(1024 * 1024 + 5);
      const init = buildGifMultipartInitRequest(HASH, DATE, credential());
      const part = buildGifMultipartPartRequest(HASH, 'upload-123', parts[0], DATE, credential());
      const complete = buildGifMultipartCompleteRequest(HASH, 'upload-123', ['"abcdef0123456789"', 'abcdef0123456789'], DATE, credential());

      expect(parts.length).assertEqual(2);
      expect(parts[0].length).assertEqual(1024 * 1024);
      expect(parts[1].offset).assertEqual(1024 * 1024);
      expect(init.url.endsWith('?uploads')).assertTrue();
      expect(part.url.includes('partNumber=1&uploadId=upload-123')).assertTrue();
      expect(complete.body?.includes('<CompleteMultipartUpload>')).assertTrue();
      expect(parseOssMultipartUploadId('<UploadId>upload-123</UploadId>')).assertEqual('upload-123');
      expect(requireOssEtag('"abcdef0123456789"')).assertEqual('"abcdef0123456789"');
      expect((): void => { requireOssEtag(undefined); }).assertThrowError('图片分片上传未返回 ETag');
      expect((): void => { parseOssMultipartUploadId('<UploadId>bad value</UploadId>'); }).assertThrowError('图片服务返回无效结果');
    });
  });
}
