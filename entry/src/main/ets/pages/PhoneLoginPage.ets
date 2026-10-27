import {
  canRequestPhoneDigits,
  canSignInWithPhone,
  defaultPhoneLoginDeviceInfo,
  defaultPhoneLoginRegion,
  defaultPhoneNumberFormatPort,
  DEFAULT_PHONE_LOGIN_REGION_ID,
  DEFAULT_THEME_COLOR,
  findPhoneLoginRegion,
  onThemeColor,
  PHONE_CODE_LENGTH,
  PHONE_RESEND_COOLDOWN_SECONDS,
  PhoneDigitsGuard,
  PhoneDigitsResultKind,
  phoneCooldownRemainingSeconds,
  PhoneLoginError,
  phoneLoginIdentityKey,
  PhoneLoginRegion,
  PhoneLoginRequestGeneration,
  PhoneNumberIssue,
  PhoneSignInGuard,
  regionEntryLabel,
  resolvePhoneNumber,
  SessionCookie,
  ZhihuPhoneLoginClient
} from 'data';
import { PhoneCountryCodeSheet } from './PhoneCountryCodeSheet';

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
 * 流程：选择国家/地区 + 手机号 → 发送短信验证码（可能要求图形验证码）→ 输入验证码登录。
 *
 * 与大陆专用版本的差异（见 docs/phone-login-country-code-plan.md）：
 * - 号码规范化统一走 PhoneLoginNumberPolicy，UI 按钮、发码、登录三处使用同一结果；
 * - 已发码身份 = 地区 + 完整 username，切换地区（含 US→CA 这类同码切换）都会失效旧验证码；
 * - 冷却按到期时间计算，切换地区或号码不清零；
 * - 所有异步回调带请求代次，页面退出或身份变更后的迟到结果直接丢弃。
 */
@Component
export struct PhoneLoginPage {
  onCookiesCaptured: (cookies: Array<SessionCookie>) => void = (): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private regionId: string = DEFAULT_PHONE_LOGIN_REGION_ID;
  @State private regionSheetShown: boolean = false;
  @State private phone: string = '';
  @State private numberValid: boolean = false;
  @State private numberHint: string = '';
  @State private digits: string = '';
  @State private captchaInput: string = '';
  @State private captchaImageBase64: string = '';
  @State private captchaRequired: boolean = false;
  @State private agreementChecked: boolean = false;
  @State private isSendingDigits: boolean = false;
  @State private isLoggingIn: boolean = false;
  @State private resendSeconds: number = 0;
  @State private message: string = '';
  private sentIdentity: string = '';
  private username: string = '';
  private cooldownDeadlineMs: number = 0;
  private generation: PhoneLoginRequestGeneration = new PhoneLoginRequestGeneration();
  private disposed: boolean = false;
  private client?: ZhihuPhoneLoginClient;
  private resendTimerId: number = -1;

  aboutToAppear(): void {
    this.client = new ZhihuPhoneLoginClient([], defaultPhoneLoginDeviceInfo());
    this.applyNumberValidation();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.generation.invalidate();
    this.stopResendCountdown();
    this.client?.destroy();
    this.client = undefined;
  }

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Text('手机号登录')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      Text('使用知乎官方 Android 登录协议。是否需要图形验证码由知乎风控实时决定。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))

      Row({ space: $r('app.float.spacing_small') }) {
        this.regionEntry()
        TextInput({ text: this.phone, placeholder: this.phonePlaceholder() })
          .id('phone_input')
          .type(InputType.PhoneNumber)
          .layoutWeight(1)
          .maxLength(64)
          .enabled(this.editable())
          .onChange((value: string): void => {
            this.onPhoneChanged(value);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.numberHint.length > 0) {
        Text(this.numberHint)
          .id('phone_number_hint')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.error_text'))
      }

      if (this.captchaRequired) {
        Column({ space: $r('app.float.spacing_small') }) {
          Image(this.captchaDataUri())
            .id('phone_captcha_image')
            .width('100%')
            .height(96)
            .objectFit(ImageFit.Contain)
            .backgroundColor($r('app.color.divider_color'))
          TextInput({ text: this.captchaInput, placeholder: '图形验证码' })
            .id('phone_captcha_input')
            .maxLength(16)
            .enabled(!this.isSendingDigits)
            .onChange((value: string): void => {
              this.captchaInput = value;
            })
          Row({ space: $r('app.float.spacing_medium') }) {
            Button('换一张')
              .id('phone_captcha_refresh')
              .layoutWeight(1)
              .fontSize($r('app.float.body_font_size'))
              .fontColor(this.resolvedThemeColor)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: this.resolvedThemeColor, radius: $r('app.float.card_radius') })
              .enabled(!this.isSendingDigits)
              .onClick((): void => {
                this.refreshCaptchaImage();
              })
            Button('验证并发送')
              .backgroundColor(this.resolvedThemeColor)
              .fontColor(onThemeColor(this.resolvedThemeColor))
              .id('phone_captcha_submit')
              .layoutWeight(1)
              .fontSize($r('app.float.body_font_size'))
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
      Row({ space: $r('app.float.spacing_medium') }) {
        TextInput({ text: this.digits, placeholder: '短信验证码' })
          .id('phone_digits_input')
          .type(InputType.Number)
          .layoutWeight(1)
          .maxLength(PHONE_CODE_LENGTH)
          .enabled(this.editable())
          .onChange((value: string): void => {
            this.digits = value.replace(/\D/g, '').substring(0, PHONE_CODE_LENGTH);
          })
        Button() {
          if (this.isSendingDigits) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Color.White)
          } else {
            Text(this.resendSeconds > 0 ? `${this.resendSeconds}s` : '发送验证码')
              .fontSize($r('app.float.body_font_size'))
              .fontColor(Color.White)
          }
        }
        .id('phone_send')
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
      Row({ space: $r('app.float.spacing_small') }) {
        Checkbox()
          .id('phone_agreement')
          .select(this.agreementChecked)
          .selectedColor(this.resolvedThemeColor)
          .onChange((checked: boolean): void => {
            this.agreementChecked = checked;
          })
        Text('我已阅读并同意《知乎协议》《个人信息保护指引》')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
      }
      .id('phone_agreement_row')
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.agreementChecked = !this.agreementChecked;
      })

      Button(this.isLoggingIn ? '正在登录…' : '登录')
        .backgroundColor(this.resolvedThemeColor)
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .id('phone_signin')
        .width('100%')
        .enabled(this.canSignIn())
        .onClick((): void => {
          this.signIn();
        })

      if (this.message.length > 0) {
        Text(this.message)
          .id('phone_status')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor(this.message.includes('失败') || this.message.includes('错误') ||
            this.message.includes('不正确') ? $r('app.color.error_text') : $r('app.color.secondary_text'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .bindSheet(this.regionSheetShown, this.countrySheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      maskColor: '#66000000',
      backgroundColor: $r('app.color.surface_background'),
      onDisappear: (): void => {
        if (this.regionSheetShown) {
          this.regionSheetShown = false;
        }
      }
    })
  }

  @Builder
  private regionEntry() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 2 }) {
        Text(regionEntryLabel(this.currentRegion()))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.secondary_text')])
      }
    }
    .id('phone_region_entry')
    .constraintSize({ maxWidth: 132, minHeight: 40 })
    .padding({ left: 10, right: 8 })
    .backgroundColor($r('app.color.control_background'))
    .borderRadius($r('app.float.card_radius'))
    .enabled(this.editable())
    .accessibilityText(`选择国家/地区，当前${this.currentRegion().displayName}，` +
      `区号加${this.currentRegion().dialPrefix}`)
    .onClick((): void => {
      this.regionSheetShown = true;
    })
  }

  @Builder
  private countrySheet() {
    PhoneCountryCodeSheet({
      selectedRegionId: this.regionId,
      onSelect: (region: PhoneLoginRegion): void => {
        this.applyRegion(region);
      },
      onClose: (): void => {
        this.regionSheetShown = false;
      }
    })
  }

  private currentRegion(): PhoneLoginRegion {
    return findPhoneLoginRegion(this.regionId) ?? defaultPhoneLoginRegion();
  }

  private editable(): boolean {
    return !this.isSendingDigits && !this.isLoggingIn;
  }

  private phonePlaceholder(): string {
    return this.regionId === DEFAULT_PHONE_LOGIN_REGION_ID ? '请输入手机号' : '请输入本地手机号';
  }

  /** 当前输入的规范化结果；发送与登录都使用同一次解析得到的 username。 */
  private applyNumberValidation(): boolean {
    const resolution = resolvePhoneNumber(this.phone, this.currentRegion(), defaultPhoneNumberFormatPort());
    this.numberValid = resolution.valid;
    this.username = resolution.username;
    this.numberHint = resolution.issue === PhoneNumberIssue.EMPTY || resolution.valid
      ? '' : resolution.message;
    return resolution.valid;
  }

  /** 身份（地区 + 号码）变更：清空短信码、图形验证码、已发码身份与旧提示，但保留冷却。 */
  private invalidateDigits(): void {
    this.generation.invalidate();
    this.digits = '';
    this.captchaRequired = false;
    this.captchaImageBase64 = '';
    this.captchaInput = '';
    this.sentIdentity = '';
    this.message = '';
  }

  private onPhoneChanged(value: string): void {
    if (this.phone === value) {
      return;
    }
    // 不做静默截断：超长、非法字符由统一策略给出明确提示（输入长度上限由 maxLength 兜底）。
    this.phone = value;
    this.applyNumberValidation();
    this.invalidateDigits();
  }

  private applyRegion(region: PhoneLoginRegion): void {
    this.regionSheetShown = false;
    if (region.id === this.regionId) {
      return;
    }
    this.regionId = region.id;
    this.applyNumberValidation();
    this.invalidateDigits();
  }

  /** 对齐上游 sendDigits 按钮可用条件：已同意协议 + 号码可用 + 不在倒计时 + 不在请求中。 */
  private canSendDigits(): boolean {
    const guard: PhoneDigitsGuard = {
      agreementChecked: this.agreementChecked,
      numberValid: this.numberValid,
      cooldownSeconds: this.resendSeconds,
      busy: !this.editable()
    };
    return canRequestPhoneDigits(guard);
  }

  private canSignIn(): boolean {
    const identity: string = phoneLoginIdentityKey(this.regionId, this.username);
    const guard: PhoneSignInGuard = {
      agreementChecked: this.agreementChecked,
      numberValid: this.numberValid,
      codeLength: this.digits.length,
      requestedIdentityMatches: this.sentIdentity.length > 0 && identity === this.sentIdentity,
      busy: !this.editable()
    };
    return canSignInWithPhone(guard);
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
    this.cooldownDeadlineMs = Date.now() + PHONE_RESEND_COOLDOWN_SECONDS * 1000;
    this.resendSeconds = phoneCooldownRemainingSeconds(this.cooldownDeadlineMs, Date.now());
    this.resendTimerId = setInterval((): void => {
      const remaining: number = phoneCooldownRemainingSeconds(this.cooldownDeadlineMs, Date.now());
      this.resendSeconds = remaining;
      if (remaining <= 0) {
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

  /** 迟到结果（页面已退出或代次已过期）一律丢弃，不修改状态也不触发登录成功回调。 */
  private isStale(token: number): boolean {
    return this.disposed || !this.generation.isCurrent(token);
  }

  private async sendDigits(): Promise<void> {
    const client = this.client;
    if (client === undefined || !this.canSendDigits()) {
      return;
    }
    this.isSendingDigits = true;
    this.message = '';
    const token: number = this.generation.begin();
    try {
      await this.requestDigitsInternal(client, token);
    } catch (error) {
      if (!this.isStale(token)) {
        this.message = error instanceof PhoneLoginError
          ? friendlyPhoneLoginMessage(error.message, '网络错误，请稍后重试')
          : '网络错误，请稍后重试';
      }
    } finally {
      this.isSendingDigits = false;
    }
  }

  /** 实际发码请求：不含忙状态守卫，供图形验证码校验通过后复用（修复验证码后未真正发码的问题）。 */
  private async requestDigitsInternal(client: ZhihuPhoneLoginClient, token: number): Promise<void> {
    const region: PhoneLoginRegion = this.currentRegion();
    const username: string = this.username;
    const identity: string = phoneLoginIdentityKey(region.id, username);
    const result = await client.requestDigits(username, region.id);
    if (this.isStale(token)) {
      return;
    }
    if (result.kind === PhoneDigitsResultKind.SENT) {
      this.sentIdentity = identity;
      this.captchaRequired = false;
      this.captchaImageBase64 = '';
      this.captchaInput = '';
      this.startResendCountdown();
      this.message = '短信验证码已发送，请注意查收';
    } else if (result.kind === PhoneDigitsResultKind.CAPTCHA_REQUIRED) {
      this.captchaRequired = true;
      this.captchaImageBase64 = result.captchaImageBase64 ?? '';
      this.captchaInput = '';
      this.message = this.captchaImageBase64.length === 0
        ? '服务器未返回图形验证码，请换一张重试' : '请先完成图形验证码';
    } else {
      this.message = friendlyPhoneLoginMessage(result.errorMessage ?? '', '验证码发送失败，请重试');
    }
  }

  private async refreshCaptchaImage(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.isSendingDigits) {
      return;
    }
    this.message = '';
    const token: number = this.generation.begin();
    try {
      const image: string = await client.refreshCaptcha();
      if (this.isStale(token)) {
        return;
      }
      this.captchaImageBase64 = image;
      if (this.captchaImageBase64.length === 0) {
        this.message = '服务器未返回图形验证码，请稍后重试';
      }
    } catch (error) {
      if (!this.isStale(token)) {
        this.message = error instanceof PhoneLoginError ? error.message : '刷新图形验证码失败';
      }
    }
  }

  private async verifyCaptchaAndSend(): Promise<void> {
    const client = this.client;
    if (client === undefined || !this.editable()) {
      return;
    }
    if (this.captchaInput.trim().length === 0) {
      return;
    }
    this.isSendingDigits = true;
    this.message = '';
    const token: number = this.generation.begin();
    try {
      const verified: boolean = await client.verifyCaptcha(this.captchaInput);
      if (this.isStale(token)) {
        return;
      }
      if (!verified) {
        this.message = '图形验证码不正确';
        return;
      }
      this.captchaRequired = false;
      this.captchaImageBase64 = '';
      this.captchaInput = '';
      // 复用同一个代次直接发码：不再走 sendDigits()，避免被 isSendingDigits 守卫提前返回。
      await this.requestDigitsInternal(client, token);
    } catch (error) {
      if (!this.isStale(token)) {
        this.message = error instanceof PhoneLoginError
          ? friendlyPhoneLoginMessage(error.message, '验证图形验证码失败')
          : '验证图形验证码失败';
      }
    } finally {
      this.isSendingDigits = false;
    }
  }

  private async signIn(): Promise<void> {
    const client = this.client;
    if (client === undefined || !this.canSignIn()) {
      return;
    }
    const region: PhoneLoginRegion = this.currentRegion();
    const username: string = this.username;
    const digits: string = this.digits;
    this.isLoggingIn = true;
    this.message = '';
    const token: number = this.generation.begin();
    try {
      const result = await client.signIn(username, digits, region.id);
      if (this.isStale(token)) {
        return;
      }
      this.onCookiesCaptured(result.cookies);
    } catch (error) {
      if (!this.isStale(token)) {
        this.message = error instanceof PhoneLoginError
          ? friendlyPhoneLoginMessage(error.message, '登录失败，请稍后重试')
          : '登录失败，请稍后重试';
      }
    } finally {
      this.isLoggingIn = false;
    }
  }
}
