import { ReaderBlock, ReaderBlockKind } from './ReaderDocument';

@Component
export struct ReaderImageBlock {
  item: ReaderBlock = { id: '', kind: ReaderBlockKind.IMAGE, text: '', sourceUrl: '' };
  onPreview: (url: string) => void = () => {};
  @State private status: string = '图片等待加载';
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
        .id(`p0_reader_image_${this.item.id}`)
        .width('100%')
        .height(260)
        .objectFit(ImageFit.Contain)
        .onComplete(() => {
          this.failed = false;
          this.status = '图片加载成功';
        })
        .onError(() => {
          this.failed = true;
          this.status = '图片加载失败';
        })
        .onClick(() => {
          if (!this.failed) {
            this.onPreview(this.item.sourceUrl);
          }
        })

      if (this.item.text.length > 0) {
        Text(this.item.text)
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      Row({ space: 12 }) {
        Text(this.status)
          .id(`p0_reader_image_status_${this.item.id}`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        if (this.failed) {
          Button('重试')
            .id(`p0_reader_image_retry_${this.item.id}`)
            .onClick(() => {
              this.failed = false;
              this.status = '正在重试…';
              this.retryRevision += 1;
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
  }
}
