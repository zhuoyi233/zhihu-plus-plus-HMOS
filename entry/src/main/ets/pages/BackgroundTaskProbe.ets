import { BusinessError } from '@kit.BasicServicesKit';
import { BackgroundTaskProbe } from '../background/BackgroundTaskProbe';
import {
  BackgroundRoute,
  decideBackgroundRoute,
  ZhihuWorkload
} from '../background/BackgroundWorkPolicy';

@Component
export struct BackgroundTaskProbePage {
  onBack: () => void = () => {};
  @State private transientStatus: string = '短时任务配额尚未读取';
  @State private deferredStatus: string = '延迟任务登记尚未验证';
  @State private busy: boolean = false;
  private readonly probe: BackgroundTaskProbe = new BackgroundTaskProbe();

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Button('返回')
          .id('p0_background_back')
          .onClick(() => this.onBack())

        Text('API 24 后台任务约束')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text('P0 只验证系统任务登记与资源配额，不执行真实接口轮询、Feed 抓取或常驻保活。')
          .fontSize(16)
          .lineHeight(26)
          .fontColor($r('app.color.secondary_text'))

        Button('读取并释放短时任务配额')
          .id('p0_probe_transient_task')
          .enabled(!this.busy)
          .onClick(() => this.runTransientProbe())

        Text(this.transientStatus)
          .id('p0_transient_task_status')
          .fontSize(16)
          .lineHeight(24)
          .fontColor($r('app.color.primary_text'))

        Button('登记并清理延迟任务')
          .id('p0_probe_deferred_task')
          .enabled(!this.busy)
          .onClick(() => this.runDeferredProbe())

        Text(this.deferredStatus)
          .id('p0_deferred_task_status')
          .fontSize(16)
          .lineHeight(24)
          .fontColor($r('app.color.primary_text'))

        Text('首版执行边界')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text(this.policySummary())
          .id('p0_background_policy_summary')
          .fontSize(15)
          .lineHeight(24)
          .fontColor($r('app.color.secondary_text'))

        Text('长时任务结论')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text('P0 不申请 KEEP_BACKGROUND_RUNNING。只有未来明确启用的音频播放或用户可感知数据传输，' +
          '才能按对应模式、通知和停止条件单独接入；周期性 Feed 抓取不属于合规长时任务。')
          .fontSize(15)
          .lineHeight(24)
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private async runTransientProbe(): Promise<void> {
    this.busy = true;
    this.transientStatus = '正在申请短时任务并读取系统配额…';
    try {
      const result = await this.probe.probeTransientTask();
      this.transientStatus = `通过：本次获批 ${Math.round(result.actualDelayMs / 1000)} 秒，` +
        `读取时剩余 ${Math.round(result.remainingDelayMs / 1000)} 秒，` +
        `当日剩余配额 ${Math.round(result.remainingQuotaMs / 1000)} 秒；请求已主动释放`;
    } catch (error) {
      this.transientStatus = this.errorMessage('短时任务探针失败', error);
    } finally {
      this.busy = false;
    }
  }

  private async runDeferredProbe(): Promise<void> {
    this.busy = true;
    this.deferredStatus = '正在登记延迟任务…';
    try {
      const result = await this.probe.probeDeferredTask();
      this.deferredStatus = result.registeredWorkCount === 1 && result.remainingWorkCount === 0
        ? `通过：任务 ${result.workId} 已登记，最早 ${Math.round(result.earliestStartDelayMs / 1000)} 秒后触发；已取消清理`
        : `失败：登记数 ${result.registeredWorkCount}，清理后剩余 ${result.remainingWorkCount}`;
    } catch (error) {
      this.deferredStatus = this.errorMessage('延迟任务探针失败', error);
    } finally {
      this.busy = false;
    }
  }

  private policySummary(): string {
    const refresh = decideBackgroundRoute(ZhihuWorkload.USER_REFRESH);
    const finish = decideBackgroundRoute(ZhihuWorkload.FINISH_IN_FLIGHT_REQUEST);
    const maintenance = decideBackgroundRoute(ZhihuWorkload.NON_URGENT_MAINTENANCE);
    const crawl = decideBackgroundRoute(ZhihuWorkload.PERIODIC_FEED_CRAWL);
    return `• 主动刷新：${refresh.route}，${refresh.reason}\n` +
      `• 操作收尾：${finish.route}，${finish.reason}\n` +
      `• 非紧急维护：${maintenance.route}，${maintenance.reason}\n` +
      `• 周期 Feed 抓取：${crawl.route}，${crawl.reason}`;
  }

  private errorMessage(prefix: string, error: Object): string {
    const businessError = error as BusinessError;
    return `${prefix}（错误码 ${businessError.code ?? '未知'}）`;
  }
}
