import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
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
  ReaderInlineRun,
  readerDocumentStats
} from 'reader';

function inlineFormulaWidth(tex: string): number {
  return Math.min(220, Math.max(20, tex.length * 9));
}

@Component
struct ReaderInlineFormulaBlock {
  item: ReaderBlock = {
    id: '',
    kind: ReaderBlockKind.PARAGRAPH,
    text: '',
    sourceUrl: '',
    inlineRuns: []
  };
  onFormulaDecoded: (id: string) => void = () => {};
  onFormulaFailed: (id: string, reason: string) => void = () => {};
  @State private failedRunIds: Array<string> = [];
  @State private loadedRunIds: Array<string> = [];
  private pixelMaps: Map<string, image.PixelMap> = new Map();
  private active: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.loadGeneration += 1;
    const generation = this.loadGeneration;
    this.item.inlineRuns.forEach((run: ReaderInlineRun) => {
      if (run.kind === ReaderInlineKind.FORMULA) {
        this.loadFormula(run, generation);
      }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadGeneration += 1;
    this.loadedRunIds = [];
    this.pixelMaps.forEach((pixelMap: image.PixelMap) => {
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
        if (run.kind === ReaderInlineKind.TEXT) {
          Span(run.text)
        } else if (!this.loadedRunIds.includes(run.id)) {
          Span(`「${run.text}」`)
            .fontColor($r('app.color.secondary_text'))
        } else {
          if (this.pixelMaps.get(run.id) !== undefined) {
            ImageSpan(this.pixelMaps.get(run.id) ?? run.text)
              .id(`inline_formula_${run.id}`)
              .width(inlineFormulaWidth(run.text))
              .height(24)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
              .onError(() => {
                this.failFormula(run.id, 'ImageSpan 展示失败');
              })
          } else {
            Span(`「${run.text}」`)
              .fontColor($r('app.color.secondary_text'))
          }
        }
      }, (run: ReaderInlineRun) => run.id)
    }
    .fontSize(18)
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
      this.onFormulaDecoded(run.id);
    } catch (error) {
      if (this.active) {
        const reason = error instanceof Error ? error.message : '公式加载失败';
        this.failFormula(run.id, reason);
      }
    }
  }

  private async formulaCookieHeader(): Promise<string> {
    const context = this.getUIContext().getHostContext();
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

  private failFormula(id: string, reason: string): void {
    if (!this.failedRunIds.includes(id)) {
      const pixelMap = this.pixelMaps.get(id);
      this.pixelMaps.delete(id);
      pixelMap?.release();
      this.loadedRunIds = this.loadedRunIds.filter((loadedId: string) => loadedId !== id);
      this.failedRunIds = this.failedRunIds.concat(id);
      this.onFormulaFailed(id, reason);
    }
  }
}

@Component
struct ReaderBlockFormulaBlock {
  item: ReaderBlock = {
    id: '',
    kind: ReaderBlockKind.FORMULA,
    text: '',
    sourceUrl: '',
    inlineRuns: []
  };
  onFormulaDecoded: (id: string) => void = () => {};
  onFormulaFailed: (id: string, reason: string) => void = () => {};
  @State private failed: boolean = false;
  @State private pixelMap: image.PixelMap | undefined = undefined;
  private active: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.loadGeneration += 1;
    this.loadFormula(this.loadGeneration);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadGeneration += 1;
    this.releasePixelMap();
  }

  build() {
    Column({ space: 6 }) {
      if (this.pixelMap !== undefined && !this.failed) {
        Image(this.pixelMap)
          .id(`formula_${this.item.id}`)
          .width('100%')
          .height(88)
          .objectFit(ImageFit.Contain)
          .onError(() => {
            this.failed = true;
            this.releasePixelMap();
            this.onFormulaFailed(this.item.id, 'Image 展示失败');
          })
      } else {
        Text(this.item.text)
          .id(`formula_fallback_${this.item.id}`)
          .fontSize(16)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#F5F5F5')
    .borderRadius(8)
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
      this.onFormulaDecoded(this.item.id);
    } catch (error) {
      if (this.active) {
        this.failed = true;
        const reason = error instanceof Error ? error.message : '公式加载失败';
        this.onFormulaFailed(this.item.id, reason);
      }
    }
  }

  private async formulaCookieHeader(): Promise<string> {
    const context = this.getUIContext().getHostContext();
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
export struct ReaderProbe {
  onBack: () => void = () => {};
  @State private status: string = '正在载入真实长正文…';
  @State private formulaStatus: string = '公式节点等待进入可见区域';
  @State private previewUrl: string = '';
  @State private formulaCount: number = 0;
  private decodedFormulaIds: Array<string> = [];
  private failedFormulaIds: Array<string> = [];
  private lastFormulaFailure: string = '';
  private readonly dataSource: ReaderBlockDataSource = new ReaderBlockDataSource();

  aboutToAppear(): void {
    this.loadDocument();
  }

  aboutToDisappear(): void {
    clearFormulaByteCache();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Row({ space: 12 }) {
          Button('返回')
            .id('reader_back')
            .onClick(() => this.onBack())

          Column({ space: 4 }) {
            Text('原生长正文验证')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Text(this.status)
              .id('reader_status')
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
            Text(this.formulaStatus)
              .id('formula_status')
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        Divider()

        List({ space: 12 }) {
          LazyForEach(this.dataSource, (item: ReaderBlock) => {
            ListItem() {
              this.readerBlock(item)
            }
          }, (item: ReaderBlock) => item.id)
        }
        .id('reader_list')
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
        .cachedCount(6)
      }
      .width('100%')
      .height('100%')

      if (this.previewUrl.length > 0) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.previewUrl)
            .id('reader_image_preview')
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
          Button('关闭预览')
            .id('reader_image_preview_close')
            .margin(20)
            .onClick(() => {
              this.previewUrl = '';
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#EE000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private readerBlock(item: ReaderBlock) {
    if (item.kind === ReaderBlockKind.HEADING) {
      Text(item.text)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    } else if (item.kind === ReaderBlockKind.DIVIDER) {
      Divider()
        .margin({ top: 8, bottom: 8 })
    } else if (item.kind === ReaderBlockKind.FORMULA) {
      ReaderBlockFormulaBlock({
        item: item,
        onFormulaDecoded: (id: string) => this.recordFormulaDecoded(id),
        onFormulaFailed: (id: string, reason: string) => this.recordFormulaFailed(id, reason)
      })
    } else if (item.kind === ReaderBlockKind.IMAGE) {
      ReaderImageBlock({
        item: item,
        secondaryTextColor: $r('app.color.secondary_text'),
        onPreview: (url: string) => {
          this.previewUrl = url;
        }
      })
    } else if (item.inlineRuns.length > 0) {
      ReaderInlineFormulaBlock({
        item: item,
        onFormulaDecoded: (id: string) => this.recordFormulaDecoded(id),
        onFormulaFailed: (id: string, reason: string) => this.recordFormulaFailed(id, reason)
      })
    } else {
      Text(item.kind === ReaderBlockKind.LIST_ITEM ? `• ${item.text}` : item.text)
        .fontSize(18)
        .lineHeight(30)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
    }
  }

  private async loadDocument(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('无法获取应用上下文');
      }
      const bytes = await context.resourceManager.getRawFileContent('reader_probe.html');
      const html = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const blocks = parseZhihuHtml(html);
      const stats = readerDocumentStats(blocks);
      this.formulaCount = stats.formulaCount;
      this.dataSource.replace(blocks);
      this.status = `${stats.blockCount} 个原生块 · ${stats.textLength} 字符 · ` +
        `${stats.blockFormulaCount} 个块公式 + ${stats.inlineFormulaCount} 个行内公式 · ` +
        `${stats.imageCount} 张图片`;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.status = `长正文载入失败：${message}`;
    }
  }

  private recordFormulaDecoded(id: string): void {
    this.failedFormulaIds = this.failedFormulaIds.filter((failedId: string) => failedId !== id);
    if (!this.decodedFormulaIds.includes(id)) {
      this.decodedFormulaIds.push(id);
    }
    this.updateFormulaStatus();
  }

  private recordFormulaFailed(id: string, reason: string): void {
    this.decodedFormulaIds = this.decodedFormulaIds.filter((decodedId: string) => decodedId !== id);
    this.lastFormulaFailure = reason;
    if (!this.failedFormulaIds.includes(id)) {
      this.failedFormulaIds.push(id);
    }
    this.updateFormulaStatus();
  }

  private updateFormulaStatus(): void {
    if (this.failedFormulaIds.length > 0) {
      this.formulaStatus = `${this.decodedFormulaIds.length} 个公式原生解码，` +
        `${this.failedFormulaIds.length} 个已降级为 TeX（最近：${this.lastFormulaFailure}）`;
      return;
    }
    this.formulaStatus = `API 24 原生公式已解码 ${this.decodedFormulaIds.length}/${this.formulaCount}`;
  }
}
