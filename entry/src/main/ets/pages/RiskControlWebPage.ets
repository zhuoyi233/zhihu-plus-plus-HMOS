import { webview } from '@kit.ArkWeb';
import {
  getAppSessionOwner,
  parseWebCookieHeader,
  SessionCookie,
  toCookieHeader
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

const ZHIHU_RISK_HOSTS: Array<string> = ['www.zhihu.com', 'zhuanlan.zhihu.com'];

function isTrustedRiskUrl(url: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  const match = /^https:\/\/([^/?#]+)(?:[/?#]|$)/.exec(url);
  if (match === null) {
    return false;
  }
  const authority = match[1];
  if (authority.includes('@') || authority.includes(':')) {
    return false;
  }
  return ZHIHU_RISK_HOSTS.includes(authority);
}

/** 桌面 Chrome UA（对齐上游 ZHIHU_DESKTOP_USER_AGENT）。 */
const RISK_DESKTOP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

/**
 * P3-10：ArkWeb 风控验证页（对齐上游 configureRiskControlWebView）。
 * 注入会话 cookie + 桌面 UA，加载知乎风控页，页面加载完成后读回 cookie。
 */
@Component
export struct RiskControlWebPage {
  url: string = '';
  onCookiesChanged: (cookies: Array<SessionCookie>) => void = (): void => {
  };
  onDismiss: () => void = (): void => {
  };
  @State private ready: boolean = false;
  @State private loadFailed: boolean = false;
  @State private status: string = '正在打开验证页面…';
  private readonly controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.loadFailed = true;
      this.status = '无法获取应用上下文';
      return;
    }
    // 注入会话 cookie（对齐上游 CookieManager.setCookie + Domain=.zhihu.com）。
    const cookies = getAppSessionOwner(context).getRepository().getCookies();
    if (cookies.length > 0) {
      try {
        webview.WebCookieManager.setCookie('https://www.zhihu.com/',
          `${toCookieHeader(cookies, Date.now())}; Domain=.zhihu.com; Path=/`);
      } catch (_error) {
        // 继续加载，cookie 注入失败由页面内流程决定
      }
    }
    try {
      webview.WebviewController.setUserAgentForHosts(RISK_DESKTOP_UA, ZHIHU_RISK_HOSTS);
    } catch (_error) {
    }
  }

  private targetUrl(): string {
    return isTrustedRiskUrl(this.url) ? this.url : 'https://www.zhihu.com/account/risk_control/';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Web({ src: this.targetUrl(), controller: this.controller })
        .id('p3_risk_control_web')
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .onPageBegin((): void => {
          this.ready = true;
          this.status = '页面加载中…';
        })
        .onPageEnd((): void => {
          this.ready = true;
          this.status = '验证页面已加载，请完成页面内的验证';
          this.readCookies();
        })
        .onErrorReceive((_event): void => {
          this.loadFailed = true;
          this.status = '验证页面加载失败，请检查网络';
        })

      if (!this.ready || this.loadFailed) {
        Column({ space: $r('app.float.p1_spacing_medium') }) {
          if (!this.loadFailed) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.brand_primary'))
          }
          Text(this.status)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Center)
            .width('100%')
          if (this.loadFailed) {
            Button('重试')
              .id('p3_risk_control_retry')
              .onClick((): void => {
                this.loadFailed = false;
                this.ready = false;
                this.status = '正在打开验证页面…';
                this.controller.loadUrl(this.targetUrl());
              })
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      }

      Button('取消验证')
        .id('p3_risk_control_dismiss')
        .margin({ left: $r('app.float.p1_spacing_medium'), top: $r('app.float.p1_spacing_medium') })
        .opacity(0.9)
        .onClick((): void => {
          this.onDismiss();
        })
    }
    .id('p3_risk_control_container')
    .width('100%')
    .height('100%')
  }

  private readCookies(): void {
    try {
      const raw = webview.WebCookieManager.getCookie('https://www.zhihu.com/');
      const cookies = parseWebCookieHeader(raw);
      if (cookies.length > 0) {
        this.onCookiesChanged(cookies);
      }
    } catch (_error) {
      // cookie 读取失败不阻断页面
    }
  }
}
