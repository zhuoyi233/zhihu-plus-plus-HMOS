import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Want } from '@kit.AbilityKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import {
  createSystemShareService
} from '../platform/SystemShareService';
import {
  ShareImageSourceKind,
  ShareImagePayload,
  ShareOutcome,
  SharePayloadKind
} from '../platform/ShareContracts';
import { getAppSessionOwner, getGuestDeviceCookieManager, toCookieHeader } from 'data';
import {
  blockFormulaDisplayAspectRatio,
  clearFormulaByteCache,
  inlineFormulaDisplayWidth,
  loadFormulaPixelMap,
  parseZhihuHtml,
  ReaderBlock,
  ReaderBlockDataSource,
  ReaderBlockKind,
  ReaderImageBlock,
  ReaderInlineKind,
  ReaderInlineRun
} from 'reader';
import {
  READING_PROGRESS_BAR_HIT_WIDTH_VP,
  READING_PROGRESS_BAR_RIGHT_INSET_VP,
  ReadingProgressBar
} from './components/ReadingProgressBar';
import {
  readerBlockSpacing,
  readerBodyFontSize,
  readerBodyLineHeight,
  readerHeadingFontSize
} from './ReaderTypography';

/**
 * 块高缺失时的估算兜底（vp）：未渲染块按实测平均块高估，无实测值时用该值。
 * 见 NativeContentDocument 的"内容总高估算"注释。
 */
const DEFAULT_BLOCK_HEIGHT_VP = 48;

/** 暂无实测块时，未测块按"默认块高 + 一个块间距"计入估算。 */
function defaultEstimatedBlockHeightVp(blockSpacingPercent: number): number {
  return DEFAULT_BLOCK_HEIGHT_VP + readerBlockSpacing(blockSpacingPercent);
}

/** 对齐上游 telephoto 默认 ZoomSpec(maxZoomFactor = 2f)。 */
const IMAGE_PREVIEW_MAX_SCALE = 2;

function clampPreviewScale(value: number): number {
  return Math.min(IMAGE_PREVIEW_MAX_SCALE, Math.max(1, value));
}

function clampValue(value: number, limit: number): number {
  if (limit <= 0) {
    return 0;
  }
  return Math.min(limit, Math.max(-limit, value));
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
export struct ContentImagePreview {
  @Prop url: string = '';
  onClose: () => void = () => {};
  @State private previewScale: number = 1;
  @State private previewOffsetX: number = 0;
  @State private previewOffsetY: number = 0;
  @State private actionStatus: string = '';
  private saveInFlight: boolean = false;
  private statusTimerId: number = -1;
  private pinchStartScale: number = 1;
  /** 源图宽高比与容器尺寸：用于计算放大后允许的平移范围。 */
  private imageRatio: number = 0;
  private containerWidth: number = 0;
  private containerHeight: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;

  aboutToDisappear(): void {
    if (this.statusTimerId >= 0) {
      clearTimeout(this.statusTimerId);
      this.statusTimerId = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.url)
        .id('p2_content_image_preview')
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .onComplete((event) => {
          if (event !== undefined && event.width > 0 && event.height > 0) {
            this.imageRatio = event.width / event.height;
          }
        })
        .scale({ x: this.previewScale, y: this.previewScale, z: 1 })
        .translate({ x: this.previewOffsetX, y: this.previewOffsetY })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart((): void => {
              this.pinchStartScale = this.previewScale;
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.previewScale = clampPreviewScale(this.pinchStartScale * event.scale);
              this.clampPreviewOffset();
            })
        )
        .gesture(
          PanGesture({ fingers: 1 })
            .onActionStart((): void => {
              this.panStartX = this.previewOffsetX;
              this.panStartY = this.previewOffsetY;
            })
            .onActionUpdate((event: GestureEvent): void => {
              const maxX = this.maxPreviewOffsetX();
              const maxY = this.maxPreviewOffsetY();
              this.previewOffsetX = clampValue(this.panStartX + event.offsetX, maxX);
              this.previewOffsetY = clampValue(this.panStartY + event.offsetY, maxY);
            })
        )
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction((): void => {
                // 对齐上游 telephoto 双击：在适配屏幕与最大倍数间切换，缩放回 1 时复位平移。
                this.previewScale = this.previewScale > 1 ? 1 : IMAGE_PREVIEW_MAX_SCALE;
                this.clampPreviewOffset();
              }),
            TapGesture({ count: 1 })
              .onAction((): void => {
                this.onClose();
              })
          )
        )
        // 对齐上游 OpenImageDialog：长按在按压点弹出操作菜单（无顶栏按钮）。
        .bindContextMenu(this.imageContextMenu, ResponseType.LongPress)

      if (this.actionStatus.length > 0) {
        Column() {
          Blank()
          Text(this.actionStatus)
            .id('p2_content_image_preview_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor(Color.White)
            .margin({ bottom: 64 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EE000000')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.containerWidth = Number(newArea.width);
      this.containerHeight = Number(newArea.height);
    })
  }

  /** 放大后单指平移的最大位移：超出适配尺寸的部分才允许拖动（对齐 telephoto 平移边界）。 */
  private maxPreviewOffsetX(): number {
    if (this.containerWidth <= 0 || this.containerHeight <= 0 || this.imageRatio <= 0) {
      return 0;
    }
    const ratio = this.containerWidth / this.containerHeight;
    const baseWidth = this.imageRatio > ratio ? this.containerWidth : this.containerHeight * this.imageRatio;
    return Math.max(0, (baseWidth * this.previewScale - this.containerWidth) / 2);
  }

  private maxPreviewOffsetY(): number {
    if (this.containerWidth <= 0 || this.containerHeight <= 0 || this.imageRatio <= 0) {
      return 0;
    }
    const ratio = this.containerWidth / this.containerHeight;
    const baseHeight = this.imageRatio > ratio ? this.containerWidth / this.imageRatio : this.containerHeight;
    return Math.max(0, (baseHeight * this.previewScale - this.containerHeight) / 2);
  }

  private clampPreviewOffset(): void {
    this.previewOffsetX = clampValue(this.previewOffsetX, this.maxPreviewOffsetX());
    this.previewOffsetY = clampValue(this.previewOffsetY, this.maxPreviewOffsetY());
  }

  @Builder
  private imageContextMenu() {
    Menu() {
      MenuItem({ content: '保存图片' })
        .id('p2_content_image_preview_menu_save')
        .onClick((): void => {
          this.saveImage();
        })
      MenuItem({ content: '分享图片' })
        .id('p2_content_image_preview_menu_share')
        .onClick((): void => {
          this.shareImage();
        })
      MenuItem({ content: '在浏览器中打开' })
        .id('p2_content_image_preview_menu_browser')
        .onClick((): void => {
          this.openInBrowser();
        })
    }
  }

  /** 状态提示 2 秒自动消退；空串表示不展示。 */
  private showStatus(message: string): void {
    if (this.statusTimerId >= 0) {
      clearTimeout(this.statusTimerId);
      this.statusTimerId = -1;
    }
    this.actionStatus = message;
    if (message.length === 0) {
      return;
    }
    this.statusTimerId = setTimeout((): void => {
      this.statusTimerId = -1;
      this.actionStatus = '';
    }, 2000);
  }

  private async openInBrowser(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || !isTrustedPreviewImageUrl(this.url)) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: this.url
    };
    try {
      await context.startAbility(want);
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法在浏览器中打开' });    }
  }

  /**
   * 保存走系统安全弹窗（showAssetsCreationDialog，带图片预览与禁止/允许），无需
   * WRITE_IMAGEVIDEO 权限：先下载到应用沙箱临时文件，用户允许后把字节写入返回的
   * 媒体库 URI；用户拒绝返回空列表，视为取消。
   */
  private async saveImage(): Promise<void> {
    if (this.saveInFlight) {
      return;
    }
    if (!isTrustedPreviewImageUrl(this.url)) {
      this.showStatus('图片来源不受支持');
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.showStatus('当前页面无法访问相册');
      return;
    }
    this.saveInFlight = true;
    this.showStatus('正在下载图片…');
    let request: http.HttpRequest | undefined = undefined;
    let tempPath: string = '';
    try {
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
        this.showStatus('图片下载失败');
        return;
      }
      const buffer: ArrayBuffer = response.result as ArrayBuffer;
      const extension = previewImageExtension(this.url);
      tempPath = `${context.cacheDir}/preview-save-${Date.now()}.${extension}`;
      this.writeBufferToFile(tempPath, buffer);
      this.showStatus('正在保存…');
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: `zhihu_${Date.now()}`,
        fileNameExtension: extension,
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      const uris = await photoAccessHelper.getPhotoAccessHelper(context)
        .showAssetsCreationDialog([fileUri.getUriFromPath(tempPath)], [config]);
      if (uris.length === 0) {
        this.showStatus('');
        return;
      }
      this.writeBufferToUri(uris[0], buffer);
      this.showStatus('已保存到相册');
    } catch {
      this.showStatus('保存失败，请稍后重试');
    } finally {
      request?.destroy();
      this.saveInFlight = false;
      this.removeTempFileBestEffort(tempPath);
    }
  }

  private writeBufferToFile(path: string, buffer: ArrayBuffer): void {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, buffer);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private writeBufferToUri(uri: string, buffer: ArrayBuffer): void {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, buffer);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private removeTempFileBestEffort(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (_error) {
      // 清理失败不影响保存结果
    }
  }

  private shareImage(): void {
    const context = getAbilityContext();
    if (context === undefined || !isTrustedPreviewImageUrl(this.url)) {
      this.showStatus('图片来源不受支持');
      return;
    }
    const shareService = createSystemShareService(context);
    const payload: ShareImagePayload = {
      kind: SharePayloadKind.IMAGE,
      title: '知乎图片',
      summary: '来自知乎++的受信图片链接',
      sourceKind: ShareImageSourceKind.TRUSTED_URL,
      trustedImageUrl: this.url
    };
    shareService.share(payload).then((outcome: ShareOutcome): void => {
      this.showStatus(outcome === ShareOutcome.CANCELLED ? '' : '已打开分享面板');
    }).catch((): void => {
      this.showStatus('暂时无法打开分享面板');
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
  /** 排版偏好与宿主同源（AppStorage 广播），行内公式所在段落随字号/行高联动。 */
  @StorageProp('contentFontSize') private fontSizePercent: number = 100;
  @StorageProp('contentLineHeight') private lineHeightPercent: number = 160;
  @StorageProp('appearanceThemeTick') @Watch('onAppearanceThemeChanged')
  private appearanceThemeTick: number = 0;
  @StorageProp('formulaForegroundColor') private formulaColor: string = '#111111';
  @State private loadedRunIds: Array<string> = [];
  private pixelMaps: Map<string, image.PixelMap> = new Map();
  private formulaWidths: Map<string, number> = new Map();
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
    this.formulaWidths.clear();
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
            .width(this.formulaWidths.get(run.id) ?? 20)
            .height(24)
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .onError((): void => {
              this.failFormula(run.id);
            })
        }
      }, (run: ReaderInlineRun): string => run.id)
    }
    .fontSize(readerBodyFontSize(this.fontSizePercent))
    .lineHeight(readerBodyLineHeight(this.fontSizePercent, this.lineHeightPercent))
    .fontColor($r('app.color.primary_text'))
    .width('100%')
  }

  private async loadFormula(run: ReaderInlineRun, generation: number): Promise<void> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await loadFormulaPixelMap(run.sourceUrl, await this.formulaCookieHeader(),
        this.formulaColor);
      const info = await pixelMap.getImageInfo();
      if (!this.active || this.loadGeneration !== generation) {
        await pixelMap.release();
        pixelMap = undefined;
        return;
      }
      const previous = this.pixelMaps.get(run.id);
      if (previous !== undefined) {
        await previous.release();
      }
      this.pixelMaps.set(run.id, pixelMap);
      this.formulaWidths.set(run.id, inlineFormulaDisplayWidth(info.size.width, info.size.height));
      pixelMap = undefined;
      this.loadedRunIds = this.loadedRunIds.concat(run.id);
    } catch (_error) {
      await pixelMap?.release();
      if (this.active && this.loadGeneration === generation) {
        this.failFormula(run.id);
      }
    }
  }

  private onAppearanceThemeChanged(): void {
    if (!this.active) {
      return;
    }
    const generation = ++this.loadGeneration;
    this.loadedRunIds = [];
    this.pixelMaps.forEach((pixelMap: image.PixelMap): void => {
      pixelMap.release();
    });
    this.pixelMaps.clear();
    this.formulaWidths.clear();
    this.item.inlineRuns.forEach((run: ReaderInlineRun): void => {
      if (run.kind === ReaderInlineKind.FORMULA) {
        this.loadFormula(run, generation);
      }
    });
  }

  private async formulaCookieHeader(): Promise<string> {
    const context = getAbilityContext();
    if (context === undefined) {
      return '';
    }
    const repository = getAppSessionOwner(context).getRepository();
    const sessionCookies = repository.getCookies();
    if (sessionCookies.length > 0) {
      return toCookieHeader(sessionCookies, Date.now());
    }
    return getGuestDeviceCookieManager(context).getCookieHeader();
  }

  private failFormula(id: string): void {
    const pixelMap = this.pixelMaps.get(id);
    this.pixelMaps.delete(id);
    this.formulaWidths.delete(id);
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
  @State private formulaAspectRatio: number = 4;
  @StorageProp('appearanceThemeTick') @Watch('onAppearanceThemeChanged')
  private appearanceThemeTick: number = 0;
  @StorageProp('formulaForegroundColor') private formulaColor: string = '#111111';
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
          .aspectRatio(this.formulaAspectRatio)
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
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await loadFormulaPixelMap(this.item.sourceUrl, await this.formulaCookieHeader(),
        this.formulaColor);
      const info = await pixelMap.getImageInfo();
      if (!this.active || this.loadGeneration !== generation) {
        await pixelMap.release();
        pixelMap = undefined;
        return;
      }
      if (this.pixelMap !== undefined) {
        await this.pixelMap.release();
      }
      this.formulaAspectRatio = blockFormulaDisplayAspectRatio(info.size.width, info.size.height);
      this.pixelMap = pixelMap;
      pixelMap = undefined;
      this.failed = false;
    } catch (_error) {
      await pixelMap?.release();
      if (this.active && this.loadGeneration === generation) {
        this.failed = true;
      }
    }
  }

  private onAppearanceThemeChanged(): void {
    if (!this.active) {
      return;
    }
    this.failed = false;
    this.releasePixelMap();
    this.loadFormula(++this.loadGeneration);
  }

  private async formulaCookieHeader(): Promise<string> {
    const context = getAbilityContext();
    if (context === undefined) {
      return '';
    }
    const repository = getAppSessionOwner(context).getRepository();
    const sessionCookies = repository.getCookies();
    if (sessionCookies.length > 0) {
      return toCookieHeader(sessionCookies, Date.now());
    }
    return getGuestDeviceCookieManager(context).getCookieHeader();
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
  /** P3-9-B：正文滚动像素偏移回调（用于详情页顶栏折叠联动）。 */
  onScrollOffset?: (offset: number) => void;
  /** 正文视频卡片点击回调；播放上下文由详情页补齐。 */
  onVideoOpen?: (videoId: string) => void;
  /** 问题详情页在正文末尾追加的 section（回答信息流）；未传入时渲染空。 */
  @BuilderParam documentHeader: () => void = this.emptyFooter;
  @BuilderParam documentBodyFooter: () => void = this.emptyFooter;
  @BuilderParam documentItems: () => void = this.emptyFooter;
  @BuilderParam documentFooter: () => void = this.emptyFooter;
  /** 列表触底回调：问题详情页用于回答信息流分页加载。 */
  onListReachEnd?: () => void;
  /** 回答详情页切换：正文是否贴在列表底边（用于自定义 overscroll 手势）。 */
  onBottomEdgeChange?: (atBottom: boolean) => void;
  /** 回答详情页切换：正文是否贴在列表顶边（顶部过滑切上一答依赖此信号）。 */
  onTopEdgeChange?: (atTop: boolean) => void;
  /** 电纸书翻页在正文边界继续翻页时，由回答页切换相邻回答。 */
  onPageTurnPastStart?: () => void;
  onPageTurnPastEnd?: () => void;
  /** 回答详情页关闭 Spring 边缘效果：自定义 overscroll 需要独占边界拖动量。 */
  disableEdgeSpring: boolean = false;
  /** 问题页正文折叠预览：正文超阈值（纯文本≥100 字或含图）时收起为 180vp 视口。 */
  collapsible: boolean = false;
  @State private detailExpanded: boolean = false;
  @State private collapsibleActive: boolean = false;
  /** 正文自然高度（vp）：由内层 onAreaChange 单调更新；视口高度据此派生，勿存快照——
   * 首帧测量偏小若被存死，内容长高后视口将永久被压小（正文整块消失）。 */
  @State private naturalHeightVp: number = 0;
  private blocks: ReaderBlock[] = [];
  @State private empty: boolean = true;
  /** 正文是否贴在列表底边：onReachEnd 置位；出现任何实际滚动（回滚/内容增高后续滚）即复位。 */
  private atBottomEdge: boolean = false;
  /** 正文是否贴在列表顶边：初始即顶；滚动进正文（yOffset 越过容差）即复位，滚回顶部再置位。 */
  private atTopEdge: boolean = true;
  private lastYOffset: number = 0;
  private readonly dataSource: ReaderBlockDataSource = new ReaderBlockDataSource();
  private readonly scroller: Scroller = new Scroller();
  /**
   * 正文排版偏好（AppStorage 广播，键名与持久化键同名，对齐上游 contentFontSize 等）：
   * 设置页滑块实时写入，详情页开着即联动。
   */
  @StorageProp('contentFontSize') @Watch('onTypographyChanged') private fontSizePercent: number = 100;
  @StorageProp('contentLineHeight') @Watch('onTypographyChanged') private lineHeightPercent: number = 160;
  @StorageProp('contentBlockSpacing') @Watch('onTypographyChanged') private blockSpacingPercent: number = 100;
  @StorageProp('showPageTurnFab') private showPageTurnFab: boolean = false;
  @StorageProp('volumeKeyPageTurn') private volumeKeyPageTurn: boolean = false;
  @StorageProp('pageTurnPercent') private pageTurnPercent: number = 90;
  @StorageProp('showPageTurnGuide') private showPageTurnGuide: boolean = false;
  @StorageProp('showContentEndMarker') private showContentEndMarker: boolean = false;
  @State private pageTurnGuideVisible: boolean = false;
  /** 正文视口高度（vp）：List 的 onAreaChange 回填，供阅读进度条换算拇指高度。 */
  @State private viewportHeightVp: number = 0;
  /** 正文内容总高（vp）：本页 SDK 无最大滚动距离 API，按实测块高估算、触底时校准。 */
  @State private contentHeightVp: number = 0;
  /** 当前滚动偏移（vp）：onDidScroll 回填，驱动阅读进度条拇指位置。 */
  @State private scrollYVp: number = 0;
  /** 实测块高（vp，块 id → 高度）：已渲染块实测后用 onAreaChange 回填，用于估算内容总高。 */
  private readonly blockHeights: Map<string, number> = new Map();
  private measuredBlockHeightSumVp: number = 0;
  private measuredBlockCount: number = 0;
  /** 实测的非正文块固定槽位高（vp，槽位名 → 高度）：页头/正文页脚/页脚等。 */
  private readonly chromeHeights: Map<string, number> = new Map();
  /** 触底校准得到的精确内容总高（vp）：0 表示尚未校准；内容增高后自动失效。 */
  private exactContentHeightVp: number = 0;

  @Builder
  private emptyFooter(): void {
  }

  /**
   * 问题正文折叠视口（对齐上游 QuestionAnimatedBodyHeader）：收起 180vp + 底部渐变遮罩 +
   * 右下角展开/收起开关，420ms FastOutSlowIn 动画。内层 Scroll 让子列不受视口高度约束、
   * 始终按自然高度测量（onAreaChange 回填展开目标高度），规避"父锁高→子测量被压缩"死锁。
   */
  @Builder
  private collapsibleBodyViewport() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: this.blockSpacing() }) {
          ForEach(this.blocks, (item: ReaderBlock) => {
            this.readerBlock(item)
          }, (item: ReaderBlock): string => item.id)
        }
        .width('100%')
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const height = Number(newArea.height);
          if (height > 0 && Math.abs(height - this.naturalHeightVp) > 1) {
            this.naturalHeightVp = height;
          }
        })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      // 该 Scroll 仅用于让子列按自然高度测量（无约束约束），自身永不滚动；
      // 不禁用滚动交互会抢占全部滑动手势，外层列表（回答流）将无法滚动。
      .enableScrollInteraction(false)

      Column()
          .linearGradient({
            angle: 180,
            colors: [['rgba(0,0,0,0)', 0], [$r('app.color.page_background'), 1]]
          })
          .width('100%')
          .height(88)
          .opacity(this.detailExpanded ? 0 : 1)
          .hitTestBehavior(HitTestMode.None)

      Row() {
        Blank()
        Row({ space: 4 }) {
          SymbolGlyph(this.detailExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.brand_primary')])
          Text(this.detailExpanded ? '收起详情' : '展开详情')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.brand_primary'))
        }
        .padding({ left: 12, right: 12 }).height(56)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_background'))
        .onClick((): void => this.toggleDetailExpanded())
        .accessibilityText(this.detailExpanded ? '收起问题详情' : '展开问题详情')
      }
      .id('p3_question_detail_toggle')
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })
    }
    .id('p3_question_detail_content')
    .height(this.detailExpanded ? this.expandedViewportHeight() : this.collapsedViewportHeight())
    .clip(true)
    .width('100%')
  }

  /** 收起态视口高：未测得自然高前用 180，测得后取 min(自然高,180) 兜底短正文。 */
  private collapsedViewportHeight(): number {
    return this.naturalHeightVp > 0 ? Math.min(this.naturalHeightVp, 180) : 180;
  }

  private expandedViewportHeight(): number {
    return Math.max(this.naturalHeightVp, 1) + 64;
  }

  private toggleDetailExpanded(): void {
    this.getUIContext().animateTo({
      duration: 420,
      curve: Curve.FastOutSlowIn
    }, (): void => {
      this.detailExpanded = !this.detailExpanded;
    });
  }

  aboutToAppear(): void {
    const blocks = parseZhihuHtml(this.html);
    this.empty = blocks.length === 0;
    this.blocks = blocks;
    this.dataSource.replace(blocks);
    const plainLength = this.html.replace(/<[^>]*>/g, '').trim().length;
    this.collapsibleActive = this.collapsible && (plainLength >= 100 || this.html.includes('<img'));
  }

  aboutToDisappear(): void {
    clearFormulaByteCache();
  }

  build() {
    // TopEnd：正文 List 为 100%×100% 不受影响，进度条靠右缘对齐。
    Stack({ alignContent: Alignment.TopEnd }) {
      List({ space: this.blockSpacing(), scroller: this.scroller }) {
          ListItem() { this.documentHeader() }
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              this.reportChromeHeight('header', newArea);
            })
          if (this.empty) {
            ListItem() {
              Text(this.emptyMessage).id('p2_content_document_empty')
                .fontColor($r('app.color.secondary_text')).padding(12)
            }
          }
          if (this.collapsibleActive) {
            ListItem() {
              this.collapsibleBodyViewport()
            }
            .width('100%')
          } else {
            LazyForEach(this.dataSource, (item: ReaderBlock) => {
              ListItem() {
                this.readerBlock(item)
              }
              .onAreaChange((_oldArea: Area, newArea: Area): void => {
                this.reportBlockHeight(item.id, newArea);
              })
            }, (item: ReaderBlock): string => item.id)
          }
          ListItem() { this.documentBodyFooter() }
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              this.reportChromeHeight('bodyFooter', newArea);
            })
          this.documentItems()
          if (this.showContentEndMarker && !this.empty) {
            ListItem() {
              Text('— 内容结束 —')
                .id('p3_content_end_marker')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 24, bottom: 12 })
            }
          }
          ListItem() {
            this.documentFooter()
          }
          .width('100%')
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            this.reportChromeHeight('footer', newArea);
          })
        }
        .id('p2_content_document_list')
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .padding({
          left: $r('app.float.p1_page_padding'),
          right: $r('app.float.p1_page_padding'),
          top: $r('app.float.p1_spacing_medium')
        })
        // 末尾避让随正文滚动，避免底部 padding 压缩视口、在悬浮操作栏下方形成固定留白。
        .contentEndOffset(100)
        .cachedCount(6)
        .edgeEffect(this.disableEdgeSpring ? EdgeEffect.None : EdgeEffect.Spring)
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const height = Number(newArea.height);
          if (height > 0 && Math.abs(height - this.viewportHeightVp) > 0.5) {
            this.viewportHeightVp = height;
            this.refreshContentHeightEstimate();
          }
        })
        // 触底回调：问题详情页据此加载回答信息流下一页。
        .onReachEnd((): void => {
          this.updateBottomEdge(true);
          // 触底即拿到真实内容总高：本页 SDK 无读取最大滚动距离的 API，
          // 只能在此把估算值校准为精确值（此后拇指比例完全正确）。
          const yOffset = this.scroller.currentOffset().yOffset;
          this.scrollYVp = yOffset;
          this.exactContentHeightVp = yOffset + this.viewportHeightVp;
          this.refreshContentHeightEstimate();
          const callback = this.onListReachEnd;
          if (callback !== undefined) {
            callback();
          }
        })
        // 用像素偏移而非 onScrollIndex 驱动顶栏折叠：索引会随视口高度变化回弹造成振荡闪烁，
        // 像素偏移在顶栏收起（视口变高）时保持不变，状态稳定。
        // 同时维护底部边界状态：贴底后回滚（y 减小）即离开底边；y 反向增大只可能是
        // 内容增高后继续上滚（onReachEnd 提前触发的残余滚动在 2px 容差内不复位）。
        .onDidScroll((): void => {
          const yOffset = this.scroller.currentOffset().yOffset;
          if (yOffset < this.lastYOffset - 0.5 || yOffset > this.lastYOffset + 2) {
            this.updateBottomEdge(false);
          }
          this.updateTopEdge(yOffset <= 2);
          this.lastYOffset = yOffset;
          this.scrollYVp = yOffset;
          this.refreshContentHeightEstimate();
          const callback = this.onScrollOffset;
          if (callback !== undefined) {
            callback(yOffset);
          }
        })

      // 右缘可拖动阅读进度条：问题/回答/文章三页共用（上游 ArticleScreen 接入方式一致）。
      // 上下留白与几何换算在组件内按上游 `ArticleScreen`（statusBars + 64 / systemBars + 96）
      // 与 `VerticalReadingProgressBar`（拇指高度与行程都按"轨道高"）对齐，宿主无需传参。
      // 直接作为 Stack 的右对齐子节点、宽仅 12vp：Stack 内重叠区域的触摸测试默认只命中
      // 最上层节点，进度条可见时右缘这 12vp 归它（拖动定位），其余区域照常命中正文列表；
      // 隐藏时进度条自身把 `hitTestBehavior` 切到 `HitTestMode.None`，右缘手势完整交回正文。
      // 不用整页覆盖层：加宽后即使 `HitTestMode.Transparent` 也会进入命中链，
      // 实测会干扰正文列表自身的滚动（详见 ReadingProgressBar 顶部注释）。
      ReadingProgressBar({
        scroller: this.scroller,
        viewportHeightVp: this.viewportHeightVp,
        contentHeightVp: this.contentHeightVp,
        scrollYVp: this.scrollYVp,
        onSeekStateChange: (dragging: boolean): void => {
          if (dragging) {
            // 拖动期间正文由 scrollTo 驱动：屏蔽贴边过滑，否则贴底向上拖滚动条
            // 会被回答页误判为"下一答"过滑。
            this.updateBottomEdge(false);
            this.updateTopEdge(false);
          }
        }
      })
        .width(READING_PROGRESS_BAR_HIT_WIDTH_VP)
        .height('100%')
        .margin({ right: READING_PROGRESS_BAR_RIGHT_INSET_VP })

      if (this.pageTurnGuideVisible && this.showPageTurnGuide) {
        Divider()
          .id('p3_page_turn_guide')
          .color($r('app.color.brand_primary'))
          .strokeWidth(1)
          .opacity(0.55)
          .width('100%')
          .align(Alignment.Center)
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.showPageTurnFab) {
        Column({ space: 8 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(20)
          }
          .id('p3_page_turn_previous')
          .width(44).height(44)
          .backgroundColor($r('app.color.surface_background'))
          .onClick((): void => this.turnPage(-1))
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20)
          }
          .id('p3_page_turn_next')
          .width(44).height(44)
          .backgroundColor($r('app.color.surface_background'))
          .onClick((): void => this.turnPage(1))
        }
        .align(Alignment.End)
        .margin({ right: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .focusable(this.volumeKeyPageTurn)
    .defaultFocus(this.volumeKeyPageTurn)
    .onKeyPreIme((event: KeyEvent): boolean => {
      if (!this.volumeKeyPageTurn || (event.keyCode !== 16 && event.keyCode !== 17)) {
        return false;
      }
      if (event.type === KeyType.Down) {
        this.turnPage(event.keyCode === 16 ? -1 : 1);
      }
      return true;
    })
  }

  /** 正文字号（fp，`Text.fontSize` 传 number 即 fp）：16 × 字号%，默认 16 == 改造前 16fp。 */
  private bodyFontSize(): number {
    return readerBodyFontSize(this.fontSizePercent);
  }

  private turnPage(direction: number): void {
    const maxOffset = Math.max(0, this.contentHeightVp - this.viewportHeightVp);
    if (direction < 0 && this.scrollYVp <= 2) {
      const callback = this.onPageTurnPastStart;
      if (callback !== undefined) callback();
      return;
    }
    if (direction > 0 && this.scrollYVp >= maxOffset - 2) {
      const callback = this.onPageTurnPastEnd;
      if (callback !== undefined) callback();
      return;
    }
    const distance = this.viewportHeightVp * this.pageTurnPercent / 100;
    const target = Math.max(0, Math.min(maxOffset, this.scrollYVp + direction * distance));
    this.scroller.scrollTo({ xOffset: 0, yOffset: target, animation: true });
    this.pageTurnGuideVisible = this.showPageTurnGuide;
  }

  /** 正文行高（fp）：行高 160% ↔ 改造前的 30，见 ReaderTypography 的归一说明。 */
  private bodyLineHeight(): number {
    return readerBodyLineHeight(this.fontSizePercent, this.lineHeightPercent);
  }

  /** 段间距/块间距（vp，`List({ space })` 传 number 即 vp）：12 × 段间距%，默认 12 == 改造前。 */
  private blockSpacing(): number {
    return readerBlockSpacing(this.blockSpacingPercent);
  }

  /** 标题字号（fp）：20 × 字号%，默认 20 == 改造前 p1_heading_font_size。 */
  private headingFontSize(): number {
    return readerHeadingFontSize(this.fontSizePercent);
  }

  /**
   * 字号/行高/段间距变化：已实测块高随排版失效，清空重算；列表块自身靠 @StorageProp
   * 依赖刷新（行内公式子组件同源，无需外部传参）。
   */
  private onTypographyChanged(): void {
    this.blockHeights.clear();
    this.measuredBlockHeightSumVp = 0;
    this.measuredBlockCount = 0;
    this.exactContentHeightVp = 0;
    this.refreshContentHeightEstimate();
  }

  /** 正文块渲染后回报实测高度（vp），用于估算未渲染块的高度。 */
  private reportBlockHeight(id: string, area: Area): void {
    if (id.length === 0) {
      return;
    }
    const height = Number(area.height);
    if (!(height > 0)) {
      return;
    }
    const previous = this.blockHeights.get(id);
    if (previous !== undefined && Math.abs(previous - height) < 0.5) {
      return;
    }
    this.blockHeights.set(id, height);
    if (previous === undefined) {
      this.measuredBlockCount += 1;
      // 每个块自带一段 List space（末块多算的一段在误差范围内）。
      this.measuredBlockHeightSumVp += height + this.blockSpacing();
    } else {
      this.measuredBlockHeightSumVp += height - previous;
    }
    this.refreshContentHeightEstimate();
  }

  /** 正文块之外的固定槽位（页头/正文页脚/页脚）实测高度（vp）。 */
  private reportChromeHeight(key: string, area: Area): void {
    const height = Number(area.height);
    if (!(height > 0)) {
      return;
    }
    const previous = this.chromeHeights.get(key);
    if (previous !== undefined && Math.abs(previous - height) < 0.5) {
      return;
    }
    this.chromeHeights.set(key, height);
    this.refreshContentHeightEstimate();
  }

  private chromeHeightVp(): number {
    let sum = 0;
    this.chromeHeights.forEach((height: number): void => {
      sum += height;
    });
    return sum;
  }

  /**
   * 内容总高估算：已测块高 + 未测块数 × 实测均块高 + 页头页脚；
   * 并以"已滚过的范围"为硬下界（估算偏小时拇指会越出轨道）。
   * 触底校准值为精确值时优先采用，直到内容增高（回答流分页）使其失效。
   */
  private refreshContentHeightEstimate(): void {
    const scrollExtent = this.scrollYVp + this.viewportHeightVp;
    if (this.exactContentHeightVp > 0 && scrollExtent <= this.exactContentHeightVp + 1) {
      this.updateContentHeight(this.exactContentHeightVp);
      return;
    }
    this.exactContentHeightVp = 0;
    const total = this.blocks.length;
    const average = this.measuredBlockCount > 0
      ? this.measuredBlockHeightSumVp / this.measuredBlockCount
      : defaultEstimatedBlockHeightVp(this.blockSpacingPercent);
    const estimated = this.measuredBlockHeightSumVp
      + Math.max(0, total - this.measuredBlockCount) * average
      + this.chromeHeightVp();
    this.updateContentHeight(Math.max(estimated, scrollExtent));
  }

  private updateContentHeight(value: number): void {
    const next = Math.round(value);
    if (Math.abs(next - this.contentHeightVp) >= 1) {
      this.contentHeightVp = next;
    }
  }

  /** 触底/离底状态变化时通知页面侧（下滑切换回答依赖此信号）。 */
  private updateBottomEdge(atBottom: boolean): void {
    this.lastYOffset = this.scroller.currentOffset().yOffset;
    if (this.atBottomEdge === atBottom) { return; }
    this.atBottomEdge = atBottom;
    const callback = this.onBottomEdgeChange;
    if (callback !== undefined) {
      callback(atBottom);
    }
  }

  /** 贴顶/离顶状态变化时通知页面侧（顶部过滑切上一答依赖此信号）。 */
  private updateTopEdge(atTop: boolean): void {
    if (this.atTopEdge === atTop) { return; }
    this.atTopEdge = atTop;
    const callback = this.onTopEdgeChange;
    if (callback !== undefined) {
      callback(atTop);
    }
  }

  @Builder
  private readerBlock(item: ReaderBlock) {
    if (item.kind === ReaderBlockKind.HEADING) {
      Text(item.text)
        .fontSize(this.headingFontSize())
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
          // 全屏查看器由详情页根 Stack 叠层渲染（AppStorage 广播）：正文组件处于列表
          // 惰性树内，本地渲染全屏层会受标题栏约束，且模态覆盖层树不响应状态更新。
          AppStorage.setOrCreate('p2ImagePreviewUrl', url);
        }
      })
    } else if (item.kind === ReaderBlockKind.VIDEO) {
      Stack({ alignContent: Alignment.Center }) {
        if (item.sourceUrl.length > 0) {
          Image(item.sourceUrl)
            .width('100%')
            .height(200)
            .objectFit(ImageFit.Cover)
        } else {
          Row().width('100%').height(200).backgroundColor('#202124')
        }
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(30)
            .fontColor([Color.White])
        }
          .width(56)
          .height(56)
          .padding(0)
          .backgroundColor('#B3000000')
          .accessibilityText('播放视频')
      }
      .id(`p2_content_video_${item.targetId ?? 'invalid'}`)
      .width('100%')
      .height(200)
      .borderRadius(12)
      .clip(true)
      .accessibilityText(item.text.length > 0 ? `播放视频：${item.text}` : '播放视频')
      .onClick((): void => {
        if (item.targetId !== undefined) {
          this.onVideoOpen?.(item.targetId);
        }
      })
    } else if (item.inlineRuns.length > 0) {
      ContentInlineFormula({ item: item })
    } else {
      Text(item.kind === ReaderBlockKind.LIST_ITEM ? `• ${item.text}` : item.text)
        .fontSize(this.bodyFontSize())
        .lineHeight(this.bodyLineHeight())
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    }
  }
}
