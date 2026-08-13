import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl, Want } from '@kit.AbilityKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import {
  clearFormulaByteCache,
  loadFormulaPixelMap,
  parseZhihuHtml,
  ReaderBlock,
  ReaderBlockDataSource,
  ReaderBlockKind,
  ReaderImageBlock,
  ReaderInlineKind,
  ReaderInlineRun
} from 'reader';

function inlineFormulaWidth(tex: string): number {
  return Math.min(220, Math.max(20, tex.length * 9));
}

function clampPreviewScale(value: number): number {
  return Math.min(4, Math.max(1, value));
}

function isTrustedPreviewImageUrl(value: string): boolean {
  return /^https:\/\/(?:picx?|pic[0-9]+)\.zhimg\.com\//i.test(value);
}

function previewImageExtension(value: string): string {
  const match = value.match(/\.([a-z0-9]{2,5})(?:[?#]|$)/i);
  if (match === null || match[1] === undefined) {
    return 'jpg';
  }
  const extension = match[1].toLowerCase();
  return extension === 'jpeg' || extension === 'png' || extension === 'gif' || extension === 'webp'
    ? extension
    : 'jpg';
}

@Component
struct ContentImagePreview {
  url: string = '';
  onClose: () => void = () => {};
  @State private previewScale: number = 1;
  @State private actionStatus: string = '';
  private saveInFlight: boolean = false;
  private pinchStartScale: number = 1;

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(this.url)
        .id('p2_content_image_preview')
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .scale({ x: this.previewScale, y: this.previewScale, z: 1 })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart((): void => {
              this.pinchStartScale = this.previewScale;
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.previewScale = clampPreviewScale(this.pinchStartScale * event.scale);
            })
        )
        .parallelGesture(
          TapGesture({ count: 2 })
            .onAction((): void => {
              this.previewScale = 1;
              this.actionStatus = '已恢复原始大小';
            })
        )
        .parallelGesture(
          LongPressGesture({ duration: 600 })
            .onAction((): void => {
              this.saveImage();
            })
        )

      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Button('保存')
            .id('p2_content_image_preview_save')
            .onClick((): void => {
              this.saveImage();
            })
          Button('分享')
            .id('p2_content_image_preview_share')
            .onClick((): void => {
              this.shareImage();
            })
          Button('关闭')
            .id('p2_content_image_preview_close')
            .onClick((): void => {
              this.onClose();
            })
        }
        if (this.actionStatus.length > 0) {
          Text(this.actionStatus)
            .id('p2_content_image_preview_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor(Color.White)
        }
      }
      .margin($r('app.float.p1_page_padding'))
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EE000000')
  }

  private async saveImage(): Promise<void> {
    if (this.saveInFlight || !isTrustedPreviewImageUrl(this.url)) {
      this.actionStatus = '图片来源不受支持';
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.actionStatus = '当前页面无法访问相册';
      return;
    }
    this.saveInFlight = true;
    this.actionStatus = '正在保存…';
    let request: http.HttpRequest | undefined = undefined;
    try {
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context,
        ['ohos.permission.WRITE_IMAGEVIDEO']
      );
      if (permission.permissions.length === 0 || permission.authResults.length === 0 ||
        permission.authResults[0] !== 0) {
        this.actionStatus = '未获得相册写入权限';
        return;
      }
      request = http.createHttp();
      const response = await request.request(this.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false,
        maxLimit: 8 * 1024 * 1024,
        maxRedirects: 0
      });
      if (Number(response.responseCode) !== 200 || !(response.result instanceof ArrayBuffer) ||
        response.result.byteLength === 0 || response.result.byteLength > 8 * 1024 * 1024) {
        this.actionStatus = '图片下载失败';
        return;
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const changeRequest = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        context,
        photoAccessHelper.PhotoType.IMAGE,
        previewImageExtension(this.url)
      );
      changeRequest.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, response.result);
      await helper.applyChanges(changeRequest);
      this.actionStatus = '已保存到相册';
    } catch {
      this.actionStatus = '保存失败，请稍后重试';
    } finally {
      request?.destroy();
      this.saveInFlight = false;
    }
  }

  private shareImage(): void {
    const context = getAbilityContext();
    if (context === undefined || !isTrustedPreviewImageUrl(this.url)) {
      this.actionStatus = '图片来源不受支持';
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.sendData',
      type: 'text/plain',
      uri: this.url
    };
    context.startAbility(want).then((): void => {
      this.actionStatus = '已打开分享面板';
    }).catch((): void => {
      this.actionStatus = '暂时无法打开分享面板';
    });
  }
}

@Component
struct ContentInlineFormula {
  item: ReaderBlock = {
    id: '',
    kind: ReaderBlockKind.PARAGRAPH,
    text: '',
    sourceUrl: '',
    inlineRuns: []
  };
  @State private loadedRunIds: Array<string> = [];
  private pixelMaps: Map<string, image.PixelMap> = new Map();
  private active: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.active = true;
    const generation = ++this.loadGeneration;
    this.item.inlineRuns.forEach((run: ReaderInlineRun): void => {
      if (run.kind === ReaderInlineKind.FORMULA) {
        this.loadFormula(run, generation);
      }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadGeneration += 1;
    this.loadedRunIds = [];
    this.pixelMaps.forEach((pixelMap: image.PixelMap): void => {
      pixelMap.release();
    });
    this.pixelMaps.clear();
  }

  build() {
    Text() {
      if (this.item.kind === ReaderBlockKind.LIST_ITEM) {
        Span('• ')
      }
      ForEach(this.item.inlineRuns, (run: ReaderInlineRun) => {
        if (run.kind === ReaderInlineKind.TEXT || !this.loadedRunIds.includes(run.id) ||
          this.pixelMaps.get(run.id) === undefined) {
          Span(run.kind === ReaderInlineKind.TEXT ? run.text : `「${run.text}」`)
            .fontColor(run.kind === ReaderInlineKind.TEXT
              ? $r('app.color.primary_text')
              : $r('app.color.secondary_text'))
        } else {
          ImageSpan(this.pixelMaps.get(run.id) ?? run.text)
            .id(`p2_content_inline_formula_${run.id}`)
            .width(inlineFormulaWidth(run.text))
            .height(24)
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .onError((): void => {
              this.failFormula(run.id);
            })
        }
      }, (run: ReaderInlineRun): string => run.id)
    }
    .fontSize($r('app.float.p1_body_font_size'))
    .lineHeight(30)
    .fontColor($r('app.color.primary_text'))
    .width('100%')
  }

  private async loadFormula(run: ReaderInlineRun, generation: number): Promise<void> {
    try {
      const pixelMap = await loadFormulaPixelMap(run.sourceUrl);
      if (!this.active || this.loadGeneration !== generation) {
        await pixelMap.release();
        return;
      }
      const previous = this.pixelMaps.get(run.id);
      if (previous !== undefined) {
        await previous.release();
      }
      this.pixelMaps.set(run.id, pixelMap);
      this.loadedRunIds = this.loadedRunIds.concat(run.id);
    } catch (_error) {
      if (this.active && this.loadGeneration === generation) {
        this.failFormula(run.id);
      }
    }
  }

  private failFormula(id: string): void {
    const pixelMap = this.pixelMaps.get(id);
    this.pixelMaps.delete(id);
    pixelMap?.release();
    this.loadedRunIds = this.loadedRunIds.filter((loadedId: string): boolean => loadedId !== id);
  }
}

@Component
struct ContentBlockFormula {
  item: ReaderBlock = {
    id: '',
    kind: ReaderBlockKind.FORMULA,
    text: '',
    sourceUrl: '',
    inlineRuns: []
  };
  @State private failed: boolean = false;
  @State private pixelMap: image.PixelMap | undefined = undefined;
  private active: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.loadFormula(++this.loadGeneration);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadGeneration += 1;
    this.releasePixelMap();
  }

  build() {
    Column() {
      if (this.pixelMap !== undefined && !this.failed) {
        Image(this.pixelMap)
          .id(`p2_content_formula_${this.item.id}`)
          .width('100%')
          .height(88)
          .objectFit(ImageFit.Contain)
          .onError((): void => {
            this.failed = true;
            this.releasePixelMap();
          })
      } else {
        Text(this.item.text)
          .id(`p2_content_formula_fallback_${this.item.id}`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_small'))
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  private async loadFormula(generation: number): Promise<void> {
    try {
      const pixelMap = await loadFormulaPixelMap(this.item.sourceUrl);
      if (!this.active || this.loadGeneration !== generation) {
        await pixelMap.release();
        return;
      }
      if (this.pixelMap !== undefined) {
        await this.pixelMap.release();
      }
      this.pixelMap = pixelMap;
      this.failed = false;
    } catch (_error) {
      if (this.active && this.loadGeneration === generation) {
        this.failed = true;
      }
    }
  }

  private releasePixelMap(): void {
    this.pixelMap?.release();
    this.pixelMap = undefined;
  }
}

@Component
export struct NativeContentDocument {
  html: string = '';
  emptyMessage: string = '正文为空';
  @State private previewUrl: string = '';
  @State private empty: boolean = true;
  private readonly dataSource: ReaderBlockDataSource = new ReaderBlockDataSource();

  aboutToAppear(): void {
    const blocks = parseZhihuHtml(this.html);
    this.empty = blocks.length === 0;
    this.dataSource.replace(blocks);
  }

  aboutToDisappear(): void {
    clearFormulaByteCache();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.empty) {
        Text(this.emptyMessage)
          .id('p2_content_document_empty')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding($r('app.float.p1_page_padding'))
      } else {
        List({ space: 12 }) {
          LazyForEach(this.dataSource, (item: ReaderBlock) => {
            ListItem() {
              this.readerBlock(item)
            }
          }, (item: ReaderBlock): string => item.id)
        }
        .id('p2_content_document_list')
        .width('100%')
        .height('100%')
        .padding({
          left: $r('app.float.p1_page_padding'),
          right: $r('app.float.p1_page_padding'),
          top: $r('app.float.p1_spacing_medium'),
          bottom: $r('app.float.p1_page_padding')
        })
        .cachedCount(6)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.previewUrl.length > 0) {
        ContentImagePreview({
          url: this.previewUrl,
          onClose: (): void => {
            this.previewUrl = '';
          }
        })
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private readerBlock(item: ReaderBlock) {
    if (item.kind === ReaderBlockKind.HEADING) {
      Text(item.text)
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    } else if (item.kind === ReaderBlockKind.DIVIDER) {
      Divider().margin({ top: 8, bottom: 8 })
    } else if (item.kind === ReaderBlockKind.FORMULA) {
      ContentBlockFormula({ item: item })
    } else if (item.kind === ReaderBlockKind.IMAGE) {
      ReaderImageBlock({
        item: item,
        secondaryTextColor: $r('app.color.secondary_text'),
        onPreview: (url: string): void => {
          this.previewUrl = url;
        }
      })
    } else if (item.inlineRuns.length > 0) {
      ContentInlineFormula({ item: item })
    } else {
      Text(item.kind === ReaderBlockKind.LIST_ITEM ? `• ${item.text}` : item.text)
        .fontSize($r('app.float.p1_body_font_size'))
        .lineHeight(30)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    }
  }
}
