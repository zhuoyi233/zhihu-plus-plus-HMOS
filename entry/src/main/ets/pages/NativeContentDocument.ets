import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl } from '@kit.AbilityKit';
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
export struct ContentImagePreview {
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
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context,
        ['ohos.permission.WRITE_IMAGEVIDEO']
      );
      const grantStatus = await abilityAccessCtrl.createAtManager().checkAccessToken(
        context.applicationInfo.accessTokenId,
        'ohos.permission.WRITE_IMAGEVIDEO'
      );
      if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
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
    const shareService = createSystemShareService(context);
    const payload: ShareImagePayload = {
      kind: SharePayloadKind.IMAGE,
      title: '知乎图片',
      summary: '来自知乎++的受信图片链接',
      sourceKind: ShareImageSourceKind.TRUSTED_URL,
      trustedImageUrl: this.url
    };
    shareService.share(payload).then((outcome: ShareOutcome): void => {
      this.actionStatus = outcome === ShareOutcome.CANCELLED ? '' : '已打开分享面板';
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
      const pixelMap = await loadFormulaPixelMap(run.sourceUrl, await this.formulaCookieHeader());
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
      const pixelMap = await loadFormulaPixelMap(this.item.sourceUrl, await this.formulaCookieHeader());
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
  @State private previewUrl: string = '';
  @State private empty: boolean = true;
  /** 正文是否贴在列表底边：onReachEnd 置位；出现任何实际滚动（回滚/内容增高后续滚）即复位。 */
  private atBottomEdge: boolean = false;
  /** 正文是否贴在列表顶边：初始即顶；滚动进正文（yOffset 越过容差）即复位，滚回顶部再置位。 */
  private atTopEdge: boolean = true;
  private lastYOffset: number = 0;
  private readonly dataSource: ReaderBlockDataSource = new ReaderBlockDataSource();
  private readonly scroller: Scroller = new Scroller();

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
        Column({ space: 12 }) {
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
    Stack({ alignContent: Alignment.Center }) {
      List({ space: 12, scroller: this.scroller }) {
          ListItem() { this.documentHeader() }
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
            }, (item: ReaderBlock): string => item.id)
          }
          ListItem() { this.documentBodyFooter() }
          this.documentItems()
          ListItem() {
            this.documentFooter()
          }
          .width('100%')
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
        // 触底回调：问题详情页据此加载回答信息流下一页。
        .onReachEnd((): void => {
          this.updateBottomEdge(true);
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
          const callback = this.onScrollOffset;
          if (callback !== undefined) {
            callback(yOffset);
          }
        })

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
