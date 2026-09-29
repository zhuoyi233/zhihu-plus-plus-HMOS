import { fileUri } from '@kit.CoreFileKit';
import { DEFAULT_THEME_COLOR, ImageUploadFailureKind, LocalDraftImageReference, onThemeColor } from 'data';
import {
  MediaPickerCoordinator,
  MediaPickerPhase,
  MediaPickerViewState,
  PreparedPickedImage
} from '../platform/MediaPickerCoordinator';
import {
  createProductionMediaPickerCoordinator,
  RestoredControlledImages,
  restoreControlledPickedImages
} from '../platform/SystemPickedImageFileStore';

export type ImagePickerSelectionCallback = (images: Array<PreparedPickedImage>) => void;

/**
 * P4 创作页可复用的图片选择面板。它只展示应用 cache 中受控副本，不展示相册 URI、文件路径、原图名或
 * 上传协议状态；网络上传只能由后续的显式发布确认链路接管。
 */
@Component
export struct ImagePickerPanel {
  /** 当前生效主题色（AppShell 广播），驱动面板按钮强调色。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  onPreparedImagesChanged: ImagePickerSelectionCallback = (_images: Array<PreparedPickedImage>): void => {};
  /** 编辑器持有本地图片引用时保留受控副本，供草稿重新打开；状态需随父页面更新。 */
  @Prop retainPreparedImages: boolean = false;
  /** 已保存草稿的受控缓存引用；只用于恢复本地预览和移除操作，不包含系统相册 URI。 */
  @Prop @Watch('onRestoredReferencesChanged') restoredLocalImageReferences: Array<LocalDraftImageReference> = [];
  @State private viewState: MediaPickerViewState = initialPickerViewState();
  @State private unavailableImageCount: number = 0;
  private coordinator: MediaPickerCoordinator | undefined = undefined;
  private cacheDir: string = '';
  private restoreGeneration: number = 0;
  private lastRestoredReferencesKey: string = '';

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
    } catch (_error) {
      this.viewState = failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT);
      return;
    }
    this.cacheDir = context.cacheDir;
    // 恢复为异步解析：校验受控缓存文件的尺寸与 magic bytes，完成后再挂载预览；
    // 24 小时缓存回收已移交启动维护（带草稿引用保护），面板内不再做无保护清理。
    void this.restorePersistedImages();
  }

  /**
   * 草稿恢复是异步流程：页面先进入 READY 挂载面板，引用在草稿元数据加载完成后才到达。
   * 引用变化（含初次到达）都必须重新触发解析，否则恢复永远拿到空引用、草稿图片无法找回。
   */
  onRestoredReferencesChanged(): void {
    if (this.coordinator === undefined) {
      return;
    }
    if (this.lastRestoredReferencesKey === this.restoredReferencesKey()) {
      return;
    }
    void this.restorePersistedImages();
  }

  private restoredReferencesKey(): string {
    let key = '';
    for (let index = 0; index < this.restoredLocalImageReferences.length; index += 1) {
      key += (index > 0 ? ',' : '') + this.restoredLocalImageReferences[index].fileName;
    }
    return key;
  }

  private restorePersistedImages(): void {
    const coordinator = this.coordinator;
    if (coordinator === undefined) {
      return;
    }
    this.restoreGeneration += 1;
    const generation = this.restoreGeneration;
    restoreControlledPickedImages(this.cacheDir, this.restoredLocalImageReferences)
      .then((restored: RestoredControlledImages): void => {
        if (this.coordinator !== coordinator || generation !== this.restoreGeneration) {
          return;
        }
        this.lastRestoredReferencesKey = this.restoredReferencesKey();
        this.unavailableImageCount = restored.unavailableCount;
        this.viewState = coordinator.restorePreparedImages(restored.images);
      })
      .catch((_error: Error): void => {
        if (this.coordinator === coordinator && generation === this.restoreGeneration) {
          this.viewState = failedPickerViewState(ImageUploadFailureKind.INVALID_INPUT);
        }
      });
  }

  aboutToDisappear(): void {
    const coordinator = this.coordinator;
    this.coordinator = undefined;
    if (coordinator !== undefined && !this.retainPreparedImages) {
      void coordinator.release();
    }
  }

  build() {
    Column({ space: $r('app.float.spacing_small') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('图片')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button('从相册选择')
          .id('image_picker_select')
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .backgroundColor(this.resolvedThemeColor)
          .enabled(this.canSelect())
          .onClick((): void => this.pickExplicitly())
        if (this.viewState.images.length > 0) {
          Button('清空')
            .backgroundColor($r('app.color.control_background'))
            .fontColor($r('app.color.primary_text'))
            .id('image_picker_clear')
            .enabled(this.canClear())
            .onClick((): void => this.clear())
        }
      }
      .width('100%')

      Text(this.statusMessage())
        .id('image_picker_status')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor(this.viewState.phase === MediaPickerPhase.FAILED ? $r('app.color.error_text') :
          $r('app.color.secondary_text'))
        .width('100%')

      if (this.unavailableImageCount > 0) {
        Text(`有 ${this.unavailableImageCount} 张本地图片已不可用，草稿正文已保留。`)
          .id('image_picker_unavailable_hint')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.error_text'))
          .width('100%')
      }

      if (this.viewState.images.length > 0) {
        ForEach(this.viewState.images, (item: PreparedPickedImage, index: number) => {
          this.previewItem(item, index);
        }, (item: PreparedPickedImage): string => item.lifecycle.file.path)
      }

      Text('所选图片仅复制到应用缓存；本组件不上传、不读取会话，也不会发送网络请求。')
        .id('image_picker_upload_gate')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
    }
    .id('image_picker_panel')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private previewItem(item: PreparedPickedImage, index: number) {
    Row({ space: $r('app.float.spacing_small') }) {
      Image(controlledPreviewUri(item.lifecycle.file.path))
        .id(`image_picker_preview_${index}`)
        .width(72)
        .height(72)
        .objectFit(ImageFit.Cover)
        .borderRadius($r('app.float.card_radius'))
        .onError((): void => {
          // 缓存副本被系统回收时，立即经协调器删除所有受控副本；不显示内部路径或平台错误。
          this.discardUnavailablePreview();
        })
      Text(previewDescription(item))
        .id(`image_picker_metadata_${index}`)
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Button('移除')
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .id(`image_picker_remove_${index}`)
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
