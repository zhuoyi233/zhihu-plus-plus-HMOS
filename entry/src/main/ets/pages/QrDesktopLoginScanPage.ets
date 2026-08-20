import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { QrScanner } from '../platform/P4PlatformServices';
import { SystemQrScanner } from '../platform/SystemQrScanner';
import {
  QrDesktopLoginScanController,
  QrDesktopLoginScanPhase,
  QrDesktopLoginScanViewState
} from '../scan/QrDesktopLoginScanFlow';

const INITIAL_STATE: QrDesktopLoginScanViewState = {
  phase: QrDesktopLoginScanPhase.READY,
  message: '请扫描电脑端显示的知乎登录二维码',
  scanEnabled: true,
  confirmEnabled: false,
  cancelEnabled: false
};

class QrDesktopLoginApplicationStateCallback extends ApplicationStateChangeCallback {
  private readonly controller: QrDesktopLoginScanController;

  constructor(controller: QrDesktopLoginScanController) {
    super();
    this.controller = controller;
  }

  onApplicationForeground(): void {
    this.controller.setForeground(true);
  }

  onApplicationBackground(): void {
    this.controller.setForeground(false);
  }
}

/** P4-6 生产入口：只完成扫码与明确确认，不执行未冻结的确认网络请求。 */
@Component
export struct QrDesktopLoginScanPage {
  onBack: () => void = (): void => {
  };
  @State private viewState: QrDesktopLoginScanViewState = INITIAL_STATE;
  private controller?: QrDesktopLoginScanController;
  private applicationContext?: common.ApplicationContext;
  private applicationStateCallback?: QrDesktopLoginApplicationStateCallback;

  aboutToAppear(): void {
    this.controller = new QrDesktopLoginScanController((state: QrDesktopLoginScanViewState): void => {
      this.viewState = state;
    });
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const applicationContext = context.getApplicationContext();
    const callback = new QrDesktopLoginApplicationStateCallback(this.controller);
    try {
      applicationContext.on('applicationStateChange', callback);
      this.applicationContext = applicationContext;
      this.applicationStateCallback = callback;
    } catch (_error) {
      this.applicationContext = undefined;
      this.applicationStateCallback = undefined;
    }
  }

  aboutToDisappear(): void {
    const applicationContext = this.applicationContext;
    const callback = this.applicationStateCallback;
    this.applicationContext = undefined;
    this.applicationStateCallback = undefined;
    if (applicationContext !== undefined && callback !== undefined) {
      try {
        applicationContext.off('applicationStateChange', callback);
      } catch (_error) {
      }
    }
    this.controller?.setForeground(false);
    this.controller = undefined;
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        Text('扫描电脑端登录码')
          .id('p4_qr_desktop_login_title')
          .fontSize($r('app.float.p1_display_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text('仅识别知乎电脑端登录二维码。识别后必须由你明确确认；扫码本身不会登录电脑。')
          .fontSize($r('app.float.p1_body_font_size'))
          .lineHeight(24)
          .fontColor($r('app.color.secondary_text'))

        Text(this.viewState.message)
          .id('p4_qr_desktop_login_status')
          .fontSize($r('app.float.p1_body_font_size'))
          .lineHeight(24)
          .fontColor($r('app.color.primary_text'))

        if (this.viewState.phase === QrDesktopLoginScanPhase.AWAITING_CONFIRMATION) {
          Column({ space: $r('app.float.p1_spacing_small') }) {
            Text('来源：www.zhihu.com')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
            Button('确认登录电脑')
              .id('p4_qr_desktop_login_confirm')
              .width('100%')
              .enabled(this.viewState.confirmEnabled)
              .onClick((): void => {
                this.controller?.confirm();
              })
            Button('取消')
              .id('p4_qr_desktop_login_cancel')
              .width('100%')
              .onClick((): void => {
                this.controller?.cancel();
              })
          }
          .width('100%')
        } else {
          Button(this.viewState.phase === QrDesktopLoginScanPhase.SCANNING ? '系统扫码中…' : '打开系统扫码')
            .id('p4_qr_desktop_login_scan')
            .width('100%')
            .enabled(this.viewState.scanEnabled)
            .onClick((): void => {
              this.startScan();
            })
        }

        Text('不会显示、保存或记录二维码令牌；当前确认请求合同尚未冻结，因此不会自动发送网络请求。')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .lineHeight(22)
          .fontColor($r('app.color.secondary_text'))

        Button('返回')
          .id('p4_qr_desktop_login_back')
          .width('100%')
          .onClick((): void => this.onBack())
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private startScan(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.viewState = {
        phase: QrDesktopLoginScanPhase.ERROR,
        message: '无法获取应用上下文，请返回后重试',
        scanEnabled: true,
        confirmEnabled: false,
        cancelEnabled: false
      };
      return;
    }
    const scanner: QrScanner = new SystemQrScanner(context);
    this.controller?.scan(scanner);
  }
}
