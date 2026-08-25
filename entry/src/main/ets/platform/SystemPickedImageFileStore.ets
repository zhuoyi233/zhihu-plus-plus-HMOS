import { fileIo } from '@kit.CoreFileKit';
import {
  createImageTemporaryLifecycle,
  IMAGE_TEMPORARY_MAX_AGE_MILLIS,
  ImageTemporaryFile,
  ImageUploadFailure,
  ImageUploadFailureKind,
  inspectPickedImage,
  PickedImageInspection,
  ValidatedPickedImage
} from 'data';
import {
  defaultMediaPickerRuntimePolicy,
  MediaPickerCoordinator,
  PhotoPickerSelection,
  PickedImageInspector,
  PickedImageTemporaryStore
} from './MediaPickerCoordinator';
import { createSystemPhotoPickerGateway } from './SystemPhotoPickerGateway';

const INSPECTION_HEADER_BYTES: number = 65536;
const CONTROLLED_FILE_NAME: RegExp = /^[a-f0-9]{32}\.(?:jpg|png|webp|gif)$/;
const CONTROLLED_TEMPORARY_ARTIFACT_NAME: RegExp = /^[a-f0-9]{32}\.(?:jpg|png|webp|gif)(?:\.copying)?$/;
const PICKED_MEDIA_URI: RegExp = /^file:\/\/(?:media|com\.ohos\.filemanager\.dir)\/[A-Za-z0-9._~%/-]+$/;

/**
 * 系统 Photo Picker 的 URI 只在本次用户明确选择后以只读方式使用。此适配器不申请全量相册权限，
 * 不把 URI、原始字节或文件名传进草稿、日志或网络层。
 */
export class HarmonyPickedImageInspector implements PickedImageInspector {
  async inspect(selection: PhotoPickerSelection): Promise<PickedImageInspection> {
    const sourceUri = selection.image.uri;
    if (!isPickedMediaUri(sourceUri)) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    return await readImageInspection(sourceUri, sourceUri);
  }
}

/**
 * 将已检查的系统媒体副本写入 cache/p4-images。目标文件名完全由应用生成；复制后再次按 magic bytes
 * 校验，避免源文件在检查与复制之间变化。这里只保存短生命周期副本，绝不触发上传。
 */
export class HarmonyPickedImageTemporaryStore implements PickedImageTemporaryStore {
  private readonly cacheDir: string;

  constructor(cacheDir: string) {
    this.cacheDir = normalizeCacheDir(cacheDir);
  }

  async write(selection: PhotoPickerSelection, image: ValidatedPickedImage, nowMillis: number): Promise<ImageTemporaryFile> {
    if (!isPickedMediaUri(selection.image.uri) || selection.image.uri !== image.sourceUri ||
      !Number.isSafeInteger(nowMillis) || nowMillis < 0) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const directory = this.directory();
    const fileName = randomControlledFileName(image.descriptor.extension);
    const temporaryPath = `${directory}/${fileName}.copying`;
    const finalPath = `${directory}/${fileName}`;
    try {
      await ensureDirectory(directory);
      await fileIo.copyFile(selection.image.uri, temporaryPath, 0);
      const copied = await readImageInspection(temporaryPath, image.sourceUri);
      const verified = inspectPickedImage(copied);
      if (!sameValidatedImage(verified, image)) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }
      await fileIo.rename(temporaryPath, finalPath);
      const file: ImageTemporaryFile = {
        path: finalPath,
        mimeType: image.descriptor.mimeType,
        byteLength: image.byteLength,
        createdAtMillis: nowMillis
      };
      createImageTemporaryLifecycle(file, this.cacheDir);
      return file;
    } catch (error) {
      await removeIfPresent(temporaryPath);
      await removeIfPresent(finalPath);
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }

  async remove(file: ImageTemporaryFile): Promise<void> {
    try {
      createImageTemporaryLifecycle(file, this.cacheDir);
      await removeIfPresent(file.path);
    } catch (error) {
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }

  private directory(): string {
    return `${this.cacheDir}/p4-images`;
  }
}

/** 组合根只能调用本工厂；它不接受 HTTP、会话或上传凭证，因而无法意外执行外部写入。 */
export function createProductionMediaPickerCoordinator(cacheDir: string, nowMillis: number = Date.now()): MediaPickerCoordinator {
  const normalizedCacheDir = normalizeCacheDir(cacheDir);
  return new MediaPickerCoordinator(
    createSystemPhotoPickerGateway(),
    new HarmonyPickedImageInspector(),
    new HarmonyPickedImageTemporaryStore(normalizedCacheDir),
    defaultMediaPickerRuntimePolicy(normalizedCacheDir, nowMillis)
  );
}

export function isPickedMediaUri(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 4096 && PICKED_MEDIA_URI.test(value) &&
    !value.includes('..') && !/[\r\n\t ]/.test(value);
}

export function isControlledImageTemporaryPath(cacheDir: string, path: string): boolean {
  try {
    const directory = `${normalizeCacheDir(cacheDir)}/p4-images/`;
    return path.startsWith(directory) && CONTROLLED_FILE_NAME.test(path.substring(directory.length));
  } catch (_error) {
    return false;
  }
}

export function buildControlledImageTemporaryPath(cacheDir: string, fileName: string): string {
  if (!CONTROLLED_FILE_NAME.test(fileName)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return `${normalizeCacheDir(cacheDir)}/p4-images/${fileName}`;
}

/**
 * 页面进入时回收崩溃、系统回收或进程终止后遗留的受控缓存。仅匹配应用随机名；目录错误、文件错误
 * 和并发删除均安全忽略，不能影响选图流程或访问用户目录。
 */
export async function purgeExpiredControlledImageCache(cacheDir: string, nowMillis: number = Date.now()): Promise<number> {
  const normalizedCacheDir = normalizeCacheDir(cacheDir);
  if (!Number.isSafeInteger(nowMillis) || nowMillis < 0) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const directory = `${normalizedCacheDir}/p4-images`;
  let entries: Array<string>;
  try {
    entries = await fileIo.listFile(directory);
  } catch (_error) {
    return 0;
  }
  let removedCount = 0;
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    if (!shouldPurgeControlledImageTemporaryArtifact(entry, -1, nowMillis)) {
      continue;
    }
    const path = `${directory}/${entry}`;
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isFile() || !shouldPurgeControlledImageTemporaryArtifact(entry, stat.mtime, nowMillis)) {
        continue;
      }
      await fileIo.unlink(path);
      removedCount += 1;
    } catch (_error) {
      // 文件在枚举后被正常清理、不可访问或不是普通文件时不重试，也不泄漏其名称。
    }
  }
  return removedCount;
}

/** 纯函数，供测试固定 24 小时的缓存回收边界；-1 用于只判定应用生成的文件名。 */
export function shouldPurgeControlledImageTemporaryArtifact(
  fileName: string,
  modifiedAtSeconds: number,
  nowMillis: number
): boolean {
  if (!CONTROLLED_TEMPORARY_ARTIFACT_NAME.test(fileName) || !Number.isSafeInteger(nowMillis) || nowMillis < 0) {
    return false;
  }
  if (modifiedAtSeconds === -1) {
    return true;
  }
  if (!Number.isSafeInteger(modifiedAtSeconds) || modifiedAtSeconds < 0) {
    return false;
  }
  return nowMillis >= modifiedAtSeconds * 1000 + IMAGE_TEMPORARY_MAX_AGE_MILLIS;
}

async function readImageInspection(reference: string, sourceUri: string): Promise<PickedImageInspection> {
  let openedFd: number = -1;
  try {
    const opened = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
    openedFd = opened.fd;
    const stat = await fileIo.stat(openedFd);
    if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size < 1) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const headerLength = Math.min(stat.size, INSPECTION_HEADER_BYTES);
    const buffer = new ArrayBuffer(headerLength);
    const read = await fileIo.read(openedFd, buffer, { offset: 0, length: headerLength });
    if (!Number.isSafeInteger(read) || read < 1) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const headerBytes: Array<number> = [];
    const view = new Uint8Array(buffer);
    for (let index = 0; index < read; index += 1) {
      headerBytes.push(view[index]);
    }
    return { sourceUri: sourceUri, byteLength: stat.size, headerBytes: headerBytes };
  } catch (error) {
    if (error instanceof ImageUploadFailure) {
      throw error;
    }
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  } finally {
    if (openedFd >= 0) {
      try {
        await fileIo.close(openedFd);
      } catch (_error) {
      }
    }
  }
}

async function ensureDirectory(path: string): Promise<void> {
  try {
    await fileIo.mkdir(path, true);
  } catch (_error) {
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
      }
    } catch (error) {
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }
}

async function removeIfPresent(path: string): Promise<void> {
  try {
    if (await fileIo.access(path)) {
      await fileIo.unlink(path);
    }
  } catch (_error) {
  }
}

function sameValidatedImage(left: ValidatedPickedImage, right: ValidatedPickedImage): boolean {
  return left.byteLength === right.byteLength && left.descriptor.format === right.descriptor.format &&
    left.descriptor.mimeType === right.descriptor.mimeType && left.descriptor.extension === right.descriptor.extension &&
    left.descriptor.width === right.descriptor.width && left.descriptor.height === right.descriptor.height &&
    left.descriptor.animated === right.descriptor.animated;
}

function randomControlledFileName(extension: string): string {
  if (extension !== 'jpg' && extension !== 'png' && extension !== 'webp' && extension !== 'gif') {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  let random = '';
  for (let index = 0; index < 32; index += 1) {
    random += Math.floor(Math.random() * 16).toString(16);
  }
  return `${random}.${extension}`;
}

function normalizeCacheDir(value: string): string {
  const normalized = value.replace(/\\/g, '/').replace(/\/+$/g, '');
  if (!/^\/[A-Za-z0-9._/-]+$/.test(normalized) || normalized.includes('..')) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return normalized;
}
