import { describe, expect, it } from '@ohos/hypium';
import {
  createSystemShareRecords,
  ShareFileUriResolver,
  SharePanelLauncher,
  ShareRecordSpec,
  ShareThumbnailFetcher,
  SystemShareService
} from '../main/ets/platform/SystemShareService';
import {
  createTemporaryShareLifecycle,
  markSharePanelOpened,
  prepareSharePayload,
  ShareDispatchKind,
  ShareFailure,
  ShareFailureKind,
  ShareFilePayload,
  ShareImageSourceKind,
  ShareImagePayload,
  ShareOutcome,
  SharePayloadKind,
  ShareRuntimePolicy,
  ShareTemporaryFile,
  ShareTextPayload,
  shouldCleanupTemporaryShareFile
} from '../main/ets/platform/ShareContracts';

const NOW: number = 1770000000000;
const CACHE_DIR: string = '/data/storage/el2/base/cache';

class RecordingShareLauncher implements SharePanelLauncher {
  readonly panels: Array<Array<ShareRecordSpec>> = [];
  nextError: Error | undefined = undefined;

  async showPanel(records: Array<ShareRecordSpec>): Promise<void> {
    if (this.nextError !== undefined) {
      throw this.nextError;
    }
    this.panels.push(records);
  }
}

class FixedFileUriResolver implements ShareFileUriResolver {
  getUriFromPath(path: string): string {
    return `file://sandbox${path}`;
  }
}

class StubShareThumbnailFetcher implements ShareThumbnailFetcher {
  private readonly result: Uint8Array | undefined;

  constructor(result: Uint8Array | undefined) {
    this.result = result;
  }

  async fetchThumbnail(_url: string): Promise<Uint8Array | undefined> {
    return this.result;
  }
}

function policy(): ShareRuntimePolicy {
  const runtimePolicy: ShareRuntimePolicy = { cacheDir: CACHE_DIR, nowMillis: NOW };
  return runtimePolicy;
}

function temporaryFile(
  path: string = `${CACHE_DIR}/p4-share/image-123.png`,
  mimeType: string = 'image/png',
  createdAtMillis: number = NOW - 1000
): ShareTemporaryFile {
  const file: ShareTemporaryFile = { path: path, mimeType: mimeType, createdAtMillis: createdAtMillis };
  return file;
}

function textPayload(
  contentUrl: string = 'https://www.zhihu.com/question/123/answer/456',
  summary: string = '知乎++ 的 P4 执行计划'
): ShareTextPayload {
  const payload: ShareTextPayload = {
    kind: SharePayloadKind.TEXT,
    title: '鸿蒙迁移进展',
    summary: summary,
    contentUrl: contentUrl
  };
  return payload;
}

function remoteImagePayload(url: string, temporary?: ShareTemporaryFile): ShareImagePayload {
  const payload: ShareImagePayload = {
    kind: SharePayloadKind.IMAGE,
    title: '知乎图片',
    summary: '图片链接',
    sourceKind: ShareImageSourceKind.TRUSTED_URL,
    trustedImageUrl: url,
    temporaryFile: temporary
  };
  return payload;
}

function temporaryImagePayload(file: ShareTemporaryFile): ShareImagePayload {
  const payload: ShareImagePayload = {
    kind: SharePayloadKind.IMAGE,
    title: '二进制图片',
    summary: '应用临时图片',
    sourceKind: ShareImageSourceKind.TEMPORARY_FILE,
    temporaryFile: file
  };
  return payload;
}

function filePayload(file: ShareTemporaryFile): ShareFilePayload {
  const payload: ShareFilePayload = {
    kind: SharePayloadKind.FILE,
    title: '导出文件',
    summary: '应用文件',
    temporaryFile: file
  };
  return payload;
}

export default function shareServiceTest(): void {
  describe('shareServiceTest', () => {
    it('preparesBoundedTrustedTextLink', 0, () => {
      const prepared = prepareSharePayload(textPayload(), policy());

      expect(prepared.dispatchKind).assertEqual(ShareDispatchKind.TEXT_LINK);
      expect(prepared.mimeType).assertEqual('text/plain');
      expect(prepared.source).assertEqual('https://www.zhihu.com/question/123/answer/456');
      expect(prepared.title).assertEqual('鸿蒙迁移进展');
    });

    it('allowsEveryP4ContentLinkFamily', 0, () => {
      const urls: Array<string> = [
        'https://www.zhihu.com/question/1',
        'https://www.zhihu.com/pin/2',
        'https://www.zhihu.com/people/zhuoyi233',
        'https://www.zhihu.com/zvideo/3',
        'https://zhuanlan.zhihu.com/p/4'
      ];
      const accepted = urls.every((url: string): boolean => {
        try {
          prepareSharePayload(textPayload(url), policy());
          return true;
        } catch (_error) {
          return false;
        }
      });

      expect(accepted).assertTrue();
    });

    it('rejectsHtmlHeadersAndUntrustedContentLinks', 0, () => {
      const htmlPayload = textPayload('https://www.zhihu.com/question/1', '<p>正文 HTML</p>');
      const cookiePayload = textPayload('https://www.zhihu.com/question/1', 'Cookie: redacted');
      const externalPayload = textPayload('https://www.zhihu.com.evil.example/question/1');

      expect((): void => { prepareSharePayload(htmlPayload, policy()); }).assertThrowError('分享内容不受支持');
      expect((): void => { prepareSharePayload(cookiePayload, policy()); }).assertThrowError('分享内容不受支持');
      expect((): void => { prepareSharePayload(externalPayload, policy()); }).assertThrowError('分享内容不受支持');
    });

    it('keepsTrustedRemoteImageAsExplicitTextLinkFallback', 0, () => {
      const prepared = prepareSharePayload(remoteImagePayload('https://picx.zhimg.com/v2-safe-image.png'), policy());

      expect(prepared.dispatchKind).assertEqual(ShareDispatchKind.REMOTE_IMAGE_LINK);
      expect(prepared.mimeType).assertEqual('text/plain');
      expect(prepared.source).assertEqual('https://picx.zhimg.com/v2-safe-image.png');
    });

    it('rejectsUntrustedOrAmbiguousImageSources', 0, () => {
      const untrusted = remoteImagePayload('https://picx.zhimg.com.evil.example/image.png');
      const ambiguous = remoteImagePayload('https://picx.zhimg.com/image.png', temporaryFile());

      expect((): void => { prepareSharePayload(untrusted, policy()); }).assertThrowError('分享内容不受支持');
      expect((): void => { prepareSharePayload(ambiguous, policy()); }).assertThrowError('分享内容不受支持');
    });

    it('acceptsOnlyDedicatedCurrentCacheFiles', 0, () => {
      const prepared = prepareSharePayload(temporaryImagePayload(temporaryFile()), policy());

      expect(prepared.dispatchKind).assertEqual(ShareDispatchKind.TEMPORARY_FILE);
      expect(prepared.mimeType).assertEqual('image/png');
      expect(prepared.source).assertEqual(`${CACHE_DIR}/p4-share/image-123.png`);
    });

    it('rejectsInternalPathsTraversalExpiredFilesAndUnexpectedMime', 0, () => {
      const outside = temporaryFile(`${CACHE_DIR}/drafts/secret.png`);
      const traversal = temporaryFile(`${CACHE_DIR}/p4-share/../secret.png`);
      const expired = temporaryFile(`${CACHE_DIR}/p4-share/image-123.png`, 'image/png', NOW - 24 * 60 * 60 * 1000 - 1);
      const html = temporaryFile(`${CACHE_DIR}/p4-share/image-123.png`, 'text/html');

      expect((): void => { prepareSharePayload(filePayload(outside), policy()); }).assertThrowError('分享内容不受支持');
      expect((): void => { prepareSharePayload(filePayload(traversal), policy()); }).assertThrowError('分享内容不受支持');
      expect((): void => { prepareSharePayload(filePayload(expired), policy()); }).assertThrowError('分享文件已不可用');
      expect((): void => { prepareSharePayload(filePayload(html), policy()); }).assertThrowError('分享内容不受支持');
    });

    it('usesDelayedAndBoundedTemporaryFileCleanup', 0, () => {
      const lifecycle = createTemporaryShareLifecycle(temporaryFile());
      const opened = markSharePanelOpened(lifecycle, NOW);

      expect(shouldCleanupTemporaryShareFile(lifecycle, NOW + 1000)).assertFalse();
      expect(shouldCleanupTemporaryShareFile(opened, NOW + 30 * 60 * 1000 - 1)).assertFalse();
      expect(shouldCleanupTemporaryShareFile(opened, NOW + 30 * 60 * 1000)).assertTrue();
      expect(opened.cleanupAfterMillis <= lifecycle.createdAtMillis + 24 * 60 * 60 * 1000).assertTrue();
    });

    it('buildsHyperlinkRecordWithoutSensitivePayloadForTrustedLink', 0, () => {
      const records = createSystemShareRecords(
        prepareSharePayload(textPayload(), policy()), new FixedFileUriResolver()
      );
      const serialized = JSON.stringify(records);

      expect(records.length).assertEqual(1);
      expect(records[0].utd).assertEqual('general.hyperlink');
      expect(records[0].content).assertEqual('https://www.zhihu.com/question/123/answer/456');
      expect(records[0].title).assertEqual('鸿蒙迁移进展');
      expect(serialized.includes('cookie')).assertFalse();
      expect(serialized.includes('authorization')).assertFalse();
      expect(serialized.includes('headers')).assertFalse();
    });

    it('buildsTypedFileRecordForTemporaryFiles', 0, () => {
      const imagePrepared = prepareSharePayload(temporaryImagePayload(temporaryFile()), policy());
      const imageRecords = createSystemShareRecords(imagePrepared, new FixedFileUriResolver());
      const filePrepared = prepareSharePayload(filePayload(temporaryFile(
        `${CACHE_DIR}/p4-share/export-123.pdf`, 'application/pdf', NOW
      )), policy());
      const fileRecords = createSystemShareRecords(filePrepared, new FixedFileUriResolver());

      expect(imageRecords.length).assertEqual(1);
      expect(imageRecords[0].utd).assertEqual('general.image');
      expect(imageRecords[0].uri).assertEqual(`file://sandbox${CACHE_DIR}/p4-share/image-123.png`);
      expect(fileRecords[0].utd).assertEqual('general.file');
      expect(fileRecords[0].uri).assertEqual(`file://sandbox${CACHE_DIR}/p4-share/export-123.pdf`);
    });

    it('validatesOptionalTrustedThumbnailUrlOnTextPayload', 0, () => {
      const withThumbnail = textPayload();
      const payload: ShareTextPayload = {
        kind: withThumbnail.kind,
        title: withThumbnail.title,
        summary: withThumbnail.summary,
        contentUrl: withThumbnail.contentUrl,
        thumbnailUrl: 'https://picx.zhimg.com/v2-avatar.jpg'
      };
      const prepared = prepareSharePayload(payload, policy());

      expect(prepared.thumbnailUrl).assertEqual('https://picx.zhimg.com/v2-avatar.jpg');

      const untrusted: ShareTextPayload = {
        kind: withThumbnail.kind,
        title: withThumbnail.title,
        summary: withThumbnail.summary,
        contentUrl: withThumbnail.contentUrl,
        thumbnailUrl: 'https://evil.example/avatar.jpg'
      };

      expect((): void => { prepareSharePayload(untrusted, policy()); }).assertThrowError('分享内容不受支持');
    });

    it('attachesFetchedThumbnailAndDescriptionToHyperlinkRecord', 0, async () => {
      const launcher = new RecordingShareLauncher();
      const thumbnail = new Uint8Array([1, 2, 3]);
      const service = new SystemShareService(
        launcher, policy(), new FixedFileUriResolver(), new StubShareThumbnailFetcher(thumbnail)
      );
      const payload = textPayload();
      const payloadWithThumbnail: ShareTextPayload = {
        kind: payload.kind,
        title: payload.title,
        summary: payload.summary,
        contentUrl: payload.contentUrl,
        thumbnailUrl: 'https://picx.zhimg.com/v2-avatar.jpg'
      };

      const outcome = await service.share(payloadWithThumbnail);
      const records = launcher.panels[0];

      expect(outcome).assertEqual(ShareOutcome.OPENED);
      expect(records.length).assertEqual(1);
      expect(records[0].description).assertEqual('知乎++ 的 P4 执行计划');
      expect(records[0].thumbnail?.length).assertEqual(3);
    });

    it('opensPanelWithoutThumbnailWhenFetcherFails', 0, async () => {
      const launcher = new RecordingShareLauncher();
      const service = new SystemShareService(
        launcher, policy(), new FixedFileUriResolver(), new StubShareThumbnailFetcher(undefined)
      );
      const payload = textPayload();
      const payloadWithThumbnail: ShareTextPayload = {
        kind: payload.kind,
        title: payload.title,
        summary: payload.summary,
        contentUrl: payload.contentUrl,
        thumbnailUrl: 'https://picx.zhimg.com/v2-avatar.jpg'
      };

      const outcome = await service.share(payloadWithThumbnail);
      const records = launcher.panels[0];

      expect(outcome).assertEqual(ShareOutcome.OPENED);
      expect(records[0].thumbnail).assertUndefined();
      expect(records[0].content).assertEqual('https://www.zhihu.com/question/123/answer/456');
    });

    it('treatsShareCancellationAsNormalOutcome', 0, async () => {
      const launcher = new RecordingShareLauncher();
      launcher.nextError = new Error('user cancelled chooser');
      const service = new SystemShareService(launcher, policy(), new FixedFileUriResolver());

      const outcome = await service.share(textPayload());

      expect(outcome).assertEqual(ShareOutcome.CANCELLED);
      expect(launcher.panels.length).assertEqual(0);
    });

    it('mapsMissingHandlerToFixedFailureWithoutRawMessage', 0, async () => {
      const launcher = new RecordingShareLauncher();
      launcher.nextError = new Error('ability not found: private package detail');
      const service = new SystemShareService(launcher, policy(), new FixedFileUriResolver());
      let failure: ShareFailure | undefined = undefined;

      try {
        await service.share(textPayload());
      } catch (error) {
        if (error instanceof ShareFailure) {
          failure = error;
        }
      }

      expect(failure?.kind).assertEqual(ShareFailureKind.NO_HANDLER);
      expect(failure?.message.includes('private package detail')).assertFalse();
    });
  });
}
