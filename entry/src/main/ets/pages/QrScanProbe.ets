import { BusinessError } from '@kit.BasicServicesKit';
import { detectBarcode, scanCore } from '@kit.ScanKit';
import { assessQrScanValue, QrScanDecision } from 'core';
import { QrScanner } from '../platform/P4PlatformServices';
import { SystemQrScanner } from '../platform/SystemQrScanner';
import { QR_FIXTURE_VALUE, writeQrScanFixture } from '../scan/QrScanFixture';

class QrScanServiceFailure extends Error {
  readonly code: number;

  constructor(code: number) {
    super('QR scan service failed');
    this.code = code;
  }
}

interface QrPolicyCase {
  input: string;
  expected: QrScanDecision;
}

const POLICY_CASES: Array<QrPolicyCase> = [
  { input: QR_FIXTURE_VALUE, expected: QrScanDecision.ZHIHU_DESKTOP_LOGIN },
  { input: 'https://www.zhihu.com.evil.example/account/scan/login/token', expected: QrScanDecision.UNSUPPORTED },
  { input: 'http://www.zhihu.com/account/scan/login/token', expected: QrScanDecision.UNSUPPORTED },
  { input: 'https://www.zhihu.com:8443/account/scan/login/token', expected: QrScanDecision.UNSUPPORTED },
  { input: 'https://user@www.zhihu.com/account/scan/login/token', expected: QrScanDecision.UNSUPPORTED },
  { input: 'https://www.zhihu.com/account//scan/login/token', expected: QrScanDecision.UNSUPPORTED },
  { input: 'https://www.zhihu.com/account/scan/login/token/', expected: QrScanDecision.UNSUPPORTED },
  { input: '   ', expected: QrScanDecision.INVALID }
];

@Component
export struct QrScanProbePage {
  onBack: () => void = () => {};
  @State private status: string = '尚未启动扫码';
  @State private policyStatus: string = '安全策略矩阵尚未运行';
  @State private scanning: boolean = false;

  aboutToAppear(): void {
    const passed = POLICY_CASES.filter((policyCase: QrPolicyCase) =>
      assessQrScanValue(policyCase.input).decision === policyCase.expected).length;
    this.policyStatus = passed === POLICY_CASES.length
      ? `通过：${passed}/${POLICY_CASES.length} 条二维码 URL 安全策略正确`
      : `失败：${passed}/${POLICY_CASES.length} 条二维码 URL 安全策略正确`;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Button('返回')
          .id('qr_scan_back')
          .onClick(() => this.onBack())

        Text('Scan Kit 二维码原型')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text('调用 HarmonyOS 系统扫码界面，仅识别 QR Code，并允许从相册选择码图。')
          .fontSize(16)
          .lineHeight(26)
          .fontColor($r('app.color.secondary_text'))

        Text('不发送登录确认请求，也不在页面或日志中显示二维码令牌。')
          .fontSize(16)
          .lineHeight(26)
          .fontColor($r('app.color.secondary_text'))

        Button(this.scanning ? '扫码界面启动中…' : '打开系统扫码')
          .id('open_system_qr_scan')
          .enabled(!this.scanning)
          .onClick(() => {
            this.startScan();
          })

        Button('运行内置码图识别')
          .id('decode_qr_fixture')
          .enabled(!this.scanning)
          .onClick(() => {
            this.decodeFixture();
          })

        Text(this.status)
          .id('qr_scan_status')
          .fontSize(17)
          .lineHeight(26)
          .fontColor($r('app.color.primary_text'))

        Text(this.policyStatus)
          .id('qr_policy_status')
          .fontSize(16)
          .lineHeight(24)
          .fontColor($r('app.color.primary_text'))

        Text('登录链路边界')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text('• 本原型：本机扫描电脑端知乎登录二维码。\n' +
          '• 后续登录实现：本机生成二维码、轮询知乎登录状态并将 Cookie 汇入 Session Repository。\n' +
          '• 两条路径都需要独立的风控与失效处理。')
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

  private async startScan(): Promise<void> {
    this.scanning = true;
    this.status = '正在打开 HarmonyOS 系统扫码界面…';
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('无法获取应用上下文');
      }
      const scanner: QrScanner = new SystemQrScanner(context);
      const value = await scanner.scanSingleQrCode();
      this.status = value === undefined ? '用户取消扫码' : assessQrScanValue(value).message;
    } catch (error) {
      const code = error instanceof QrScanServiceFailure ? error.code : undefined;
      this.status = code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED
        ? '用户取消扫码'
        : `扫码服务不可用（错误码 ${code ?? '未知'}）`;
    } finally {
      this.scanning = false;
    }
  }

  private async decodeFixture(): Promise<void> {
    this.scanning = true;
    this.status = '正在用 Scan Kit 识别内置测试码图…';
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('无法获取应用上下文');
      }
      const fixturePath = writeQrScanFixture(context.cacheDir);
      const results = await detectBarcode.decode({ uri: fixturePath }, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false
      }).catch((error: BusinessError) => {
        throw new QrScanServiceFailure(error.code);
      });
      const decodedValue = results.length === 1 ? results[0].originalValue : '';
      const assessment = assessQrScanValue(decodedValue);
      const success = decodedValue === QR_FIXTURE_VALUE &&
        assessment.decision === QrScanDecision.ZHIHU_DESKTOP_LOGIN;
      this.status = success
        ? '内置码图识别通过；登录二维码令牌未显示、未记录'
        : '内置码图识别失败或结果不符合登录 URL 策略';
    } catch (error) {
      const code = error instanceof QrScanServiceFailure ? error.code : '未知';
      this.status = `内置码图识别失败（错误码 ${code}）`;
    } finally {
      this.scanning = false;
    }
  }
}
