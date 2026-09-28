import {
  AppReleaseDetail,
  AppReleaseDetailStatus,
  AppUpdateClient,
  DEFAULT_THEME_COLOR,
  flattenBlockquoteInner,
  flattenReleaseMarkdownList,
  formatReleaseDate,
  onThemeColor,
  parseReleaseMarkdown,
  ReleaseMarkdownBlock,
  ReleaseMarkdownBlockKind,
  ReleaseMarkdownDocument,
  ReleaseMarkdownListRow,
  ReleaseMarkdownSpan,
  ReleaseMarkdownSpanKind,
  releaseAlertLabel
} from 'data';
import bundleManager from '@ohos.bundle.bundleManager';

const GITHUB_RELEASES_PAGE: string = 'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases';
/** HdsNavDestination 悬浮标题栏高度（vp）：NavDestination 内容区从状态栏下缘开始，
 * 悬浮标题栏覆盖其上且不自动避让，长内容页需自行让出（模拟器实测 137..332px / 密度3）。 */
const TITLE_BAR_CLEARANCE_VP: number = 65;
/** 列表嵌套层每深一层的缩进（vp）。 */
const LIST_DEPTH_INDENT_VP: number = 18;

/**
 * “新版本更新”页，两种模式：
 * 1. 版本说明（默认）：展示本机已装版本对应 GitHub Release 的描述，版本更迭后首次
 *    启动自动进入（P1Shell 推入），关闭时经 onClosed 通知 P1Shell 持久化“已看过本版本”；
 * 2. 更新内容预览（targetVersionName 非空）：检查到更新后由主页更新卡片/设置页进入，
 *    展示更新目标版本（GitHub 最新 Release）的描述。此模式关闭不写“已看过”标记。
 * 链接点击经 onOpenLink 交由壳层拉起系统浏览器。
 */
@Component
export struct WhatsNewPage {
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private loading: boolean = true;
  @State private errorMessage: string = '';
  @State private detail: AppReleaseDetail | undefined = undefined;
  @State private markdownDocument: ReleaseMarkdownDocument | undefined = undefined;
  /** 更新预览模式的目标版本名；空串表示版本说明模式（展示本机已装版本）。 */
  @Prop targetVersionName: string = '';
  private readonly client: AppUpdateClient = new AppUpdateClient();
  private disposed: boolean = false;
  private installedVersionName: string = '';
  /** 页面关闭时回调，携带实际展示的版本名；壳层据此决定是否记录“已看过本版本”。 */
  onClosed: (shownVersionName: string) => void = (_shownVersionName: string): void => {};
  /** 行内链接/发布页跳转回调，壳层据此拉起系统浏览器。 */
  onOpenLink: (url: string) => void = (_url: string): void => {};

  aboutToAppear(): void {
    void this.loadReleaseDetail();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.client.destroy();
    this.onClosed(this.shownVersionName());
  }

  private shownVersionName(): string {
    return this.targetVersionName.length > 0 ? this.targetVersionName : this.installedVersionName;
  }

  private async loadReleaseDetail(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.installedVersionName = this.readInstalledVersionName();
    const versionName = this.shownVersionName();
    if (versionName.length === 0) {
      this.loading = false;
      this.errorMessage = '无法读取本机版本号，暂时无法获取更新说明';
      return;
    }
    const result = await this.client.fetchReleaseDetail(versionName);
    if (this.disposed) {
      return;
    }
    this.loading = false;
    if (result.status === AppReleaseDetailStatus.OK && result.detail !== undefined) {
      this.detail = result.detail;
      this.markdownDocument = parseReleaseMarkdown(result.detail.body);
      return;
    }
    this.errorMessage = result.message.length > 0 ? result.message : '获取更新说明失败，请稍后重试';
  }

  private readInstalledVersionName(): string {
    try {
      const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return bundle.versionName;
    } catch (_error) {
      return '';
    }
  }

  /** 正文块：文档首部的 H1（“ZhihuPlusPlus-HMOS vX.Y.Z”）与页头版本展示重复，跳过不渲染。 */
  private visibleBlocks(): ReleaseMarkdownBlock[] {
    const document = this.markdownDocument;
    if (document === undefined) {
      return [];
    }
    const blocks = document.blocks;
    if (blocks.length > 0 && blocks[0].kind === ReleaseMarkdownBlockKind.HEADING && blocks[0].level === 1) {
      return blocks.slice(1);
    }
    return blocks;
  }

  private releasePageUrl(): string {
    const detail = this.detail;
    if (detail !== undefined && detail.htmlUrl.length > 0) {
      return detail.htmlUrl;
    }
    if (this.targetVersionName.length > 0) {
      return `${GITHUB_RELEASES_PAGE}/tag/HMOSv${this.targetVersionName}`;
    }
    return GITHUB_RELEASES_PAGE;
  }

  build() {
    Scroll() {
      Column({ space: 24 }) {
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(32).height(32).color(this.resolvedThemeColor)
            Text('正在获取更新说明…').id('p8_whats_new_loading')
              .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
          }.width('100%').margin({ top: 48 })
        } else if (this.errorMessage.length > 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.info_circle')).fontSize(36)
              .fontColor([$r('app.color.secondary_text')])
            Text(this.errorMessage).id('p8_whats_new_error_message')
              .fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center).width('100%')
            Button('重试').id('p8_whats_new_retry')
              .fontColor(onThemeColor(this.resolvedThemeColor))
              .backgroundColor(this.resolvedThemeColor)
              .onClick((): void => {
                void this.loadReleaseDetail();
              })
          }.width('100%').margin({ top: 48 })
        } else {
          this.releaseHeader()
          Text('更新内容').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.secondary_text')).width('100%')
          this.markdownBlocks()
        }
        if (!this.loading && this.targetVersionName.length > 0) {
          this.downloadFooter()
        }
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: TITLE_BAR_CLEARANCE_VP + 16, bottom: 48 })
    }
    .id('p8_whats_new_scroll')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private releaseHeader() {
    Column({ space: 14 }) {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18)
            .fontColor([onThemeColor(this.resolvedThemeColor)])
        }.width(36).height(36).borderRadius(12).backgroundColor(this.resolvedThemeColor)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        Text(this.targetVersionName.length > 0 ? '发现新版本' : '当前版本')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.secondary_text'))
        Text(`v${this.detail?.versionName ?? ''}`).id('p8_whats_new_version')
          .fontSize(34).fontWeight(FontWeight.Bold).fontColor($r('app.color.primary_text'))
        if (this.targetVersionName.length > 0 && this.installedVersionName.length > 0) {
          Text(`当前 v${this.installedVersionName}  →  新版 v${this.targetVersionName}`)
            .id('p8_whats_new_upgrade_hint')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor(this.resolvedThemeColor)
        }
        if (this.detail !== undefined && formatReleaseDate(this.detail.publishedAt).length > 0) {
          Text(`发布于 ${formatReleaseDate(this.detail.publishedAt)}`)
            .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding(20).borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row() {
          Text('在 GitHub 查看完整发布说明').fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18)
            .fontColor([$r('app.color.secondary_text')])
        }.width('100%').justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Center)
      }.id('p8_whats_new_open_release').width('100%')
      .padding({ top: 8, bottom: 8, left: 2, right: 2 })
      .backgroundColor(Color.Transparent)
      .onClick((): void => {
        this.onOpenLink(this.releasePageUrl());
      })
    }.width('100%')
  }

  @Builder
  private downloadFooter() {
    Column({ space: 10 }) {
      Text('准备升级？').fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text')).width('100%')
      Text('前往 GitHub 发布页获取未签名安装包')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text')).width('100%')
      Button('下载新版本').id('p8_whats_new_download').width('100%').height(48)
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .onClick((): void => this.onOpenLink(this.releasePageUrl()))
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ top: 20 })
  }

  @Builder
  private markdownBlocks() {
    Column({ space: 18 }) {
      ForEach(this.visibleBlocks(), (block: ReleaseMarkdownBlock, index: number) => {
        this.markdownBlock(block)
      }, (block: ReleaseMarkdownBlock, index: number): string =>
        `${index}:${block.kind}:${block.level}:${block.alert}:${block.spans.length}:${block.items.length}`)
      if (this.visibleBlocks().length === 0) {
        Text('本次更新没有填写发布说明').id('p8_whats_new_empty')
          .fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.secondary_text'))
      }
    }.width('100%')
  }

  @Builder
  private markdownBlock(block: ReleaseMarkdownBlock) {
    if (block.kind === ReleaseMarkdownBlockKind.HEADING) {
      this.headingBlock(block)
    } else if (block.kind === ReleaseMarkdownBlockKind.PARAGRAPH) {
      Text() {
        this.inlineSpans(block.spans, $r('app.float.p1_body_font_size'), false)
      }.width('100%')
    } else if (block.kind === ReleaseMarkdownBlockKind.LIST) {
      this.listRows(flattenReleaseMarkdownList(block.items, block.ordered, block.startNumber))
    } else if (block.kind === ReleaseMarkdownBlockKind.BLOCKQUOTE) {
      this.quoteCard(block)
    }
  }

  @Builder
  private headingBlock(block: ReleaseMarkdownBlock) {
    Text() {
      this.inlineSpans(block.spans, this.headingFontSize(block.level), true)
    }
    .width('100%')
    .fontColor(block.level === 2 ? this.resolvedThemeColor : $r('app.color.primary_text'))
    .margin({ top: block.level === 2 ? 12 : 4 })
  }

  private headingFontSize(level: number): number {
    if (level <= 1) {
      return 22;
    }
    if (level === 2) {
      return 18;
    }
    return 16;
  }

  @Builder
  private listRows(rows: ReleaseMarkdownListRow[]) {
    Column({ space: 10 }) {
      ForEach(rows, (row: ReleaseMarkdownListRow, index: number) => {
        Row({ space: 8 }) {
          if (row.number > 0) {
            Text(`${row.number}.`).fontSize(14).fontColor($r('app.color.secondary_text'))
              .width(20).textAlign(TextAlign.End)
          } else {
            Text('•').fontSize(16).fontColor(this.resolvedThemeColor)
              .width(20).textAlign(TextAlign.End)
          }
          Text() {
            this.inlineSpans(row.spans, $r('app.float.p1_body_font_size'), false)
          }.layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: row.depth * LIST_DEPTH_INDENT_VP })
        .id(`p8_whats_new_list_row_${index}`)
      }, (row: ReleaseMarkdownListRow, index: number): string =>
        `${index}:${row.depth}:${row.number}:${row.spans.length}`)
    }.width('100%')
  }

  @Builder
  private quoteCard(quote: ReleaseMarkdownBlock) {
    // 左侧强调条用 border-left 实现（随内容自适应高度）；子元素高度 '100%' 会在
    // Row 中被解析成父级剩余整屏高度，不能用（实测画成整屏竖条）。
    Column({ space: 8 }) {
      if (releaseAlertLabel(quote.alert).length > 0) {
        Text(releaseAlertLabel(quote.alert))
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolvedThemeColor)
      }
      ForEach(flattenBlockquoteInner(quote), (inner: ReleaseMarkdownBlock, index: number) => {
        this.quoteInnerBlock(inner)
      }, (inner: ReleaseMarkdownBlock, index: number): string =>
        `${index}:${inner.kind}:${inner.level}:${inner.spans.length}:${inner.items.length}`)
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .border({
      width: { left: 4 },
      color: { left: quote.alert.length > 0 ? this.resolvedThemeColor : '#33808080' }
    })
  }

  @Builder
  private quoteInnerBlock(inner: ReleaseMarkdownBlock) {
    if (inner.kind === ReleaseMarkdownBlockKind.HEADING) {
      Text() {
        this.inlineSpans(inner.spans, $r('app.float.p1_body_font_size'), true)
      }.width('100%')
    } else if (inner.kind === ReleaseMarkdownBlockKind.PARAGRAPH) {
      Text() {
        this.inlineSpans(inner.spans, $r('app.float.p1_body_font_size'), false)
      }.width('100%')
    } else if (inner.kind === ReleaseMarkdownBlockKind.LIST) {
      this.listRows(flattenReleaseMarkdownList(inner.items, inner.ordered, inner.startNumber))
    } else {
      Text() {
        this.inlineSpans(inner.spans, $r('app.float.p1_body_font_size'), false)
      }.width('100%')
    }
  }

  /** 行内 Span 序列：链接用主题色并可点击，行内代码用等宽字体 + 半透明底色（同正文渲染口径）。 */
  @Builder
  private inlineSpans(spans: ReleaseMarkdownSpan[], fontSizeValue: Length, baseBold: boolean) {
    ForEach(spans, (seg: ReleaseMarkdownSpan, index: number) => {
      if (seg.kind === ReleaseMarkdownSpanKind.CODE) {
        Span(seg.text)
          .fontSize(fontSizeValue)
          .fontFamily('monospace')
          .fontColor($r('app.color.primary_text'))
          .textBackgroundStyle({ color: '#14808080', radius: 3 })
      } else if (seg.kind === ReleaseMarkdownSpanKind.LINK) {
        Span(seg.text)
          .fontSize(fontSizeValue)
          .fontColor(this.resolvedThemeColor)
          .onClick((): void => {
            this.onOpenLink(seg.url);
          })
      } else if (seg.kind === ReleaseMarkdownSpanKind.BOLD) {
        Span(seg.text)
          .fontSize(fontSizeValue)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
      } else if (seg.kind === ReleaseMarkdownSpanKind.ITALIC) {
        Span(seg.text)
          .fontSize(fontSizeValue)
          .fontStyle(FontStyle.Italic)
          .fontColor($r('app.color.primary_text'))
      } else {
        Span(seg.text)
          .fontSize(fontSizeValue)
          .fontWeight(baseBold ? FontWeight.Bold : FontWeight.Normal)
          .fontColor($r('app.color.primary_text'))
      }
    }, (seg: ReleaseMarkdownSpan, index: number): string => `${index}:${seg.kind}:${seg.text}`)
  }
}
