import {
  onThemeColor,
  DEFAULT_THEME_COLOR,
  defaultPhoneLoginDeviceInfo,
  PhoneDigitsResultKind,
  PhoneLoginError,
  SessionCookie,
  ZhihuPhoneLoginClient
} from 'data';

const RESEND_COUNTDOWN_SECONDS = 60;

/** 服务端英文参数级报错（如 miss arg grant_type，实测为风控/网关层拒绝）直译无指导意义，
 * 转译为可行动提示并括注原文。协议层已与上游逐字节对齐，此类报错不是客户端参数缺失。 */
function friendlyPhoneLoginMessage(raw: string, fallback: string): string {
  if (raw.length === 0) {
    return fallback;
  }
  if (/miss arg/i.test(raw)) {
    return `登录失败：服务端拒绝了本次请求（疑似风控），请稍后重试或改用 Cookie 登录（${raw}）`;
  }
  return raw;
}

/**
 * P3-10：手机号登录卡片（对齐上游 PhoneLoginPane）。
 * 流程：手机号 → 发送短信验证码（可能要求图形验证码）→ 输入验证码登录。
 * 布局对齐上游：验证码输入框在左、发送/倒计时按钮在右（60s 倒计时），
 * 下方为整行可点按的协议勾选行；登录按钮需勾选协议 + 手机号 11 位 + 验证码 6 位。
 * 登录成功后通过 onCookiesCaptured 把会话 cookie 交给登录页控制器验证。
 */
@Component
export struct PhoneLoginPage {
  onCookiesCaptured: (cookies: Array<SessionCookie>) => void = (): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private phone: string = '';
  @State private digits: string = '';
  @State private captchaInput: string = '';
  @State private captchaImageBase64: string = '';
  @State private captchaRequired: boolean = false;
  @State private agreementChecked: boolean = false;
  @State private hasRequestedDigits: boolean = false;
  @State private isSendingDigits: boolean = false;
  @State private isLoggingIn: boolean = false;
  @State private resendSeconds: number = 0;
  @State private message: string = '';
  private client?: ZhihuPhoneLoginClient;
  private resendTimerId: number = -1;

  aboutToAppear(): void {
    this.client = new ZhihuPhoneLoginClient([], defaultPhoneLoginDeviceInfo());
  }

  aboutToDisappear(): void {
    this.stopResendCountdown();
    this.client?.destroy();
    this.client = undefined;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('手机号登录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      Text('使用知乎官方 Android 登录协议。是否需要图形验证码由知乎风控实时决定。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))

      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('+86')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
        TextInput({ text: this.phone, placeholder: '请输入手机号' })
          .id('p3_phone_input')
          .type(InputType.PhoneNumber)
          .layoutWeight(1)
          .maxLength(11)
          .enabled(!this.isSendingDigits && !this.isLoggingIn)
          .onChange((value: string): void => {
            this.onPhoneChanged(value);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.captchaRequired) {
        Column({ space: $r('app.float.p1_spacing_small') }) {
          Image(this.captchaDataUri())
            .id('p3_phone_captcha_image')
            .width('100%')
            .height(96)
            .objectFit(ImageFit.Contain)
            .backgroundColor($r('app.color.divider_color'))
          TextInput({ text: this.captchaInput, placeholder: '图形验证码' })
            .id('p3_phone_captcha_input')
            .maxLength(16)
            .enabled(!this.isSendingDigits)
            .onChange((value: string): void => {
              this.captchaInput = value;
            })
          Row({ space: $r('app.float.p1_spacing_medium') }) {
            Button('换一张')
              .id('p3_phone_captcha_refresh')
              .layoutWeight(1)
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor(this.resolvedThemeColor)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: this.resolvedThemeColor, radius: $r('app.float.p1_card_radius') })
              .enabled(!this.isSendingDigits)
              .onClick((): void => {
                this.refreshCaptchaImage();
              })
            Button('验证并发送')
              .backgroundColor(this.resolvedThemeColor)
              .fontColor(onThemeColor(this.resolvedThemeColor))
              .id('p3_phone_captcha_submit')
              .layoutWeight(1)
              .fontSize($r('app.float.p1_body_font_size'))
              .enabled(this.captchaInput.trim().length > 0 && !this.isSendingDigits)
              .onClick((): void => {
                this.verifyCaptchaAndSend();
              })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      // 对齐上游：短信验证码输入框（左）+ 发送/倒计时按钮（右）同一行
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        TextInput({ text: this.digits, placeholder: '短信验证码' })
          .id('p3_phone_digits_input')
          .type(InputType.Number)
          .layoutWeight(1)
          .maxLength(6)
          .enabled(!this.isSendingDigits && !this.isLoggingIn)
          .onChange((value: string): void => {
            this.digits = value.replace(/\D/g, '').substring(0, 6);
          })
        Button() {
          if (this.isSendingDigits) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Color.White)
          } else {
            Text(this.resendSeconds > 0 ? `${this.resendSeconds}s` : '发送验证码')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor(Color.White)
          }
        }
        .id('p3_phone_send')
        .width(112)
        .height(40)
        .padding({ left: 8, right: 8 })
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(this.canSendDigits())
        .onClick((): void => {
          this.sendDigits();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 对齐上游：协议勾选行，整行可点按切换
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Checkbox()
          .id('p3_phone_agreement')
          .select(this.agreementChecked)
          .selectedColor(this.resolvedThemeColor)
          .onChange((checked: boolean): void => {
            this.agreementChecked = checked;
          })
        Text('我已阅读并同意《知乎协议》《个人信息保护指引》')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
      }
      .id('p3_phone_agreement_row')
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.agreementChecked = !this.agreementChecked;
      })

      Button(this.isLoggingIn ? '正在登录…' : '登录')
        .backgroundColor(this.resolvedThemeColor)
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .id('p3_phone_signin')
        .width('100%')
        .enabled(this.canSignIn())
        .onClick((): void => {
          this.signIn();
        })

      if (this.message.length > 0) {
        Text(this.message)
          .id('p3_phone_status')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor(this.message.includes('失败') || this.message.includes('错误') ||
            this.message.includes('不正确') ? $r('app.color.error_text') : $r('app.color.secondary_text'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  private onPhoneChanged(value: string): void {
    const next = value.replace(/\D/g, '').substring(0, 11);
    if (this.phone === next) {
      return;
    }
    // 对齐上游：手机号变更后重置验证码/图形验证码状态，需重新发送
    this.phone = next;
    this.digits = '';
    this.hasRequestedDigits = false;
    this.captchaRequired = false;
    this.captchaImageBase64 = '';
    this.captchaInput = '';
  }

  /** 对齐上游 sendDigits 按钮可用条件：已同意协议 + 手机号 11 位 + 不在倒计时 + 不在请求中。 */
  private canSendDigits(): boolean {
    return this.agreementChecked && this.phone.length === 11 &&
      this.resendSeconds === 0 && !this.isSendingDigits && !this.isLoggingIn;
  }

  private canSignIn(): boolean {
    return this.agreementChecked && this.hasRequestedDigits && this.phone.length === 11 &&
      this.digits.length === 6 && !this.isSendingDigits && !this.isLoggingIn;
  }

  private captchaDataUri(): string {
    const image = this.captchaImageBase64;
    if (image.length === 0) {
      return '';
    }
    return image.startsWith('/9j') ? `data:image/jpeg;base64,${image}` : `data:image/png;base64,${image}`;
  }

  private startResendCountdown(): void {
    this.stopResendCountdown();
    this.resendSeconds = RESEND_COUNTDOWN_SECONDS;
    this.resendTimerId = setInterval((): void => {
      if (this.resendSeconds > 0) {
        this.resendSeconds -= 1;
      }
      if (this.resendSeconds === 0) {
        this.stopResendCountdown();
      }
    }, 1000);
  }

  private stopResendCountdown(): void {
    if (this.resendTimerId !== -1) {
      clearInterval(this.resendTimerId);
      this.resendTimerId = -1;
    }
  }

  private async sendDigits(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.isSendingDigits || this.phone.length !== 11) {
      return;
    }
    this.isSendingDigits = true;
    this.message = '';
    try {
      const result = await client.requestDigits(this.phone);
      if (result.kind === PhoneDigitsResultKind.SENT) {
        this.hasRequestedDigits = true;
        this.captchaRequired = false;
        this.captchaImageBase64 = '';
        this.captchaInput = '';
        this.startResendCountdown();
        this.message = '短信验证码已发送，请注意查收';
      } else if (result.kind === PhoneDigitsResultKind.CAPTCHA_REQUIRED) {
        this.captchaRequired = true;
        this.captchaImageBase64 = result.captchaImageBase64 ?? '';
        this.captchaInput = '';
        this.message = this.captchaImageBase64.length === 0 ? '服务器未返回图形验证码，请换一张重试' : '请先完成图形验证码';
      } else {
        this.message = friendlyPhoneLoginMessage(result.errorMessage ?? '', '验证码发送失败，请重试');
      }
    } catch (error) {
      this.message = error instanceof PhoneLoginError
        ? friendlyPhoneLoginMessage(error.message, '网络错误，请稍后重试')
        : '网络错误，请稍后重试';
    } finally {
      this.isSendingDigits = false;
    }
  }

  private async refreshCaptchaImage(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.isSendingDigits) {
      return;
    }
    this.message = '';
    try {
      this.captchaImageBase64 = await client.refreshCaptcha();
      if (this.captchaImageBase64.length === 0) {
        this.message = '服务器未返回图形验证码，请稍后重试';
      }
    } catch (error) {
      this.message = error instanceof PhoneLoginError ? error.message : '刷新图形验证码失败';
    }
  }

  private async verifyCaptchaAndSend(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.isSendingDigits) {
      return;
    }
    this.isSendingDigits = true;
    this.message = '';
    try {
      const verified = await client.verifyCaptcha(this.captchaInput);
      if (!verified) {
        this.message = '图形验证码不正确';
        return;
      }
      await this.sendDigits();
    } catch (error) {
      this.message = error instanceof PhoneLoginError
        ? friendlyPhoneLoginMessage(error.message, '验证图形验证码失败')
        : '验证图形验证码失败';
    } finally {
      this.isSendingDigits = false;
    }
  }

  private async signIn(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.isLoggingIn || !this.canSignIn()) {
      return;
    }
    this.isLoggingIn = true;
    this.message = '';
    try {
      const token = await client.signIn(this.phone, this.digits);
      this.onCookiesCaptured(token.cookies);
    } catch (error) {
      this.message = error instanceof PhoneLoginError
        ? friendlyPhoneLoginMessage(error.message, '登录失败，请稍后重试')
        : '登录失败，请稍后重试';
    } finally {
      this.isLoggingIn = false;
    }
  }
}
