import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { LengthMetrics } from '@ohos.arkui.node';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { DoubleTapDetector } from './DoubleTapDetector';
import {
  DEFAULT_THEME_COLOR,
  effectiveSegmentMeta,
  getAppSessionOwner,
  getGuestDeviceCookieManager,
  LinkCardMeta,
  LinkCardMetaRepository,
  SegmentInfoMark,
  SegmentInfoParagraph,
  toCookieHeader
} from 'data';
import {
  boxedFormulaText,
  FORMULA_EM_PER_EX,
  formulaDisplaySize,
  FormulaDisplaySize,
  loadFormulaPixelMap,
  ReaderBlock,
  ReaderBlockKind,
  ReaderImageBlock,
  ReaderInlineKind,
  ReaderInlineRun
} from 'reader';
import {
  flattenStyledTextSegments,
  HighlightSegment,
  SegmentHighlightRef,
  splitTextByHighlights,
  StyledTextSegment
} from './ContentAnnotations';
import {
  readerBlockSpacing,
  readerBodyFontSize,
  readerBodyLineHeight,
  readerHeadingFontSize
} from './ReaderTypography';
import { linkCardMetaLine } from './LinkCardMetaText';
import { readerBlockLeadingSpace } from './ReaderBlockLayout';
import { readerCaptionLineHeightFp } from './ReaderViewportLayout';

/** 公式解码采样密度（px/ex）：字号 × 0.5em/ex × 屏幕密度——让栅格与显示物理像素
 * 1:1，规避"固定 15px/ex 采样在显示端被放大"造成的模糊（issue #51）。 */
export function formulaDecodeDensity(fontSizeFp: number): number {
  let density = 1;
  try {
    density = display.getDefaultDisplaySync().densityPixels;
  } catch (_error) {
    density = 1;
  }
  const safeDensity = Number.isFinite(density) && density > 0 ? density : 1;
  return fontSizeFp * FORMULA_EM_PER_EX * safeDensity;
}

/**
 * 推荐阅读卡片元数据串行加载器：ZhihuHttpClient 是单飞设计（同一实例并发第二请求
 * 直接失败），卡片元数据必须逐个串行拉取；已登记 URL 去重（含在途），失败静默跳过，
 * 卡片保持展示链接地址的回退形态。宿主销毁时 dispose，迟到回包不再回调。
 */
export class LinkCardMetaLoader {
  private readonly repository: LinkCardMetaRepository;
  /** 已登记（含已加载/在途）的 URL：同一 URL 不会重复请求。 */
  private readonly scheduled: Set<string> = new Set();
  private readonly queue: Array<string> = [];
  private generation: number = 0;
  private pumping: boolean = false;
  /** 每拉到一条元数据回调宿主（宿主负责更新状态并强制对应卡片重渲染）。 */
  onUpdate: (url: string, meta: LinkCardMeta) => void = (_url: string, _meta: LinkCardMeta): void => {};

  constructor(repository: LinkCardMetaRepository) {
    this.repository = repository;
  }

  /** 批量登记待拉取 URL（自动去重、跳过已登记项），在既有串行链上继续拉取。 */
  load(urls: Array<string>): void {
    urls.forEach((url: string): void => {
      if (url.length === 0 || this.scheduled.has(url)) {
        return;
      }
      this.scheduled.add(url);
      this.queue.push(url);
    });
    this.pump();
  }

  /** 宿主销毁：排队作废、迟到回包丢弃（同实例不再复用，仅防御性保持语义完整）。 */
  dispose(): void {
    this.generation += 1;
    this.queue.length = 0;
    this.pumping = false;
  }

  private pump(): void {
    if (this.pumping) {
      return;
    }
    this.pumping = true;
    const generation = this.generation;
    this.pumpNext(generation);
  }

  private pumpNext(generation: number): void {
    if (generation !== this.generation) {
      this.pumping = false;
      return;
    }
    const url = this.queue.shift();
    if (url === undefined) {
      this.pumping = false;
      return;
    }
    this.repository.getMeta(url).then((meta: LinkCardMeta | undefined): void => {
      if (generation === this.generation && meta !== undefined) {
        this.onUpdate(url, meta);
      }
      this.pumpNext(generation);
    }).catch((_error: Error): void => {
      this.pumpNext(generation);
    });
  }
}

// 导出供连续阅读原型（ContinuousReadingPrototype）复用同一公式渲染实现。
@Component
export struct ContentInlineFormula {
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
  @StorageProp('contentTypographyPreset') private typographyPreset: string = 'comfortable';
  @StorageProp('formulaForegroundColor') private formulaColor: string = '#111111';
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 正文内联链接点击回调（行内公式所在段落同样生效）。 */
  onLinkClick?: (url: string) => void;
  /** 参考标记点击回调：跳转文末参考条目。 */
  onReferenceClick?: (numero: number) => void;
  /** 行内公式段落 Text 的选区状态回调（转发宿主）。 */
  onBodySelectionActive?: (active: boolean) => void;
  @State private loadedRunIds: Array<string> = [];
  private pixelMaps: Map<string, image.PixelMap> = new Map();
  /** 公式 SVG 固有尺寸（ex 单位，run.id → exSize）：显示尺寸按 ex × 字号换算。 */
  private formulaExSizes: Map<string, FormulaDisplaySize> = new Map();
  @State @Watch('onFormulaWidthChanged') private formulaAvailableWidth: number = 320;
  private active: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.loadFormulas();
  }

  private onFormulaWidthChanged(): void {
    if (this.active && this.item.inlineRuns.some((run: ReaderInlineRun): boolean =>
      run.kind === ReaderInlineKind.FORMULA && boxedFormulaText(run.text) !== undefined)) {
      this.loadFormulas();
    }
  }

  private loadFormulas(): void {
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
    this.formulaExSizes.clear();
  }

  build() {
    Text() {
      if (this.item.kind === ReaderBlockKind.LIST_ITEM) {
        Span('• ')
      }
      ForEach(this.item.inlineRuns, (run: ReaderInlineRun) => {
        if (run.kind === ReaderInlineKind.TEXT || !this.loadedRunIds.includes(run.id) ||
          this.pixelMaps.get(run.id) === undefined) {
          if (run.kind === ReaderInlineKind.TEXT) {
            Span(run.text)
              .fontSize(readerBodyFontSize(this.fontSizePercent, this.typographyPreset) *
                (run.referenceNumero !== undefined ? 0.75 : 1))
              .baselineOffset(run.referenceNumero !== undefined ?
                LengthMetrics.vp(readerBodyFontSize(this.fontSizePercent, this.typographyPreset) * 0.35) : LengthMetrics.vp(0))
              .fontColor((run.linkUrl ?? '').length > 0 || run.referenceNumero !== undefined
                ? this.resolvedThemeColor : $r('app.color.primary_text'))
              .fontWeight(run.bold === true ? FontWeight.Bold : FontWeight.Normal)
              .fontStyle(run.italic === true ? FontStyle.Italic : FontStyle.Normal)
              .decoration({
                type: run.strikethrough === true ? TextDecorationType.LineThrough : TextDecorationType.None,
                style: TextDecorationStyle.SOLID,
                color: Color.Transparent
              })
              .textBackgroundStyle(run.mark === true
                ? { color: '#66FDD835', radius: 3 }
                : { color: Color.Transparent, radius: 0 })
              .onClick((): void => {
                const link = run.linkUrl ?? '';
                if (link.length > 0) {
                  if (this.onLinkClick !== undefined) {
                    this.onLinkClick(link);
                  }
                  return;
                }
                if (run.referenceNumero !== undefined && this.onReferenceClick !== undefined) {
                  this.onReferenceClick(run.referenceNumero);
                }
              })
          } else {
            Span(`「${run.text}」`)
              .fontColor($r('app.color.secondary_text'))
          }
        } else {
          ImageSpan(this.pixelMaps.get(run.id) ?? run.text)
            .id(`content_inline_formula_${run.id}`)
            .width(this.displaySize(run.id).width)
            .height(this.displaySize(run.id).height)
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .onError((): void => {
              this.failFormula(run.id);
            })
        }
      }, (run: ReaderInlineRun): string => run.id)
    }
    .fontSize(readerBodyFontSize(this.fontSizePercent, this.typographyPreset))
    .lineHeight(readerBodyLineHeight(this.fontSizePercent, this.lineHeightPercent, this.typographyPreset))
    .fontColor($r('app.color.primary_text'))
    // 鸿蒙原生长按选字：启用系统文本选择菜单（复制 / 全选 / 翻译 / 分享等"更多操作"）。
    .copyOption(CopyOptions.LocalDevice)
    .onTextSelectionChange((start: number, end: number): void => {
      this.onBodySelectionActive?.(start !== end);
    })
    .width('100%')
    .onAreaChange((_oldArea: Area, area: Area): void => {
      this.formulaAvailableWidth = Number(area.width);
    })
  }

  private displaySize(id: string): FormulaDisplaySize {
    const exSize = this.formulaExSizes.get(id);
    return formulaDisplaySize(exSize?.width ?? 0, exSize?.height ?? 0,
      this.formulaFontSizeVp(), this.formulaAvailableWidth);
  }

  private formulaFontSizeVp(): number {
    const context = this.getUIContext();
    return context.px2vp(context.fp2px(readerBodyFontSize(this.fontSizePercent, this.typographyPreset)));
  }

  private async loadFormula(run: ReaderInlineRun, generation: number): Promise<void> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const result = await loadFormulaPixelMap(run.sourceUrl, await this.formulaCookieHeader(),
        this.formulaColor, formulaDecodeDensity(this.formulaFontSizeVp()),
        this.getUIContext().vp2px(this.formulaAvailableWidth));
      pixelMap = result.pixelMap;
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
      this.formulaExSizes.set(run.id, result.exSize);
      pixelMap = undefined;
      this.loadedRunIds = this.loadedRunIds.filter((id: string): boolean => id !== run.id).concat(run.id);
    } catch (_error) {
      await pixelMap?.release();
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
    this.formulaExSizes.delete(id);
    pixelMap?.release();
    this.loadedRunIds = this.loadedRunIds.filter((loadedId: string): boolean => loadedId !== id);
  }
}

@Component
export struct ContentBlockFormula {
  item: ReaderBlock = {
    id: '',
    kind: ReaderBlockKind.FORMULA,
    text: '',
    sourceUrl: '',
    inlineRuns: []
  };
  @State private failed: boolean = false;
  @State private pixelMap: image.PixelMap | undefined = undefined;
  /** 公式 SVG 固有尺寸（ex 单位）：显示尺寸按 ex × 字号换算。 */
  @State private formulaExSize: FormulaDisplaySize = { width: 0, height: 0 };
  @State @Watch('onFormulaWidthChanged') private formulaAvailableWidth: number = 320;
  @StorageProp('contentFontSize') private fontSizePercent: number = 100;
  @StorageProp('contentTypographyPreset') private typographyPreset: string = 'comfortable';
  @StorageProp('formulaForegroundColor') private formulaColor: string = '#111111';
  /** 加载失败兜底 Text 的选区状态回调（转发宿主）。 */
  onBodySelectionActive?: (active: boolean) => void;
  private active: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.loadFormula(++this.loadGeneration);
  }

  private onFormulaWidthChanged(): void {
    if (this.active && boxedFormulaText(this.item.text) !== undefined) {
      this.loadFormula(++this.loadGeneration);
    }
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
          .id(`content_formula_${this.item.id}`)
          .width(this.blockDisplaySize().width)
          .height(this.blockDisplaySize().height)
          .objectFit(ImageFit.Contain)
          // 栅格按载入时字号解码，字号调小后 Image 缩小显示：开高质量插值避免锯齿。
          .interpolation(ImageInterpolation.High)
          .onError((): void => {
            this.failed = true;
            this.releasePixelMap();
          })
      } else {
        Text(this.item.text)
          .id(`content_formula_fallback_${this.item.id}`)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .copyOption(CopyOptions.LocalDevice)
          .onTextSelectionChange((start: number, end: number): void => {
            this.onBodySelectionActive?.(start !== end);
          })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_small'))
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.card_radius'))
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const padding = this.getUIContext().getHostContext()?.resourceManager
        .getNumber($r('app.float.spacing_small').id) ?? 10;
      this.formulaAvailableWidth = Math.max(1, Number(area.width) - padding * 2);
    })
  }

  private blockDisplaySize(): FormulaDisplaySize {
    return formulaDisplaySize(this.formulaExSize.width, this.formulaExSize.height,
      this.formulaFontSizeVp(), this.formulaAvailableWidth);
  }

  private formulaFontSizeVp(): number {
    const context = this.getUIContext();
    return context.px2vp(context.fp2px(readerBodyFontSize(this.fontSizePercent, this.typographyPreset)));
  }

  private async loadFormula(generation: number): Promise<void> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const result = await loadFormulaPixelMap(this.item.sourceUrl, await this.formulaCookieHeader(),
        this.formulaColor, formulaDecodeDensity(this.formulaFontSizeVp()),
        this.getUIContext().vp2px(this.formulaAvailableWidth));
      pixelMap = result.pixelMap;
      if (!this.active || this.loadGeneration !== generation) {
        await pixelMap.release();
        pixelMap = undefined;
        return;
      }
      if (this.pixelMap !== undefined) {
        await this.pixelMap.release();
      }
      this.formulaExSize = result.exSize;
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

/**
 * 双击后临时禁选窗口（ms）：需覆盖双击选词判定（第二击抬起后立即）与双击序列中
 * 第二击演化成长按的选词触发（按下后约 500ms）两个时机，取 800ms 留余量；
 * 正常的独立长按选词没有前置双击，不经过此窗口。
 */
const DOUBLE_TAP_SELECTION_SUPPRESS_MS = 800;

/**
 * 正文块共享渲染单元（P1 抽离，docs/continuous-answer-reading-plan.md §6）：
 * 单篇详情（NativeContentDocument）与连续阅读页共用同一份富文本渲染——样式化 Span、
 * 他人划线叠加与点击、双击动作识别与选词抑制、链接卡片元数据、公式主题/字号重建、
 * 参考条目跳转、图片 caption 排版。宿主只负责滚动结构与回调落地（滚动定位、导航、
 * 弹层），块内交互全部显式携带事件来源（scopeId 由宿主闭包绑定）。
 *
 * 组件为懒加载列表的行级单元：item/previousBlock 按值传入、行键变化时整体重建，
 * 因此除 @State 外的属性不做响应式观察（对齐 ContentBlockFormula 既有约定）。
 */
@Component
export struct ReaderBlockView {
  item: ReaderBlock = {
    id: '',
    kind: ReaderBlockKind.PARAGRAPH,
    text: '',
    sourceUrl: '',
    inlineRuns: []
  };
  /** 同一文档中上一个正文块：计算标题/图片/引用前的额外段前留白。 */
  previousBlock: ReaderBlock | undefined = undefined;
  /** 服务端返回的他人划线（segment_infos），按段落 pid 对齐渲染蓝色虚线高亮。 */
  segmentInfos: SegmentInfoParagraph[] = [];
  /** 推荐阅读卡片站内元数据：宿主异步回填后传入；未就绪时卡片回退展示链接地址。 */
  linkCardMeta?: LinkCardMeta = undefined;
  /** 正文内联链接（a[href]）与卡片/参考条目链接点击回调，由宿主决定导航方式。 */
  onLinkClick?: (url: string) => void;
  /** 参考标记点击回调：宿主滚动到文末对应参考条目。 */
  onReferenceClick?: (numero: number) => void;
  /** 参考条目 ↩ 点击回调：宿主滚回点标记前的阅读位置。 */
  onReferenceBack?: (numero: number) => void;
  /** 正文视频卡片点击回调；播放上下文由宿主补齐。 */
  onVideoOpen?: (videoId: string) => void;
  /** 点击他人划线高亮片段回调（打开点赞/评论面板）。 */
  onSegmentClick?: (paragraph: SegmentInfoParagraph, markIndex: number) => void;
  /** 正文区域双击回调（宿主按共享偏好执行动作）。 */
  onBodyDoubleTap?: () => void;
  /**
   * 正文选区状态回调：active=true 表示存在选区（长按建词/拖选扩展中），宿主据此
   * 挂起回答切换过滑手势——过滑 pan 是 parallelGesture，与 Text 内部拖选并行识别。
   */
  onBodySelectionActive?: (active: boolean) => void;

  /** 正文双击识别器；宿主可传入文档共享实例，以便列表滚动时统一抑制双击。 */
  bodyTapDetector: DoubleTapDetector = new DoubleTapDetector();
  /** 正文当前是否存在选区：onTextSelectionChange 回填去重，仅作信号，不参与渲染。 */
  private bodySelectionActive: boolean = false;
  /**
   * 双击后临时禁选窗口：系统 Text 的"双击选词"在第二击抬起后才判定，且不经过
   * onGestureJudgeBegin（实测长按路径即使进 judge，REJECT 也拦不住选词），唯一能
   * 够拦下它的是让 Text 在双击序列内处于 copyOption(None) 不可选状态。双击识别
   * 命中（第二击按下）即置位，短暂窗口后恢复，长按选词（无前置双击）不受影响。
   */
  @State private bodySelectionSuppressed: boolean = false;
  private bodySelectionRestoreTimerId: number = -1;
  /** 卡片封面加载失败：本块只渲染一张封面，块级布尔即可。 */
  @State private cardCoverFailed: boolean = false;

  /** 排版偏好（AppStorage 广播，键名与持久化键同名，对齐上游 contentFontSize 等）。 */
  @StorageProp('contentFontSize') @Watch('onFontSizeChanged') private fontSizePercent: number = 100;
  @StorageProp('contentLineHeight') private lineHeightPercent: number = 160;
  @StorageProp('contentBlockSpacing') private blockSpacingPercent: number = 100;
  @StorageProp('contentTypographyPreset') private typographyPreset: string = 'comfortable';
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  /**
   * 主题切换 tick（EntryAbility 系统深浅色联动 / 设置页切换主题时递增）：
   * 按奇偶用 if/else 分支翻转强制重建公式组件。公式 PixelMap 的前景色在解码时固化，
   * 主题切换必须整体重解码；而公式组件在原实例上清空重载（@Watch + 清缓存再异步回填）
   * 在 Text+ForEach+ImageSpan 子树上不生效（实测重载成功但 UI 永远停在回退分支），
   * 因此改为整体销毁重建：新实例走 aboutToAppear 首载路径（实测可靠），且创建时直读
   * AppStorage 当前 formulaForegroundColor，天然免疫"颜色与 tick 两个 @StorageProp
   * 广播时序竞态"。
   */
  @StorageProp('appearanceThemeTick') private formulaRecreateTick: number = 0;
  /**
   * 字号变化 tick：字号档位变化时递增。公式栅格按载入时字号密度解码
   * （见 formulaDecodeDensity），字号调整后需整体销毁重建公式组件才能按新密度
   * 重新解码；与主题 tick 同用 if/else 翻转分支的强制重建机制（实测可靠）。
   * 行高/段间距不影响公式栅格，不触发。
   */
  @State private formulaDecodeTick: number = 0;
  private lastDecodedFontSizePercent: number = 100;

  aboutToAppear(): void {
    this.lastDecodedFontSizePercent = this.fontSizePercent;
  }

  aboutToDisappear(): void {
    if (this.bodySelectionRestoreTimerId >= 0) {
      clearTimeout(this.bodySelectionRestoreTimerId);
      this.bodySelectionRestoreTimerId = -1;
    }
    // 组件销毁不触发 onTextSelectionChange：行被回收时清掉残留的选区信号，
    // 避免宿主过滑手势被永久挂起。
    this.setBodySelectionActive(false);
  }

  private onFontSizeChanged(): void {
    if (this.fontSizePercent !== this.lastDecodedFontSizePercent) {
      this.lastDecodedFontSizePercent = this.fontSizePercent;
      this.formulaDecodeTick += 1;
    }
  }

  /** 正文字号（fp，`Text.fontSize` 传 number 即 fp）：16 × 字号%，默认 16 == 改造前 16fp。 */
  private bodyFontSize(): number {
    return readerBodyFontSize(this.fontSizePercent, this.typographyPreset);
  }

  /** 正文行高（fp）：行高 160% ↔ 改造前的 30，见 ReaderTypography 的归一说明。 */
  private bodyLineHeight(): number {
    return readerBodyLineHeight(this.fontSizePercent, this.lineHeightPercent, this.typographyPreset);
  }

  /** 段间距/块间距（vp）：12 × 段间距%，默认 12 == 改造前。 */
  private blockSpacing(): number {
    return readerBlockSpacing(this.blockSpacingPercent, this.typographyPreset);
  }

  /** 标题字号（fp）：20 × 字号%，默认 20 == 改造前 heading_font_size。 */
  private headingFontSize(): number {
    return readerHeadingFontSize(this.fontSizePercent);
  }

  /** 参考条目字号（fp）：脚注样式取正文的 85%。 */
  private referenceFontSize(): number {
    return this.bodyFontSize() * 0.85;
  }

  build() {
    Column() {
      this.blockContent()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: (this.item.quoteDepth ?? 0) > 0 ? 12 : 0
    })
    .margin({
      left: Math.min(Math.max((this.item.quoteDepth ?? 0) - 1, 0), 4) * 8,
      top: readerBlockLeadingSpace(this.item, this.previousBlock, this.blockSpacing())
    })
    .borderWidth({ left: (this.item.quoteDepth ?? 0) > 0 ? 2 : 0 })
    .borderColor($r('app.color.reader_quote_border'))
  }

  @Builder
  private blockContent() {
    if (this.item.kind === ReaderBlockKind.HEADING) {
      if (this.item.inlineRuns.length > 0) {
        Text() {
          this.styledSpanChildren(this.item, true, this.headingFontSize())
        }
        .fontSize(this.headingFontSize())
        .fontWeight(FontWeight.Bold)
        .copyOption(this.bodySelectionSuppressed ? CopyOptions.None : CopyOptions.LocalDevice)
        .onTouch((event: TouchEvent): void => {
          this.onBodyTouch(event);
        })
        .onTextSelectionChange((start: number, end: number): void => {
          this.onBodySelectionChange(start, end);
        })
        .width('100%')
      } else {
        Text() {
          ForEach(splitTextByHighlights(this.item.text, this.blockSegments(this.item)), (seg: HighlightSegment) => {
            Span(seg.text)
              .fontColor($r('app.color.primary_text'))
              .decoration({
                type: seg.segmentRef !== undefined ? TextDecorationType.Underline : TextDecorationType.None,
                style: seg.segmentRef !== undefined ? TextDecorationStyle.DASHED : TextDecorationStyle.SOLID,
                color: seg.segmentRef !== undefined ? this.resolvedThemeColor : Color.Transparent
              })
              .onClick((): void => {
                if (seg.segmentRef !== undefined && this.onSegmentClick !== undefined) {
                  this.bodyTapDetector.markForeignClick();
                  this.onSegmentClick(seg.segmentRef.paragraph, seg.segmentRef.markIndex);
                }
              })
          }, (seg: HighlightSegment): string => `h:${seg.segmentRef !== undefined ? 's' : 'n'}:${seg.text}`)
        }
        .fontSize(this.headingFontSize())
        .fontWeight(FontWeight.Bold)
        .copyOption(this.bodySelectionSuppressed ? CopyOptions.None : CopyOptions.LocalDevice)
        .onTouch((event: TouchEvent): void => {
          this.onBodyTouch(event);
        })
        .onTextSelectionChange((start: number, end: number): void => {
          this.onBodySelectionChange(start, end);
        })
        .width('100%')
      }
    } else if (this.item.kind === ReaderBlockKind.DIVIDER) {
      Divider().margin({ top: 8, bottom: 8 })
    } else if (this.item.kind === ReaderBlockKind.REFERENCE) {
      this.referenceEntryBlock(this.item)
    } else if (this.item.kind === ReaderBlockKind.LINK_CARD) {
      this.linkCardBlock(this.item)
    } else if (this.item.kind === ReaderBlockKind.FORMULA) {
      // 按主题/字号 tick 奇偶翻转分支强制销毁重建（见 formulaRecreateTick/formulaDecodeTick 注释）。
      if ((this.formulaRecreateTick + this.formulaDecodeTick) % 2 === 0) {
        ContentBlockFormula({ item: this.item, onBodySelectionActive: (active: boolean): void => {
          this.setBodySelectionActive(active);
        } })
      } else {
        ContentBlockFormula({ item: this.item, onBodySelectionActive: (active: boolean): void => {
          this.setBodySelectionActive(active);
        } })
      }
    } else if (this.item.kind === ReaderBlockKind.IMAGE) {
      ReaderImageBlock({
        item: this.item,
        captionSpacing: this.blockSpacing() * 0.5,
        captionFontSize: this.bodyFontSize() * 0.8125,
        captionLineHeight: readerCaptionLineHeightFp(this.bodyFontSize(), this.bodyLineHeight()),
        secondaryTextColor: $r('app.color.secondary_text'),
        onPreview: (url: string): void => {
          // 全屏查看器由页面根 Stack 叠层渲染（AppStorage 广播）：正文组件处于列表
          // 惰性树内，本地渲染全屏层会受标题栏约束，且模态覆盖层树不响应状态更新。
          AppStorage.setOrCreate('imagePreviewUrl', url);
        }
      })
    } else if (this.item.kind === ReaderBlockKind.VIDEO) {
      this.videoBlock(this.item)
    } else if (this.item.inlineRuns.length > 0) {
      // 含行内公式的段落走公式宿主；其余 styled runs 走统一样式渲染（划线叠加保留）。
      if (this.inlineHasFormula(this.item)) {
        // 按主题/字号 tick 奇偶翻转分支强制销毁重建（见 formulaRecreateTick/formulaDecodeTick 注释）。
        if ((this.formulaRecreateTick + this.formulaDecodeTick) % 2 === 0) {
          ContentInlineFormula({ item: this.item, onLinkClick: (url: string): void => {
            this.onLinkClick?.(url);
          }, onReferenceClick: (numero: number): void => this.onReferenceClick?.(numero),
            onBodySelectionActive: (active: boolean): void => {
              this.setBodySelectionActive(active);
            } })
        } else {
          ContentInlineFormula({ item: this.item, onLinkClick: (url: string): void => {
            this.onLinkClick?.(url);
          }, onReferenceClick: (numero: number): void => this.onReferenceClick?.(numero),
            onBodySelectionActive: (active: boolean): void => {
              this.setBodySelectionActive(active);
            } })
        }
      } else {
        Text() {
          this.styledSpanChildren(this.item, false, this.bodyFontSize())
        }
        .fontSize(this.bodyFontSize())
        .lineHeight(this.bodyLineHeight())
        .copyOption(this.bodySelectionSuppressed ? CopyOptions.None : CopyOptions.LocalDevice)
        .onTouch((event: TouchEvent): void => {
          this.onBodyTouch(event);
        })
        .onTextSelectionChange((start: number, end: number): void => {
          this.onBodySelectionChange(start, end);
        })
        .width('100%')
      }
    } else {
      Text() {
        if (this.item.kind === ReaderBlockKind.LIST_ITEM) {
          Span('• ')
        }
        ForEach(splitTextByHighlights(this.item.text, this.blockSegments(this.item)), (seg: HighlightSegment) => {
          Span(seg.text)
            .fontColor($r('app.color.primary_text'))
            .decoration({
              type: seg.segmentRef !== undefined ? TextDecorationType.Underline : TextDecorationType.None,
              style: seg.segmentRef !== undefined ? TextDecorationStyle.DASHED : TextDecorationStyle.SOLID,
              color: seg.segmentRef !== undefined ? this.resolvedThemeColor : Color.Transparent
            })
            .onClick((): void => {
              if (seg.segmentRef !== undefined && this.onSegmentClick !== undefined) {
                this.bodyTapDetector.markForeignClick();
                this.onSegmentClick(seg.segmentRef.paragraph, seg.segmentRef.markIndex);
              }
            })
        }, (seg: HighlightSegment): string => `p:${seg.segmentRef !== undefined ? 's' : 'n'}:${seg.text}`)
      }
      .fontSize(this.bodyFontSize())
      .lineHeight(this.bodyLineHeight())
      .copyOption(this.bodySelectionSuppressed ? CopyOptions.None : CopyOptions.LocalDevice)
      .onTouch((event: TouchEvent): void => {
        this.onBodyTouch(event);
      })
      .onTextSelectionChange((start: number, end: number): void => {
        this.onBodySelectionChange(start, end);
      })
      .width('100%')
    }
  }

  /** 正文视频卡片：封面 + 播放按钮，点击回调宿主（播放上下文由宿主补齐）。 */
  @Builder
  private videoBlock(item: ReaderBlock) {
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
    .id(`content_video_${item.targetId ?? 'invalid'}`)
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
  }

  /** 推荐阅读卡片：封面 + 标题 + 站内元数据行（回退为链接地址），点击走链接回调。 */
  @Builder
  private linkCardBlock(item: ReaderBlock) {
    Row({ space: 12 }) {
      if ((item.coverUrl ?? '').length > 0 && !this.cardCoverFailed) {
        Image(item.coverUrl ?? '')
          .id(`content_link_cover_${item.id}`)
          .width(64)
          .height(64)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .clip(true)
          .accessibilityLevel('no')
          .onError((): void => {
            this.cardCoverFailed = true;
          })
      }
      Column({ space: 6 }) {
        Text(item.text)
          .fontSize(this.bodyFontSize())
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        // 站内资源回填元数据后展示 `赞同 X · 评论 Y · 类型`（对齐网页卡片 meta 行）；
        // 外链/拉取失败回退为展示链接地址。
        if (this.linkCardMeta !== undefined) {
          Text(linkCardMetaLine(this.linkCardMeta))
            .fontSize(this.referenceFontSize())
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else if ((item.displayUrl ?? item.sourceUrl).length > 0 &&
          (item.displayUrl ?? item.sourceUrl) !== item.text) {
          Text(item.displayUrl ?? item.sourceUrl)
            .fontSize(this.referenceFontSize())
            .fontColor(this.resolvedThemeColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
    }
    .id(`content_link_card_${item.id}`)
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_background'))
    .borderWidth(1)
    .borderColor($r('app.color.secondary_text'))
    .onClick((): void => {
      if (item.sourceUrl.length > 0) {
        this.bodyTapDetector.markForeignClick();
        this.onLinkClick?.(item.sourceUrl);
      }
    })
  }

  /** 文末参考条目行（对齐上游脚注定义渲染：[N] + ↩ 返回 + 说明文本 + 可点击链接，脚注字号）。 */
  @Builder
  private referenceEntryBlock(item: ReaderBlock) {
    Row({ space: 8 }) {
      Text(`[${item.reference?.numero ?? ''}]`)
        .fontSize(this.referenceFontSize())
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
        .fontSize(this.referenceFontSize())
        .fontColor([this.resolvedThemeColor])
        .onClick((): void => {
          if (item.reference !== undefined) {
            this.bodyTapDetector.markForeignClick();
            this.onReferenceBack?.(item.reference.numero);
          }
        })
        .id(`reader_reference_back_${item.id}`)
        .accessibilityText('返回正文引用位置')
      Column({ space: 4 }) {
        if (item.text.length > 0) {
          Text(item.text)
            .fontSize(this.referenceFontSize())
            .fontColor($r('app.color.primary_text'))
            .width('100%')
        }
        if ((item.reference?.url ?? '').length > 0) {
          Text(item.reference?.url ?? '')
            .fontSize(this.referenceFontSize())
            .fontColor(this.resolvedThemeColor)
            .wordBreak(WordBreak.BREAK_ALL)
            .width('100%')
            .onClick((): void => {
              const url = item.reference?.url ?? '';
              if (url.length > 0) {
                this.onLinkClick?.(url);
              }
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  /** 内联 runs 是否含公式 run（决定段落走公式宿主还是统一样式渲染）。 */
  private inlineHasFormula(item: ReaderBlock): boolean {
    return item.inlineRuns.some((run: ReaderInlineRun): boolean => run.kind === ReaderInlineKind.FORMULA);
  }

  /** 选区变化入口：建词/扩展置 active，清除（start==end）复位；去重后转发宿主。 */
  private onBodySelectionChange(start: number, end: number): void {
    this.setBodySelectionActive(start !== end);
  }

  private setBodySelectionActive(active: boolean): void {
    if (active === this.bodySelectionActive) { return; }
    this.bodySelectionActive = active;
    const callback = this.onBodySelectionActive;
    if (callback !== undefined) {
      callback(active);
    }
  }

  /** 正文 Text 原始触摸入口：喂给双击识别器，识别到双击上报宿主（见 DoubleTapDetector 注释）。 */
  private onBodyTouch(event: TouchEvent): void {
    if (this.bodyTapDetector.feed(event)) {
      this.suppressBodySelection();
      const callback = this.onBodyDoubleTap;
      if (callback !== undefined) {
        callback();
      }
    }
  }

  /** 双击命中即临时关掉正文选择（见 bodySelectionSuppressed 注释）。窗口结束后恢复，
   * 期间再次双击则顺延；纯长按选词没有前置双击，不受影响。 */
  private suppressBodySelection(): void {
    this.bodySelectionSuppressed = true;
    if (this.bodySelectionRestoreTimerId >= 0) {
      clearTimeout(this.bodySelectionRestoreTimerId);
    }
    this.bodySelectionRestoreTimerId = setTimeout((): void => {
      this.bodySelectionRestoreTimerId = -1;
      this.bodySelectionSuppressed = false;
    }, DOUBLE_TAP_SELECTION_SUPPRESS_MS);
  }

  /**
   * 展平内联 runs × 他人划线：划线偏移按段落文本对齐，含公式 run 时偏移无法
   * 与纯文本逐字对齐，退化为不叠加划线（公式段落原本也不参与划线渲染）。
   */
  private styledSegments(item: ReaderBlock): Array<StyledTextSegment> {
    return flattenStyledTextSegments(item.inlineRuns, item.text,
      this.inlineHasFormula(item) ? [] : this.blockSegments(item));
  }

  /** 统一样式渲染的 Span 序列（列表项圆点与纯文本路径一致）。 */
  @Builder
  private styledSpanChildren(item: ReaderBlock, baseBold: boolean, fontSizeVp: number) {
    if (item.kind === ReaderBlockKind.LIST_ITEM) {
      Span('• ')
    }
    ForEach(this.styledSegments(item), (seg: StyledTextSegment, index: number) => {
      this.styledSpan(seg, baseBold, fontSizeVp)
    }, (seg: StyledTextSegment, index: number): string => `${index}:${seg.text}`)
  }

  /**
   * 单个样式化 Span：加粗/斜体/删除线/行内代码/高亮/上下标/链接 + 他人划线虚线叠加。
   * code 与其余样式互斥分支（fontFamily 无中性值可传）；链接色跟随主题色。
   */
  @Builder
  private styledSpan(seg: StyledTextSegment, baseBold: boolean, fontSizeVp: number) {
    if (seg.code) {
      Span(seg.text)
        .fontSize(seg.superscript || seg.subscript ? fontSizeVp * 0.75 : fontSizeVp)
        .fontWeight(seg.bold || baseBold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(seg.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily('monospace')
        .fontColor(seg.linkUrl.length > 0 || seg.referenceNumero !== undefined
          ? this.resolvedThemeColor : $r('app.color.primary_text'))
        .textBackgroundStyle({ color: '#14808080', radius: 3 })
        .decoration({
          type: seg.segmentRef !== undefined ? TextDecorationType.Underline :
            (seg.strikethrough ? TextDecorationType.LineThrough : TextDecorationType.None),
          style: seg.segmentRef !== undefined ? TextDecorationStyle.DASHED : TextDecorationStyle.SOLID,
          color: seg.segmentRef !== undefined ? this.resolvedThemeColor : Color.Transparent
        })
        .baselineOffset(seg.superscript ? LengthMetrics.vp(fontSizeVp * 0.35) :
          (seg.subscript ? LengthMetrics.vp(-fontSizeVp * 0.18) : LengthMetrics.vp(0)))
        .onClick((): void => {
          this.handleStyledSpanClick(seg);
        })
    } else {
      Span(seg.text)
        .fontSize(seg.superscript || seg.subscript ? fontSizeVp * 0.75 : fontSizeVp)
        .fontWeight(seg.bold || baseBold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(seg.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontColor(seg.linkUrl.length > 0 || seg.referenceNumero !== undefined
          ? this.resolvedThemeColor : $r('app.color.primary_text'))
        .textBackgroundStyle(seg.mark ? { color: '#66FDD835', radius: 3 } : { color: Color.Transparent, radius: 0 })
        .decoration({
          type: seg.segmentRef !== undefined ? TextDecorationType.Underline :
            (seg.strikethrough ? TextDecorationType.LineThrough : TextDecorationType.None),
          style: seg.segmentRef !== undefined ? TextDecorationStyle.DASHED : TextDecorationStyle.SOLID,
          color: seg.segmentRef !== undefined ? this.resolvedThemeColor : Color.Transparent
        })
        .baselineOffset(seg.superscript ? LengthMetrics.vp(fontSizeVp * 0.35) :
          (seg.subscript ? LengthMetrics.vp(-fontSizeVp * 0.18) : LengthMetrics.vp(0)))
        .onClick((): void => {
          this.handleStyledSpanClick(seg);
        })
    }
  }

  /** 样式片段点击：链接优先于参考跳转，参考标记优先于他人划线面板。 */
  private handleStyledSpanClick(seg: StyledTextSegment): void {
    if (seg.linkUrl.length > 0) {
      this.bodyTapDetector.markForeignClick();
      if (this.onLinkClick !== undefined) {
        this.onLinkClick(seg.linkUrl);
      }
      return;
    }
    if (seg.referenceNumero !== undefined && seg.referenceNumero > 0) {
      this.bodyTapDetector.markForeignClick();
      this.onReferenceClick?.(seg.referenceNumero);
      return;
    }
    if (seg.segmentRef !== undefined && this.onSegmentClick !== undefined) {
      this.bodyTapDetector.markForeignClick();
      this.onSegmentClick(seg.segmentRef.paragraph, seg.segmentRef.markIndex);
    }
  }

  /** 本块对应的他人划线引用（按 data-pid 对齐 segment_infos）。@Builder 体内禁止非 UI 语句，故提为方法。 */
  private blockSegments(item: ReaderBlock): Array<SegmentHighlightRef> {
    if (item.pid === undefined || item.pid.length === 0 || this.segmentInfos.length === 0) {
      return [];
    }
    const paragraph = this.segmentInfos.find((p: SegmentInfoParagraph): boolean => p.pid === item.pid);
    if (paragraph === undefined) {
      return [];
    }
    const refs: Array<SegmentHighlightRef> = [];
    paragraph.marks.forEach((mark: SegmentInfoMark, index: number): void => {
      if (effectiveSegmentMeta(mark) !== undefined) {
        refs.push({ paragraph: paragraph, markIndex: index });
      }
    });
    return refs;
  }
}
