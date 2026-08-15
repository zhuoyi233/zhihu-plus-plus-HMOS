import { ReaderBlock, ReaderBlockKind } from './ReaderDocument';

@Component
export struct ReaderImageBlock {
  item: ReaderBlock = { id: '', kind: ReaderBlockKind.IMAGE, text: '', sourceUrl: '', inlineRuns: [] };
  onPreview: (url: string) => void = () => {};
  secondaryTextColor: ResourceColor = Color.Gray;
  @State private failed: boolean = false;
  @State private retryRevision: number = 0;

  private imageSource(): string {
    if (this.retryRevision === 0) {
      return this.item.sourceUrl;
    }
    const separator = this.item.sourceUrl.includes('?') ? '&' : '?';
    return `${this.item.sourceUrl}${separator}zhplus_retry=${this.retryRevision}`;
  }

  build() {
    Column({ space: 8 }) {
      Image(this.imageSource())
        .id(`reader_image_${this.item.id}`)
        .width('100%')
        .height(260)
        .objectFit(ImageFit.Contain)
        .onComplete(() => {
          this.failed = false;
        })
        .onError(() => {
          this.failed = true;
        })
        .onClick(() => {
          if (!this.failed) {
            this.onPreview(this.item.sourceUrl);
          }
        })

      if (this.item.text.length > 0) {
        Text(this.item.text)
          .fontSize(14)
          .fontColor(this.secondaryTextColor)
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      // 加载成功/加载中不显示状态小字；仅失败时展示错误与重试。
      if (this.failed) {
        Row({ space: 12 }) {
          Text('图片加载失败')
            .id(`reader_image_status_${this.item.id}`)
            .fontSize(13)
            .fontColor(this.secondaryTextColor)
          Button('重试')
            .id(`reader_image_retry_${this.item.id}`)
            .onClick(() => {
              this.failed = false;
              this.retryRevision += 1;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
  }
}
