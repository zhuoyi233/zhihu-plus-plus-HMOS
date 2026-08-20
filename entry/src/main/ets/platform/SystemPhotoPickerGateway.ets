import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { PickedImage } from './P4PlatformServices';
import {
  PhotoPickerResult,
  PhotoPickerResultKind,
  PhotoPickerSelection,
  SystemPhotoPickerGateway
} from './MediaPickerCoordinator';

const MIN_PICK_COUNT: number = 1;
const MAX_PICK_COUNT: number = 500;

/**
 * 可替换的系统选择器调用面。测试仅替换此接口，页面不需要了解系统 Kit 的结果类型。
 */
export interface SystemPhotoPickerClient {
  selectImages(maxCount: number): Promise<Array<string>>;
}

/**
 * API 24 可证明可用的 Photo Picker 接入：仅请求图片 MIME 和上限数量。
 * URI 不作为路径、名称或 MIME 信任来源；后续只能由受控 inspector 流式读取并复核。
 */
export class HarmonyPhotoPickerClient implements SystemPhotoPickerClient {
  private readonly picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();

  async selectImages(maxCount: number): Promise<Array<string>> {
    const options: photoAccessHelper.PhotoSelectOptions = {
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: maxCount
    };
    const result = await this.picker.select(options);
    return copyUris(result.photoUris);
  }
}

/** 将系统选择器结果收缩为 P4-2 协调器允许处理的最小输入。 */
export class HarmonySystemPhotoPickerGateway implements SystemPhotoPickerGateway {
  private readonly client: SystemPhotoPickerClient;

  constructor(client: SystemPhotoPickerClient) {
    this.client = client;
  }

  async pickImages(maxCount: number): Promise<PhotoPickerResult> {
    if (!isAllowedPickCount(maxCount)) {
      return cancelledResult();
    }
    try {
      const uris = await this.client.selectImages(maxCount);
      return toPhotoPickerResult(uris, maxCount);
    } catch (_error) {
      // 用户取消、拒绝和系统失败均不能把原始平台错误或 URI 外泄给页面。
      return cancelledResult();
    }
  }
}

export function createSystemPhotoPickerGateway(): SystemPhotoPickerGateway {
  return new HarmonySystemPhotoPickerGateway(new HarmonyPhotoPickerClient());
}

/** 纯转换，供 Hypium 覆盖平台返回的异常边界而不打开系统选择器。 */
export function toPhotoPickerResult(uris: Array<string>, maxCount: number): PhotoPickerResult {
  if (!isAllowedPickCount(maxCount)) {
    return cancelledResult();
  }
  const selections: Array<PhotoPickerSelection> = [];
  const acceptedUris: Map<string, boolean> = new Map<string, boolean>();
  for (let index = 0; index < uris.length && selections.length < maxCount; index += 1) {
    const uri = uris[index];
    if (uri.trim().length === 0 || acceptedUris.has(uri)) {
      continue;
    }
    acceptedUris.set(uri, true);
    const image: PickedImage = { uri: uri };
    const selection: PhotoPickerSelection = { image: image };
    selections.push(selection);
  }
  if (selections.length === 0) {
    return cancelledResult();
  }
  const result: PhotoPickerResult = {
    kind: PhotoPickerResultKind.SELECTED,
    selections: selections
  };
  return result;
}

function isAllowedPickCount(maxCount: number): boolean {
  return Number.isInteger(maxCount) && maxCount >= MIN_PICK_COUNT && maxCount <= MAX_PICK_COUNT;
}

function cancelledResult(): PhotoPickerResult {
  const result: PhotoPickerResult = { kind: PhotoPickerResultKind.CANCELLED };
  return result;
}

function copyUris(uris: Array<string>): Array<string> {
  const result: Array<string> = [];
  for (let index = 0; index < uris.length; index += 1) {
    result.push(uris[index]);
  }
  return result;
}
