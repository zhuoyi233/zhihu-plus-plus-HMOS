import { image } from '@kit.ImageKit';
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
        if (run.kind === ReaderInlineKind.TEXT || !this.loadedRunIds.includes(run.id)) {
          Span(run.kind === ReaderInlineKind.TEXT ? run.text : `「${run.text}」`)
            .fontColor(run.kind === ReaderInlineKind.TEXT
              ? $r('app.color.primary_text')
              : $r('app.color.secondary_text'))
        } else {
          ImageSpan(this.pixelMaps.get(run.id) as image.PixelMap)
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

/** 仅把知乎正文转换为受控 ArkUI 节点；不会执行 HTML、脚本或 WebView 内容。 */
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
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.previewUrl)
            .id('p2_content_image_preview')
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
          Button('关闭预览')
            .id('p2_content_image_preview_close')
            .margin($r('app.float.p1_page_padding'))
            .onClick((): void => {
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
