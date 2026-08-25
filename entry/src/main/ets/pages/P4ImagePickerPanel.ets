import { fileUri } from '@kit.CoreFileKit';
import { ImageUploadFailureKind } from 'data';
import {
  MediaPickerCoordinator,
  MediaPickerPhase,
  MediaPickerViewState,
  PreparedPickedImage
} from '../platform/MediaPickerCoordinator';
import {
  createProductionMediaPickerCoordinator,
  purgeExpiredControlledImageCache
} from '../platform/SystemPickedImageFileStore';

export type P4ImagePickerSelectionCallback = (images: Array<PreparedPickedImage>) => void;

/**
 * P4 创作页可复用的图片选择面板。它只展示应用 cache 中受控副本，不展示相册 URI、文件路径、原图名或
 * 上传协议状态；网络上传只能由后续的显式发布确认链路接管。
 */
@Component
export struct P4ImagePickerPanel {
  onPreparedImagesChanged: P4ImagePickerSelectionCallback = (_images: Array<PreparedPickedImage>): void => {};
  /**
   * 编辑器在 DraftRepository 确认保存受控引用后设为 true，所有权随之移交给草稿；
   * 面板离开时不得删除仍可恢复的缓存副本。未保存的选择仍按原逻辑立即清理。
   */
  retainPreparedImages: boolean = false;
  @State private viewState: MediaPickerViewState = initialPickerViewState();
  private coordinator: MediaPickerCoordinator | undefined = undefined;

  aboutToAppear(): void {
    if (this.coordinator !== undefined) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.viewState = failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT);
      return;
    }
    try {
      this.coordinator = createProductionMediaPickerCoordinator(context.cacheDir);
      this.sync(this.coordinator.snapshot());
      // 仅回收 24 小时前的应用缓存；失败不影响用户本次显式选择。
      void purgeExpiredControlledImageCache(context.cacheDir);
    } catch (_error) {
      this.viewState = failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT);
    }
  }

  aboutToDisappear(): void {
    const coordinator = this.coordinator;
    this.coordinator = undefined;
    if (coordinator !== undefined && !this.retainPreparedImages) {
      void coordinator.release();
    }
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('图片')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button('从相册选择')
          .id('p4_image_picker_select')
          .enabled(this.canSelect())
          .onClick((): void => this.pickExplicitly())
        if (this.viewState.images.length > 0) {
          Button('清空')
            .id('p4_image_picker_clear')
            .enabled(this.canClear())
            .onClick((): void => this.clear())
        }
      }
      .width('100%')

      Text(this.statusMessage())
        .id('p4_image_picker_status')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor(this.viewState.phase === MediaPickerPhase.FAILED ? $r('app.color.error_text') :
          $r('app.color.secondary_text'))
        .width('100%')

      if (this.viewState.images.length > 0) {
        ForEach(this.viewState.images, (item: PreparedPickedImage, index: number) => {
          this.previewItem(item, index);
        }, (item: PreparedPickedImage): string => item.lifecycle.file.path)
      }

      Text('所选图片仅复制到应用缓存；本组件不上传、不读取会话，也不会发送网络请求。')
        .id('p4_image_picker_upload_gate')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .id('p4_image_picker_panel')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private previewItem(item: PreparedPickedImage, index: number) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Image(controlledPreviewUri(item.lifecycle.file.path))
        .id(`p4_image_picker_preview_${index}`)
        .width(72)
        .height(72)
        .objectFit(ImageFit.Cover)
        .borderRadius($r('app.float.p1_card_radius'))
        .onError((): void => {
          // 缓存副本被系统回收时，立即经协调器删除所有受控副本；不显示内部路径或平台错误。
          this.discardUnavailablePreview();
        })
      Text(previewDescription(item))
        .id(`p4_image_picker_metadata_${index}`)
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Button('移除')
        .id(`p4_image_picker_remove_${index}`)
        .enabled(this.canClear())
        .onClick((): void => this.remove(index))
    }
    .width('100%')
  }

  private canSelect(): boolean {
    return this.coordinator !== undefined && this.viewState.phase !== MediaPickerPhase.PICKING &&
      this.viewState.phase !== MediaPickerPhase.PROCESSING && this.viewState.phase !== MediaPickerPhase.RELEASED;
  }

  private canClear(): boolean {
    return this.coordinator !== undefined && this.viewState.phase === MediaPickerPhase.READY;
  }

  private pickExplicitly(): void {
    const coordinator = this.coordinator;
    if (coordinator === undefined || !this.canSelect()) {
      return;
    }
    this.viewState = {
      phase: MediaPickerPhase.PICKING,
      generation: this.viewState.generation + 1,
      images: []
    };
    void coordinator.pickExplicitly().then((state: MediaPickerViewState): void => {
      this.sync(state);
    }, (): void => {
      this.sync(failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT));
    });
  }

  private remove(index: number): void {
    const coordinator = this.coordinator;
    if (coordinator === undefined || !this.canClear()) {
      return;
    }
    void coordinator.removePreparedImage(index).then((state: MediaPickerViewState): void => {
      this.sync(state);
    }, (): void => {
      this.sync(failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT));
    });
  }

  private clear(): void {
    const coordinator = this.coordinator;
    if (coordinator === undefined || !this.canClear()) {
      return;
    }
    void coordinator.cancel().then((state: MediaPickerViewState): void => {
      this.sync(state);
    }, (): void => {
      this.sync(failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT));
    });
  }

  private discardUnavailablePreview(): void {
    const coordinator = this.coordinator;
    if (coordinator === undefined) {
      this.sync(failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT));
      return;
    }
    void coordinator.cancel().then((): void => {
      this.sync(failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT));
    }, (): void => {
      this.sync(failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT));
    });
  }

  private sync(state: MediaPickerViewState): void {
    this.viewState = state;
    this.onPreparedImagesChanged(state.images);
  }

  private statusMessage(): string {
    if (this.viewState.phase === MediaPickerPhase.PICKING) return '正在打开系统相册…';
    if (this.viewState.phase === MediaPickerPhase.PROCESSING) return '正在检查图片格式、尺寸和大小…';
    if (this.viewState.phase === MediaPickerPhase.READY) return `已安全准备 ${this.viewState.images.length} 张图片`;
    if (this.viewState.phase === MediaPickerPhase.CANCELLED) return '已取消选择，未上传图片';
    if (this.viewState.phase === MediaPickerPhase.RELEASED) return '已清理图片缓存';
    if (this.viewState.phase === MediaPickerPhase.FAILED) return failureMessage(this.viewState.failureKind);
    return '可从系统相册选择最多 9 张图片';
  }
}

function initialPickerViewState(): MediaPickerViewState {
  return { phase: MediaPickerPhase.IDLE, generation: 0, images: [] };
}

function failedPickerViewState(kind: ImageUploadFailureKind): MediaPickerViewState {
  return { phase: MediaPickerPhase.FAILED, generation: 0, images: [], failureKind: kind };
}

function controlledPreviewUri(path: string): string {
  try {
    return fileUri.getUriFromPath(path);
  } catch (_error) {
    return '';
  }
}

function previewDescription(item: PreparedPickedImage): string {
  const width = item.image.descriptor.width;
  const height = item.image.descriptor.height;
  return `${formatName(item.image.descriptor.extension)} · ${formatBytes(item.image.byteLength)} · ${width} × ${height}`;
}

function formatName(extension: string): string {
  if (extension === 'jpg') return 'JPEG';
  if (extension === 'png') return 'PNG';
  if (extension === 'webp') return 'WebP';
  return 'GIF';
}

function formatBytes(byteLength: number): string {
  if (byteLength < 1024 * 1024) return `${Math.max(1, Math.ceil(byteLength / 1024))} KB`;
  return `${(byteLength / (1024 * 1024)).toFixed(1)} MB`;
}

function failureMessage(kind: ImageUploadFailureKind | undefined): string {
  if (kind === ImageUploadFailureKind.UNSUPPORTED_FORMAT) return '无法识别图片格式，请重新选择';
  if (kind === ImageUploadFailureKind.LIMIT_EXCEEDED) return '图片数量、尺寸或大小超出限制';
  if (kind === ImageUploadFailureKind.CANCELLED) return '已取消选择，未上传图片';
  return '无法安全读取所选图片，请重新选择';
}
