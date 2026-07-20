import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ReaderBlockDataSource } from '../reader/ReaderBlockDataSource';
import {
  parseZhihuHtml,
  ReaderBlock,
  ReaderBlockKind,
  readerDocumentStats
} from '../reader/ReaderDocument';

function formulaMarkup(url: string): string {
  if (!url.startsWith('https://www.zhihu.com/equation?tex=')) {
    return '<html><body></body></html>';
  }
  const safeUrl = url.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  return `<html><head><meta name="viewport" content="width=device-width,initial-scale=1.0">` +
    `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https://www.zhihu.com; ` +
    `style-src 'unsafe-inline'">` +
    `<style>html,body{margin:0;background:#f5f5f5;height:100%;overflow:hidden}` +
    `body{display:flex;align-items:center;justify-content:center}` +
    `img{max-width:100%;max-height:100%}</style></head><body><img src="${safeUrl}"></body></html>`;
}

@Component
export struct ReaderProbe {
  onBack: () => void = () => {};
  @State private status: string = '正在载入真实长正文…';
  @State private formulaStatus: string = '公式节点等待进入可见区域';
  private readonly dataSource: ReaderBlockDataSource = new ReaderBlockDataSource();

  aboutToAppear(): void {
    this.loadDocument();
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回')
          .id('p0_reader_back')
          .onClick(() => this.onBack())

        Column({ space: 4 }) {
          Text('原生长正文验证')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text(this.status)
            .id('p0_reader_status')
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
          Text(this.formulaStatus)
            .id('p0_formula_status')
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
      .id('p0_reader_list')
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      .cachedCount(6)
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
      Column({ space: 6 }) {
        // 知乎公式端点返回 SVG；API 20 的 Image 无法稳定加载，故只在公式节点使用受限 RichText。
        RichText(formulaMarkup(item.formulaUrl))
          .id(`p0_formula_${item.id}`)
          .width('100%')
          .height(80)
          .onStart(() => {
            this.formulaStatus = '受限公式节点正在加载';
          })
          .onComplete(() => {
            this.formulaStatus = '受限公式节点已完成加载；正文保持原生';
          })
        Text(item.text)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .padding(8)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
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
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const bytes = await context.resourceManager.getRawFileContent('reader_probe.html');
      const html = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const blocks = parseZhihuHtml(html);
      const stats = readerDocumentStats(blocks);
      this.dataSource.replace(blocks);
      this.status = `${stats.blockCount} 个原生块 · ${stats.textLength} 字符 · ${stats.formulaCount} 个块公式`;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.status = `长正文载入失败：${message}`;
    }
  }
}
