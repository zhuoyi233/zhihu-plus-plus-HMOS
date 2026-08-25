import {
  ImageBinaryDescriptor,
  ImageTemporaryFile,
  MAX_IMAGE_BATCH_BYTES,
  MAX_IMAGE_SELECTION_COUNT,
  MAX_IMAGE_SINGLE_BYTES
} from '../repository/ImageUploadContracts';
import {
  JsonArrayValue,
  JsonBooleanValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson
} from 'core';

/**
 * 可恢复草稿只保存应用缓存文件的随机名和已验证元数据；绝不保存系统 Photo Picker URI、图片字节、
 * 原始文件名、会话或上传凭证。完整路径由当前应用 cacheDir 在使用时重建。
 */
export interface LocalDraftImageReference {
  readonly fileName: string;
  readonly mimeType: string;
  readonly byteLength: number;
  readonly width: number;
  readonly height: number;
  readonly animated: boolean;
  readonly createdAtMillis: number;
}

const CONTROLLED_FILE_NAME: RegExp = /^[a-f0-9]{32}\.(?:jpg|png|webp|gif)$/;
const CONTROLLED_FILE_PATH: RegExp = /(?:^|\/)p4-images\/([a-f0-9]{32}\.(?:jpg|png|webp|gif))$/;

export function createLocalDraftImageReference(file: ImageTemporaryFile,
  descriptor: ImageBinaryDescriptor): LocalDraftImageReference {
  const fileName = controlledFileName(file.path);
  if (!isMatchingDescriptor(fileName, file.mimeType, descriptor) || !isSafeByteLength(file.byteLength) ||
    !Number.isSafeInteger(file.createdAtMillis) || file.createdAtMillis < 0) {
    throw new Error('Local draft image reference is invalid');
  }
  return {
    fileName: fileName,
    mimeType: file.mimeType,
    byteLength: file.byteLength,
    width: descriptor.width,
    height: descriptor.height,
    animated: descriptor.animated,
    createdAtMillis: file.createdAtMillis
  };
}

/** 仅在持久化到 DraftRepository 时序列化，并对数量、总大小和重复随机名再次做约束。 */
export function serializeLocalDraftImageReferences(references: Array<LocalDraftImageReference>): string {
  validateReferences(references);
  return JSON.stringify(references.map((item: LocalDraftImageReference): LocalDraftImageReference => cloneReference(item)));
}

/**
 * 历史草稿可能混有已上传图片的远端元数据；它们不符合本地引用格式，安全跳过即可。
 * 损坏的本地引用同样不恢复，不能令草稿打开流程访问应用缓存以外的路径。
 */
export function parseLocalDraftImageReferences(serialized: string): Array<LocalDraftImageReference> {
  if (typeof serialized !== 'string' || serialized.length > 65536) {
    return [];
  }
  let parsed: JsonValue;
  try {
    parsed = parseStrictJson(serialized);
  } catch (_error) {
    return [];
  }
  if (!(parsed instanceof JsonArrayValue) || parsed.items.length > MAX_IMAGE_SELECTION_COUNT) {
    return [];
  }
  const result: Array<LocalDraftImageReference> = [];
  for (let index = 0; index < parsed.items.length; index += 1) {
    const reference = parseReference(parsed.items[index]);
    if (reference !== undefined) {
      result.push(reference);
    }
  }
  try {
    validateReferences(result);
    return result;
  } catch (_error) {
    return [];
  }
}

export function cloneLocalDraftImageReferences(references: Array<LocalDraftImageReference>): Array<LocalDraftImageReference> {
  const result: Array<LocalDraftImageReference> = [];
  for (let index = 0; index < references.length; index += 1) {
    result.push(cloneReference(references[index]));
  }
  return result;
}

function parseReference(value: JsonValue): LocalDraftImageReference | undefined {
  if (!(value instanceof JsonObjectValue)) {
    return undefined;
  }
  const fileName = value.get('fileName');
  const mimeType = value.get('mimeType');
  const byteLength = value.get('byteLength');
  const width = value.get('width');
  const height = value.get('height');
  const animated = value.get('animated');
  const createdAtMillis = value.get('createdAtMillis');
  if (!(fileName instanceof JsonStringValue) || !(mimeType instanceof JsonStringValue) ||
    !(byteLength instanceof JsonNumberValue) || !(width instanceof JsonNumberValue) ||
    !(height instanceof JsonNumberValue) || !(animated instanceof JsonBooleanValue) ||
    !(createdAtMillis instanceof JsonNumberValue)) {
    return undefined;
  }
  const reference: LocalDraftImageReference = {
    fileName: fileName.value,
    mimeType: mimeType.value,
    byteLength: byteLength.value,
    width: width.value,
    height: height.value,
    animated: animated.value,
    createdAtMillis: createdAtMillis.value
  };
  try {
    validateReferences([reference]);
    return reference;
  } catch (_error) {
    return undefined;
  }
}

function validateReferences(references: Array<LocalDraftImageReference>): void {
  if (references.length > MAX_IMAGE_SELECTION_COUNT) {
    throw new Error('Too many local draft images');
  }
  let totalBytes = 0;
  const names: Set<string> = new Set<string>();
  for (let index = 0; index < references.length; index += 1) {
    const reference = references[index];
    if (!isSafeReference(reference) || names.has(reference.fileName)) {
      throw new Error('Local draft image reference is invalid');
    }
    names.add(reference.fileName);
    totalBytes += reference.byteLength;
    if (totalBytes > MAX_IMAGE_BATCH_BYTES) {
      throw new Error('Local draft image batch is too large');
    }
  }
}

function isSafeReference(reference: LocalDraftImageReference): boolean {
  return CONTROLLED_FILE_NAME.test(reference.fileName) && isAllowedMimeForFile(reference.fileName, reference.mimeType) &&
    isSafeByteLength(reference.byteLength) && Number.isSafeInteger(reference.width) && reference.width > 0 &&
    Number.isSafeInteger(reference.height) && reference.height > 0 &&
    Number.isSafeInteger(reference.createdAtMillis) && reference.createdAtMillis >= 0;
}

function isSafeByteLength(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0 && value <= MAX_IMAGE_SINGLE_BYTES;
}

function isMatchingDescriptor(fileName: string, mimeType: string, descriptor: ImageBinaryDescriptor): boolean {
  return isAllowedMimeForFile(fileName, mimeType) && descriptor.mimeType === mimeType &&
    Number.isSafeInteger(descriptor.width) && descriptor.width > 0 && Number.isSafeInteger(descriptor.height) &&
    descriptor.height > 0 && extensionForMime(mimeType) === extensionForFileName(fileName);
}

function controlledFileName(path: string): string {
  if (typeof path !== 'string' || path.includes('..') || /[\r\n\t]/.test(path)) {
    throw new Error('Local draft image path is invalid');
  }
  const normalized = path.replace(/\\/g, '/');
  const match = CONTROLLED_FILE_PATH.exec(normalized);
  if (match === null || match[1] === undefined) {
    throw new Error('Local draft image path is invalid');
  }
  return match[1];
}

function isAllowedMimeForFile(fileName: string, mimeType: string): boolean {
  return extensionForFileName(fileName) === extensionForMime(mimeType);
}

function extensionForFileName(fileName: string): string {
  if (fileName.endsWith('.jpg')) return 'jpg';
  if (fileName.endsWith('.png')) return 'png';
  if (fileName.endsWith('.webp')) return 'webp';
  return fileName.endsWith('.gif') ? 'gif' : '';
}

function extensionForMime(mimeType: string): string {
  if (mimeType === 'image/jpeg') return 'jpg';
  if (mimeType === 'image/png') return 'png';
  if (mimeType === 'image/webp') return 'webp';
  return mimeType === 'image/gif' ? 'gif' : '';
}

function cloneReference(reference: LocalDraftImageReference): LocalDraftImageReference {
  return {
    fileName: reference.fileName,
    mimeType: reference.mimeType,
    byteLength: reference.byteLength,
    width: reference.width,
    height: reference.height,
    animated: reference.animated,
    createdAtMillis: reference.createdAtMillis
  };
}
