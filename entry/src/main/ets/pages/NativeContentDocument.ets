import { fileIo, fileUri } from '@kit.CoreFileKit';
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
import {
  DEFAULT_THEME_COLOR,
  createReaderPositionStore,
  ReaderPosition,
  ReaderPositionRepository,
  LinkCardMeta,
  LinkCardMetaRepository,
  SegmentInfoParagraph
} from 'data';
import {
  clearFormulaByteCache,
  isTrustedReaderImageUrl,
  parseZhihuHtml,
  ReaderBlock,
  ReaderBlockDataSource,
  ReaderBlockKind,
  ReaderInlineRun
} from 'reader';
import {
  READING_PROGRESS_BAR_HIT_WIDTH_VP,
  READING_PROGRESS_BAR_RIGHT_INSET_VP,
  ReadingProgressBar
} from './components/ReadingProgressBar';
import { readerBlockSpacing } from './ReaderTypography';
import { readerHorizontalPaddingVp } from './ReaderViewportLayout';
import {
  readerBlockSignature,
  readerPositionBlockIndex,
  readerPositionFraction,
  readerPositionTargetY
} from './ReaderPositionAnchor';
import { LinkCardMetaLoader, ReaderBlockView } from './ReaderBlockView';
import { DoubleTapDetector } from './DoubleTapDetector';

/**
 * 块高缺失时的估算兜底（vp）：未渲染块按实测平均块高估，无实测值时用该值。
 * 见 NativeContentDocument 的"内容总高估算"注释。
 */
const DEFAULT_BLOCK_HEIGHT_VP = 48;

/** 暂无实测块时，未测块按"默认块高 + 一个块间距"计入估算。 */
function defaultEstimatedBlockHeightVp(blockSpacingPercent: number, preset: string): number {
  return DEFAULT_BLOCK_HEIGHT_VP + readerBlockSpacing(blockSpacingPercent, preset);
}

/** 对齐上游 telephoto 默认 ZoomSpec(maxZoomFactor = 2f)。 */
const IMAGE_PREVIEW_MAX_SCALE = 2;

/**
 * 问题折叠详情的按钮保留区高（vp）：按钮行总高（胶囊 40 + 底边距 8）。
 * 对齐上游 QUESTION_DETAIL_TOGGLE_ZONE：计入测量列高度，正文止步于按钮区之上。
 */
const COLLAPSIBLE_TOGGLE_ZONE_VP = 48;

function clampPreviewScale(value: number): number {
  return Math.min(IMAGE_PREVIEW_MAX_SCALE, Math.max(1, value));
}

function clampValue(value: number, limit: number): number {
  if (limit <= 0) {
    return 0;
  }
  return Math.min(limit, Math.max(-limit, value));
}

/**
 * 预览/存图/分享的图片来源判定：与 reader 的 `isTrustedReaderImageUrl` 同一口径
 * （https、无用户信息、无自定义端口、主机在 pic / pica / picx / picN 的 zhimg 子域白名单内）。
 * 曾因这里只用 picx 与 picN 的正则而漏掉 `pica.zhimg.com`，导致日报正文图能看不能存。
 */
function isTrustedPreviewImageUrl(value: string): boolean {
  return isTrustedReaderImageUrl(value);
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
        .id('content_image_preview')
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
            .id('content_image_preview_status')
            .fontSize($r('app.float.secondary_font_size'))
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
        .id('content_image_preview_menu_save')
        .onClick((): void => {
          this.saveImage();
        })
      MenuItem({ content: '分享图片' })
        .id('content_image_preview_menu_share')
        .onClick((): void => {
          this.shareImage();
        })
      MenuItem({ content: '在浏览器中打开' })
        .id('content_image_preview_menu_browser')
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

let mountedNativeDocuments: number = 0;
let nativeDocumentSequence: number = 0;

@Component
export struct NativeContentDocument {
  private readonly bodyTapDetector: DoubleTapDetector = new DoubleTapDetector();
  html: string = '';
  /**
   * 预解析正文块（可选）：提供时不再内部调用 `parseZhihuHtml`，直接按块渲染。
   * 与 `html` 互斥——两者同时存在时以 `documentBlocks` 为准（日报原生页据此复用整份阅读器，
   * 避免把已解析的块再转回 HTML 二次解析）。块身份（id）决定阅读锚点，必须稳定。
   */
  documentBlocks: ReaderBlock[] = [];
  /** 预解析正文的完整性提示：非空时在正文末尾就地提示（日报 PARTIAL 态）。 */
  contentNotice: string = '';
  /** 仅真实回答/文章传入；问题列表和相邻回答预览不读写进度。 */
  positionKey: string = '';
  /** 导航目的地身份保持不变；在同一路由内切换回答时，保存键仍使用实际回答 ID。 */
  positionOwnerKey: string = '';
  /** 单篇回答双实例共存时，只有已提交实例可写进度和响应翻页。 */
  answerDocumentKey: string = '';
  /** 候选正文（已预挂载、尚未提交）：按自己保存的位置预排版，但不写进度、不响应翻页、不广播折叠标题。 */
  candidatePane: boolean = false;
  @StorageProp('readerActiveAnswerDocument') @Watch('onPositionActiveChanged') private activeAnswerDocument: string = '';
  onDocumentPrepared?: () => void;
  onViewportPrepared?: (ready: boolean) => void;
  private viewportPreparedReported: boolean = false;
  private headerHasLayout: boolean = false;
  private registeredDocument: boolean = false;
  @StorageProp('readerActiveRouteKey') @Watch('onPositionActiveChanged') private positionVisibleOwner: string = '';
  @StorageProp('readerPositionFlushTick') @Watch('onPositionBackground') private positionFlushTick: number = 0;
  emptyMessage: string = '正文为空';
  /** 服务端返回的他人划线（segment_infos），按段落 pid 对齐渲染蓝色高亮。 */
  @Prop segmentInfos: SegmentInfoParagraph[] = [];
  /** 点击他人划线高亮片段回调（打开点赞/评论面板）。 */
  onSegmentClick?: (paragraph: SegmentInfoParagraph, markIndex: number) => void;
  /** P3-9-B：正文滚动像素偏移回调（用于详情页顶栏折叠联动）。 */
  onScrollOffset?: (offset: number) => void;
  /** 正文视频卡片点击回调；播放上下文由详情页补齐。 */
  onVideoOpen?: (videoId: string) => void;
  /** 正文内联链接（a[href]）点击回调：站内内容导航、外链交系统浏览器，由宿主详情页决定。 */
  onLinkClick?: (url: string) => void;
  /** 推荐阅读卡片元数据仓库：解析站内链接并拉取赞同/评论计数；未配置时卡片回退为展示链接地址。 */
  linkCardMetaRepository?: LinkCardMetaRepository = undefined;
  /** 正文区域双击回调（各详情页按共享偏好执行动作）。 */
  onBodyDoubleTap?: () => void;
  /**
   * 正文选区状态回调：active=true 表示存在选区（长按建词/拖选扩展中），宿主据此
   * 挂起回答切换过滑手势——过滑 pan 是 parallelGesture，与 Text 内部拖选并行识别
   * （选词吞手势只影响互斥仲裁路径），页顶拖选会被误判为"贴顶继续过滑"直接切答。
   * 选区识别在 ReaderBlockView 内完成，经此转发宿主。
   */
  onBodySelectionActive?: (active: boolean) => void;
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

  /**
   * 滚动内容起始内缩（vp）：让视口延伸到悬浮标题栏之下、由内容自身让位，
   * 滚动时正文才会从玻璃顶栏下穿过（顶栏占位式布局下内容到不了顶栏后面，无透光）。
   * 0 表示不额外让位（沉浸阅读隐藏顶栏 / 非详情页场景）。
   */
  @Prop topInsetVp: number = 0;
  /** 动态文末避让，随操作栏实测高度及沉浸状态更新。 */
  @Prop bottomInsetVp: number = 100;
  /** 回答/文章阅读布局：独立正文边距，信息头到正文至少留 24vp；其他宿主沿用原布局。 */
  readingLayout: boolean = false;
  /** 问题页正文折叠预览：正文超阈值（纯文本≥100 字或含图）时收起为 180vp 视口。 */
  collapsible: boolean = false;
  @State private detailExpanded: boolean = false;
  @State private collapsibleActive: boolean = false;
  /** 正文自然高度（vp）：由内层 onAreaChange 单调更新；视口高度据此派生，勿存快照——
   * 首帧测量偏小若被存死，内容长高后视口将永久被压小（正文整块消失）。 */
  @State private naturalHeightVp: number = 0;
  private blocks: ReaderBlock[] = [];
  private previousBlocks: Map<string, ReaderBlock> = new Map();
  /** 惰性列表的块身份随排版/主题变化，重建捕获过旧字号的 Span 与公式组件。 */
  @State private renderRevision: number = 0;
  @State private empty: boolean = true;
  /** 推荐阅读卡片站内元数据（卡片 url → meta）：串行拉取后回填，重赋值触发重渲染。 */
  @State private linkCardMetas: Map<string, LinkCardMeta> = new Map();
  /** 卡片元数据回填版本（url → 递增次数）：计入 LazyForEach 行键，强制对应卡片行重建。 */
  @State private linkCardMetaVersions: Map<string, number> = new Map();
  private linkCardMetaLoader?: LinkCardMetaLoader = undefined;
  /** 正文是否贴在列表底边：onReachEnd 置位；出现任何实际滚动（回滚/内容增高后续滚）即复位。 */
  private atBottomEdge: boolean = false;
  /** 正文是否贴在列表顶边：初始即顶；滚动进正文（yOffset 越过容差）即复位，滚回顶部再置位。 */
  private atTopEdge: boolean = true;
  private lastYOffset: number = 0;
  private readonly dataSource: ReaderBlockDataSource = new ReaderBlockDataSource();
  private readonly scroller: Scroller = new Scroller();
  private positionStore?: ReaderPositionRepository = undefined;
  private pendingPosition?: ReaderPosition = undefined;
  private positionSnapshot?: ReaderPosition = undefined;
  private positionMounted: boolean = false;
  private positionWasActive: boolean = false;
  private positionEverActive: boolean = false;
  private positionPreparationFailed: boolean = false;
  private focusRequested: boolean = false;
  private focusRequestTimer: number = -1;
  private focusRequestAttempts: number = 0;
  private readonly documentFocusId: string = `reader_document_${++nativeDocumentSequence}`;
  private positionWritable: boolean = false;
  private positionFirstIndex: number = 0;
  private positionLastIndex: number = 0;
  private positionTargetIndex: number = 0;
  private positionNeedsJump: boolean = false;
  private positionRestoreStarted: number = 0;
  private positionLayoutChanged: number = 0;
  private positionRestoreTimer: number = -1;
  private positionSaveTimer: number = -1;
  /**
   * 正文排版偏好（AppStorage 广播，键名与持久化键同名，对齐上游 contentFontSize 等）：
   * 设置页滑块实时写入，详情页开着即联动。
   */
  @StorageProp('contentFontSize') @Watch('onTypographyChanged') private fontSizePercent: number = 100;
  @StorageProp('contentLineHeight') @Watch('onTypographyChanged') private lineHeightPercent: number = 160;
  @StorageProp('contentBlockSpacing') @Watch('onTypographyChanged') private blockSpacingPercent: number = 100;
  @StorageProp('contentTypographyPreset') @Watch('onTypographyChanged') private typographyPreset: string = 'comfortable';
  @StorageProp('systemFontSizeScale') @Watch('onTypographyChanged') private systemFontSizeScale: number = 1;
  @StorageProp('showPageTurnFab') private showPageTurnFab: boolean = false;
  @StorageProp('volumeKeyPageTurn') @Watch('onVolumeKeyPageTurnChanged') private volumeKeyPageTurn: boolean = false;
  @StorageProp('pageTurnPercent') private pageTurnPercent: number = 90;
  @StorageProp('showPageTurnGuide') private showPageTurnGuide: boolean = false;
  @StorageProp('showContentEndMarker') private showContentEndMarker: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /**
   * 主题切换 tick（EntryAbility 系统深浅色联动 / 设置页切换主题时递增）：
   * onAppearanceChanged 据此整体重建正文行（renderRevision 进行键），让捕获过旧主题
   * 的 Span 与公式组件（ReaderBlockView 及其内部公式宿主）全部销毁重建。
   */
  @StorageProp('appearanceThemeTick') @Watch('onAppearanceChanged') private formulaRecreateTick: number = 0;
  @State private pageTurnGuideVisible: boolean = false;
  /** 正文视口高度（vp）：List 的 onAreaChange 回填，供阅读进度条换算拇指高度。 */
  @State private viewportHeightVp: number = 0;
  @State private viewportWidthVp: number = 0;
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
   * 问题正文折叠视口（对齐上游 QuestionDetailAnimatedViewport）：收起 180vp + 底部渐变遮罩 +
   * 右下角展开/收起开关，420ms FastOutSlowIn 动画。内层 Scroll 让子列不受视口高度约束、
   * 始终按自然高度测量（onAreaChange 回填展开目标高度），规避"父锁高→子测量被压缩"死锁。
   * 对齐上游：测量列自带 bottom=按钮区高 的保留区，展开视口=完整内容高（含保留区），
   * 正文天然止步于按钮区之上，按钮永不大压文字。
   */
  @Builder
  private collapsibleBodyViewport() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: this.blockSpacing() }) {
          ForEach(this.blocks, (item: ReaderBlock) => {
            this.readerBlock(item)
          }, (item: ReaderBlock): string => this.blockRowKey(item))
        }
        .width('100%')
        // 按钮保留区（上游 QUESTION_DETAIL_TOGGLE_ZONE 思路）：计入测量高，
        // 使展开态视口底部留出按钮行空间；收起态该区域被渐变遮罩与按钮覆盖，无感知。
        .padding({ bottom: COLLAPSIBLE_TOGGLE_ZONE_VP })
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
          // 遮罩底边略超出胶囊按钮顶（胶囊 40 + 底边距 8 = 48，遮罩 56）：收起态渐隐
          // 覆盖到按钮上缘附近即止，保留上方更多正文可见性。
          .height(56)
          .opacity(this.detailExpanded ? 0 : 1)
          .hitTestBehavior(HitTestMode.None)

      Row() {
        Blank()
        Row({ space: 4 }) {
          SymbolGlyph(this.detailExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([this.resolvedThemeColor])
          Text(this.detailExpanded ? '收起详情' : '展开详情')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor(this.resolvedThemeColor)
        }
        .padding({ left: 16, right: 16 }).height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.surface_background'))
        .onClick((): void => this.toggleDetailExpanded())
        .accessibilityText(this.detailExpanded ? '收起问题详情' : '展开问题详情')
      }
      .id('question_detail_toggle')
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })
    }
    .id('question_detail_content')
    .height(this.detailExpanded ? this.expandedViewportHeight() : this.collapsedViewportHeight())
    .clip(true)
    .width('100%')
  }

  /** 收起态视口高：未测得自然高前用 180，测得后取 min(自然高,180) 兜底短正文。 */
  private collapsedViewportHeight(): number {
    return this.naturalHeightVp > 0 ? Math.min(this.naturalHeightVp, 180) : 180;
  }

  /** 展开态视口高=完整内容高（测量列已含按钮保留区，对齐上游 coerce 到内容高内）。 */
  private expandedViewportHeight(): number {
    return Math.max(this.naturalHeightVp, 1);
  }

  private toggleDetailExpanded(): void {
    const collapsing = this.detailExpanded;
    this.getUIContext().animateTo({
      duration: 420,
      curve: Curve.FastOutSlowIn
    }, (): void => {
      this.detailExpanded = !this.detailExpanded;
    });
    // 收起后视口骤缩，若停留在原偏移只会看到回答流；对齐"回到详情开头"预期，
    // 立即滚回列表顶（标题头+详情起点）。已在顶部时为 no-op。
    if (collapsing && this.scrollYVp > 1) {
      this.scroller.scrollToIndex(0, false);
    }
  }

  aboutToAppear(): void {
    if (!this.registeredDocument) {
      this.registeredDocument = true;
      mountedNativeDocuments += 1;
    }
    // 预解析输入（日报原生页）优先：不再把块转回 HTML 二次解析。
    const preParsed = this.documentBlocks;
    const blocks = preParsed.length > 0 || this.html.length === 0 ? preParsed : parseZhihuHtml(this.html);
    this.empty = blocks.length === 0;
    this.blocks = blocks;
    this.previousBlocks.clear();
    for (let index = 1; index < blocks.length; index++) {
      this.previousBlocks.set(blocks[index].id, blocks[index - 1]);
    }
    this.dataSource.replace(blocks);
    if (this.answerDocumentKey.length === 0 || this.positionIsActive()) {
      this.loadLinkCardMetas(blocks);
    }
    // 折叠判定只看可读文本与图片：预解析输入没有 HTML 源串，不能按标签剥离长度判断。
    let plainLength = 0;
    blocks.forEach((block: ReaderBlock): void => {
      plainLength += block.text.length;
    });
    const hasImage = blocks.some((block: ReaderBlock): boolean => block.kind === ReaderBlockKind.IMAGE);
    this.collapsibleActive = this.collapsible && (plainLength >= 100 || hasImage);
    this.prepareReaderPosition();
    this.onDocumentPrepared?.();
  }

  private prepareReaderPosition(): void {
    this.positionMounted = true;
    this.positionWasActive = this.positionIsActive();
    this.positionEverActive = this.positionWasActive;
    this.positionPreparationFailed = false;
    this.positionRestoreStarted = 0;
    this.pendingPosition = undefined;
    this.positionWritable = false;
    const context = getAbilityContext();
    if (!this.readingLayout || this.positionKey.length === 0 || context === undefined || this.empty) { return; }
    try {
      this.positionStore = createReaderPositionStore(context);
      const saved = this.positionStore.load(this.positionKey);
      const index = saved === undefined ? -1 : readerPositionBlockIndex(saved, this.blocks);
      if (saved !== undefined && (saved.blockIndex === -1 || index >= 0)) {
        this.pendingPosition = saved;
        this.positionSnapshot = saved;
        this.positionTargetIndex = index + 1;
        this.positionNeedsJump = true;
        this.positionLayoutChanged = Date.now();
      }
      this.positionWritable = this.pendingPosition === undefined;
    } catch (_error) {
      // 进度损坏或本地存储不可用时仍能从顶部阅读。
      this.positionWritable = true;
    }
  }

  private positionIsActive(): boolean {
    return this.positionOwnerKey.length > 0 && this.positionVisibleOwner === this.positionOwnerKey &&
      (this.answerDocumentKey.length === 0 || this.activeAnswerDocument === this.answerDocumentKey);
  }

  /** 可执行位置恢复的主体：当前正文，或尚未提交但已预挂载的候选正文（不写回进度）。 */
  private positionRestorable(): boolean {
    return this.positionIsActive() || (this.candidatePane && this.positionOwnerKey.length > 0 &&
      this.positionVisibleOwner === this.positionOwnerKey);
  }

  private reportViewportPrepared(): void {
    const ready = this.positionMounted && this.headerHasLayout && this.viewportWidthVp > 0 &&
      this.viewportHeightVp > 0 && this.pendingPosition === undefined && !this.positionPreparationFailed;
    if (ready !== this.viewportPreparedReported) {
      this.viewportPreparedReported = ready;
      this.onViewportPrepared?.(ready);
    }
    if (ready) { this.requestDocumentFocus(); }
  }

  private onVolumeKeyPageTurnChanged(): void {
    this.focusRequested = false;
    this.focusRequestAttempts = 0;
    this.requestDocumentFocus();
  }

  private requestDocumentFocus(): void {
    if (!this.positionMounted || !this.positionIsActive() || !this.volumeKeyPageTurn || this.focusRequested ||
      this.focusRequestTimer >= 0 || this.focusRequestAttempts >= 4 ||
      !this.viewportPreparedReported || this.answerDocumentKey.length === 0) { return; }
    // 提交后的启用状态需先进入渲染树；焦点成功以 onFocus 为准，API 返回 void。
    this.focusRequestTimer = setTimeout((): void => {
      this.focusRequestTimer = -1;
      if (!this.positionMounted || !this.positionIsActive() || !this.volumeKeyPageTurn ||
        !this.viewportPreparedReported || this.focusRequested) { return; }
      this.focusRequestAttempts += 1;
      try {
        this.getUIContext().getFocusController().requestFocus(this.documentFocusId);
      } catch (_error) {
      }
      if (!this.focusRequested) { this.requestDocumentFocus(); }
    }, 50);
  }

  private schedulePositionRestore(layoutChanged: boolean = false): void {
    if (layoutChanged) { this.positionLayoutChanged = Date.now(); }
    if (!this.positionMounted || !this.positionRestorable() || this.pendingPosition === undefined ||
      this.viewportHeightVp <= 0 ||
      this.viewportWidthVp <= 0 || this.positionRestoreTimer >= 0) { return; }
    this.positionRestoreTimer = setTimeout((): void => {
      this.positionRestoreTimer = -1;
      this.adjustReaderPosition();
    }, 80);
  }

  private adjustReaderPosition(): void {
    const saved = this.pendingPosition;
    if (!this.positionMounted || !this.positionRestorable() || saved === undefined) { return; }
    const now = Date.now();
    if (this.positionRestoreStarted === 0) { this.positionRestoreStarted = now; }
    const expired = now - this.positionRestoreStarted >= 8000;
    try {
      if (this.positionNeedsJump) {
        this.positionNeedsJump = false;
        if (saved.blockIndex === -1 && saved.fraction === 0) {
          this.scroller.scrollEdge(Edge.Top);
        } else if (saved.atEnd) {
          this.scroller.scrollEdge(Edge.Bottom);
        } else {
          this.scroller.scrollToIndex(this.positionTargetIndex, false, ScrollAlign.START);
        }
        this.schedulePositionRestore();
        return;
      }
      const rect = this.scroller.getItemRect(this.positionTargetIndex);
      if (!saved.atEnd && !(rect.height > 0)) {
        if (!expired) {
          this.positionNeedsJump = true;
          this.schedulePositionRestore();
        } else { this.finishPositionRestore(false); }
        return;
      }
      const delta = saved.atEnd || (saved.blockIndex === -1 && saved.fraction === 0) ? 0 :
        rect.y - readerPositionTargetY(saved.fraction, rect.height, this.topInsetVp);
      if (saved.atEnd) {
        if (!this.scroller.isAtEnd()) { this.scroller.scrollEdge(Edge.Bottom); }
      } else if (Math.abs(delta) > 0.5) {
        this.scroller.scrollBy(0, delta);
      }
      // 等待惰性块、图片及公式排版稳定；上方块变高时以同一段落再次校正。
      if (expired || (Math.abs(delta) <= 0.5 && now - this.positionLayoutChanged >= 1500 &&
        now - this.positionRestoreStarted >= 2000)) {
        this.finishPositionRestore(true);
      } else { this.schedulePositionRestore(); }
    } catch (_error) {
      if (expired) { this.finishPositionRestore(false); } else { this.schedulePositionRestore(); }
    }
  }

  private finishPositionRestore(success: boolean): void {
    this.pendingPosition = undefined;
    this.positionWritable = success;
    this.positionPreparationFailed = !success;
    this.reportViewportPrepared();
    if (success) { this.persistReaderPosition(); }
  }

  private cancelPositionRestore(): void {
    if (this.positionStore !== undefined) { this.positionWritable = true; }
    if (this.pendingPosition === undefined) { return; }
    if (this.positionRestoreTimer >= 0) { clearTimeout(this.positionRestoreTimer); }
    this.positionRestoreTimer = -1;
    this.pendingPosition = undefined;
    this.positionWritable = true;
    this.reportViewportPrepared();
  }

  private onPositionActiveChanged(): void {
    const active = this.positionIsActive();
    const wasActive = this.positionWasActive;
    this.positionWasActive = active;
    if (active) { this.positionEverActive = true; }
    if (active && !wasActive && this.positionMounted && this.answerDocumentKey.length > 0 &&
      this.linkCardMetaLoader === undefined) {
      this.loadLinkCardMetas(this.blocks);
    }
    if (!active && wasActive) {
      this.focusRequested = false;
      this.focusRequestAttempts = 0;
      if (this.focusRequestTimer >= 0) { clearTimeout(this.focusRequestTimer); }
      this.focusRequestTimer = -1;
      this.linkCardMetaLoader?.dispose();
      this.linkCardMetaLoader = undefined;
      this.persistReaderPosition(true);
      if (this.positionSaveTimer >= 0) { clearTimeout(this.positionSaveTimer); }
      if (this.positionRestoreTimer >= 0) { clearTimeout(this.positionRestoreTimer); }
      this.positionSaveTimer = -1;
      this.positionRestoreTimer = -1;
    } else if (active && !wasActive) {
      // 候选已按自己的锚点完成恢复；提交只接管输入和写入，不再重新跳转。
      this.schedulePositionRestore();
      this.onScrollOffset?.(this.scrollYVp);
      this.onTopEdgeChange?.(this.atTopEdge);
      this.onBottomEdgeChange?.(this.atBottomEdge);
      this.requestDocumentFocus();
    }
  }

  private onPositionBackground(): void {
    if (this.positionIsActive()) { this.persistReaderPosition(true); }
  }

  private captureReaderPosition(): ReaderPosition | undefined {
    if (this.blocks.length === 0) { return undefined; }
    if (this.scrollYVp <= 1) {
      const top: ReaderPosition = {
        version: 1, blockId: '', signature: '00000000', blockIndex: -1, fraction: 0, atEnd: false
      };
      return top;
    }
    const last = this.blocks.length - 1;
    if (this.atBottomEdge || this.positionFirstIndex > this.blocks.length) {
      const end: ReaderPosition = { version: 1, blockId: this.blocks[last].id,
        signature: readerBlockSignature(this.blocks[last]), blockIndex: last, fraction: 1, atEnd: true };
      return end;
    }
    for (let index = this.positionFirstIndex; index <= Math.min(this.positionLastIndex, this.blocks.length); index++) {
      const rect = this.scroller.getItemRect(index);
      if (rect.height <= 0 || rect.y + rect.height <= this.topInsetVp) { continue; }
      const block = index > 0 ? this.blocks[index - 1] : undefined;
      const position: ReaderPosition = {
        version: 1, blockId: block?.id ?? '', signature: block === undefined ? '00000000' : readerBlockSignature(block),
        blockIndex: index - 1, fraction: readerPositionFraction(rect.y, rect.height, this.topInsetVp), atEnd: false
      };
      return position;
    }
    return undefined;
  }

  private schedulePositionSave(): void {
    if (!this.positionMounted || !this.positionIsActive() || !this.positionWritable || this.positionStore === undefined ||
      this.positionSaveTimer >= 0) { return; }
    // 持续滚动也定期落盘，不能只依赖退出回调（强制停止不会触发它）。
    this.positionSaveTimer = setTimeout((): void => {
      this.positionSaveTimer = -1;
      this.persistReaderPosition();
    }, 500);
  }

  private persistReaderPosition(synchronous: boolean = false): void {
    if (!this.positionMounted || (!this.positionIsActive() && (!synchronous || !this.positionEverActive)) ||
      !this.positionWritable || this.positionStore === undefined) { return; }
    if (this.positionSaveTimer >= 0) { clearTimeout(this.positionSaveTimer); }
    this.positionSaveTimer = -1;
    try {
      this.positionSnapshot = this.captureReaderPosition() ?? this.positionSnapshot;
    } catch (_error) {
      // List 已卸载时，使用最后一次有效快照；不以初始零偏移覆盖旧记录。
    }
    if (this.positionSnapshot !== undefined) {
      try {
        this.positionStore.save(this.positionKey, this.positionSnapshot, synchronous);
      } catch (_error) { console.error('Reading position save failed'); }
    }
  }

  /**
   * 推荐阅读卡片元数据拉取：逐个卡片链接（去重）解析站内资源并取赞同/评论计数。
   * 串行与去重由 LinkCardMetaLoader 承担（ZhihuHttpClient 单飞设计，并发即失败）；
   * 失败或非站内资源静默跳过，卡片保持展示链接地址的回退形态。
   */
  private loadLinkCardMetas(blocks: ReaderBlock[]): void {
    const repository = this.linkCardMetaRepository;
    if (repository === undefined || (this.answerDocumentKey.length > 0 && !this.positionIsActive())) {
      return;
    }
    const loader = new LinkCardMetaLoader(repository);
    loader.onUpdate = (url: string, meta: LinkCardMeta): void => {
      if (this.positionMounted && (this.answerDocumentKey.length === 0 || this.positionIsActive())) { this.applyLinkCardMeta(url, meta); }
    };
    this.linkCardMetaLoader = loader;
    const urls: Array<string> = [];
    blocks.forEach((block: ReaderBlock): void => {
      if (block.kind === ReaderBlockKind.LINK_CARD && block.sourceUrl.length > 0 &&
        !urls.includes(block.sourceUrl)) {
        urls.push(block.sourceUrl);
      }
    });
    if (urls.length > 0) {
      loader.load(urls);
    }
  }

  /** 元数据回填：更新 url → meta 状态并递增该 url 的行键版本，强制对应卡片行重建。 */
  private applyLinkCardMeta(url: string, meta: LinkCardMeta): void {
    const updated: Map<string, LinkCardMeta> = new Map();
    this.linkCardMetas.forEach((existing: LinkCardMeta, key: string): void => {
      updated.set(key, existing);
    });
    updated.set(url, meta);
    this.linkCardMetas = updated;
    const versions: Map<string, number> = new Map();
    this.linkCardMetaVersions.forEach((version: number, key: string): void => {
      versions.set(key, version);
    });
    versions.set(url, (versions.get(url) ?? 0) + 1);
    this.linkCardMetaVersions = versions;
  }

  aboutToDisappear(): void {
    if (this.positionWasActive) { this.persistReaderPosition(true); }
    this.positionMounted = false;
    this.positionWasActive = false;
    if (this.focusRequestTimer >= 0) { clearTimeout(this.focusRequestTimer); }
    this.focusRequestTimer = -1;
    this.reportViewportPrepared();
    if (this.positionRestoreTimer >= 0) { clearTimeout(this.positionRestoreTimer); }
    if (this.positionSaveTimer >= 0) { clearTimeout(this.positionSaveTimer); }
    this.positionRestoreTimer = -1;
    this.positionSaveTimer = -1;
    this.linkCardMetaLoader?.dispose();
    this.linkCardMetaLoader = undefined;
    if (this.registeredDocument) {
      this.registeredDocument = false;
      mountedNativeDocuments = Math.max(0, mountedNativeDocuments - 1);
      if (mountedNativeDocuments === 0) { clearFormulaByteCache(); }
    }
  }

  build() {
    // TopEnd：正文 List 为 100%×100% 不受影响，进度条靠右缘对齐。
    Stack({ alignContent: Alignment.TopEnd }) {
      List({ space: this.blockSpacing(), scroller: this.scroller }) {
          ListItem() { this.documentHeader() }
            // List.space 已含段间距，仅补足信息头与正文之间的留白；大段间距偏好不被压缩。
            .padding({ top: this.topInsetVp, bottom: this.readingLayout ? Math.max(0, 24 - this.blockSpacing()) : 0 })
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              this.reportChromeHeight('header', newArea);
              this.headerHasLayout = Number(newArea.width) > 0 && Number(newArea.height) > 0;
              this.reportViewportPrepared();
            })
          if (this.empty) {
            ListItem() {
              Text(this.emptyMessage).id('content_document_empty')
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
            }, (item: ReaderBlock): string => this.blockRowKey(item))
          }
          ListItem() { this.documentBodyFooter() }
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              this.reportChromeHeight('bodyFooter', newArea);
            })
          this.documentItems()
          if (this.contentNotice.length > 0) {
            ListItem() {
              Text(this.contentNotice)
                .id('content_document_notice')
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .width('100%')
                .padding({ top: 12, bottom: 12 })
            }
            .width('100%')
          }
          if (this.showContentEndMarker && !this.empty) {
            ListItem() {
              Text('— 内容结束 —')
                .id('content_end_marker')
                .fontSize($r('app.float.secondary_font_size'))
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
        .id('content_document_list')
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .padding({
          left: this.readingLayout ? readerHorizontalPaddingVp(this.viewportWidthVp) : $r('app.float.page_padding'),
          right: this.readingLayout ? readerHorizontalPaddingVp(this.viewportWidthVp) : $r('app.float.page_padding'),
          top: 16
        })
        // 末尾避让随正文滚动，避免底部 padding 压缩视口、在悬浮操作栏下方形成固定留白。
        .contentEndOffset(this.bottomInsetVp)
        // 起始内缩随正文滚动（同 contentEndOffset 思路）：视口可延伸到悬浮顶栏之下，
        // 未滚动时正文仍从顶栏下方开始，滚动后正文从玻璃顶栏背后穿过。
        .cachedCount(6)
        .edgeEffect(this.disableEdgeSpring ? EdgeEffect.None : EdgeEffect.Spring)
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const height = Number(newArea.height);
          if (height >= 0 && Math.abs(height - this.viewportHeightVp) > 0.5) {
            this.viewportHeightVp = height;
            this.refreshContentHeightEstimate();
          }
          this.schedulePositionRestore();
          this.reportViewportPrepared();
        })
        .onScrollIndex((start: number, end: number): void => {
          this.positionFirstIndex = start;
          this.positionLastIndex = end;
          this.schedulePositionSave();
        })
        .onScrollStop((): void => {
          this.persistReaderPosition();
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
          // 只有真正发生位移才算滚动：轻点不改变偏移，不会刷新滚动静默时刻。
          this.bodyTapDetector.markScrollActive();
          const yOffset = this.scroller.currentOffset().yOffset;
          if (yOffset < this.lastYOffset - 0.5 || yOffset > this.lastYOffset + 2) {
            this.updateBottomEdge(false);
          }
          this.updateTopEdge(yOffset <= 2);
          this.lastYOffset = yOffset;
          this.scrollYVp = yOffset;
          this.refreshContentHeightEstimate();
          this.schedulePositionSave();
          const callback = this.onScrollOffset;
          if (callback !== undefined) {
            callback(yOffset);
          }
        })

      // 右缘可拖动阅读进度条：问题/回答/文章三页共用（上游 ArticleScreen 接入方式一致）。
      // 上下留白由悬浮顶栏与实测底栏决定；拇指高度与行程均按轨道高度换算。
      // 直接作为 Stack 的右对齐子节点、宽仅 12vp：Stack 内重叠区域的触摸测试默认只命中
      // 最上层节点，进度条可见时右缘这 12vp 归它（拖动定位），其余区域照常命中正文列表；
      // 隐藏时进度条自身把 `hitTestBehavior` 切到 `HitTestMode.None`，右缘手势完整交回正文。
      // 不用整页覆盖层：加宽后即使 `HitTestMode.Transparent` 也会进入命中链，
      // 实测会干扰正文列表自身的滚动（详见 ReadingProgressBar 顶部注释）。
      ReadingProgressBar({
        active: this.positionIsActive(),
        scroller: this.scroller,
        viewportHeightVp: this.viewportHeightVp,
        contentHeightVp: this.contentHeightVp,
        scrollYVp: this.scrollYVp,
        topInsetVp: this.topInsetVp,
        bottomInsetVp: Math.max(96, this.bottomInsetVp),
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
        .margin({ right: READING_PROGRESS_BAR_RIGHT_INSET_VP })

      if (this.pageTurnGuideVisible && this.showPageTurnGuide) {
        Divider()
          .id('page_turn_guide')
          .color(this.resolvedThemeColor)
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
          .id('page_turn_previous')
          .width(44).height(44)
          .backgroundColor($r('app.color.surface_background'))
          .onClick((): void => this.turnPage(-1))
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20)
          }
          .id('page_turn_next')
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
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.cancelPositionRestore(); }
    })
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const width = Number(area.width);
      if (width >= 0 && Math.abs(width - this.viewportWidthVp) > 0.5) {
        this.viewportWidthVp = width;
        this.exactContentHeightVp = 0;
        this.refreshContentHeightEstimate();
      }
      this.schedulePositionRestore();
      this.reportViewportPrepared();
    })
    .id(this.documentFocusId)
    .onFocus((): void => {
      this.focusRequested = true;
      this.focusRequestAttempts = 0;
    })
    // 关闭音量键翻页只停止抢焦点，不能阻断正文图片等子节点的键盘导航。
    .focusable(this.documentCanFocus())
    .defaultFocus(this.volumeKeyPageTurn && this.documentCanFocus())
    .onKeyPreIme((event: KeyEvent): boolean => this.handleReaderKey(event))
  }

  /** 段间距/块间距（vp，`List({ space })` 传 number 即 vp）：12 × 段间距%，默认 12 == 改造前。 */
  private blockSpacing(): number {
    return readerBlockSpacing(this.blockSpacingPercent, this.typographyPreset);
  }

  /** 正文行键：renderRevision 随排版/主题整体重建；卡片元数据回填只递增对应 url 版本。 */
  private blockRowKey(item: ReaderBlock): string {
    if (item.kind !== ReaderBlockKind.LINK_CARD) {
      return `${item.id}:${this.renderRevision}`;
    }
    return `${item.id}:${this.renderRevision}:${this.linkCardMetaVersions.get(item.sourceUrl) ?? 0}`;
  }

  private documentCanFocus(): boolean {
    return this.answerDocumentKey.length === 0 || this.positionIsActive();
  }

  private handleReaderKey(event: KeyEvent): boolean {
    if (!this.volumeKeyPageTurn || (this.answerDocumentKey.length > 0 && !this.positionIsActive()) ||
      (event.keyCode !== 16 && event.keyCode !== 17)) { return false; }
    // 一次释放只翻一页，兼容系统保留音量键按下事件的设备，也避免按住期间重复切答。
    if (event.type === KeyType.Up) { this.turnPage(event.keyCode === 16 ? -1 : 1); }
    return true;
  }

  private turnPage(direction: number): void {
    if (this.answerDocumentKey.length > 0 && !this.positionIsActive()) { return; }
    this.cancelPositionRestore();
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

  /**
   * 字号/行高/段间距变化：已实测块高随排版失效，清空重算；正文块内字号样式由
   * ReaderBlockView 自身的 @StorageProp 依赖刷新（公式组件解码密度由其内部处理）。
   */
  private onTypographyChanged(): void {
    this.blockHeights.clear();
    this.measuredBlockHeightSumVp = 0;
    this.measuredBlockCount = 0;
    this.exactContentHeightVp = 0;
    this.rebuildRenderedBlocks();
    this.refreshContentHeightEstimate();
  }

  private onAppearanceChanged(): void {
    this.rebuildRenderedBlocks();
  }

  private rebuildRenderedBlocks(): void {
    this.viewportPreparedReported = false;
    this.onViewportPrepared?.(false);
    // 设置页覆盖着详情时，字号仍会广播到缓存的正文；保留隐藏前的锚点，禁止布局变化覆盖进度。
    if (this.positionMounted && this.positionStore !== undefined && this.pendingPosition === undefined &&
      this.positionWritable) {
      if (this.positionIsActive()) {
        try { this.positionSnapshot = this.captureReaderPosition() ?? this.positionSnapshot; } catch (_error) {}
      }
      const snapshot = this.positionSnapshot;
      if (snapshot !== undefined) {
        const index = readerPositionBlockIndex(snapshot, this.blocks);
        if (snapshot.blockIndex === -1 || index >= 0) {
          this.pendingPosition = snapshot;
          this.positionTargetIndex = index + 1;
          this.positionNeedsJump = true;
          this.positionRestoreStarted = 0;
          this.positionWritable = false;
        }
      }
    }
    this.renderRevision += 1;
    this.dataSource.replace(this.blocks);
    this.schedulePositionRestore(true);
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
    this.schedulePositionRestore(true);
    this.reportViewportPrepared();
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
    this.schedulePositionRestore(true);
    this.reportViewportPrepared();
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
      : defaultEstimatedBlockHeightVp(this.blockSpacingPercent, this.typographyPreset);
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

  /** 正文块渲染委托共享 ReaderBlockView（P1 抽离，单篇与连续阅读页共用同一富文本实现）。 */
  @Builder
  private readerBlock(item: ReaderBlock) {
    ReaderBlockView({
      item: item,
      bodyTapDetector: this.bodyTapDetector,
      previousBlock: this.previousBlocks.get(item.id),
      segmentInfos: this.segmentInfos,
      linkCardMeta: this.linkCardMetas.get(item.sourceUrl),
      onLinkClick: (url: string): void => {
        this.onLinkClick?.(url);
      },
      onReferenceClick: (numero: number): void => this.scrollToReference(numero),
      onReferenceBack: (numero: number): void => this.scrollBackToReference(numero),
      onVideoOpen: (videoId: string): void => {
        this.onVideoOpen?.(videoId);
      },
      onSegmentClick: (paragraph: SegmentInfoParagraph, markIndex: number): void => {
        this.onSegmentClick?.(paragraph, markIndex);
      },
      onBodyDoubleTap: (): void => {
        this.onBodyDoubleTap?.();
      },
      onBodySelectionActive: (active: boolean): void => {
        this.onBodySelectionActive?.(active);
      }
    })
  }

  /**
   * 点击正文参考标记：滚动到文末对应参考条目（对齐上游脚注引用跳转）。
   * 跳转前记忆当前偏移供条目 ↩ 返回（对齐上游 rememberReturnPosition）。
   * List 索引 = 块下标 + 1 个页头槽位；折叠视口内块不占独立槽位，退化为滚到视口本体。
   */
  private readonly referenceReturnOffsets: Map<number, number> = new Map();

  private scrollToReference(numero: number): void {
    const blockIndex = this.blocks.findIndex((block: ReaderBlock): boolean =>
      block.kind === ReaderBlockKind.REFERENCE && block.reference?.numero === numero);
    if (blockIndex < 0) {
      return;
    }
    this.referenceReturnOffsets.set(numero, this.scroller.currentOffset().yOffset);
    if (this.collapsibleActive) {
      this.scroller.scrollToIndex(1, true, ScrollAlign.START);
      return;
    }
    this.scroller.scrollToIndex(blockIndex + 1, true, ScrollAlign.START);
  }

  /**
   * 条目 ↩ 返回（对齐上游 onFootnoteBackClick）：优先滚回点标记前的阅读位置；
   * 无记忆（未点过标记）则回退滚到标记所在段落。折叠视口内段落不可按槽位滚动，忽略。
   */
  private scrollBackToReference(numero: number): void {
    const remembered = this.referenceReturnOffsets.get(numero);
    if (remembered !== undefined && remembered >= 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: remembered, animation: true });
      return;
    }
    const blockIndex = this.blocks.findIndex((block: ReaderBlock): boolean =>
      block.inlineRuns.some((run: ReaderInlineRun): boolean => run.referenceNumero === numero));
    if (blockIndex >= 0 && !this.collapsibleActive) {
      this.scroller.scrollToIndex(blockIndex + 1, true, ScrollAlign.START);
    }
  }

}
