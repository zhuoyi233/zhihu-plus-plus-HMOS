import { common } from '@kit.AbilityKit';
import { DatabaseProbe, DatabaseProbeResult } from 'data';

@Component
export struct DatabaseProbePage {
  onBack: () => void = () => {};
  @State private status: string = '等待验证建库、升级和失败回滚';
  @State private running: boolean = false;

  build() {
    Column({ space: 20 }) {
      Button('返回')
        .id('p0_database_back')
        .onClick(() => this.onBack())

      Text('RDB Schema 与迁移验证')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))

      Text('先用隔离库验证故障迁移回滚，再通过生产数据库验证自动升级、覆盖写、关闭重开和清理。')
        .fontSize(16)
        .lineHeight(26)
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)

      Text(this.status)
        .id('p0_database_status')
        .fontSize(16)
        .lineHeight(26)
        .fontColor($r('app.color.primary_text'))
        .textAlign(TextAlign.Center)

      Button('运行数据库迁移验证')
        .id('p0_run_database_probe')
        .enabled(!this.running)
        .onClick(() => this.runProbe())
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
  }

  private async runProbe(): Promise<void> {
    this.running = true;
    this.status = '正在执行事务迁移与故障回滚…';
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('无法获取应用上下文');
      }
      const result: DatabaseProbeResult = await new DatabaseProbe(context).run();
      this.status = `通过：失败迁移回滚到 v${result.rollbackVersion}；` +
        `隔离库升级并重开为 v${result.finalVersion}；保留 ${result.recordCount} 条记录，` +
        `默认类型 ${result.restoredType}；生产库 v${result.productionVersion} 覆盖写恢复 ` +
        `${result.productionRestoredType}@${result.productionRestoredAt}，探针记录已删除`;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.status = `数据库验证失败：${message}`;
    } finally {
      this.running = false;
    }
  }
}
