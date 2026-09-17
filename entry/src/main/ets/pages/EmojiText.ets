import { EmojiSegment, EmojiPathResolver, emojiStore, parseEmojiSegments } from 'data';

/**
 * 支持知乎小表情的文本组件：文本中的 `[占位符]`（如 `[惊喜]`）在表情表命中时
 * 以行内 ImageSpan 渲染（1.3 倍字号、居中对齐，对齐上游 InlineTextContent 尺寸），
 * 未命中保持原文。表情表异步加载完成后经 `emojiCatalogVersion` 广播自动重建。
 */
@Component
export struct EmojiText {
  @Prop text: string = '';
  @Prop fontSize: number | Resource = 16;
  @Prop lineHeight: number = 0;
  @Prop fontColor: ResourceColor = $r('app.color.primary_text');
  @Prop maxLines: number = 0;
  @Prop copyOption: CopyOptions = CopyOptions.None;
  /** 透传给内部 Text 的无障碍/测试 id（自定义组件不接受外部属性链）。 */
  @Prop componentId: string = '';
  @StorageProp('emojiCatalogVersion') @Watch('onCatalogVersionChanged') catalogVersion: number = 0;
  @State private renderTick: number = 0;

  onCatalogVersionChanged(): void {
    this.renderTick = this.catalogVersion;
  }

  private segments(): Array<EmojiSegment> {
    const store = emojiStore;
    const resolve: EmojiPathResolver = (placeholder: string): string => store.path(placeholder);
    return parseEmojiSegments(this.text, resolve);
  }

  /** 上游按 1.3em 设定行内表情占位；字号为资源引用时退回固定 22vp。 */
  private emojiSide(): number {
    return typeof this.fontSize === 'number' ? Math.round(this.fontSize * 1.3) : 22;
  }

  build() {
    Text() {
      ForEach(this.segments(), (segment: EmojiSegment) => {
        if (segment.kind === 'emoji') {
          ImageSpan(segment.path)
            .width(this.emojiSide())
            .height(this.emojiSide())
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
        } else {
          Span(segment.text)
        }
      }, (segment: EmojiSegment, index: number): string =>
        `${this.renderTick}_${index}_${segment.kind}_${segment.text}`)
    }
    .id(this.componentId)
    .fontSize(this.fontSize)
    .fontColor(this.fontColor)
    .lineHeight(this.lineHeight > 0 ? this.lineHeight : undefined)
    .maxLines(this.maxLines > 0 ? this.maxLines : undefined)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .copyOption(this.copyOption)
    .width('100%')
  }
}
