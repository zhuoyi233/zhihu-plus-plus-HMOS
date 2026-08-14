import {
  defaultPhoneLoginDeviceInfo,
  PhoneDigitsResultKind,
  PhoneLoginError,
  SessionCookie,
  ZhihuPhoneLoginClient
} from 'data';

/** 手机号登录卡片内部步骤（对齐上游 PhoneLoginPane 的 UI 状态机）。 */
enum PhoneLoginStep {
  IDLE = 'idle',
  SENDING = 'sending',
  CAPTCHA_REQUIRED = 'captcha_required',
  DIGITS_SENT = 'digits_sent',
  SIGNING_IN = 'signing_in'
}

function normalizePhoneInput(input: string): string {
  let compact = input.trim().replace(/ /g, '').replace(/-/g, '');
  if (compact.startsWith('+86')) {
    compact = compact.substring(3);
  } else if (compact.startsWith('86') && compact.length === 13) {
    compact = compact.substring(2);
  }
  return compact;
}

/**
 * P3-10：手机号登录卡片（对齐上游 PhoneLoginPane）。
 * 流程：手机号 → 发送短信验证码（可能要求图形验证码）→ 输入验证码登录。
 * 登录成功后通过 onCookiesCaptured 把会话 cookie 交给登录页控制器验证。
 */
@Component
export struct PhoneLoginPage {
  onCookiesCaptured: (cookies: Array<SessionCookie>) => void = (): void => {
  };
  @State private phone: string = '';
  @State private digits: string = '';
  @State private captchaInput: string = '';
  @State private captchaImageBase64: string = '';
  @State private step: PhoneLoginStep = PhoneLoginStep.IDLE;
  @State private message: string = '';
  @State private agreementChecked: boolean = true;
  private client?: ZhihuPhoneLoginClient;

  aboutToAppear(): void {
    this.client = new ZhihuPhoneLoginClient([], defaultPhoneLoginDeviceInfo());
  }

  aboutToDisappear(): void {
    this.client?.destroy();
    this.client = undefined;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('手机号登录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      Text('使用知乎账号绑定的手机号接收短信验证码登录。')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))

      TextInput({ text: this.phone, placeholder: '请输入手机号' })
        .id('p3_phone_input')
        .type(InputType.PhoneNumber)
        .maxLength(20)
        .enabled(!this.busy())
        .onChange((value: string): void => {
          this.phone = value;
        })

      Row({ space: $r('app.float.p1_spacing_small') }) {
        Checkbox()
          .id('p3_phone_agreement')
          .select(this.agreementChecked)
          .selectedColor($r('app.color.brand_primary'))
          .onChange((checked: boolean): void => {
            this.agreementChecked = checked;
          })
        Text('已阅读并同意《知乎协议》')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')

      Button(this.step === PhoneLoginStep.DIGITS_SENT ? '重新发送验证码' : '发送短信验证码')
        .id('p3_phone_send')
        .width('100%')
        .enabled(!this.busy() && this.agreementChecked && this.phoneValid())
        .onClick((): void => {
          this.sendDigits();
        })

      if (this.step === PhoneLoginStep.CAPTCHA_REQUIRED) {
        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('需要完成图形验证码')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
          Row({ space: $r('app.float.p1_spacing_medium') }) {
            Image(this.captchaDataUri())
              .id('p3_phone_captcha_image')
              .width(120)
              .height(44)
              .objectFit(ImageFit.Contain)
              .backgroundColor($r('app.color.divider_color'))
            Button('换一张')
              .id('p3_phone_captcha_refresh')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .onClick((): void => {
                this.refreshCaptchaImage();
              })
          }
          TextInput({ text: this.captchaInput, placeholder: '输入图中字符' })
            .id('p3_phone_captcha_input')
            .maxLength(16)
            .enabled(!this.busy())
            .onChange((value: string): void => {
              this.captchaInput = value;
            })
          Button('验证并发送验证码')
            .id('p3_phone_captcha_submit')
            .width('100%')
            .enabled(!this.busy() && this.captchaInput.trim().length > 0)
            .onClick((): void => {
              this.verifyCaptchaAndSend();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      if (this.step === PhoneLoginStep.DIGITS_SENT || this.step === PhoneLoginStep.SIGNING_IN) {
        Column({ space: $r('app.float.p1_spacing_small') }) {
          TextInput({ text: this.digits, placeholder: '输入短信验证码' })
            .id('p3_phone_digits_input')
            .type(InputType.Number)
            .maxLength(8)
            .enabled(this.step !== PhoneLoginStep.SIGNING_IN)
            .onChange((value: string): void => {
              this.digits = value;
            })
          Button('登录')
            .id('p3_phone_signin')
            .width('100%')
            .enabled(this.step !== PhoneLoginStep.SIGNING_IN && this.digits.trim().length > 0)
            .onClick((): void => {
              this.signIn();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

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

  private busy(): boolean {
    return this.step === PhoneLoginStep.SENDING || this.step === PhoneLoginStep.SIGNING_IN;
  }

  private phoneValid(): boolean {
    return /^1\d{10}$/.test(normalizePhoneInput(this.phone));
  }

  private captchaDataUri(): string {
    const image = this.captchaImageBase64;
    if (image.length === 0) {
      return '';
    }
    return image.startsWith('/9j') ? `data:image/jpeg;base64,${image}` : `data:image/png;base64,${image}`;
  }

  private async sendDigits(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.busy() || !this.phoneValid()) {
      return;
    }
    this.step = PhoneLoginStep.SENDING;
    this.message = '';
    try {
      const result = await client.requestDigits(this.phone);
      if (result.kind === PhoneDigitsResultKind.SENT) {
        this.step = PhoneLoginStep.DIGITS_SENT;
        this.message = '短信验证码已发送，请注意查收';
      } else if (result.kind === PhoneDigitsResultKind.CAPTCHA_REQUIRED) {
        this.step = PhoneLoginStep.CAPTCHA_REQUIRED;
        this.captchaImageBase64 = result.captchaImageBase64 ?? '';
        this.captchaInput = '';
        this.message = '请先完成图形验证码';
      } else {
        this.step = PhoneLoginStep.IDLE;
        this.message = result.errorMessage ?? '验证码发送失败，请重试';
      }
    } catch (error) {
      this.step = PhoneLoginStep.IDLE;
      this.message = error instanceof PhoneLoginError ? error.message : '网络错误，请稍后重试';
    }
  }

  private async refreshCaptchaImage(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.busy()) {
      return;
    }
    this.message = '';
    try {
      this.captchaImageBase64 = await client.refreshCaptcha();
    } catch (error) {
      this.message = error instanceof PhoneLoginError ? error.message : '验证码获取失败，请重试';
    }
  }

  private async verifyCaptchaAndSend(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.busy()) {
      return;
    }
    this.step = PhoneLoginStep.SENDING;
    this.message = '';
    try {
      const verified = await client.verifyCaptcha(this.captchaInput);
      if (!verified) {
        this.step = PhoneLoginStep.CAPTCHA_REQUIRED;
        this.message = '图形验证码不正确，请重试';
        return;
      }
      const result = await client.requestDigits(this.phone);
      if (result.kind === PhoneDigitsResultKind.SENT) {
        this.step = PhoneLoginStep.DIGITS_SENT;
        this.message = '短信验证码已发送，请注意查收';
      } else if (result.kind === PhoneDigitsResultKind.CAPTCHA_REQUIRED) {
        this.step = PhoneLoginStep.CAPTCHA_REQUIRED;
        this.captchaImageBase64 = result.captchaImageBase64 ?? '';
        this.captchaInput = '';
        this.message = '仍需完成图形验证码';
      } else {
        this.step = PhoneLoginStep.IDLE;
        this.message = result.errorMessage ?? '验证码发送失败，请重试';
      }
    } catch (error) {
      this.step = PhoneLoginStep.CAPTCHA_REQUIRED;
      this.message = error instanceof PhoneLoginError ? error.message : '网络错误，请稍后重试';
    }
  }

  private async signIn(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.busy()) {
      return;
    }
    this.step = PhoneLoginStep.SIGNING_IN;
    this.message = '';
    try {
      const token = await client.signIn(this.phone, this.digits);
      this.onCookiesCaptured(token.cookies);
    } catch (error) {
      this.step = PhoneLoginStep.DIGITS_SENT;
      this.message = error instanceof PhoneLoginError ? error.message : '登录失败，请稍后重试';
    }
  }
}
