import { ApplicationStateChangeCallback, common, Want } from '@kit.AbilityKit';
import {
  COOKIE_HEADER_MAX_LENGTH,
  getAppSessionOwner,
  SessionCookie,
  ZhihuQrLoginClient
} from 'data';
import { completesUserAuthentication, LoginController, LoginPhase, LoginViewState } from './LoginController';
import { PhoneLoginPage } from './PhoneLoginPage';
import { RiskControlWebPage } from './RiskControlWebPage';
import { WebLoginPage } from './WebLoginPage';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/** 登录模式（对齐上游 LOGIN_MODE_PHONE=2 / LOGIN_MODE_QR=1 / LOGIN_MODE_WEB=0）。 */
const LOGIN_MODE_PHONE = 0;
const LOGIN_MODE_QR = 1;
const LOGIN_MODE_WEB = 2;

class LoginApplicationStateCallback extends ApplicationStateChangeCallback {
  private readonly controller: LoginController;

  constructor(controller: LoginController) {
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

@Component
export struct LoginPage {
  onBack: () => void = (): void => {
  };
  onAuthenticated: () => void = (): void => {
  };
  onScanDesktopLogin: () => void = (): void => {
  };
  @State private cookieInput: string = '';
  @State private viewState: LoginViewState = {
    phase: LoginPhase.GUEST,
    message: '当前为游客模式',
    manualLoginEnabled: true,
    qrStartEnabled: true,
    qrCancelable: false,
    logoutEnabled: false,
    retainedSessionRetryEnabled: false
  };
  @State private selectedMode: number = LOGIN_MODE_PHONE;
  @State private showWebLogin: boolean = false;
  @State private riskCookies: Array<SessionCookie> = [];
  private controller?: LoginController;
  private abilityContext?: common.UIAbilityContext;
  private applicationContext?: common.ApplicationContext;
  private applicationStateCallback?: LoginApplicationStateCallback;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.viewState = {
        phase: LoginPhase.ERROR,
        message: '无法获取应用上下文，请重新打开页面',
        manualLoginEnabled: false,
        qrStartEnabled: false,
        qrCancelable: false,
        logoutEnabled: false,
        retainedSessionRetryEnabled: false
      };
      return;
    }
    this.abilityContext = getAbilityContext();
    this.controller = new LoginController(
      getAppSessionOwner(context).getRepository(),
      new ZhihuQrLoginClient(),
      (state: LoginViewState): void => {
        const previousPhase = this.viewState.phase;
        this.viewState = state;
        if (completesUserAuthentication(previousPhase, state.phase)) {
          this.onAuthenticated();
        }
        // 退出登录完成：广播会话变更，账号概览等界面据此刷新（见 P1Shell sessionStateTick）
        if (previousPhase === LoginPhase.LOGGING_OUT && state.phase === LoginPhase.GUEST) {
          const nextSessionTick = (AppStorage.get<number>('sessionStateTick') ?? 0) + 1;
          AppStorage.setOrCreate('sessionStateTick', nextSessionTick);
        }
      }
    );
    this.controller.activate();
    const applicationContext = context.getApplicationContext();
    const callback = new LoginApplicationStateCallback(this.controller);
    try {
      applicationContext.on('applicationStateChange', callback);
      this.applicationContext = applicationContext;
      this.applicationStateCallback = callback;
    } catch (_error) {
      this.applicationContext = undefined;
      this.applicationStateCallback = undefined;
      this.controller.setForeground(false);
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
    this.controller?.deactivate();
    this.controller = undefined;
    this.abilityContext = undefined;
    this.cookieInput = '';
    this.showWebLogin = false;
    this.riskCookies = [];
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
          Column({ space: $r('app.float.p1_spacing_small') }) {
            Text(this.viewState.profileName === undefined ? '游客模式' : this.viewState.profileName)
              .id('p2_login_identity')
              .fontSize($r('app.float.p1_heading_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
            Text(this.viewState.message)
              .id('p2_login_status')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          if (this.viewState.retainedSessionRetryEnabled) {
            Button('重试验证已保留会话')
              .id('p2_login_retry_retained_session')
              .width('100%')
              .onClick(() => this.controller?.retryRetainedSession())
          }

          Scroll() {
            Row({ space: $r('app.float.p1_spacing_medium') }) {
              this.modeTab(LOGIN_MODE_PHONE, '手机号')
              this.modeTab(LOGIN_MODE_QR, '扫码')
              this.modeTab(LOGIN_MODE_WEB, '网页')
            }
          }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)

          if (this.selectedMode === LOGIN_MODE_PHONE) {
            Column({ space: $r('app.float.p1_spacing_medium') }) {
              PhoneLoginPage({
                onCookiesCaptured: (cookies: Array<SessionCookie>): void => {
                  this.controller?.loginWithCookies(cookies);
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding($r('app.float.p1_card_padding'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
          }

          if (this.selectedMode === LOGIN_MODE_QR) {
            Column({ space: $r('app.float.p1_spacing_medium') }) {
              Text('二维码登录')
                .fontSize($r('app.float.p1_heading_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
              Text('请使用另一台已登录知乎的设备扫码。本机 Scan Kit 识码结果不会被当作登录完成。')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))

              Button('扫描电脑端登录二维码')
                .id('p4_login_desktop_scan_open')
                .width('100%')
                .onClick((): void => {
                  this.onScanDesktopLogin();
                })

              if (this.viewState.qrLink !== undefined) {
                QRCode(this.viewState.qrLink)
                  .id('p2_login_qr_code')
                  .width(220)
                  .height(220)
                  .color(Color.Black)
                  .backgroundColor(Color.White)
                  .accessibilityText('知乎登录二维码')
              }

              if (this.viewState.qrCancelable) {
                Button('取消二维码登录')
                  .id('p2_login_qr_cancel')
                  .width('100%')
                  .onClick(() => this.controller?.cancelQrLogin())
              } else {
                Button(this.viewState.phase === LoginPhase.QR_EXPIRED ? '刷新二维码' : '获取登录二维码')
                  .id('p2_login_qr_start')
                  .width('100%')
                  .enabled(this.viewState.qrStartEnabled)
                  .onClick(() => this.controller?.startQrLogin())
              }
            }
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .padding($r('app.float.p1_card_padding'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
          }

          if (this.selectedMode === LOGIN_MODE_WEB) {
            Column({ space: $r('app.float.p1_spacing_medium') }) {
              Text('网页登录（备用）')
                .fontSize($r('app.float.p1_heading_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
              Text('在应用内打开知乎网页版登录页，支持手机号/密码/邮箱等所有登录方式；登录成功后自动读回会话。')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
              Button('打开网页登录')
                .id('p3_web_login_open')
                .width('100%')
                .enabled(this.viewState.manualLoginEnabled)
                .onClick((): void => {
                  this.showWebLogin = true;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding($r('app.float.p1_card_padding'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
          }

          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text('手动 Cookie 登录（高级）')
              .fontSize($r('app.float.p1_heading_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
            Text('Cookie 仅用于本机身份验证并加密保存，提交后输入框会立即清空。')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
            TextInput({ text: this.cookieInput, placeholder: '粘贴 z_c0=…; d_c0=…' })
              .id('p2_login_cookie_input')
              .type(InputType.Password)
              .maxLength(COOKIE_HEADER_MAX_LENGTH)
              .enabled(this.viewState.manualLoginEnabled)
              .onChange((value: string): void => {
                this.cookieInput = value;
              })
            Button('验证并登录')
              .id('p2_login_cookie_submit')
              .width('100%')
              .enabled(this.viewState.manualLoginEnabled && this.cookieInput.trim().length > 0)
              .onClick((): void => {
                const submittedCookie = this.cookieInput;
                this.cookieInput = '';
                this.controller?.loginWithCookieHeader(submittedCookie);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          if (this.viewState.logoutEnabled) {
            Button('退出登录')
              .id('p2_login_logout')
              .width('100%')
              .onClick(() => this.controller?.logout())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
          top: 94, bottom: $r('app.float.p1_page_padding') })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))

      if (this.showWebLogin) {
        WebLoginPage({
          onCookiesCaptured: (cookies: Array<SessionCookie>): void => {
            this.showWebLogin = false;
            this.controller?.loginWithCookies(cookies);
          },
          onExternalUrl: (url: string): void => {
            this.openExternalLogin(url);
          },
          onBack: (): void => {
            this.showWebLogin = false;
          }
        })
          .width('100%')
          .height('100%')
      }

      if (this.viewState.phase === LoginPhase.RISK_CONTROL) {
        Column() {
          RiskControlWebPage({
            url: this.viewState.riskControlUrl ?? '',
            onCookiesChanged: (cookies: Array<SessionCookie>): void => {
              this.riskCookies = cookies;
            },
            onDismiss: (): void => {
              this.controller?.cancelQrLogin();
            }
          })
            .layoutWeight(1)
            .width('100%')

          Row({ space: $r('app.float.p1_spacing_medium') }) {
            Button('完成验证后继续扫码')
              .id('p3_risk_continue')
              .layoutWeight(1)
              .onClick((): void => {
                this.controller?.continueQrAfterRiskControl(this.riskCookies);
              })
            Button('取消')
              .id('p3_risk_abort')
              .onClick((): void => {
                this.controller?.cancelQrLogin();
              })
          }
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .backgroundColor($r('app.color.surface_background'))
        }
        .width('100%')
        .height('100%')
      }
    }
    .id('p2_login_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  modeTab(index: number, label: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor(this.selectedMode === index ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
        .fontWeight(this.selectedMode === index ? FontWeight.Medium : FontWeight.Regular)
      Blank()
        .height(2)
        .width('100%')
        .backgroundColor(this.selectedMode === index ? $r('app.color.brand_primary') : Color.Transparent)
    }
      .width(72)
      .id(index === LOGIN_MODE_PHONE ? 'p3_login_mode_phone' :
        index === LOGIN_MODE_QR ? 'p3_login_mode_qr' : 'p3_login_mode_web')
      .padding({ left: $r('app.float.p1_spacing_small'), right: $r('app.float.p1_spacing_small'), top: 8, bottom: 4 })
      .onClick((): void => {
        this.selectedMode = index;
      })
  }

  private openExternalLogin(url: string): void {
    const context = this.abilityContext;
    if (context === undefined) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url
    };
    context.startAbility(want).catch((_error: Error): void => {
    });
  }
}
