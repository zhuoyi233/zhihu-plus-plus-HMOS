import { CommentLikeState } from './CommentLikeState';

@Component
export struct CommentLikeButton {
  @ObjectLink state: CommentLikeState;
  @Prop interactionEnabled: boolean = true;
  onToggle: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 4 }) {
        SymbolGlyph(this.state.liked ? $r('sys.symbol.hand_thumbsup_fill') : $r('sys.symbol.hand_thumbsup'))
          .fontSize(16)
          .fontColor([this.state.liked ? $r('app.color.brand_primary') : $r('app.color.secondary_text')])
        Text(`${this.state.count}`)
          .id(`p3_comments_like_count_${this.state.id}`)
          .fontSize(12)
          .fontColor(this.state.liked ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
      }
    }
    .id(`p3_comments_like_button_${this.state.id}`)
    .height(28)
    .padding({ left: 4, right: 4 })
    .margin({ left: 8 })
    .backgroundColor(Color.Transparent)
    // 并发请求由控制器门禁处理，不因点赞请求切换所有按钮的禁用样式。
    .enabled(this.interactionEnabled)
    .accessibilityText(this.state.liked ? '取消点赞' : '点赞')
    .onClick((): void => this.onToggle())
  }
}
