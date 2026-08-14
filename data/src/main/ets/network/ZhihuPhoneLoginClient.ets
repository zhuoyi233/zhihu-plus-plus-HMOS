/**
 * 知乎 Android 手机号登录协议客户端（对齐上游 shared/.../account/ZhihuPhoneLoginClient.kt）。
 *
 * 使用知乎官方 Android 登录协议（api.zhihu.com）：
 * 1. ensureGuestToken：访客初始化（/udid 取 d_c0 + /api/account/prod/init/udid_guest 换访客 token）
 * 2. requestDigits：发送短信验证码（/api/account/prod/auth/digits，可能要求图形验证码）
 * 3. refreshCaptcha / verifyCaptcha：图形验证码获取与校验（/captcha）
 * 4. signIn：短信验证码登录（/api/account/prod/sign_in）
 *
 * 请求体用 ZhihuMessageBodyEncryptor 加密（form urlencoded → 自定义分组密码 → base64）。
 */

import { http } from '@kit.NetworkKit';
import {
  SessionCookie,
  parseCookieJarEntries
} from '../session/CookieSession';
import { encryptZhihuMessageBody } from './ZhihuMessageBodyEncryptor';
import { hmacSha1Hex } from './ZhihuHmacSha1';

const PHONE_LOGIN_API_BASE_URL = 'https://api.zhihu.com';
const DEVICE_GUEST_INIT_PATH = '/api/account/prod/init/udid_guest';
const CAPTCHA_PATH = '/captcha';
const AUTH_DIGITS_PATH = '/api/account/prod/auth/digits';
const SIGN_IN_PATH = '/api/account/prod/sign_in';

const MOBILE_CLIENT_ID = '8d5227e0aaaa4797a763ac64e0c3b8';
const MOBILE_CLIENT_SECRET = 'ecbefbf6b17e47ecb9035107866380';
const MOBILE_SOURCE = 'com.zhihu.android';
const DIGITS_GRANT_TYPE = 'digits';
const CLOUD_APP_ID = '1355';
const CLOUD_APP_SECRET = 'dd49a835-56e7-4a0f-95b5-efd51ea5397f';
const CLOUD_SIGN_VERSION = '2';

const ZHIHU_ANDROID_PHONE_LOGIN_USER_AGENT =
  'com.zhihu.android/Futureve/11.4.0 Mozilla/5.0 (Linux; Android 12; Android SDK built for arm64 ' +
  'Build/SE1A.220621.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 ' +
  'Chrome/57.0.1000.10 Mobile Safari/537.36';

const CAPTCHA_INVALID_ERROR_CODES = new Set<number>([120001, 120002]);
const CAPTCHA_NEEDED_ERROR_CODE = 120005;
const PHONE_LOGIN_TIMEOUT_MS = 10_000;
const PHONE_LOGIN_RESPONSE_LIMIT_BYTES = 1024 * 1024;

export enum PhoneDigitsResultKind {
  SENT = 'sent',
  CAPTCHA_REQUIRED = 'captcha_required',
  FAILED = 'failed'
}

export interface PhoneDigitsResult {
  readonly kind: PhoneDigitsResultKind;
  readonly captchaImageBase64?: string;
  readonly errorMessage?: string;
}

export interface PhoneLoginToken {
  readonly accessToken: string;
  readonly refreshToken?: string;
  readonly expiresAt?: number;
  readonly cookies: Array<SessionCookie>;
}

interface CaptchaState {
  readonly showCaptcha: boolean;
}

interface PhoneLoginHttpResponse {
  readonly statusCode: number;
  readonly body: string;
}

function parseCaptchaState(body: string): CaptchaState {
  const root = parseJsonObject(body);
  return { showCaptcha: root['show_captcha'] === true };
}

export interface PhoneLoginDeviceInfo {
  readonly timezoneOffsetSeconds: number;
  readonly appInstallTimeMillis: number;
  readonly notificationEnabled: boolean;
  readonly bluetoothAvailable: boolean;
  readonly phoneBrand: string;
  readonly phoneModel: string;
  readonly systemRelease: string;
  readonly cpuType: string;
  readonly cpuCount: number;
  readonly totalMemoryMegabytes: number;
  readonly freeMemoryMegabytes: number;
  readonly totalStorageMegabytes: number;
  readonly freeStorageMegabytes: number;
}

/** 手机号登录错误（含分类，供 UI 展示）。 */
export class PhoneLoginError extends Error {
  readonly kind: string;

  constructor(message: string, kind: string = 'failed') {
    super(message);
    this.name = 'PhoneLoginError';
    this.kind = kind;
  }
}

function isTrustedPhoneLoginUrl(url: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  return url.startsWith('https://api.zhihu.com/');
}

function formUrlEncode(entries: Array<Array<string>>): string {
  const parts: Array<string> = [];
  entries.forEach((entry: Array<string>): void => {
    parts.push(`${encodeURIComponent(entry[0])}=${encodeURIComponent(entry[1])}`);
  });
  return parts.join('&');
}

function parseJsonObject(body: string): Record<string, Object> {
  const parsed: Object = JSON.parse(body);
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new PhoneLoginError('知乎返回了无效响应');
  }
  return parsed as Record<string, Object>;
}

function readErrorText(body: string, fallback: string): string {
  try {
    const root = parseJsonObject(body);
    const rawError = root['error'];
    const error = rawError !== null && typeof rawError === 'object' && !Array.isArray(rawError)
      ? rawError as Record<string, Object>
      : root;
    const message = error['message'];
    if (typeof message === 'string' && message.trim().length > 0) {
      return message;
    }
  } catch (_error) {
    // fallthrough
  }
  return fallback;
}

function readErrorCode(body: string): number | undefined {
  try {
    const root = parseJsonObject(body);
    const rawError = root['error'];
    const error = rawError !== null && typeof rawError === 'object' && !Array.isArray(rawError)
      ? rawError as Record<string, Object>
      : root;
    const code = error['code'];
    if (typeof code === 'number') {
      return code;
    }
    if (typeof code === 'string') {
      const parsed = Number.parseInt(code, 10);
      if (!Number.isNaN(parsed)) {
        return parsed;
      }
    }
  } catch (_error) {
    // fallthrough
  }
  return undefined;
}

function readCookieMap(body: string): Array<SessionCookie> {
  try {
    const root = parseJsonObject(body);
    const cookie = root['cookie'];
    if (cookie !== null && typeof cookie === 'object' && !Array.isArray(cookie)) {
      const result: Array<SessionCookie> = [];
      const names: Array<string> = Object.keys(cookie as Record<string, Object>);
      names.forEach((name: string): void => {
        const value = (cookie as Record<string, Object>)[name];
        if (typeof value === 'string' && value.length > 0) {
          result.push({ name: name, value: value });
        }
      });
      return result;
    }
  } catch (_error) {
    // fallthrough
  }
  return [];
}

export class ZhihuPhoneLoginClient {
  private readonly http: http.HttpRequest = http.createHttp();
  private cookies: Array<SessionCookie>;
  private deviceInfo: PhoneLoginDeviceInfo;
  private nowEpochSeconds: () => number;
  private authorization: string = `oauth ${MOBILE_CLIENT_ID}`;
  private deviceId: string | undefined = undefined;
  private webDeviceCookie: string | undefined = undefined;

  constructor(cookies: Array<SessionCookie>, deviceInfo: PhoneLoginDeviceInfo,
    nowEpochSeconds?: () => number) {
    this.cookies = cookies;
    this.deviceInfo = deviceInfo;
    this.nowEpochSeconds = nowEpochSeconds ?? ((): number => Math.floor(Date.now() / 1000));
    const dC0 = this.cookies.find((cookie: SessionCookie): boolean => cookie.name === 'd_c0');
    if (dC0 !== undefined && dC0.value.length > 0) {
      this.webDeviceCookie = dC0.value;
    }
  }

  destroy(): void {
    this.http.destroy();
  }

  /** 发送短信验证码；需要图形验证码时返回 CAPTCHA_REQUIRED。 */
  async requestDigits(phoneNumber: string): Promise<PhoneDigitsResult> {
    const username = normalizePhoneNumber(phoneNumber);
    await this.ensureGuestToken();

    const captchaState = await this.requestCaptchaState();
    if (captchaState.showCaptcha) {
      const image = await this.refreshCaptcha();
      return { kind: PhoneDigitsResultKind.CAPTCHA_REQUIRED, captchaImageBase64: image };
    }

    return this.sendDigits(username, true);
  }

  private static pair(name: string, value: string): Array<string> {
    return [name, value];
  }

  private async sendDigits(username: string, recheckCaptchaWhenRequested: boolean): Promise<PhoneDigitsResult> {
    const response = await this.execute(
      `${PHONE_LOGIN_API_BASE_URL}${AUTH_DIGITS_PATH}`,
      http.RequestMethod.POST,
      this.buildEncryptedBody([ZhihuPhoneLoginClient.pair('username', username),
        ZhihuPhoneLoginClient.pair('client_id', MOBILE_CLIENT_ID)])
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return { kind: PhoneDigitsResultKind.SENT };
    }

    const errorCode = readErrorCode(response.body);
    if (errorCode !== undefined && CAPTCHA_INVALID_ERROR_CODES.has(errorCode)) {
      const image = await this.refreshCaptcha();
      return { kind: PhoneDigitsResultKind.CAPTCHA_REQUIRED, captchaImageBase64: image };
    }
    if (errorCode === CAPTCHA_NEEDED_ERROR_CODE && recheckCaptchaWhenRequested) {
      const captchaState = await this.requestCaptchaState();
      if (captchaState.showCaptcha) {
        const image = await this.refreshCaptcha();
        return { kind: PhoneDigitsResultKind.CAPTCHA_REQUIRED, captchaImageBase64: image };
      }
      return this.sendDigits(username, false);
    }
    return {
      kind: PhoneDigitsResultKind.FAILED,
      errorMessage: readErrorText(response.body, `发送短信验证码失败（HTTP ${response.statusCode}）`)
    };
  }

  async refreshCaptcha(): Promise<string> {
    await this.ensureGuestToken();
    const response = await this.execute(
      `${PHONE_LOGIN_API_BASE_URL}${CAPTCHA_PATH}`,
      http.RequestMethod.PUT
    );
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw new PhoneLoginError(`获取图形验证码失败（HTTP ${response.statusCode}）`);
    }
    try {
      const root = parseJsonObject(response.body);
      const image = root['img_base64'];
      return typeof image === 'string' ? image : '';
    } catch (_error) {
      throw new PhoneLoginError('获取图形验证码失败：响应结构无效');
    }
  }

  async verifyCaptcha(input: string): Promise<boolean> {
    if (input.trim().length === 0) {
      throw new PhoneLoginError('图形验证码不能为空');
    }
    await this.ensureGuestToken();
    const response = await this.execute(
      `${PHONE_LOGIN_API_BASE_URL}${CAPTCHA_PATH}`,
      http.RequestMethod.POST,
      this.buildEncryptedBody([ZhihuPhoneLoginClient.pair('input_text', input.trim())])
    );
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw new PhoneLoginError(`验证图形验证码失败（HTTP ${response.statusCode}）`);
    }
    try {
      const root = parseJsonObject(response.body);
      return root['success'] === true;
    } catch (_error) {
      throw new PhoneLoginError('验证图形验证码失败：响应结构无效');
    }
  }

  async signIn(phoneNumber: string, digits: string): Promise<PhoneLoginToken> {
    const username = normalizePhoneNumber(phoneNumber);
    if (digits.trim().length === 0) {
      throw new PhoneLoginError('短信验证码不能为空');
    }
    await this.ensureGuestToken();

    const timestamp = this.nowEpochSeconds();
    const signature = hmacSha1Hex(
      MOBILE_CLIENT_SECRET,
      `${DIGITS_GRANT_TYPE}${MOBILE_CLIENT_ID}${MOBILE_SOURCE}${timestamp}`
    );
    const response = await this.execute(
      `${PHONE_LOGIN_API_BASE_URL}${SIGN_IN_PATH}`,
      http.RequestMethod.POST,
      this.buildEncryptedBody([
        ZhihuPhoneLoginClient.pair('client_id', MOBILE_CLIENT_ID),
        ZhihuPhoneLoginClient.pair('digits', digits.trim()),
        ZhihuPhoneLoginClient.pair('grant_type', DIGITS_GRANT_TYPE),
        ZhihuPhoneLoginClient.pair('signature', signature),
        ZhihuPhoneLoginClient.pair('source', MOBILE_SOURCE),
        ZhihuPhoneLoginClient.pair('timestamp', timestamp.toString()),
        ZhihuPhoneLoginClient.pair('username', username)
      ])
    );
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw new PhoneLoginError(
        readErrorText(response.body, `手机号登录失败（HTTP ${response.statusCode}）`)
      );
    }

    let token: Record<string, Object>;
    try {
      token = parseJsonObject(response.body);
    } catch (_error) {
      throw new PhoneLoginError('手机号登录失败：响应结构无效');
    }
    const accessToken = token['access_token'];
    if (typeof accessToken !== 'string' || accessToken.trim().length === 0) {
      throw new PhoneLoginError('服务器未返回登录凭证');
    }
    const cookieEntries = readCookieMap(response.body);
    const merged = mergeCookies(this.cookies, cookieEntries);
    if (cookieValue(merged, 'd_c0') === undefined) {
      if (this.webDeviceCookie === undefined) {
        throw new PhoneLoginError('服务器未返回必要的 Cookie d_c0');
      }
      merged.push({ name: 'd_c0', value: this.webDeviceCookie });
    }
    this.cookies = merged;
    const expiresIn = token['expires_in'];
    return {
      accessToken: accessToken,
      refreshToken: typeof token['refresh_token'] === 'string' ? token['refresh_token'] : undefined,
      expiresAt: typeof expiresIn === 'number' ? timestamp + expiresIn : undefined,
      cookies: merged
    };
  }

  private async ensureGuestToken(): Promise<void> {
    if (!this.authorization.startsWith('oauth ')) {
      return;
    }

    if (this.webDeviceCookie === undefined) {
      const before = this.cookies;
      let fetched: string | undefined = undefined;
      try {
        await this.execute('https://www.zhihu.com/udid', http.RequestMethod.POST, '{}', false);
        fetched = cookieValue(this.cookies, 'd_c0');
      } finally {
        // d_c0 会使移动端访客初始化返回 500；登录前不把网页预热 cookie 暴露给移动端协议。
        this.cookies = before;
      }
      if (fetched === undefined || fetched.length === 0) {
        throw new PhoneLoginError('服务器未返回必要的 Cookie d_c0');
      }
      this.webDeviceCookie = fetched;
    }

    const timestamp = this.nowEpochSeconds().toString();
    const form = formUrlEncode(this.deviceForm());
    const signature = hmacSha1Hex(
      CLOUD_APP_SECRET,
      `${CLOUD_APP_ID}${CLOUD_SIGN_VERSION}${form}${timestamp}`
    );
    const response = await this.execute(
      `${PHONE_LOGIN_API_BASE_URL}${DEVICE_GUEST_INIT_PATH}`,
      http.RequestMethod.POST,
      encryptZhihuMessageBody(form),
      true,
      {
        'x-app-id': CLOUD_APP_ID,
        'x-sign-version': CLOUD_SIGN_VERSION,
        'x-req-ts': timestamp,
        'x-req-signature': signature
      }
    );
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw new PhoneLoginError(
        readErrorText(response.body, `初始化手机号登录失败（HTTP ${response.statusCode}）`)
      );
    }
    let init: Record<string, Object>;
    try {
      init = parseJsonObject(response.body);
    } catch (_error) {
      throw new PhoneLoginError('初始化手机号登录失败：响应结构无效');
    }
    const udid = init['udid'];
    const guest = init['guest'];
    if (typeof udid !== 'string' || udid.length === 0) {
      throw new PhoneLoginError('服务器未返回设备凭证');
    }
    if (guest === null || typeof guest !== 'object') {
      throw new PhoneLoginError('服务器未返回访客凭证');
    }
    const guestObject = guest as Record<string, Object>;
    const accessToken = guestObject['access_token'];
    if (typeof accessToken !== 'string' || accessToken.length === 0) {
      throw new PhoneLoginError('服务器未返回访客凭证');
    }
    this.cookies = mergeCookies(this.cookies, readCookieMap(response.body));
    this.deviceId = udid;
    const tokenType = typeof guestObject['token_type'] === 'string'
      ? guestObject['token_type']
      : 'bearer';
    this.authorization = `${tokenType} ${accessToken}`;
  }

  private async requestCaptchaState(): Promise<CaptchaState> {
    const response = await this.execute(
      `${PHONE_LOGIN_API_BASE_URL}${CAPTCHA_PATH}`,
      http.RequestMethod.GET
    );
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw new PhoneLoginError(`检查图形验证码失败（HTTP ${response.statusCode}）`);
    }
    try {
      return parseCaptchaState(response.body);
    } catch (_error) {
      throw new PhoneLoginError('检查图形验证码失败：响应结构无效');
    }
  }

  private deviceForm(): Array<Array<string>> {
    const info = this.deviceInfo;
    const result: Array<Array<string>> = [];
    const add = (name: string, value: string): void => {
      const entry: Array<string> = [name, value];
      result.push(entry);
    };
    add('app_build', '40408');
    add('app_install_time', info.appInstallTimeMillis.toString());
    add('app_ticket', 'interface is empty');
    add('app_version', '11.4.0');
    add('bt_ck', info.bluetoothAvailable ? '1' : '0');
    add('bundle_id', MOBILE_SOURCE);
    add('cp_ct', info.cpuCount.toString());
    add('cp_tp', info.cpuType);
    add('cp_us', '0.0');
    add('d_n', info.phoneModel);
    add('fr_mem', info.freeMemoryMegabytes.toString());
    add('fr_st', info.freeStorageMegabytes.toString());
    add('latitude', '0.0');
    add('longitude', '0.0');
    add('nt_st', info.notificationEnabled ? '1' : '0');
    add('ph_br', info.phoneBrand);
    add('ph_md', info.phoneModel);
    add('ph_os', `Android ${info.systemRelease}`);
    add('pre_install', 'InterfaceIsNull');
    add('tt_mem', info.totalMemoryMegabytes.toString());
    add('tt_st', info.totalStorageMegabytes.toString());
    add('tz_of', info.timezoneOffsetSeconds.toString());
    add('zx_expired', '0');
    return result;
  }

  private buildEncryptedBody(entries: Array<Array<string>>): string {
    return encryptZhihuMessageBody(formUrlEncode(entries));
  }

  private async execute(url: string, method: http.RequestMethod, body?: string,
    useMobileHeaders: boolean = true, extraHeaders?: Record<string, string>): Promise<PhoneLoginHttpResponse> {
    if (!isTrustedPhoneLoginUrl(url) && url !== 'https://www.zhihu.com/udid') {
      throw new PhoneLoginError('手机号登录请求目标不受信任');
    }
    const headers: Record<string, string> = {};
    if (useMobileHeaders) {
      headers['User-Agent'] = ZHIHU_ANDROID_PHONE_LOGIN_USER_AGENT;
      headers['Authorization'] = this.authorization;
      // 对齐上游 applyMobileHeaders 的 accept + setEncryptedForm 的 form-urlencoded：
      // 不设 Content-Type 时 NetworkKit 默认 text/plain，服务端会把密文当原始表单解析，
      // 导致 auth/digits 返回 "miss arg username"（未走解密分支）。
      headers['Accept'] = 'application/json';
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      const cookieHeader = this.cookiesToHeader();
      if (cookieHeader.length > 0) {
        headers['Cookie'] = cookieHeader;
      }
      if (this.deviceId !== undefined) {
        headers['x-udid'] = this.deviceId;
      }
      headers['x-api-version'] = '3.0.93';
      headers['x-app-version'] = '11.4.0';
      headers['x-app-build'] = 'release';
      headers['x-app-bundleid'] = MOBILE_SOURCE;
      headers['x-app-flavor'] = 'honor';
      headers['x-app-za'] =
        'OS=Android&Release=12&Model=Android+SDK+built+for+arm64&VersionName=11.4.0&VersionCode=40408&' +
        'Product=com.zhihu.android&Width=1080&Height=2274&Installer=%E8%8D%A3%E8%80%80%E5%95%86%E5%BA%97&' +
        'DeviceType=AndroidPhone&Brand=Android';
      headers['x-network-type'] = '3G';
      headers['x-page-id'] = '44';
      headers['x-zse-93'] = '101_1_1.0';
    }
    if (extraHeaders !== undefined) {
      const names: Array<string> = Object.keys(extraHeaders);
      names.forEach((name: string): void => {
        headers[name] = extraHeaders[name];
      });
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: PHONE_LOGIN_TIMEOUT_MS,
      readTimeout: PHONE_LOGIN_TIMEOUT_MS,
      maxRedirects: 3,
      maxLimit: PHONE_LOGIN_RESPONSE_LIMIT_BYTES,
      usingCache: false
    };
    try {
      const response = await this.http.request(url, options);
      const responseCookies = parseCookieJarEntries(response.cookies);
      if (responseCookies.length > 0) {
        this.cookies = mergeCookies(this.cookies, responseCookies);
      }
      const result: PhoneLoginHttpResponse = {
        statusCode: Number(response.responseCode),
        body: typeof response.result === 'string' ? response.result : ''
      };
      return result;
    } catch (_error) {
      throw new PhoneLoginError('手机号登录网络请求失败', 'network');
    }
  }

  private cookiesToHeader(): string {
    return this.cookies
      .filter((cookie: SessionCookie): boolean => cookie.value.length > 0)
      .map((cookie: SessionCookie): string => `${cookie.name}=${cookie.value}`)
      .join('; ');
  }
}

function normalizePhoneNumber(phoneNumber: string): string {
  const compact = phoneNumber.trim().replace(/ /g, '').replace(/-/g, '');
  let local = compact;
  if (compact.startsWith('+86')) {
    local = compact.substring(3);
  } else if (compact.startsWith('86') && compact.length === 13) {
    local = compact.substring(2);
  }
  if (!/^1\d{10}$/.test(local)) {
    throw new PhoneLoginError('请输入正确的中国大陆手机号');
  }
  return `+86${local}`;
}

function cookieValue(cookies: Array<SessionCookie>, name: string): string | undefined {
  const found = cookies.find((cookie: SessionCookie): boolean => cookie.name === name && cookie.value.length > 0);
  return found?.value;
}

function mergeCookies(base: Array<SessionCookie>, incoming: Array<SessionCookie>): Array<SessionCookie> {
  const result: Array<SessionCookie> = [];
  const seen = new Set<string>();
  base.forEach((cookie: SessionCookie): void => {
    if (!seen.has(cookie.name)) {
      seen.add(cookie.name);
      result.push({ name: cookie.name, value: cookie.value });
    }
  });
  incoming.forEach((cookie: SessionCookie): void => {
    const existing = result.find((entry: SessionCookie): boolean => entry.name === cookie.name);
    if (existing !== undefined) {
      existing.value = cookie.value;
    } else {
      result.push({ name: cookie.name, value: cookie.value });
    }
  });
  return result;
}

/** 手机号登录用的设备信息（对齐上游 ZhihuPhoneLoginDeviceInfo.formParameters）。 */
export function defaultPhoneLoginDeviceInfo(): PhoneLoginDeviceInfo {
  return {
    timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
    appInstallTimeMillis: 0,
    notificationEnabled: false,
    bluetoothAvailable: false,
    phoneBrand: 'HUAWEI',
    phoneModel: 'HarmonyOS',
    systemRelease: '12',
    cpuType: 'arm64-v8a',
    cpuCount: 8,
    totalMemoryMegabytes: 4096,
    freeMemoryMegabytes: 2048,
    totalStorageMegabytes: 128 * 1024,
    freeStorageMegabytes: 64 * 1024
  };
}
