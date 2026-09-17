import { ApplicationStateChangeCallback, common, Want } from '@kit.AbilityKit';
import {
  getAppSessionOwner,
  SessionCookie,
  ZhihuQrLoginClient
} from 'data';
import { completesUserAuthentication, LoginController, LoginPhase, LoginViewState } from './LoginController';
import { PhoneLoginPage } from './PhoneLoginPage';
import { RiskControlWebPage } from './RiskControlWebPage';
import { WebLoginPage } from './WebLoginPage';
import { FLOATING_TITLE_BAR_OFFSET } from './AppPageChrome';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/** 登录模式（对齐上游 LOGIN_MODE_PHONE=2 / LOGIN_MODE_QR=1 / LOGIN_MODE_WEB=0）。 */
const LOGIN_MODE_PHONE = 0;
const LOGIN_MODE_QR = 1;
const LOGIN_MODE_WEB = 2;

/** 登录前免责声明页（对齐上游 LoginScreen.loginNotices；次级按钮为空串时隐藏）。 */
interface LoginNotice {
  message: string;
  secondaryText: string;
  secondaryUrl: string;
}

const LOGIN_NOTICE_COUNT = 3;

const LOGIN_NOTICES: Array<LoginNotice> = [
  {
    message: '我清楚，本应用由开源社区开发和维护，不由知乎官方开发并运营，也不受到知乎官方的承认或支持，' +
      '使用本应用的一切后果由我本人承担。我可以在 https://www.zhihu.com/app/ 下载官方应用。',
    secondaryText: '下载官方 App',
    secondaryUrl: 'https://www.zhihu.com/app/'
  },
  {
    message: '在使用本应用的过程中，我承诺遵守知乎使用协议 https://www.zhihu.com/term/zhihu-terms 。' +
      '我保证在使用过程中不侵犯知乎及其他作者的著作权，使用本应用产生的一切输出仅用于个人浏览和备份，' +
      '不会进行传播等其他影响作者著作权的行为。',
    secondaryText: '查看协议',
    secondaryUrl: 'https://www.zhihu.com/term/zhihu-terms'
  },
  {
    // 上游第三页指向遥测设置；鸿蒙侧暂无遥测收集，文案据实调整。
    message: '我知晓，本应用目前不收集用于统计使用人数的遥测数据；如后续引入相关功能，我可以在设置中随时关闭。',
    secondaryText: '',
    secondaryUrl: ''
  }
];

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
  @State private noticeStep: number = 0;
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
    this.riskCookies = [];
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        // 不再展示当前登录账户块；仅在验证/错误等非空闲态保留流程反馈文本
        if (this.showStatusLine()) {
          Text(this.viewState.message)
            .id('p2_login_status')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor(this.viewState.phase === LoginPhase.ERROR ||
              this.viewState.phase === LoginPhase.SESSION_EXPIRED
              ? $r('app.color.error_text')
              : $r('app.color.secondary_text'))
            .width('100%')
        }

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

        if (this.selectedMode === LOGIN_MODE_WEB) {
          WebLoginPage({
            onCookiesCaptured: (cookies: Array<SessionCookie>): void => {
              this.controller?.loginWithCookies(cookies);
            },
            onExternalUrl: (url: string): void => {
              this.openExternalLogin(url);
            }
          })
            .layoutWeight(1)
            .width('100%')
        } else {
          Scroll() {
            Column({ space: $r('app.float.p1_spacing_large') }) {
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

              if (this.viewState.logoutEnabled) {
                Button('退出登录')
                  .id('p2_login_logout')
                  .width('100%')
                  .onClick(() => this.controller?.logout())
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ bottom: $r('app.float.p1_page_padding') })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: FLOATING_TITLE_BAR_OFFSET })
      .backgroundColor($r('app.color.page_background'))

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

      // 登录前免责声明：整页不透明叠层盖住登录 UI（对齐上游 LoginScreen noticeStep 流程），
      // 三页逐页确认后才进入登录方式选择；每次进入登录页重新展示（上游 rememberSaveable 同口径）。
      if (this.noticeStep < LOGIN_NOTICE_COUNT) {
        this.loginNoticePage()
      }
    }
    .id('p2_login_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  /** 免责声明单页：文案居中于剩余空间，底部次级按钮 + 确认（对齐上游 LoginNoticeScreen）。 */
  @Builder
  loginNoticePage() {
    Column() {
      Column() {
        Text(LOGIN_NOTICES[this.noticeStep].message)
          .id('p2_login_notice_message')
          .fontSize($r('app.float.p1_body_font_size'))
          .lineHeight(24)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
          .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding') })
      }
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .width('100%')
      .padding({ top: FLOATING_TITLE_BAR_OFFSET })

      Column({ space: $r('app.float.p1_spacing_medium') }) {
        if (LOGIN_NOTICES[this.noticeStep].secondaryUrl !== '') {
          Button(LOGIN_NOTICES[this.noticeStep].secondaryText)
            .id('p2_login_notice_secondary')
            .width('100%')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.brand_primary'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.brand_primary'), radius: $r('app.float.p1_card_radius') })
            .onClick((): void => {
              this.openExternalLogin(LOGIN_NOTICES[this.noticeStep].secondaryUrl);
            })
        }

        Button('确认')
          .id('p2_login_notice_confirm')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick((): void => {
            this.noticeStep += 1;
          })
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        bottom: $r('app.float.p1_page_padding') })
    }
    .id(`p2_login_notice_step_${this.noticeStep + 1}`)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
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

  /** 游客/已登录为空闲态不显示状态文本，其余（验证中/错误/二维码流程等）保留反馈。 */
  private showStatusLine(): boolean {
    return this.viewState.phase !== LoginPhase.GUEST && this.viewState.phase !== LoginPhase.AUTHENTICATED;
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
