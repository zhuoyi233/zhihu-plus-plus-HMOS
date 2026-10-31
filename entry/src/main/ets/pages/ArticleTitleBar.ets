import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

/** 文章页顶栏状态：文章标题 + 作者摘要 + 滚动折叠信号。
 * 跨页面经 AppStorage 广播（同 AnswerTitleBar 模式，HDS 标题栏 stackBuilder 树下
 * 常规传值不更新，必须走存储通道）。 */
export interface ArticleTitleState {
  id: string;
  title: string;
  authorName: string;
  authorAvatarUrl: string;
  /** 作者认证徽章图标 URL；未认证为空串。 */
  authorBadgeIconUrl: string;
  scrolled: boolean;
}

export function publishArticleTitle(state: ArticleTitleState): void {
  const states = AppStorage.get<ArticleTitleState[]>('articleTitleStates') ?? [];
  const previous = states.find((item: ArticleTitleState): boolean => item.id === state.id);
  if (previous?.title === state.title && previous.authorName === state.authorName &&
    previous.authorAvatarUrl === state.authorAvatarUrl &&
    previous.authorBadgeIconUrl === state.authorBadgeIconUrl && previous.scrolled === state.scrolled) {
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

  private scrolled(): boolean {
    return this.state()?.scrolled ?? false;
  }

  /** 标题区：未折叠显示"文章"占位；折叠后交叉淡入文章标题 + 作者摘要两行
   * （对齐 AnswerTitleBar 折叠态的过渡方式）。 */
  @Builder
  private identitySlot() {
      Stack({ alignContent: Alignment.Start }) {
        Column() {
          Text('文章')
            .fontSize($r('app.float.heading_font_size'))
            .id('article_top_label')
            .maxFontScale(1.3)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
        }
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .opacity(this.scrolled() ? 0 : 1)
        .translate({ y: this.scrolled() ? -8 : 0 })

        Column({ space: 2 }) {
          Text(this.state()?.title ?? '')
            .fontSize($r('app.float.body_font_size'))
            .id('article_top_title')
            .maxFontScale(1.3)
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
                  .fontSize($r('app.float.caption_font_size'))
                  .maxFontScale(1.3)
                  .fontColor($r('app.color.secondary_text'))
              }
            }
              .width(18)
              .height(18)
              .clip(true)
            // 名称 + 徽章同组：名称 flexShrink 收缩省略，徽章紧跟名字右侧（对齐上游）。
            Row({ space: 4 }) {
              Text(this.state()?.authorName ?? '')
                .fontSize($r('app.float.caption_font_size'))
                .id('article_top_author')
                .maxFontScale(1.3)
                .fontColor($r('app.color.secondary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
              // 作者认证徽章（对齐上游 compact AuthorBadge：折叠顶栏名称后 14vp 图标）。
              if ((this.state()?.authorBadgeIconUrl ?? '').length > 0) {
                Image(this.state()?.authorBadgeIconUrl ?? '')
                  .id('article_top_author_badge')
                  .width(14)
                  .height(14)
                  .objectFit(ImageFit.Contain)
                  .draggable(false)
                  .flexShrink(0)
              }
            }
            .alignItems(VerticalAlign.Center)
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
        .width('100%')
        .height('100%')
        .clip(true)
  }

  build() {
    TopBarContent({
      // 返回键由 HDS 原生 backIcon 承载，标题从其右侧 80vp 预留后起排。
      backMode: TopBarBackMode.HDS,
      hasTitleSlot: true,
      titleSlot: (): void => this.identitySlot()
    })
  }
}
