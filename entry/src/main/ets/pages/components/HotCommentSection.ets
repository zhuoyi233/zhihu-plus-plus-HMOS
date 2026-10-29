import { CommentItem, DEFAULT_THEME_COLOR, emojiStore, onThemeColor } from 'data';
import { commentAvatarUrl, commentImageUrls, stripCommentHtml } from '../CommentText';
import { EmojiText } from '../EmojiText';
import { CommentAvatar } from './CommentAvatar';

/** 火焰图标固定为橙红色，不跟随主题色（主题色下火焰会变成蓝色/绿色，不符合语义）。 */
const HOT_COMMENT_FLAME_COLOR: string = '#FF5722';

/**
 * 回答尾部的「热门评论」预览：最多几条由页面决定（当前 3 条，按热度排序的根评论），
 * 文字行与图片为互不嵌套的原生点击区域；拖动由点击位移阈值过滤。
 *
 * 数据加载、失败与空态由页面控制：**没有热评时页面根本不渲染本组件**
 * （见 HotCommentState.hotCommentSectionVisible），组件内只保留一行空态兜底以防误用。
 */
@Component
export struct HotCommentSection {
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 必须用 @Prop：数据由页面异步回填，普通成员只在首次创建时赋值，加载中会一直卡住。 */
  @Prop comments: Array<CommentItem> = [];
  @Prop totalCount: number = 0;
  @Prop loading: boolean = false;
  @Prop failed: boolean = false;
  onRetry: () => void = (): void => {};
  onOpenAll: () => void = (): void => {
  };
  /** 点击评论图片：打开全屏预览，而不是进入完整评论页。 */
  onImagePreview: (url: string) => void = (_url: string): void => {
  };
  /** 表情表懒加载：热评正文里的 `[占位符]` 需要表情表才渲染为行内图片。 */
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      emojiStore.ensureLoaded(context);
    }
  }

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_xsmall') }) {
        SymbolGlyph($r('sys.symbol.flame_fill'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor([HOT_COMMENT_FLAME_COLOR])
        Text('热评')
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Text(`共 ${this.totalCount} 条`)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.secondary_text')])
      }
      .id('content_detail_hot_comments_header')
      .width('100%')
      .focusable(true)
      .accessibilityText('打开完整评论')
      .onClick((): void => this.onOpenAll(), 12)

      if (this.loading) {
        Row({ space: $r('app.float.spacing_small') }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.resolvedThemeColor)
          Text('热评正在加载中')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .id('content_detail_hot_comments_loading')
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: $r('app.float.spacing_small'), bottom: $r('app.float.spacing_small') })
      } else if (this.failed) {
        Row({ space: 12 }) {
          Text('热评加载失败')
            .fontColor($r('app.color.secondary_text'))
          Button('重试')
            .id('content_detail_hot_comments_retry')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .onClick((): void => this.onRetry())
        }
        .id('content_detail_hot_comments_error')
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.comments.length === 0) {
        // 空态不再由本组件承载：页面在 EMPTY 阶段直接不渲染整个区块（见 hotCommentSectionVisible）。
        // 保留兜底是为了防御误用（例如未来从别处传入空列表），此时只占一行提示，不留空白卡片。
        Text('暂无热评')
          .id('content_detail_hot_comments_empty')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: $r('app.float.spacing_small'), bottom: $r('app.float.spacing_small') })
      } else {
        ForEach(this.comments, (comment: CommentItem): void => {
          this.commentRow(comment)
        }, (comment: CommentItem): string => `hot_comment_${comment.id}`)
      }
    }
    .id('content_detail_hot_comments')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private commentRow(comment: CommentItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        CommentAvatar({
          avatarUrl: commentAvatarUrl(comment.author.avatarUrl),
          authorName: comment.author.name,
          commentId: `hot_${comment.id}`,
          avatarSize: 24
        })
          .hitTestBehavior(HitTestMode.None)
        Column({ space: $r('app.float.spacing_xsmall') }) {
          Row({ space: 6 }) {
            Text(comment.author.name.length > 0 ? comment.author.name : '知乎用户')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (comment.authorTag !== undefined && comment.authorTag.length > 0) {
              Text(comment.authorTag)
                .fontSize($r('app.float.caption_font_size'))
                .fontColor(this.resolvedThemeColor)
            }
            Text(`${comment.likeCount} 赞`)
              .fontSize($r('app.float.caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          EmojiText({
            text: stripCommentHtml(comment.contentHtml),
            fontSize: $r('app.float.body_font_size'),
            fontColor: $r('app.color.primary_text'),
            maxLines: 3,
            componentId: `content_detail_hot_comment_text_${comment.id}`
          })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .id(`content_detail_hot_comment_open_${comment.id}`)
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .focusable(true)
      .accessibilityDescription('打开完整评论')
      .onClick((): void => this.onOpenAll(), 12)
      // 图片是文字点击区域的兄弟节点，祖先没有评论点击处理器。
      ForEach(commentImageUrls(comment.contentHtml), (url: string, index: number): void => {
        Image(url)
          .id(`content_detail_hot_comment_image_${comment.id}_${index}`)
          .width(200)
          .height(100)
          .constraintSize({ maxWidth: '100%' })
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .focusable(true)
          .accessibilityText(`查看评论图片 ${index + 1}`)
          .onClick((): void => this.onImagePreview(url), 12)
      }, (url: string): string => url)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
