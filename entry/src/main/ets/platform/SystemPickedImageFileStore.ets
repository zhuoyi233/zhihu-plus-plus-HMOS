import { fileIo } from '@kit.CoreFileKit';
import {
  createImageTemporaryLifecycle,
  IMAGE_TEMPORARY_MAX_AGE_MILLIS,
  IMAGE_UPLOAD_TEMPORARY_DIRECTORY,
  LEGACY_IMAGE_UPLOAD_TEMPORARY_DIRECTORY,
  ImageBinaryDescriptor,
  ImageTemporaryFile,
  ImageTemporaryState,
  ImageUploadFailure,
  ImageUploadFailureKind,
  inspectPickedImage,
  LocalDraftImageReference,
  PickedImageFormat,
  PickedImageInspection,
  sniffImageBinary,
  transitionImageTemporaryLifecycle,
  ValidatedPickedImage
} from 'data';
import {
  defaultMediaPickerRuntimePolicy,
  MediaPickerCoordinator,
  PreparedPickedImage,
  PhotoPickerSelection,
  PickedImageInspector,
  PickedImageTemporaryStore
} from './MediaPickerCoordinator';
import { createSystemPhotoPickerGateway } from './SystemPhotoPickerGateway';

const INSPECTION_HEADER_BYTES: number = 65536;
const CONTENT_COMPARE_CHUNK_BYTES: number = 1024 * 1024;
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
 * 将已检查的系统媒体副本写入 cache/picked-images。目标文件名完全由应用生成；复制后再次按 magic bytes
 * 校验，避免源文件在检查与复制之间变化。这里只保存短生命周期副本，绝不触发上传。
 * 历史目录 cache/p4-images 不再新增写入，仅由解析与清理逻辑读取。
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
      await copyPickedMediaToCache(selection.image.uri, temporaryPath, image.byteLength);
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
    return `${this.cacheDir}/${IMAGE_UPLOAD_TEMPORARY_DIRECTORY}`;
  }
}

/** 清理、迁移等破坏性文件操作的进程内统一调度边界：按到达顺序串行执行，避免与恢复、上传竞争。 */
let imageMaintenanceQueue: Promise<void> = Promise.resolve();

function enqueueImageMaintenance<T>(operation: () => Promise<T>): Promise<T> {
  const result = imageMaintenanceQueue.then(operation, operation);
  imageMaintenanceQueue = result.then((): void => {
  }, (): void => {
  });
  return result;
}

async function copyPickedMediaToCache(sourceUri: string, temporaryPath: string, expectedByteLength: number): Promise<void> {
  let sourceFd: number = -1;
  let destinationFd: number = -1;
  try {
    // Photo Picker URI 可由 open 解析，但 copyFile 的字符串参数只接受沙箱文件路径。
    const source = await fileIo.open(sourceUri, fileIo.OpenMode.READ_ONLY);
    sourceFd = source.fd;
    const sourceStat = await fileIo.stat(sourceFd);
    if (!sourceStat.isFile() || sourceStat.size !== expectedByteLength) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const destination = await fileIo.open(temporaryPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    destinationFd = destination.fd;
    await fileIo.copyFile(sourceFd, destinationFd, 0);
  } finally {
    if (destinationFd >= 0) {
      try {
        await fileIo.close(destinationFd);
      } catch (_error) {
      }
    }
    if (sourceFd >= 0) {
      try {
        await fileIo.close(sourceFd);
      } catch (_error) {
      }
    }
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
    const normalizedCacheDir = normalizeCacheDir(cacheDir);
    return matchesControlledImageDirectory(normalizedCacheDir, IMAGE_UPLOAD_TEMPORARY_DIRECTORY, path) ||
      matchesControlledImageDirectory(normalizedCacheDir, LEGACY_IMAGE_UPLOAD_TEMPORARY_DIRECTORY, path);
  } catch (_error) {
    return false;
  }
}

function matchesControlledImageDirectory(cacheDir: string, directory: string, path: string): boolean {
  const prefix = `${cacheDir}/${directory}/`;
  return path.startsWith(prefix) && CONTROLLED_FILE_NAME.test(path.substring(prefix.length));
}

export function buildControlledImageTemporaryPath(cacheDir: string, fileName: string): string {
  if (!CONTROLLED_FILE_NAME.test(fileName)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return `${normalizeCacheDir(cacheDir)}/${IMAGE_UPLOAD_TEMPORARY_DIRECTORY}/${fileName}`;
}

/** 旧目录路径只由迁移与清理适配器构造；正常选图与上传写入一律走新目录构建器。 */
export function buildLegacyControlledImageTemporaryPath(cacheDir: string, fileName: string): string {
  if (!CONTROLLED_FILE_NAME.test(fileName)) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  return `${normalizeCacheDir(cacheDir)}/${LEGACY_IMAGE_UPLOAD_TEMPORARY_DIRECTORY}/${fileName}`;
}

const CONTROLLED_FILE_MISSING: string = 'missing';
const CONTROLLED_FILE_INVALID: string = 'invalid';
const CONTROLLED_FILE_VALID: string = 'valid';

/**
 * 草稿引用与上传共用的路径解析：新目录有效文件优先；旧目录文件校验通过后复制迁移；
 * 迁移失败但旧文件有效时回退旧路径。两处候选都不可用时返回 undefined，由调用方报告图片不可用，
 * 绝不静默丢弃草稿引用。整个过程串行于维护队列，暂停并发回收。
 */
export async function resolveControlledImageTemporaryFile(cacheDir: string,
  reference: LocalDraftImageReference): Promise<ImageTemporaryFile | undefined> {
  const normalizedCacheDir = normalizeCacheDir(cacheDir);
  if (!CONTROLLED_FILE_NAME.test(reference.fileName)) {
    return undefined;
  }
  let expected: ImageBinaryDescriptor;
  try {
    expected = descriptorForDraftReference(reference);
  } catch (_error) {
    return undefined;
  }
  return enqueueImageMaintenance(async (): Promise<ImageTemporaryFile | undefined> => {
    const newPath = buildControlledImageTemporaryPath(normalizedCacheDir, reference.fileName);
    const legacyPath = buildLegacyControlledImageTemporaryPath(normalizedCacheDir, reference.fileName);
    const newState = await inspectControlledImageFile(newPath, reference.byteLength, expected);
    if (newState === CONTROLLED_FILE_VALID) {
      return controlledImageFile(newPath, reference);
    }
    const legacyState = await inspectControlledImageFile(legacyPath, reference.byteLength, expected);
    if (legacyState !== CONTROLLED_FILE_VALID) {
      return undefined;
    }
    if (newState === CONTROLLED_FILE_INVALID) {
      // 同名冲突：两份都保留，不覆盖、不迁移；继续使用经验证的旧文件。
      return controlledImageFile(legacyPath, reference);
    }
    const migrated = await migrateControlledImageFile(normalizedCacheDir, reference.fileName,
      legacyPath, newPath, reference.byteLength, expected);
    return controlledImageFile(migrated ? newPath : legacyPath, reference);
  });
}

function controlledImageFile(path: string, reference: LocalDraftImageReference): ImageTemporaryFile {
  return {
    path: path,
    mimeType: reference.mimeType,
    byteLength: reference.byteLength,
    createdAtMillis: reference.createdAtMillis
  };
}

/** 存在但内容与引用不符返回 invalid；打不开才视为 missing。链接等非普通文件同样按 invalid 处理。 */
async function inspectControlledImageFile(path: string, byteLength: number,
  expected: ImageBinaryDescriptor): Promise<string> {
  let fd: number = -1;
  try {
    const opened = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    fd = opened.fd;
  } catch (_error) {
    return CONTROLLED_FILE_MISSING;
  }
  try {
    const stat = await fileIo.stat(fd);
    if (!stat.isFile() || stat.size !== byteLength) {
      return CONTROLLED_FILE_INVALID;
    }
    const headerLength = Math.min(stat.size, INSPECTION_HEADER_BYTES);
    const buffer = new ArrayBuffer(headerLength);
    const read = await fileIo.read(fd, buffer, { offset: 0, length: headerLength });
    if (read !== headerLength) {
      return CONTROLLED_FILE_INVALID;
    }
    const descriptor = sniffImageBinary(bufferToBytes(buffer, read));
    return sameDescriptor(descriptor, expected) ? CONTROLLED_FILE_VALID : CONTROLLED_FILE_INVALID;
  } catch (_error) {
    return CONTROLLED_FILE_INVALID;
  } finally {
    if (fd >= 0) {
      try {
        await fileIo.close(fd);
      } catch (_error) {
      }
    }
  }
}

/**
 * 旧目录 → 新目录的逐文件复制迁移：先写独占 .copying 临时文件，校验尺寸与 magic bytes 并逐字节
 * 比对源副本一致后原子改名；最终提交不覆盖并发出现的同名目标。失败保留旧文件供重试与回退。
 */
async function migrateControlledImageFile(cacheDir: string, fileName: string, legacyPath: string,
  newPath: string, byteLength: number, expected: ImageBinaryDescriptor): Promise<boolean> {
  const temporaryPath = `${newPath}.copying`;
  try {
    await ensureDirectory(`${cacheDir}/${IMAGE_UPLOAD_TEMPORARY_DIRECTORY}`);
    if (await fileIo.access(newPath)) {
      const targetState = await inspectControlledImageFile(newPath, byteLength, expected);
      return targetState === CONTROLLED_FILE_VALID;
    }
    await copyControlledFile(legacyPath, temporaryPath);
    const copyState = await inspectControlledImageFile(temporaryPath, byteLength, expected);
    const identical = copyState === CONTROLLED_FILE_VALID && await filesHaveSameContent(legacyPath, temporaryPath);
    if (!identical) {
      await removeIfPresent(temporaryPath);
      return false;
    }
    await fileIo.rename(temporaryPath, newPath);
    return true;
  } catch (_error) {
    await removeIfPresent(temporaryPath);
    return false;
  }
}

async function copyControlledFile(sourcePath: string, destinationPath: string): Promise<void> {
  let sourceFd: number = -1;
  let destinationFd: number = -1;
  try {
    const source = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
    sourceFd = source.fd;
    const destination = await fileIo.open(destinationPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    destinationFd = destination.fd;
    await fileIo.copyFile(sourceFd, destinationFd, 0);
  } finally {
    if (destinationFd >= 0) {
      try {
        await fileIo.close(destinationFd);
      } catch (_error) {
      }
    }
    if (sourceFd >= 0) {
      try {
        await fileIo.close(sourceFd);
      } catch (_error) {
      }
    }
  }
}

async function filesHaveSameContent(leftPath: string, rightPath: string): Promise<boolean> {
  let leftFd: number = -1;
  let rightFd: number = -1;
  try {
    const left = await fileIo.open(leftPath, fileIo.OpenMode.READ_ONLY);
    leftFd = left.fd;
    const right = await fileIo.open(rightPath, fileIo.OpenMode.READ_ONLY);
    rightFd = right.fd;
    const leftStat = await fileIo.stat(leftFd);
    const rightStat = await fileIo.stat(rightFd);
    if (!leftStat.isFile() || !rightStat.isFile() || leftStat.size !== rightStat.size) {
      return false;
    }
    const bufferA = new ArrayBuffer(CONTENT_COMPARE_CHUNK_BYTES);
    const bufferB = new ArrayBuffer(CONTENT_COMPARE_CHUNK_BYTES);
    let offset = 0;
    while (offset < leftStat.size) {
      const length = Math.min(CONTENT_COMPARE_CHUNK_BYTES, leftStat.size - offset);
      const leftRead = await fileIo.read(leftFd, bufferA, { offset: offset, length: length });
      const rightRead = await fileIo.read(rightFd, bufferB, { offset: offset, length: length });
      if (leftRead !== length || rightRead !== length) {
        return false;
      }
      const viewA = new Uint8Array(bufferA);
      const viewB = new Uint8Array(bufferB);
      for (let index = 0; index < length; index += 1) {
        if (viewA[index] !== viewB[index]) {
          return false;
        }
      }
      offset += length;
    }
    return true;
  } catch (_error) {
    return false;
  } finally {
    if (leftFd >= 0) {
      try {
        await fileIo.close(leftFd);
      } catch (_error) {
      }
    }
    if (rightFd >= 0) {
      try {
        await fileIo.close(rightFd);
      } catch (_error) {
      }
    }
  }
}

function sameDescriptor(left: ImageBinaryDescriptor, right: ImageBinaryDescriptor): boolean {
  return left.format === right.format && left.mimeType === right.mimeType && left.extension === right.extension &&
    left.width === right.width && left.height === right.height && left.animated === right.animated;
}

function bufferToBytes(buffer: ArrayBuffer, count: number): Array<number> {
  const bytes: Array<number> = [];
  const view = new Uint8Array(buffer);
  for (let index = 0; index < count; index += 1) {
    bytes.push(view[index]);
  }
  return bytes;
}

export interface RestoredControlledImages {
  readonly images: Array<PreparedPickedImage>;
  /** 引用存在但新旧目录都无法提供有效文件的图片数量；调用方需向用户明确报告，不得静默清空引用。 */
  readonly unavailableCount: number;
}

/**
 * 草稿恢复时只从受控缓存名重建应用缓存对象；不读取 Photo Picker URI，也不在恢复阶段访问网络。
 * 恢复改为异步解析：先验证新目录候选，再处理旧目录候选并尝试复制迁移；解析完成后才挂载面板。
 * 实际上传前仍会由上传读取器重新校验文件大小和 magic bytes。
 */
export async function restoreControlledPickedImages(cacheDir: string,
  references: Array<LocalDraftImageReference>): Promise<RestoredControlledImages> {
  const normalizedCacheDir = normalizeCacheDir(cacheDir);
  const result: Array<PreparedPickedImage> = [];
  let unavailableCount = 0;
  for (let index = 0; index < references.length; index += 1) {
    const reference = references[index];
    const resolved = await resolveControlledImageTemporaryFile(normalizedCacheDir, reference);
    if (resolved === undefined) {
      unavailableCount += 1;
      continue;
    }
    const selected = createImageTemporaryLifecycle(resolved, normalizedCacheDir);
    const processing = transitionImageTemporaryLifecycle(selected, ImageTemporaryState.PROCESSING);
    const ready = transitionImageTemporaryLifecycle(processing, ImageTemporaryState.READY);
    const image: ValidatedPickedImage = {
      sourceUri: `file://${resolved.path}`,
      byteLength: reference.byteLength,
      descriptor: descriptorForDraftReference(reference)
    };
    result.push({ image: image, lifecycle: ready });
  }
  return { images: result, unavailableCount: unavailableCount };
}

/**
 * 回收崩溃、系统回收或进程终止后遗留的受控缓存，覆盖新旧两个专用目录。仅匹配应用随机名；
 * 已保存草稿引用的文件名必须经 protectedFileNames 排除，引用扫描不完整时调用方应完全跳过本次清理。
 * 目录错误、文件错误和并发删除均安全忽略，不能影响选图流程或访问用户目录。
 * 该操作与图片迁移共用进程内维护队列，不会与复制迁移并发删除同一文件。
 */
export async function purgeExpiredControlledImageCache(cacheDir: string, nowMillis: number = Date.now(),
  protectedFileNames?: Set<string>): Promise<number> {
  const normalizedCacheDir = normalizeCacheDir(cacheDir);
  if (!Number.isSafeInteger(nowMillis) || nowMillis < 0) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  const directories: Array<string> = [
    `${normalizedCacheDir}/${IMAGE_UPLOAD_TEMPORARY_DIRECTORY}`,
    `${normalizedCacheDir}/${LEGACY_IMAGE_UPLOAD_TEMPORARY_DIRECTORY}`
  ];
  return enqueueImageMaintenance(async (): Promise<number> => {
    let removedCount = 0;
    for (let directoryIndex = 0; directoryIndex < directories.length; directoryIndex += 1) {
      const directory = directories[directoryIndex];
      let entries: Array<string>;
      try {
        entries = await fileIo.listFile(directory);
      } catch (_error) {
        continue;
      }
      for (let index = 0; index < entries.length; index += 1) {
        const entry = entries[index];
        if ((protectedFileNames !== undefined && protectedFileNames.has(entry)) ||
          !shouldPurgeControlledImageTemporaryArtifact(entry, -1, nowMillis)) {
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
    }
    return removedCount;
  });
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

function descriptorForDraftReference(reference: LocalDraftImageReference): ImageBinaryDescriptor {
  const format = formatForMime(reference.mimeType);
  return {
    format: format,
    mimeType: reference.mimeType,
    extension: extensionForFormat(format),
    width: reference.width,
    height: reference.height,
    animated: reference.animated
  };
}

function formatForMime(mimeType: string): PickedImageFormat {
  if (mimeType === 'image/jpeg') return PickedImageFormat.JPEG;
  if (mimeType === 'image/png') return PickedImageFormat.PNG;
  if (mimeType === 'image/webp') return PickedImageFormat.WEBP;
  if (mimeType === 'image/gif') return PickedImageFormat.GIF;
  throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
}

function extensionForFormat(format: PickedImageFormat): string {
  if (format === PickedImageFormat.JPEG) return 'jpg';
  if (format === PickedImageFormat.PNG) return 'png';
  if (format === PickedImageFormat.WEBP) return 'webp';
  return 'gif';
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
