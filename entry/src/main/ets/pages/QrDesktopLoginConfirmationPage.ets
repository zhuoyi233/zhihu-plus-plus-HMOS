import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { getAppSessionOwner, toCookieHeader } from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import {
  isConfirmedQrDesktopLoginUrl,
  shouldBlockQrDesktopLoginNavigation
} from '../scan/QrDesktopLoginConfirmationPolicy';

class QrDesktopLoginConfirmationApplicationStateCallback extends ApplicationStateChangeCallback {
  private readonly onBackgroundAction: () => void;

  constructor(onBackgroundAction: () => void) {
    super();
    this.onBackgroundAction = onBackgroundAction;
  }

  onApplicationBackground(): void {
    this.onBackgroundAction();
  }
}

/**
 * P4-6 受限确认页：只接收已由扫码控制器确认过的精确知乎电脑登录链接。
 * URL 仅存在于页面实例内存；页面关闭、取消或进入后台时立即清除，绝不进入路由、
 * 日志、持久化数据或文本 UI。
 */
@Component
export struct QrDesktopLoginConfirmationPage {
  confirmedUrl: string = '';
  onDismiss: () => void = (): void => {
  };
  @State private webVisible: boolean = false;
  @State private status: string = '正在准备电脑登录确认页…';
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private applicationContext?: common.ApplicationContext;
  private applicationStateCallback?: QrDesktopLoginConfirmationApplicationStateCallback;

  aboutToAppear(): void {
    if (!isConfirmedQrDesktopLoginUrl(this.confirmedUrl)) {
      this.status = '登录确认链接无效，已拒绝打开';
      this.clearConfirmedUrl();
      return;
    }
    this.registerApplicationStateCallback();
    this.injectSessionCookies();
    this.webVisible = true;
  }

  aboutToDisappear(): void {
    this.unregisterApplicationStateCallback();
    this.clearConfirmedUrl();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.webVisible) {
        Web({ src: this.confirmedUrl, controller: this.controller })
          .id('p4_qr_desktop_login_confirmation_web')
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
            return shouldBlockQrDesktopLoginNavigation(event.data.getRequestUrl(), event.data.isMainFrame(),
              this.confirmedUrl);
          })
          .onPageBegin((): void => {
            this.status = '正在打开电脑登录确认页…';
          })
          .onPageEnd((): void => {
            this.status = '请在页面内完成电脑登录确认';
          })
          .onErrorReceive((_event): void => {
            this.status = '确认页加载失败，请返回后重新扫描';
          })
      } else {
        Column() {
          Text(this.status)
            .id('p4_qr_desktop_login_confirmation_status')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      }

      Button('取消电脑登录')
        .id('p4_qr_desktop_login_confirmation_cancel')
        .margin({ left: $r('app.float.p1_spacing_medium'), top: $r('app.float.p1_spacing_medium') })
        .opacity(0.9)
        .onClick((): void => {
          this.dismiss();
        })
    }
    .id('p4_qr_desktop_login_confirmation_container')
    .width('100%')
    .height('100%')
  }

  private registerApplicationStateCallback(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const applicationContext = context.getApplicationContext();
    const callback = new QrDesktopLoginConfirmationApplicationStateCallback((): void => {
      this.dismiss();
    });
    try {
      applicationContext.on('applicationStateChange', callback);
      this.applicationContext = applicationContext;
      this.applicationStateCallback = callback;
    } catch (_error) {
      this.applicationContext = undefined;
      this.applicationStateCallback = undefined;
    }
  }

  private unregisterApplicationStateCallback(): void {
    const applicationContext = this.applicationContext;
    const callback = this.applicationStateCallback;
    this.applicationContext = undefined;
    this.applicationStateCallback = undefined;
    if (applicationContext === undefined || callback === undefined) {
      return;
    }
    try {
      applicationContext.off('applicationStateChange', callback);
    } catch (_error) {
    }
  }

  private injectSessionCookies(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const cookies = getAppSessionOwner(context).getRepository().getCookies();
    if (cookies.length === 0) {
      return;
    }
    try {
      webview.WebCookieManager.setCookie('https://www.zhihu.com/',
        `${toCookieHeader(cookies, Date.now())}; Domain=.zhihu.com; Path=/`);
    } catch (_error) {
      // Cookie 注入失败不扩大权限或回退到系统浏览器；页面是否可确认由知乎页面决定。
    }
  }

  private dismiss(): void {
    this.clearConfirmedUrl();
    this.webVisible = false;
    try {
      this.controller.clearHistory();
      this.controller.loadUrl('about:blank');
    } catch (_error) {
      // 控制器尚未绑定时没有页面可停止加载。
    }
    this.onDismiss();
  }

  private clearConfirmedUrl(): void {
    this.confirmedUrl = '';
  }
}
