import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@ohos.base';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import {
  PreparedSharePayload,
  prepareSharePayload,
  ShareDispatchKind,
  ShareFailure,
  ShareFailureKind,
  ShareOutcome,
  SharePayload,
  ShareRuntimePolicy,
  ShareService,
  toShareFailure
} from './ShareContracts';

/** 系统面板缩略图上限：want 数据超 32 KB 会导致 Share Kit 启动失败。 */
const MAX_THUMBNAIL_BYTES: number = 32 * 1024;
const THUMBNAIL_MAX_EDGE: number = 240;
const THUMBNAIL_QUALITIES: Array<number> = [80, 55, 35];

/** 不向业务页面泄露系统分享面板细节；测试可注入 recording launcher。 */
export interface SharePanelLauncher {
  showPanel(records: Array<ShareRecordSpec>): Promise<void>;
}

export interface ShareFileUriResolver {
  getUriFromPath(path: string): string;
}

/** 尽力获取链接卡片缩略图；失败返回 undefined，不阻断分享。 */
export interface ShareThumbnailFetcher {
  fetchThumbnail(url: string): Promise<Uint8Array | undefined>;
}

export interface ShareRecordSpec {
  readonly utd: string;
  readonly title?: string;
  readonly description?: string;
  readonly content?: string;
  readonly uri?: string;
  readonly thumbnail?: Uint8Array;
}

class AppFileUriResolver implements ShareFileUriResolver {
  getUriFromPath(path: string): string {
    try {
      return fileUri.getUriFromPath(path);
    } catch (_error) {
      throw new ShareFailure(ShareFailureKind.FILE_UNAVAILABLE);
    }
  }
}

export class SystemShareService implements ShareService {
  private readonly launcher: SharePanelLauncher;
  private readonly policy: ShareRuntimePolicy;
  private readonly fileUriResolver: ShareFileUriResolver;
  private readonly thumbnailFetcher?: ShareThumbnailFetcher;

  constructor(
    launcher: SharePanelLauncher,
    policy: ShareRuntimePolicy,
    fileUriResolver: ShareFileUriResolver,
    thumbnailFetcher?: ShareThumbnailFetcher
  ) {
    this.launcher = launcher;
    this.policy = policy;
    this.fileUriResolver = fileUriResolver;
    this.thumbnailFetcher = thumbnailFetcher;
  }

  async share(payload: SharePayload): Promise<ShareOutcome> {
    const prepared = prepareSharePayload(payload, {
      cacheDir: this.policy.cacheDir,
      nowMillis: Date.now()
    });
    const thumbnail = await this.fetchThumbnailBestEffort(prepared.thumbnailUrl);
    try {
      await this.launcher.showPanel(
        createSystemShareRecords(prepared, this.fileUriResolver, thumbnail)
      );
      return ShareOutcome.OPENED;
    } catch (error) {
      const failure = toShareFailure(error instanceof Error ? error : new Error('share panel failed'));
      if (failure.kind === ShareFailureKind.CANCELLED) {
        return ShareOutcome.CANCELLED;
      }
      throw failure;
    }
  }

  private async fetchThumbnailBestEffort(url: string | undefined): Promise<Uint8Array | undefined> {
    if (url === undefined || this.thumbnailFetcher === undefined) {
      return undefined;
    }
    try {
      return await this.thumbnailFetcher.fetchThumbnail(url);
    } catch (_error) {
      return undefined;
    }
  }
}

export class SystemSharePanelLauncher implements SharePanelLauncher {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async showPanel(records: Array<ShareRecordSpec>): Promise<void> {
    const sharedData = new systemShare.SharedData(toSharedRecord(records[0]));
    for (let index = 1; index < records.length; index++) {
      sharedData.addRecord(toSharedRecord(records[index]));
    }
    const controller = new systemShare.ShareController(sharedData);
    const options: systemShare.ShareControllerOptions = {};
    try {
      await controller.show(this.context, options);
    } catch (error) {
      const businessError = error as BusinessError;
      throw new Error(`${businessError.code}: ${businessError.message}`);
    }
  }
}

/** 下载受信 zhimg 图片并压缩到面板缩略图限制内；任何失败都返回 undefined。 */
export class HttpShareThumbnailFetcher implements ShareThumbnailFetcher {
  async fetchThumbnail(url: string): Promise<Uint8Array | undefined> {
    const buffer = await HttpShareThumbnailFetcher.download(url);
    if (buffer === undefined) {
      return undefined;
    }
    return await HttpShareThumbnailFetcher.downscale(buffer);
  }

  private static async download(url: string): Promise<ArrayBuffer | undefined> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 3000,
        readTimeout: 5000
      };
      const response = await request.request(url, options);
      if (response.responseCode !== 200) {
        return undefined;
      }
      const result = response.result;
      return result instanceof ArrayBuffer ? result : undefined;
    } catch (_error) {
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private static async downscale(buffer: ArrayBuffer): Promise<Uint8Array | undefined> {
    const source = image.createImageSource(buffer);
    try {
      const imageInfo: image.ImageInfo = await source.getImageInfo();
      const longestEdge = Math.max(imageInfo.size.width, imageInfo.size.height);
      if (longestEdge <= 0) {
        return undefined;
      }
      const scale = Math.min(1, THUMBNAIL_MAX_EDGE / longestEdge);
      const decodingOptions: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(imageInfo.size.width * scale)),
          height: Math.max(1, Math.round(imageInfo.size.height * scale))
        }
      };
      const pixelMap = await source.createPixelMap(decodingOptions);
      try {
        const packer = image.createImagePacker();
        try {
          for (const quality of THUMBNAIL_QUALITIES) {
            const packingOptions: image.PackingOption = { format: 'image/jpeg', quality: quality };
            const packed = await packer.packToData(pixelMap, packingOptions);
            if (packed.byteLength > 0 && packed.byteLength <= MAX_THUMBNAIL_BYTES) {
              return new Uint8Array(packed);
            }
          }
          return undefined;
        } finally {
          packer.release();
        }
      } finally {
        pixelMap.release();
      }
    } catch (_error) {
      return undefined;
    } finally {
      await source.release();
    }
  }
}

export function createSystemShareService(context: common.UIAbilityContext): SystemShareService {
  const policy: ShareRuntimePolicy = {
    cacheDir: context.cacheDir,
    nowMillis: Date.now()
  };
  return new SystemShareService(
    new SystemSharePanelLauncher(context),
    policy,
    new AppFileUriResolver(),
    new HttpShareThumbnailFetcher()
  );
}

export function createSystemShareRecords(
  prepared: PreparedSharePayload,
  fileUriResolver: ShareFileUriResolver,
  thumbnail?: Uint8Array
): Array<ShareRecordSpec> {
  if (prepared.dispatchKind === ShareDispatchKind.TEMPORARY_FILE) {
    const uri = fileUriResolver.getUriFromPath(prepared.source);
    const spec: ShareRecordSpec = {
      utd: prepared.mimeType.startsWith('image/') ? uniformTypeDescriptor.UniformDataType.IMAGE : uniformTypeDescriptor.UniformDataType.FILE,
      title: prepared.title,
      uri: uri
    };
    return [spec];
  }
  const spec: ShareRecordSpec = {
    utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
    title: prepared.title,
    description: prepared.summary,
    content: prepared.source
  };
  if (thumbnail !== undefined) {
    return [{
      utd: spec.utd,
      title: spec.title,
      description: spec.description,
      content: spec.content,
      thumbnail: thumbnail
    }];
  }
  return [spec];
}

function toSharedRecord(spec: ShareRecordSpec): systemShare.SharedRecord {
  const record: systemShare.SharedRecord = { utd: spec.utd };
  if (spec.title !== undefined) {
    record.title = spec.title;
  }
  if (spec.description !== undefined) {
    record.description = spec.description;
  }
  if (spec.content !== undefined) {
    record.content = spec.content;
  }
  if (spec.uri !== undefined) {
    record.uri = spec.uri;
  }
  if (spec.thumbnail !== undefined) {
    record.thumbnail = spec.thumbnail;
  }
  return record;
}
