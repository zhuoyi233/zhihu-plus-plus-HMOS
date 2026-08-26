import {
  createImageTemporaryLifecycle,
  defaultImageSelectionLimits,
  ImageSelectionLimits,
  ImageTemporaryFile,
  ImageTemporaryLifecycle,
  ImageTemporaryState,
  ImageUploadFailure,
  ImageUploadFailureKind,
  PickedImageInspection,
  ValidatedPickedImage,
  transitionImageTemporaryLifecycle,
  validatePickedImageBatch
} from 'data';
import { PickedImage } from './P4PlatformServices';

/**
 * P4-2 系统选图的窄平台边界。生产实现只能在用户明确点击选图后调用此接口；
 * 这里不绑定未审计的 API 24 Photo Picker Kit，便于先以 fake 完成选择/处理门禁验证。
 */
export interface SystemPhotoPickerGateway {
  pickImages(maxCount: number): Promise<PhotoPickerResult>;
}

export interface PhotoPickerSelection {
  readonly image: PickedImage;
}

export enum PhotoPickerResultKind {
  SELECTED = 'selected',
  CANCELLED = 'cancelled'
}

export interface PhotoPickerSelectedResult {
  readonly kind: PhotoPickerResultKind.SELECTED;
  readonly selections: Array<PhotoPickerSelection>;
}

export interface PhotoPickerCancelledResult {
  readonly kind: PhotoPickerResultKind.CANCELLED;
}

export type PhotoPickerResult = PhotoPickerSelectedResult | PhotoPickerCancelledResult;

/** 只读取有限头部和文件长度；不把系统 URI 或图片字节泄漏给草稿和上传层。 */
export interface PickedImageInspector {
  inspect(selection: PhotoPickerSelection): Promise<PickedImageInspection>;
}

/**
 * 受控缓存写入器。实现必须生成 cacheDir/p4-images 下的随机文件名，不能接受 URI 作为路径。
 * 此接口不负责网络上传，也不得保存原图到 RDB、Preferences 或日志。
 */
export interface PickedImageTemporaryStore {
  write(selection: PhotoPickerSelection, image: ValidatedPickedImage, nowMillis: number): Promise<ImageTemporaryFile>;
  remove(file: ImageTemporaryFile): Promise<void>;
}

export interface MediaPickerRuntimePolicy {
  readonly cacheDir: string;
  readonly nowMillis: number;
  readonly limits: ImageSelectionLimits;
}

export enum MediaPickerPhase {
  IDLE = 'idle',
  PICKING = 'picking',
  PROCESSING = 'processing',
  READY = 'ready',
  CANCELLED = 'cancelled',
  FAILED = 'failed',
  RELEASED = 'released'
}

export interface PreparedPickedImage {
  readonly image: ValidatedPickedImage;
  readonly lifecycle: ImageTemporaryLifecycle;
}

export interface MediaPickerViewState {
  readonly phase: MediaPickerPhase;
  readonly generation: number;
  readonly images: Array<PreparedPickedImage>;
  readonly failureKind?: ImageUploadFailureKind;
}

/**
 * 选择、magic/限额门禁和受控缓存之间的协调器。
 * 不读取 Cookie、不发网络请求；取消、迟到结果和失败均不保留用户 URI 或临时文件引用。
 */
export class MediaPickerCoordinator {
  private readonly picker: SystemPhotoPickerGateway;
  private readonly inspector: PickedImageInspector;
  private readonly temporaryStore: PickedImageTemporaryStore;
  private readonly runtime: MediaPickerRuntimePolicy;
  private state: MediaPickerViewState = emptyMediaPickerState();

  constructor(
    picker: SystemPhotoPickerGateway,
    inspector: PickedImageInspector,
    temporaryStore: PickedImageTemporaryStore,
    runtime: MediaPickerRuntimePolicy
  ) {
    this.picker = picker;
    this.inspector = inspector;
    this.temporaryStore = temporaryStore;
    this.runtime = runtime;
  }

  snapshot(): MediaPickerViewState {
    return copyMediaPickerState(this.state);
  }

  /**
   * 草稿恢复只接受平台层从受控缓存名重建的 READY 生命周期；系统相册 URI 不会参与恢复。
   * 恢复后的图片归同一个协调器管理，移除/清空仍只会删除应用缓存中的随机文件。
   */
  restorePreparedImages(images: Array<PreparedPickedImage>): MediaPickerViewState {
    if (this.state.phase === MediaPickerPhase.PICKING || this.state.phase === MediaPickerPhase.PROCESSING ||
      this.state.phase === MediaPickerPhase.RELEASED) {
      return this.snapshot();
    }
    try {
      const restored: Array<PreparedPickedImage> = [];
      for (let index = 0; index < images.length; index += 1) {
        const selected = createImageTemporaryLifecycle(images[index].lifecycle.file, this.runtime.cacheDir);
        const processing = transitionImageTemporaryLifecycle(selected, ImageTemporaryState.PROCESSING);
        const ready = transitionImageTemporaryLifecycle(processing, ImageTemporaryState.READY);
        if (images[index].lifecycle.state !== ImageTemporaryState.READY ||
          images[index].image.byteLength !== ready.file.byteLength ||
          images[index].image.descriptor.mimeType !== ready.file.mimeType) {
          throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
        }
        restored.push({ image: images[index].image, lifecycle: ready });
      }
      this.state = stateOf(restored.length === 0 ? MediaPickerPhase.IDLE : MediaPickerPhase.READY,
        this.state.generation + 1, restored);
    } catch (_error) {
      this.state = stateOf(MediaPickerPhase.FAILED, this.state.generation + 1, [], ImageUploadFailureKind.INVALID_INPUT);
    }
    return this.snapshot();
  }

  async pickExplicitly(): Promise<MediaPickerViewState> {
    const previous = this.state.images;
    const remainingCount = this.runtime.limits.maxCount - previous.length;
    if (remainingCount <= 0) {
      return this.snapshot();
    }
    const generation = this.state.generation + 1;
    this.state = stateOf(MediaPickerPhase.PICKING, generation, []);

    let result: PhotoPickerResult;
    try {
      result = await this.picker.pickImages(remainingCount);
    } catch (_error) {
      // 正常取消必须由 gateway 返回明确结果；异常一律按可重试失败处理，且不暴露系统原文。
      return this.failIfCurrent(generation, ImageUploadFailureKind.INVALID_INPUT, previous);
    }
    if (!this.isCurrent(generation)) {
      return this.snapshot();
    }
    if (result.kind === PhotoPickerResultKind.CANCELLED || result.selections.length === 0) {
      this.state = stateOf(previous.length === 0 ? MediaPickerPhase.CANCELLED : MediaPickerPhase.READY, generation, previous);
      return this.snapshot();
    }

    this.state = stateOf(MediaPickerPhase.PROCESSING, generation, []);
    try {
      const inspected = await this.inspectAll(result.selections);
      if (!this.isCurrent(generation)) {
        return this.snapshot();
      }
      validateInspectionOrigins(result.selections, inspected);
      const validated = validatePickedImageBatch(inspected, this.runtime.limits);
      validateCombinedBatchBytes(previous, validated, this.runtime.limits.maxBatchBytes);
      const prepared = await this.persistAll(result.selections, validated, generation);
      if (!this.isCurrent(generation)) {
        await this.removeAll(prepared);
        return this.snapshot();
      }
      this.state = stateOf(MediaPickerPhase.READY, generation, previous.concat(prepared));
      return this.snapshot();
    } catch (error) {
      const failure = error instanceof ImageUploadFailure ? error.kind : ImageUploadFailureKind.INVALID_INPUT;
      return this.failIfCurrent(generation, failure, previous);
    }
  }

  async cancel(): Promise<MediaPickerViewState> {
    const generation = this.state.generation + 1;
    await this.releaseCurrentImages();
    this.state = stateOf(MediaPickerPhase.CANCELLED, generation, []);
    return this.snapshot();
  }

  /**
   * 预览列表只允许移除本协调器创建的受控缓存副本。索引无效、非就绪态和迟到点击均不触碰文件。
   */
  async removePreparedImage(index: number): Promise<MediaPickerViewState> {
    if (this.state.phase !== MediaPickerPhase.READY || !Number.isSafeInteger(index) || index < 0 ||
      index >= this.state.images.length) {
      return this.snapshot();
    }
    const generation = this.state.generation + 1;
    const removed = this.state.images[index];
    const retained: Array<PreparedPickedImage> = [];
    for (let itemIndex = 0; itemIndex < this.state.images.length; itemIndex += 1) {
      if (itemIndex !== index) {
        retained.push(this.state.images[itemIndex]);
      }
    }
    this.state = stateOf(retained.length === 0 ? MediaPickerPhase.IDLE : MediaPickerPhase.READY, generation, retained);
    await this.removeAll([removed]);
    return this.snapshot();
  }

  async release(): Promise<MediaPickerViewState> {
    const generation = this.state.generation + 1;
    await this.releaseCurrentImages();
    this.state = stateOf(MediaPickerPhase.RELEASED, generation, []);
    return this.snapshot();
  }

  private async inspectAll(selections: Array<PhotoPickerSelection>): Promise<Array<PickedImageInspection>> {
    const inspections: Array<PickedImageInspection> = [];
    for (let index = 0; index < selections.length; index += 1) {
      inspections.push(await this.inspector.inspect(selections[index]));
    }
    return inspections;
  }

  private async persistAll(
    selections: Array<PhotoPickerSelection>,
    validated: Array<ValidatedPickedImage>,
    generation: number
  ): Promise<Array<PreparedPickedImage>> {
    if (selections.length !== validated.length) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
    const result: Array<PreparedPickedImage> = [];
    try {
      for (let index = 0; index < selections.length; index += 1) {
        if (!this.isCurrent(generation)) {
          break;
        }
        const file = await this.temporaryStore.write(selections[index], validated[index], this.runtime.nowMillis);
        if (file.mimeType !== validated[index].descriptor.mimeType || file.byteLength !== validated[index].byteLength) {
          await this.temporaryStore.remove(file);
          throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
        }
        const selected = createImageTemporaryLifecycle(file, this.runtime.cacheDir);
        const processing = transitionImageTemporaryLifecycle(selected, ImageTemporaryState.PROCESSING);
        const ready = transitionImageTemporaryLifecycle(processing, ImageTemporaryState.READY);
        result.push({ image: validated[index], lifecycle: ready });
      }
      if (result.length !== selections.length) {
        await this.removeAll(result);
      }
      return result;
    } catch (error) {
      await this.removeAll(result);
      if (error instanceof ImageUploadFailure) {
        throw error;
      }
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }

  private async releaseCurrentImages(): Promise<void> {
    const current = this.state.images;
    this.state = stateOf(this.state.phase, this.state.generation, []);
    await this.removeAll(current);
  }

  private async removeAll(images: Array<PreparedPickedImage>): Promise<void> {
    for (let index = 0; index < images.length; index += 1) {
      try {
        await this.temporaryStore.remove(images[index].lifecycle.file);
      } catch (_error) {
        // 清理失败不能重新暴露已取消选择的用户 URI；过期扫描会再次处理该受控路径。
      }
    }
  }

  private failIfCurrent(generation: number, failureKind: ImageUploadFailureKind,
    retained: Array<PreparedPickedImage> = []): MediaPickerViewState {
    if (this.isCurrent(generation)) {
      this.state = stateOf(retained.length === 0 ? MediaPickerPhase.FAILED : MediaPickerPhase.READY,
        generation, retained, retained.length === 0 ? failureKind : undefined);
    }
    return this.snapshot();
  }

  private isCurrent(generation: number): boolean {
    return this.state.generation === generation;
  }
}

export function defaultMediaPickerRuntimePolicy(cacheDir: string, nowMillis: number): MediaPickerRuntimePolicy {
  const policy: MediaPickerRuntimePolicy = {
    cacheDir: cacheDir,
    nowMillis: nowMillis,
    limits: defaultImageSelectionLimits()
  };
  return policy;
}

function emptyMediaPickerState(): MediaPickerViewState {
  return stateOf(MediaPickerPhase.IDLE, 0, []);
}

function stateOf(
  phase: MediaPickerPhase,
  generation: number,
  images: Array<PreparedPickedImage>,
  failureKind?: ImageUploadFailureKind
): MediaPickerViewState {
  const state: MediaPickerViewState = {
    phase: phase,
    generation: generation,
    images: copyPreparedImages(images),
    failureKind: failureKind
  };
  return state;
}

function copyMediaPickerState(state: MediaPickerViewState): MediaPickerViewState {
  return stateOf(state.phase, state.generation, state.images, state.failureKind);
}

function copyPreparedImages(images: Array<PreparedPickedImage>): Array<PreparedPickedImage> {
  return images.map((item: PreparedPickedImage): PreparedPickedImage => {
    const copy: PreparedPickedImage = {
      image: item.image,
      lifecycle: item.lifecycle
    };
    return copy;
  });
}

function validateInspectionOrigins(
  selections: Array<PhotoPickerSelection>,
  inspections: Array<PickedImageInspection>
): void {
  if (selections.length !== inspections.length) {
    throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
  }
  for (let index = 0; index < selections.length; index += 1) {
    if (selections[index].image.uri !== inspections[index].sourceUri) {
      throw new ImageUploadFailure(ImageUploadFailureKind.INVALID_INPUT);
    }
  }
}

function validateCombinedBatchBytes(existing: Array<PreparedPickedImage>,
  selected: Array<ValidatedPickedImage>, maxBatchBytes: number): void {
  let totalBytes = 0;
  for (let index = 0; index < existing.length; index += 1) {
    totalBytes += existing[index].image.byteLength;
  }
  for (let index = 0; index < selected.length; index += 1) {
    totalBytes += selected[index].byteLength;
  }
  if (!Number.isSafeInteger(totalBytes) || totalBytes > maxBatchBytes) {
    throw new ImageUploadFailure(ImageUploadFailureKind.LIMIT_EXCEEDED);
  }
}
