import { HttpProbeClient } from '../network/HttpProbeClient';

@Entry
@Component
struct Index {
  @State private networkStatus: string = 'HTTP 探针尚未运行';
  private readonly httpProbeClient: HttpProbeClient = new HttpProbeClient();

  build() {
    Column({ space: 16 }) {
      Text('Zhihu++ HarmonyOS')
        .id('p0_title')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))

      Text('P0 技术验证工程')
        .id('p0_subtitle')
        .fontSize(20)
        .fontColor($r('app.color.primary_text'))

      Text('目标 API 24 · 最低兼容 API 20')
        .id('p0_sdk_baseline')
        .fontSize(16)
        .fontColor($r('app.color.secondary_text'))

      Text('下一步：网络、会话、签名、正文与存储验证')
        .id('p0_next_step')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))

      Text(this.networkStatus)
        .id('p0_http_status')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))

      Row({ space: 12 }) {
        Button('运行 HTTP 探针')
          .id('p0_run_http_probe')
          .onClick(() => {
            this.runHttpProbe();
          })

        Button('取消')
          .id('p0_cancel_http_probe')
          .onClick(() => {
            this.httpProbeClient.cancel();
            this.networkStatus = 'HTTP 探针已取消';
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
    .backgroundColor($r('app.color.page_background'))
  }

  private async runHttpProbe(): Promise<void> {
    this.networkStatus = 'HTTP 请求中…';
    try {
      const result = await this.httpProbeClient.requestPublicQuestion();
      this.networkStatus = `HTTP ${result.statusCode}，响应 ${result.body.length} 字符`;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.networkStatus = `HTTP 探针失败：${message}`;
    }
  }
}
