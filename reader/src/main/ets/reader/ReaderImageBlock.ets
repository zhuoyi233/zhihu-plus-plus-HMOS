import { ReaderBlock, ReaderBlockKind } from './ReaderDocument';

/** 加载完成前的占位宽高比（加载后按源图比例覆盖）。 */
const IMAGE_PLACEHOLDER_ASPECT_RATIO = 4 / 3;

@Component
export struct ReaderImageBlock {
  item: ReaderBlock = { id: '', kind: ReaderBlockKind.IMAGE, text: '', sourceUrl: '', inlineRuns: [] };
  onPreview: (url: string) => void = () => {};
  secondaryTextColor: ResourceColor = Color.Gray;
  @State private failed: boolean = false;
  @State private retryRevision: number = 0;
  @State private imageAspectRatio: number = IMAGE_PLACEHOLDER_ASPECT_RATIO;

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
        // 对齐上游 RenderImage：宽度为内容宽 80% 居中，高度按源图宽高比自适应，
        // 不再用固定高度截断（固定 260vp + Contain 会把竖图/方图缩小）。
        .width('80%')
        .aspectRatio(this.imageAspectRatio)
        .objectFit(ImageFit.Contain)
        .onComplete((event) => {
          this.failed = false;
          if (event !== undefined && event.width > 0 && event.height > 0) {
            this.imageAspectRatio = event.width / event.height;
          }
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
