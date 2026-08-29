import { P4ImagePickerPanel } from './P4ImagePickerPanel';

const STATIC_IMAGE_URL = 'https://picx.zhimg.com/v2-7f36f391170ca2319d6b61239694e0ef_1440w.jpg';
const GIF_IMAGE_URL = 'https://pic2.zhimg.com/v2-5e25b72ea793eb39f3709e89e56b2513_1440w.gif';
const FAILURE_IMAGE_URL = 'https://picx.zhimg.com/probe-image-that-does-not-exist.jpg';

@Component
export struct ImageProbe {
  onBack: () => void = () => {};
  @State private staticStatus: string = '静态图片等待加载';
  @State private gifStatus: string = 'GIF 等待加载';
  @State private retryStatus: string = '首次请求将验证失败状态';
  @State private retryAttempt: number = 0;
  @State private previewUrl: string = '';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() {
        Column({ space: 20 }) {
          Blank().height(64)
          Row({ space: 12 }) {
            Button('返回')
              .id('image_back')
              .onClick(() => this.onBack())
            Column({ space: 4 }) {
              Text('图片与 GIF 验证')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
              Text('点击已加载图片进入原生全屏预览')
                .fontSize(14)
                .fontColor($r('app.color.secondary_text'))
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Text('知乎静态网络图片')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Image(STATIC_IMAGE_URL)
            .id('static_image')
            .width('100%')
            .height(220)
            .objectFit(ImageFit.Contain)
            .onComplete(() => {
              this.staticStatus = '静态图片加载成功';
            })
            .onError((error: ImageError) => {
              this.staticStatus = `静态图片加载失败：${error.message}`;
            })
            .onClick(() => {
              this.previewUrl = STATIC_IMAGE_URL;
            })
          Text(this.staticStatus)
            .id('static_image_status')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))

          Text('知乎 GIF 动图')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Image(GIF_IMAGE_URL)
            .id('gif_image')
            .width('100%')
            .height(220)
            .objectFit(ImageFit.Contain)
            .onComplete(() => {
              this.gifStatus = 'GIF 加载成功；由 Image 组件逐帧解码';
            })
            .onError((error: ImageError) => {
              this.gifStatus = `GIF 加载失败：${error.message}`;
            })
            .onClick(() => {
              this.previewUrl = GIF_IMAGE_URL;
            })
          Text(this.gifStatus)
            .id('gif_image_status')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))

          Text('失败与重试')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Image(this.retryAttempt === 0 ? FAILURE_IMAGE_URL : STATIC_IMAGE_URL)
            .id('retry_image')
            .width('100%')
            .height(160)
            .objectFit(ImageFit.Contain)
            .onComplete(() => {
              this.retryStatus = '重试成功，已恢复为有效图片';
            })
            .onError(() => {
              this.retryStatus = '图片加载失败，可点击重试';
            })
          Text(this.retryStatus)
            .id('retry_image_status')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
          Button(`重试（${this.retryAttempt}）`)
            .id('retry_image_button')
            .onClick(() => {
              this.retryStatus = '正在重试…';
              this.retryAttempt += 1;
            })

          Text('P4 系统相册选择（API 26）')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          P4ImagePickerPanel()
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')

      if (this.previewUrl.length > 0) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(this.previewUrl)
            .id('image_preview')
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
          Button('关闭预览')
            .id('close_image_preview')
            .margin(20)
            .onClick(() => {
              this.previewUrl = '';
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#EE000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
