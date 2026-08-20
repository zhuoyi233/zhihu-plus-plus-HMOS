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

  async pickExplicitly(): Promise<MediaPickerViewState> {
    const previous = this.state.images;
    const generation = this.state.generation + 1;
    this.state = stateOf(MediaPickerPhase.PICKING, generation, []);
    await this.removeAll(previous);
    if (!this.isCurrent(generation)) {
      return this.snapshot();
    }

    let result: PhotoPickerResult;
    try {
      result = await this.picker.pickImages(this.runtime.limits.maxCount);
    } catch (_error) {
      // 正常取消必须由 gateway 返回明确结果；异常一律按可重试失败处理，且不暴露系统原文。
      return this.failIfCurrent(generation, ImageUploadFailureKind.INVALID_INPUT);
    }
    if (!this.isCurrent(generation)) {
      return this.snapshot();
    }
    if (result.kind === PhotoPickerResultKind.CANCELLED || result.selections.length === 0) {
      this.state = stateOf(MediaPickerPhase.CANCELLED, generation, []);
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
      const prepared = await this.persistAll(result.selections, validated, generation);
      if (!this.isCurrent(generation)) {
        await this.removeAll(prepared);
        return this.snapshot();
      }
      this.state = stateOf(MediaPickerPhase.READY, generation, prepared);
      return this.snapshot();
    } catch (error) {
      const failure = error instanceof ImageUploadFailure ? error.kind : ImageUploadFailureKind.INVALID_INPUT;
      return this.failIfCurrent(generation, failure);
    }
  }

  async cancel(): Promise<MediaPickerViewState> {
    const generation = this.state.generation + 1;
    await this.releaseCurrentImages();
    this.state = stateOf(MediaPickerPhase.CANCELLED, generation, []);
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

  private failIfCurrent(generation: number, failureKind: ImageUploadFailureKind): MediaPickerViewState {
    if (this.isCurrent(generation)) {
      this.state = stateOf(MediaPickerPhase.FAILED, generation, [], failureKind);
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
