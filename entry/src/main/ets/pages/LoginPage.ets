import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { COOKIE_HEADER_MAX_LENGTH, getAppSessionOwner, ZhihuQrLoginClient } from 'data';
import { completesUserAuthentication, LoginController, LoginPhase, LoginViewState } from './LoginController';

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
  @State private cookieInput: string = '';
  @State private viewState: LoginViewState = {
    phase: LoginPhase.GUEST,
    message: '当前为游客模式',
    manualLoginEnabled: true,
    qrStartEnabled: true,
    qrCancelable: false,
    logoutEnabled: false
  };
  private controller?: LoginController;
  private applicationContext?: common.ApplicationContext;
  private applicationStateCallback?: LoginApplicationStateCallback;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller = new LoginController(
      getAppSessionOwner(context).getRepository(),
      new ZhihuQrLoginClient(),
      (state: LoginViewState): void => {
        const previousPhase = this.viewState.phase;
        this.viewState = state;
        if (completesUserAuthentication(previousPhase, state.phase)) {
          this.onAuthenticated();
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
    this.cookieInput = '';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Button('返回')
              .id('p2_login_back')
              .accessibilityText('返回上一页')
              .onClick(() => this.onBack())
            Text('账号与登录')
              .fontSize($r('app.float.p1_display_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
          }
          .width('100%')

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

          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text('手动 Cookie 登录')
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

          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text('二维码登录')
              .fontSize($r('app.float.p1_heading_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
            Text('请使用另一台已登录知乎的设备扫码。本机 Scan Kit 识码结果不会被当作登录完成。')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))

            if (this.viewState.qrLink !== undefined) {
              QRCode(this.viewState.qrLink)
                .id('p2_login_qr_code')
                .width(220)
                .height(220)
                .color(Color.Black)
                .backgroundColor(Color.White)
                .accessibilityText('知乎登录二维码')
            }

            if (this.viewState.riskControlUrl !== undefined) {
              Text('需要完成知乎网络环境验证，当前页面不会自动打开网页：')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
              Text(this.viewState.riskControlUrl)
                .id('p2_login_risk_url')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.brand_primary'))
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

          if (this.viewState.logoutEnabled) {
            Button('退出登录')
              .id('p2_login_logout')
              .width('100%')
              .onClick(() => this.controller?.logout())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_page_padding'))
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))
    }
    .id('p2_login_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }
}
