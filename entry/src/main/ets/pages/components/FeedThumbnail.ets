/** 共享封面只负责显示：异常 URL/加载失败保留中性画布，不改变卡片尺寸或点击入口。 */
@Component
export struct FeedThumbnail {
  @Prop @Watch('resetFailure') url: string = '';
  @State private failed: boolean = false;
  private resetFailure(): void { this.failed = false; }
  build() {
    Stack() {
      if (!this.failed && /^https:\/\/[^\s]+$/i.test(this.url)) {
        Image(this.url)
          .width('100%').height('100%').objectFit(ImageFit.Cover)
          .onError((): void => { this.failed = true; })
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.control_background'))
    .accessibilityText('内容缩略图')
    .hitTestBehavior(HitTestMode.None)
  }
}
