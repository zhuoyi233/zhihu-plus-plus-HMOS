import { common } from '@kit.AbilityKit';
import {
  DOMAIN_FIXTURE_SPECS,
  DomainFixtureCaseResult,
  DomainFixtureValidationReport,
  DomainFixtureValidator
} from '../fixtures/DomainFixtureValidator';

const DOMAIN_FIXTURE_COUNT = DOMAIN_FIXTURE_SPECS.length;

@Component
export struct DomainFixtureProbe {
  onBack: () => void = () => {};
  @State private status: string = `正在读取 ${DOMAIN_FIXTURE_COUNT} 份 rawfile fixture…`;
  @State private failures: Array<DomainFixtureCaseResult> = [];
  @State private running: boolean = false;
  private runGeneration: number = 0;

  aboutToAppear(): void {
    this.runValidation();
  }

  aboutToDisappear(): void {
    this.runGeneration += 1;
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        Row({ space: $r('app.float.p1_spacing_medium') }) {
          Button('返回')
            .id('p1_domain_fixture_gate_back')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .onClick(() => this.onBack())

          Text('Domain fixture 设备门禁')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
        }
        .width('100%')

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text(this.status)
            .id('p1_domain_fixture_gate_status')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .width('100%')

          Text(`门禁由 API 24 ResourceManager 直接读取打包后的 ${DOMAIN_FIXTURE_COUNT} 份脱敏 JSON，并调用 data 模块 decoder。`)
            .id('p1_domain_fixture_gate_description')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        if (this.failures.length > 0) {
          Column({ space: $r('app.float.p1_spacing_small') }) {
            Text('失败项（仅显示文件名与安全类别）')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .width('100%')

            ForEach(this.failures, (result: DomainFixtureCaseResult, index: number) => {
              Text(result.summary)
                .id(`p1_domain_fixture_gate_failure_${index}`)
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .width('100%')
            }, (result: DomainFixtureCaseResult): string => result.fileName)
          }
          .id('p1_domain_fixture_gate_failures')
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }

        Button(this.running ? '正在验证…' : '重新运行')
          .id('p1_run_domain_fixture_gate')
          .enabled(!this.running)
          .fontSize($r('app.float.p1_body_font_size'))
          .width('100%')
          .onClick(() => this.runValidation())
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private async runValidation(): Promise<void> {
    const generation = ++this.runGeneration;
    this.running = true;
    this.failures = [];
    this.status = `正在读取 ${DOMAIN_FIXTURE_COUNT} 份 rawfile fixture…`;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const report: DomainFixtureValidationReport = await new DomainFixtureValidator(context).validateAll();
      if (generation !== this.runGeneration) {
        return;
      }
      this.failures = report.results.filter((result: DomainFixtureCaseResult): boolean => !result.passed);
      this.status = report.passed === report.total ? `通过：${report.passed}/${report.total}` :
        `未通过：${report.passed}/${report.total}`;
    } catch (_error) {
      if (generation !== this.runGeneration) {
        return;
      }
      this.status = `未通过：0/${DOMAIN_FIXTURE_COUNT}（门禁启动失败）`;
    }
    this.running = false;
  }
}
