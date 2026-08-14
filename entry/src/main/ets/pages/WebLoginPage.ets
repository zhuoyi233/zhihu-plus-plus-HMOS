import { webview } from '@kit.ArkWeb';
import {
  getAppSessionOwner,
  parseWebCookieHeader,
  SessionCookie
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

const WEB_LOGIN_HOSTS: Array<string> = ['www.zhihu.com', 'zhuanlan.zhihu.com'];

function isTrustedWebLoginUrl(url: string): boolean {
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
  return WEB_LOGIN_HOSTS.includes(authority);
}

/** 桌面 Chrome UA（对齐上游 configureWebLogin 的桌面 UA 切换）。 */
const WEB_LOGIN_DESKTOP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

/**
 * P3-10：网页登录页（ArkWeb，对齐上游 configureWebLogin）。
 * 加载 https://www.zhihu.com/signin，登录成功后知乎跳回首页，
 * 在 onPageEnd 读回 cookie 并回调。
 */
@Component
export struct WebLoginPage {
  onCookiesCaptured: (cookies: Array<SessionCookie>) => void = (): void => {
  };
  onBack: () => void = (): void => {
  };
  @State private ready: boolean = false;
  @State private loadFailed: boolean = false;
  @State private status: string = '正在打开知乎登录页…';
  @State private captured: boolean = false;
  private readonly controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.loadFailed = true;
      this.status = '无法获取应用上下文';
      return;
    }
    // 清空 ArkWeb cookie，避免残留登录态影响（对齐上游 removeAllCookies）。
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (_error) {
    }
    try {
      webview.WebviewController.setUserAgentForHosts(WEB_LOGIN_DESKTOP_UA, WEB_LOGIN_HOSTS);
    } catch (_error) {
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Web({ src: 'https://www.zhihu.com/signin?next=%2F', controller: this.controller })
        .id('p3_web_login_web')
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .onPageBegin((): void => {
          this.ready = true;
          this.status = '登录页加载中…';
        })
        .onPageEnd((event): void => {
          this.ready = true;
          const currentUrl = event.url;
          this.status = '登录页已加载';
          if (!this.captured && isTrustedWebLoginUrl(currentUrl) && currentUrl === 'https://www.zhihu.com/') {
            // 登录成功后知乎跳回首页 → 读 cookie（对齐上游 onPageFinished + url == HOME）。
            this.captured = true;
            this.readCookies();
          }
        })
        .onErrorReceive((_event): void => {
          this.loadFailed = true;
          this.status = '登录页加载失败，请检查网络';
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
              .id('p3_web_login_retry')
              .onClick((): void => {
                this.loadFailed = false;
                this.ready = false;
                this.status = '正在打开知乎登录页…';
                this.controller.loadUrl('https://www.zhihu.com/signin?next=%2F');
              })
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      }

      Button('返回')
        .id('p3_web_login_back')
        .margin({ left: $r('app.float.p1_spacing_medium'), top: $r('app.float.p1_spacing_medium') })
        .opacity(0.9)
        .onClick((): void => {
          this.onBack();
        })
    }
    .id('p3_web_login_container')
    .width('100%')
    .height('100%')
  }

  private readCookies(): void {
    try {
      const raw = webview.WebCookieManager.getCookie('https://www.zhihu.com/');
      const cookies = parseWebCookieHeader(raw);
      if (cookies.length > 0) {
        this.onCookiesCaptured(cookies);
      }
    } catch (_error) {
      // cookie 读取失败不阻断
    }
  }
}
