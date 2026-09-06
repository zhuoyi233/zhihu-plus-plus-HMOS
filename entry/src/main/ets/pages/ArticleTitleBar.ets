import { hdsMaterial } from '@kit.UIDesignKit';
import { materialCanvas } from './components/MaterialCanvas';

/** 文章页顶栏状态：文章标题 + 作者摘要 + 滚动折叠信号。
 * 跨页面经 AppStorage 广播（同 AnswerTitleBar 模式，HDS 标题栏 stackBuilder 树下
 * 常规传值不更新，必须走存储通道）。 */
export interface ArticleTitleState {
  id: string;
  title: string;
  authorName: string;
  authorAvatarUrl: string;
  scrolled: boolean;
}

export function publishArticleTitle(state: ArticleTitleState): void {
  const states = AppStorage.get<ArticleTitleState[]>('articleTitleStates') ?? [];
  const previous = states.find((item: ArticleTitleState): boolean => item.id === state.id);
  if (previous?.title === state.title && previous.authorName === state.authorName &&
    previous.authorAvatarUrl === state.authorAvatarUrl && previous.scrolled === state.scrolled) {
    return;
  }
  AppStorage.setOrCreate('articleTitleStates',
    states.filter((item: ArticleTitleState): boolean => item.id !== state.id).concat([state]));
}

export function removeArticleTitle(id: string): void {
  const states = AppStorage.get<ArticleTitleState[]>('articleTitleStates') ?? [];
  AppStorage.setOrCreate('articleTitleStates',
    states.filter((item: ArticleTitleState): boolean => item.id !== id));
}

/** 文章页 HDS 标题栏：默认返回键 + "文章"占位；正文滚过文章标题后折叠为
 * 返回键右侧文章标题单行 + 下方作者头像/名称（对齐 AnswerTitleBar 折叠态）。 */
@Component
export struct ArticleTitleBar {
  articleId: string = '';
  onBack: () => void = (): void => {
  };
  @StorageProp('articleTitleStates') private states: ArticleTitleState[] = [];

  private state(): ArticleTitleState | undefined {
    return this.states.find((item: ArticleTitleState): boolean => item.id === this.articleId);
  }

  private supportsImmersiveMaterial(): boolean {
    try {
      return hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_error) {
      return false;
    }
  }

  private scrolled(): boolean {
    return this.state()?.scrolled ?? false;
  }

  build() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.supportsImmersiveMaterial()) {
          materialCanvas(52, 52)
        }
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .width(40)
          .height(40)
          .padding(0)
          .borderRadius(20)
          .backgroundColor(this.supportsImmersiveMaterial()
            ? Color.Transparent
            : $r('app.color.surface_background'))
          .accessibilityText('返回')
          .onClick((): void => {
            this.onBack();
          })
      }
        .width(44)
        .height(44)
        .borderRadius(22)
        .clip(true)

      // 标题区：未折叠显示"文章"占位；折叠后交叉淡入文章标题 + 作者摘要两行
      // （对齐 AnswerTitleBar 折叠态的过渡方式）。
      Stack({ alignContent: Alignment.Start }) {
        Column() {
          Text('文章')
            .id('article_top_label')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
        }
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .opacity(this.scrolled() ? 0 : 1)
        .translate({ y: this.scrolled() ? -8 : 0 })

        Column({ space: 2 }) {
          Text(this.state()?.title ?? '')
            .id('article_top_title')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: 4 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(18)
                .height(18)
                .fill($r('app.color.control_background'))
              if ((this.state()?.authorAvatarUrl ?? '').length > 0) {
                Image(this.state()?.authorAvatarUrl ?? '')
                  .id('article_top_author_avatar')
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .objectFit(ImageFit.Cover)
              } else if ((this.state()?.authorName ?? '').length > 0) {
                Text((this.state()?.authorName ?? '').substring(0, 1))
                  .fontSize($r('app.float.p1_caption_font_size'))
                  .fontColor($r('app.color.secondary_text'))
              }
            }
              .width(18)
              .height(18)
              .clip(true)
            Text(this.state()?.authorName ?? '')
              .id('article_top_author')
              .fontSize($r('app.float.p1_caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .opacity(this.scrolled() ? 1 : 0)
        .translate({ y: this.scrolled() ? 0 : 8 })
      }
        .layoutWeight(1)
        .height(48)
        .clip(true)
    }
    .width('100%')
    .height(48)
    .padding({
      left: $r('app.float.p1_page_padding'),
      right: $r('app.float.p1_page_padding')
    })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
