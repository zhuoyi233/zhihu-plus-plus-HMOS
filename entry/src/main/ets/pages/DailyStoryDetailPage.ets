import { Want } from '@kit.AbilityKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { createSystemShareService } from '../platform/SystemShareService';
import { ShareOutcome, SharePayloadKind, ShareTextPayload } from '../platform/ShareContracts';
import { AppDestination } from 'core';
import {
  DailyStoryRepository,
  DEFAULT_THEME_COLOR,
  onThemeColor
} from 'data';
import { isTrustedReaderImageUrl } from 'reader';
import {
  DailyStoryDetailController,
  DailyStoryDetailPhase,
  DailyStoryViewState
} from './DailyStoryDetailState';
import { NativeContentDocument, ContentImagePreview } from './NativeContentDocument';
import { contentLinkDestination } from './NotificationLinkResolver';
import { floatingTitleBarOffset } from './AppPageChrome';
import { readerHorizontalPaddingVp } from './ReaderViewportLayout';

/**
 * 知乎日报原生阅读页（docs/plans/知乎日报原生渲染分析计划.md §3、§6）。
 *
 * 版式遵循 docs/ui-design-guidelines.md：
 * - 内容优先：头图 → 日报标题（24fp 阅读标题）→ 栏目/作者次级信息 → 正文语义块；
 * - 中性色打底：仅主操作（重试/查看知乎讨论）使用主题色，次要操作走中性底；
 * - 顶栏由 AppShell 的 HDS 标题栏提供，页面内不再画第二条标题栏；
 * - 正文复用整份阅读器（`NativeContentDocument` 的预解析块输入）：继承字号/行高/段间距/
 *   深浅色/沉浸阅读/图片预览/文本选择，不为日报另写一套渲染。
 */
@Component
export struct DailyStoryDetailPage {
  storyId: string = '';
  repository: DailyStoryRepository | undefined = undefined;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 正文图片/头图点击后的全屏查看器（与详情页同一 AppStorage 通道）。 */
  @StorageProp('imagePreviewUrl') private imagePreviewUrl: string = '';
  @State private phase: DailyStoryDetailPhase = DailyStoryDetailPhase.IDLE;
  @State private viewState: DailyStoryViewState | undefined = undefined;
  private controller?: DailyStoryDetailController;

  aboutToAppear(): void {
    // 返回栈重显：控制器与已加载正文保留（阅读锚点在 NativeContentDocument 内），
    // 只重新激活，不重复请求，也不重建文档导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      if (this.phase === DailyStoryDetailPhase.IDLE || this.phase === DailyStoryDetailPhase.ERROR) {
        void this.controller.load(this.storyId);
      }
      return;
    }
    const repository = this.repository;
    if (repository === undefined) {
      this.phase = DailyStoryDetailPhase.ERROR;
      this.viewState = undefined;
      return;
    }
    this.controller = new DailyStoryDetailController(repository,
      (state: DailyStoryViewState): void => this.applyState(state));
    this.controller.activate();
    void this.controller.load(this.storyId);
  }

  aboutToDisappear(): void {
    // 页面离开：取消在途请求并作废其回调，避免迟到结果更新已销毁视图或触发导航。
    // 控制器本身保留，返回时可直接复用已解析正文（见 aboutToAppear）。
    this.controller?.deactivate();
  }

  private applyState(state: DailyStoryViewState): void {
    this.viewState = state;
    this.phase = state.phase;
  }

  private retry(): void {
    void this.controller?.load(this.storyId);
  }

  private webUrl(): string {
    return this.viewState?.webUrl ?? `https://daily.zhihu.com/story/${this.storyId}`;
  }

  private title(): string {
    const title = this.viewState?.payload?.title ?? '';
    return title.length > 0 ? title : '知乎日报';
  }

  private sectionName(): string {
    return this.viewState?.payload?.section?.name ?? '';
  }

  private headerImageUrl(): string {
    const candidate = this.viewState?.payload?.imageUrl ?? '';
    return isTrustedReaderImageUrl(candidate) ? candidate : '';
  }

  private partialNotice(): string {
    if (this.phase !== DailyStoryDetailPhase.PARTIAL) {
      return '';
    }
    return '部分内容暂不支持原生显示，可在浏览器中查看完整日报';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.phase === DailyStoryDetailPhase.IDLE || this.phase === DailyStoryDetailPhase.LOADING) {
        this.loadingView()
      } else if (this.phase === DailyStoryDetailPhase.READY || this.phase === DailyStoryDetailPhase.PARTIAL) {
        this.documentView()
      } else {
        this.failureView()
      }
      // 全屏图片查看器叠层：必须由本页根 Stack 渲染（正文组件在惰性列表树内），
      // 标题栏由 AppShell 监听同一 AppStorage 键隐藏。
      if (this.imagePreviewUrl.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          ContentImagePreview({
            url: this.imagePreviewUrl,
            onClose: (): void => {
              AppStorage.setOrCreate('imagePreviewUrl', '');
            }
          })
        }
        .id('daily_story_image_preview_overlay')
        .width('100%')
        .height('100%')
      }
    }
    .id('daily_story_detail_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /** 首次加载：骨架提示居中，顶栏与导航保持稳定（不先闪空数据）。 */
  @Builder
  private loadingView() {
    Column({ space: $r('app.float.spacing_medium') }) {
      LoadingProgress()
        .id('daily_story_loading_progress')
        .width(40)
        .height(40)
        .color(this.resolvedThemeColor)
      Text('正在加载日报…')
        .id('daily_story_loading_status')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: floatingTitleBarOffset() })
  }

  /**
   * 正文：头图 + 标题 + 次级元信息 + 阅读器（单滚动容器）。
   *
   * 每个 storyId 都是独立的导航目的地与页面实例（AppShell 按身份查重），
   * 因此这里不需要为「同一实例换故事」做额外重建逻辑。
   */
  @Builder
  private documentView() {
    NativeContentDocument({
      documentBlocks: this.viewState?.blocks ?? [],
      contentNotice: this.partialNotice(),
      emptyMessage: '这篇日报没有可原生展示的正文',
      readingLayout: true,
      topInsetVp: floatingTitleBarOffset(),
      bottomInsetVp: 100,
      onLinkClick: (url: string): void => this.openLink(url),
      documentHeader: (): void => {
        this.documentHeader()
      },
      documentFooter: (): void => {
        this.documentFooter()
      }
    })
  }

  @Builder
  private documentHeader() {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (this.headerImageUrl().length > 0) {
        Image(this.headerImageUrl())
          .id('daily_story_header_image')
          .width('100%')
          // 头图是入口视觉，不是正文：固定 180vp 高、Cover 裁切，避免 4:3 全宽在宽屏
          // 上占掉整屏把标题与正文挤到首屏之外（§4.3 首屏内容起点 94vp）。
          .height(180)
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.card_radius'))
          .clip(true)
          .accessibilityText('日报头图，点击查看大图')
          .onClick((): void => {
            if (isTrustedReaderImageUrl(this.headerImageUrl())) {
              AppStorage.setOrCreate('imagePreviewUrl', this.headerImageUrl());
            }
          })
      }
      Text(this.title())
        .id('daily_story_title')
        .fontSize($r('app.float.reader_title_font_size'))
        .lineHeight($r('app.float.reader_title_line_height'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
      this.metaRow()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 次级信息：栏目 / 来源 / 分享动作（低优先级，不抢标题与正文的视觉重量）。 */
  @Builder
  private metaRow() {
    Row({ space: 8 }) {
      if (this.sectionName().length > 0) {
        // 次级文本限制字号放大与行数：大字体下不得把分享按钮挤出可视区（§11 响应式布局）。
        Text(this.sectionName())
          .id('daily_story_section')
          .fontSize($r('app.float.caption_font_size'))
          .maxFontScale(1.3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.secondary_text'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10)
          .backgroundColor($r('app.color.surface_background'))
          .flexShrink(1)
      }
      Text('知乎日报')
        .fontSize($r('app.float.caption_font_size'))
        .maxFontScale(1.3)
        .maxLines(1)
        .fontColor($r('app.color.secondary_text'))
        .flexShrink(0)
      Blank()
      // 纯图标操作用 40vp 圆按钮（§4.1 / §9）：图标 20vp、中性底、带可朗读名称。
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
        .id('daily_story_share')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor($r('app.color.surface_background'))
        .accessibilityText('分享这篇日报')
        .flexShrink(0)
        .onClick((): void => this.shareStory())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 正文尾部：唯一的主动作是「查看知乎讨论」——跳到这篇日报对应的知乎问题页。
   *
   * 日报正文页尾本身带一条 `div.view-more` 的「查看知乎讨论」链接（解析器把它当导航入口丢弃），
   * 这里用胶囊按钮承接同一语义：整页只有这一条页尾操作，不再并排放浏览器入口。
   * 胶囊按内容自适应宽度（左右 32vp 内边距）并居中，圆角取半高，不随字号拉伸成整宽色块。
   * 例外：PARTIAL（确有内容未能原生化）时补一个中性底面按钮，否则被省略的内容无处可看。
   */
  @Builder
  private documentFooter() {
    if (this.viewState?.originDestination !== undefined || this.phase === DailyStoryDetailPhase.PARTIAL) {
      Column({ space: $r('app.float.spacing_small') }) {
        Divider().color($r('app.color.divider_color'))
        if (this.viewState?.originDestination !== undefined) {
          // 主操作用主题色：图标与文字都取 onThemeColor 以保证深浅色下的对比度。
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.message'))
                .fontSize(20)
                .fontColor([onThemeColor(this.resolvedThemeColor)])
              Text('查看知乎讨论')
                .fontSize($r('app.float.body_font_size'))
                .fontColor(onThemeColor(this.resolvedThemeColor))
            }
            .justifyContent(FlexAlign.Center)
          }
          .id('daily_story_discussion')
          .constraintSize({ minHeight: 46, maxWidth: '100%' })
          .padding({ top: 11, bottom: 11, left: 32, right: 32 })
          .borderRadius(23)
          .backgroundColor(this.resolvedThemeColor)
          .accessibilityText('查看这篇日报在知乎的讨论')
          .onClick((): void => this.openDiscussion())
        }
        if (this.phase === DailyStoryDetailPhase.PARTIAL) {
          Button('在浏览器中查看完整日报')
            .id('daily_story_partial_browser')
            .width('100%')
            .backgroundColor($r('app.color.control_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick((): void => this.openInBrowser(this.webUrl()))
        }
      }
      .width('100%')
      .padding({ top: $r('app.float.spacing_medium'), bottom: 24 })
    }
  }

  /** 页尾「查看知乎讨论」：已在解析阶段校验过的站内目标，不需要再走链接安全策略。 */
  private openDiscussion(): void {
    const destination = this.viewState?.originDestination;
    if (destination !== undefined) {
      this.navigate(destination);
    }
  }

  /** 失败/不支持：说明具体原因 + 重试 + 浏览器入口（不把取消当网络失败）。 */
  @Builder
  private failureView() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Blank()
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(32)
        .fontColor([$r('app.color.secondary_text')])
      Text(this.failureMessage())
        .id('daily_story_error_status')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.phase === DailyStoryDetailPhase.ERROR) {
        Button('重新加载')
          .id('daily_story_retry')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .onClick((): void => this.retry())
      }
      Button('在浏览器中查看日报')
        .id('daily_story_error_browser')
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick((): void => this.openInBrowser(this.webUrl()))
      if (this.viewState?.originDestination !== undefined) {
        Button('打开知乎原文')
          .id('daily_story_error_origin')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => {
            const destination = this.viewState?.originDestination;
            if (destination !== undefined) {
              this.navigate(destination);
            }
          })
      }
      Blank()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: readerHorizontalPaddingVp(0),
      right: readerHorizontalPaddingVp(0),
      top: floatingTitleBarOffset()
    })
  }

  private failureMessage(): string {
    const message = this.viewState?.errorMessage ?? '';
    if (message.length > 0) {
      return message;
    }
    return this.phase === DailyStoryDetailPhase.UNSUPPORTED
      ? '这篇日报暂不支持原生阅读'
      : '日报正文加载失败，请稍后重试';
  }

  /**
   * 正文链接：站内内容走原生页；其它安全 https 链接交系统浏览器。
   * 回调时再次校验协议，避免过期/被篡改的链接绕过行内解析阶段的过滤。
   */
  private openLink(url: string): void {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return;
    }
    const destination = contentLinkDestination(trimmed);
    if (destination !== undefined) {
      this.navigate(destination);
      return;
    }
    if (!/^https?:\/\//i.test(trimmed)) {
      return;
    }
    this.openInBrowser(trimmed);
  }

  private openInBrowser(url: string): void {
    const context = getAbilityContext();
    if (context === undefined || url.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开浏览器' });
      return;
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    context.startAbility(want).catch((_error: Object): void => {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开浏览器' });
    });
  }

  /** 分享：只用本应用构造的规范日报地址，不信任响应里的 url/share_url。 */
  private shareStory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开分享面板' });
      return;
    }
    const payload: ShareTextPayload = {
      kind: SharePayloadKind.TEXT,
      title: this.title(),
      summary: '来自知乎日报',
      contentUrl: this.webUrl()
    };
    createSystemShareService(context).share(payload).then((outcome: ShareOutcome): void => {
      if (outcome !== ShareOutcome.CANCELLED) {
        this.getUIContext().getPromptAction().showToast({ message: '已打开系统分享面板' });
      }
    }).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开分享面板' });
    });
  }
}
