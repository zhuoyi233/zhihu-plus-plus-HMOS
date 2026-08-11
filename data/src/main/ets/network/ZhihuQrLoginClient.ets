import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import {
  copySessionCookies,
  parseCookieAssignments,
  SessionCookie,
  toCookieHeader,
  upsertCookie
} from '../session/CookieSession';
import { HttpFailure, HttpFailureKind, httpFailureFromTransport } from './HttpFailure';
import { ZhihuHttpMethod } from './ZhihuHttpClient';
import { ZHIHU_WEB_ZSE93 } from './ZhihuFetchSignature';

export const ZHIHU_QR_SIGNIN_URL = 'https://www.zhihu.com/signin?next=%2F';
export const ZHIHU_QR_UDID_URL = 'https://www.zhihu.com/udid';
export const ZHIHU_QR_CAPTCHA_URL = 'https://www.zhihu.com/api/v3/oauth/captcha/v2?type=captcha_sign_in';
export const ZHIHU_QR_CODE_URL = 'https://www.zhihu.com/api/v3/account/api/login/qrcode';
export const ZHIHU_QR_RISK_CONTROL_URL = 'https://www.zhihu.com/account/risk_control/';
export const ZHIHU_QR_POLL_INTERVAL_MS = 500;

const ZHIHU_HOME_URL = 'https://www.zhihu.com/';
const ZHIHU_SIGNIN_REFERER_URL = 'https://www.zhihu.com/signin';
const QR_DEFAULT_TTL_MS = 120000;
const QR_MAX_TTL_SECONDS = 86400;
const QR_MAX_TTL_MS = QR_MAX_TTL_SECONDS * 1000;
const QR_REQUEST_TIMEOUT_MS = 10000;
const QR_RESPONSE_LIMIT_BYTES = 1024 * 1024;
const QR_TOKEN_PATTERN = /^[A-Za-z0-9._~-]{1,512}$/;
const QR_URL_MAX_LENGTH = 4096;
const QR_CHALLENGE_LINK_MAX_LENGTH = 2048;
const QR_CHALLENGE_LINK_PREFIX = 'https://www.zhihu.com/account/scan/login/';
const ZHIHU_QR_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
    'Chrome/145.0.0.0 Safari/537.36';
const ZHIHU_QR_SEC_CH_UA = '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"';

export enum QrLoginStatus {
  IDLE = 'idle',
  BUSY = 'busy',
  CANCELLED = 'cancelled',
  READY = 'ready',
  WAITING_CONFIRMATION = 'waiting_confirmation',
  CREDENTIAL_READY = 'credential_ready',
  EXPIRED = 'expired',
  RISK_CONTROL = 'risk_control',
  TEMPORARY_FAILURE = 'temporary_failure'
}

export interface QrLoginState {
  status: QrLoginStatus;
  message: string;
  qrLink?: string;
  expiresAt?: number;
  riskControlUrl?: string;
}

export interface QrLoginGateway {
  start(initialCookies?: Array<SessionCookie>, now?: number): Promise<QrLoginState>;
  pollOnce(now?: number): Promise<QrLoginState>;
  cancel(): void;
  getCandidateCookies(): Array<SessionCookie>;
}

export interface QrLoginHeaders {
  Accept: string;
  'Accept-Language': string;
  'User-Agent': string;
  Cookie?: string;
  Referer?: string;
  Origin?: string;
  'x-requested-with'?: string;
  'Content-Type'?: string;
  'x-xsrftoken'?: string;
  'sec-ch-ua': string;
  'sec-ch-ua-mobile': string;
  'sec-ch-ua-platform': string;
  'sec-fetch-dest'?: string;
  'sec-fetch-mode'?: string;
  'sec-fetch-site'?: string;
  'x-zse-93'?: string;
}

export interface QrLoginRequest {
  url: string;
  method: ZhihuHttpMethod;
  headers: QrLoginHeaders;
  body?: string;
}

export interface QrLoginResponse {
  statusCode: number;
  body: string;
  cookies: Array<SessionCookie>;
}

export interface QrLoginTransport {
  request(request: QrLoginRequest): Promise<QrLoginResponse>;
  destroy(): void;
}

export interface QrLoginTransportFactory {
  create(): QrLoginTransport;
}

interface QrCodePayload {
  expires_at?: number;
  link?: string;
  token?: string;
  qrcode_token?: string;
}

interface QrScanErrorPayload {
  need_login?: boolean;
  redirect?: string;
  code?: number;
}

interface QrScanPayload {
  status?: number;
  cookie?: string;
  cookies?: string;
  z_c0?: string;
  user_id?: string;
  access_token?: string;
  success?: boolean;
  logged_in?: boolean;
  login_status?: string;
  error?: QrScanErrorPayload;
}

interface ParsedQrCode {
  token: string;
  link: string;
  expiresAt: number;
}

function desktopHeaders(referer?: string): QrLoginHeaders {
  const headers: QrLoginHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'User-Agent': ZHIHU_QR_USER_AGENT,
    'sec-ch-ua': ZHIHU_QR_SEC_CH_UA,
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"'
  };
  if (referer !== undefined) {
    headers.Referer = referer;
  }
  return headers;
}

export function isTrustedQrLoginUrl(url: string): boolean {
  if (url.length === 0 || url.length > QR_URL_MAX_LENGTH || /[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]+)(?:[/?#]|$)/.exec(url);
  if (match === null || match[1].toLowerCase() !== 'https') {
    return false;
  }
  const authority = match[2];
  return !authority.includes('@') && !authority.includes(':') && authority.toLowerCase() === 'www.zhihu.com';
}

export function isTrustedQrChallengeLink(url: string, token: string): boolean {
  return url.length <= QR_CHALLENGE_LINK_MAX_LENGTH && QR_TOKEN_PATTERN.test(token) &&
    url === `${QR_CHALLENGE_LINK_PREFIX}${token}`;
}

export function createQrLoginHeaders(
  cookies: Array<SessionCookie>,
  referer: string,
  polling: boolean = false
): QrLoginHeaders {
  const cookieHeader = toCookieHeader(cookies, Date.now());
  const xsrf = cookies.find((cookie: SessionCookie) => cookie.name === '_xsrf')?.value;
  return {
    'Accept': polling ? '*/*' : 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'User-Agent': ZHIHU_QR_USER_AGENT,
    'Cookie': cookieHeader.length > 0 ? cookieHeader : undefined,
    'Referer': referer,
    'Origin': 'https://www.zhihu.com',
    'x-requested-with': 'fetch',
    'Content-Type': 'application/json;charset=UTF-8',
    'x-xsrftoken': xsrf !== undefined && xsrf.length > 0 ? xsrf : undefined,
    'sec-ch-ua': ZHIHU_QR_SEC_CH_UA,
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
    'sec-fetch-dest': polling ? 'empty' : undefined,
    'sec-fetch-mode': polling ? 'cors' : undefined,
    'sec-fetch-site': polling ? 'same-origin' : undefined,
    'x-zse-93': polling ? ZHIHU_WEB_ZSE93 : undefined
  };
}

export function normalizeQrDeadline(expiresAt: number | undefined, now: number): number {
  if (expiresAt === undefined || typeof expiresAt !== 'number' || !Number.isFinite(expiresAt) || expiresAt <= 0) {
    return now + QR_DEFAULT_TTL_MS;
  }
  const nowSeconds = Math.floor(now / 1000);
  let deadline: number;
  if (expiresAt < nowSeconds) {
    if (expiresAt <= QR_MAX_TTL_SECONDS) {
      deadline = now + expiresAt * 1000;
    } else if (expiresAt <= QR_MAX_TTL_MS) {
      deadline = now + expiresAt;
    } else {
      return now + QR_DEFAULT_TTL_MS;
    }
  } else {
    deadline = expiresAt < 10000000000 ? expiresAt * 1000 : expiresAt;
  }
  if (!Number.isFinite(deadline) || deadline <= now || deadline > now + QR_MAX_TTL_MS) {
    return now + QR_DEFAULT_TTL_MS;
  }
  return deadline;
}

function parseQrCode(statusCode: number, responseBody: string, now: number): ParsedQrCode | undefined {
  if (statusCode < 200 || statusCode >= 300) {
    return undefined;
  }
  try {
    const payload = JSON.parse(responseBody) as QrCodePayload;
    const token = payload.token ?? payload.qrcode_token;
    if (token === undefined || !QR_TOKEN_PATTERN.test(token) || payload.link === undefined ||
      !isTrustedQrChallengeLink(payload.link, token)) {
      return undefined;
    }
    return {
      token: token,
      link: payload.link,
      expiresAt: normalizeQrDeadline(payload.expires_at, now)
    };
  } catch (_error) {
    return undefined;
  }
}

function mergeCookies(current: Array<SessionCookie>, incoming: Array<SessionCookie>): Array<SessionCookie> {
  let merged = copySessionCookies(current);
  for (let index = 0; index < incoming.length; index += 1) {
    const cookie = incoming[index];
    if (cookie.value.length === 0) {
      merged = merged.filter((candidate: SessionCookie): boolean => candidate.name !== cookie.name);
    } else {
      merged = upsertCookie(merged, cookie);
    }
  }
  return merged;
}

function successfulScanPayload(payload: QrScanPayload): boolean {
  if (payload.user_id !== undefined || payload.access_token !== undefined || payload.success === true ||
    payload.logged_in === true) {
    return true;
  }
  const status = payload.login_status?.toUpperCase() ?? '';
  return ['CONFIRMED', 'LOGIN_SUCCESS', 'SUCCESS', 'OK', 'LOGGED_IN'].includes(status);
}

function expiredScanPayload(payload: QrScanPayload): boolean {
  const status = payload.login_status?.toUpperCase() ?? '';
  return payload.status === 2 || ['EXPIRED', 'QR_CODE_EXPIRED', 'LOGIN_EXPIRED'].includes(status);
}

function safeRiskControlUrl(candidate: string | undefined): string {
  if (candidate !== undefined && isTrustedQrLoginUrl(candidate)) {
    return candidate;
  }
  return ZHIHU_QR_RISK_CONTROL_URL;
}

class NetworkKitQrLoginTransport implements QrLoginTransport {
  private readonly requestHandle: http.HttpRequest = http.createHttp();

  async request(request: QrLoginRequest): Promise<QrLoginResponse> {
    if (!isTrustedQrLoginUrl(request.url)) {
      throw new HttpFailure(HttpFailureKind.CLIENT);
    }
    const options: http.HttpRequestOptions = {
      method: request.method === ZhihuHttpMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: request.headers,
      extraData: request.body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: QR_REQUEST_TIMEOUT_MS,
      readTimeout: QR_REQUEST_TIMEOUT_MS,
      maxRedirects: 0,
      maxLimit: QR_RESPONSE_LIMIT_BYTES,
      usingCache: false
    };
    try {
      const response = await this.requestHandle.request(request.url, options);
      return {
        statusCode: Number(response.responseCode),
        body: response.result as string,
        cookies: parseCookieAssignments(response.cookies, true)
      };
    } catch (error) {
      throw httpFailureFromTransport((error as BusinessError).code);
    }
  }

  destroy(): void {
    this.requestHandle.destroy();
  }
}

class NetworkKitQrLoginTransportFactory implements QrLoginTransportFactory {
  create(): QrLoginTransport {
    return new NetworkKitQrLoginTransport();
  }
}

interface QrPollResult {
  state: QrLoginState;
  cookies: Array<SessionCookie>;
}

class ActiveQrLoginOperation {
  readonly generation: number;
  readonly cancellation: Promise<QrLoginResponse>;
  private activeTransport?: QrLoginTransport;
  private rejectCancellation?: () => void;

  constructor(generation: number) {
    this.generation = generation;
    this.cancellation = new Promise<QrLoginResponse>((_resolve, reject) => {
      this.rejectCancellation = (): void => reject(new HttpFailure(HttpFailureKind.CANCELLED));
    });
  }

  attach(transport: QrLoginTransport): void {
    this.activeTransport = transport;
  }

  release(transport: QrLoginTransport): void {
    if (this.activeTransport !== transport) {
      return;
    }
    this.activeTransport = undefined;
    this.destroy(transport);
  }

  cancel(): void {
    this.rejectCancellation?.();
    this.rejectCancellation = undefined;
    const transport = this.activeTransport;
    this.activeTransport = undefined;
    if (transport !== undefined) {
      this.destroy(transport);
    }
  }

  settle(): void {
    this.rejectCancellation = undefined;
    const transport = this.activeTransport;
    this.activeTransport = undefined;
    if (transport !== undefined) {
      this.destroy(transport);
    }
  }

  private destroy(transport: QrLoginTransport): void {
    try {
      transport.destroy();
    } catch (_error) {
      // NetworkKit 句柄清理失败不能覆盖二维码协议响应、取消或已结构化的请求错误。
    }
  }
}

export class ZhihuQrLoginClient implements QrLoginGateway {
  private readonly transportFactory: QrLoginTransportFactory;
  private cookies: Array<SessionCookie> = [];
  private token?: string;
  private expiresAt?: number;
  private state: QrLoginState = {
    status: QrLoginStatus.IDLE,
    message: '二维码登录尚未开始'
  };
  private operationGeneration: number = 0;
  private activeOperation?: ActiveQrLoginOperation;

  constructor(transportFactory: QrLoginTransportFactory = new NetworkKitQrLoginTransportFactory()) {
    this.transportFactory = transportFactory;
  }

  async start(initialCookies: Array<SessionCookie> = [], now: number = Date.now()): Promise<QrLoginState> {
    const operation = this.beginOperation();
    if (operation === undefined) {
      return this.busyState();
    }
    this.cookies = [];
    this.token = undefined;
    this.expiresAt = undefined;
    this.state = {
      status: QrLoginStatus.BUSY,
      message: '正在获取二维码'
    };
    let workingCookies = copySessionCookies(initialCookies);
    try {
      workingCookies = await this.prefetch(operation, workingCookies);
      const response = await this.execute(operation, {
        url: ZHIHU_QR_CODE_URL,
        method: ZhihuHttpMethod.POST,
        headers: createQrLoginHeaders(workingCookies, ZHIHU_SIGNIN_REFERER_URL),
        body: '{}'
      });
      workingCookies = mergeCookies(workingCookies, response.cookies);
      const challenge = parseQrCode(response.statusCode, response.body, now);
      if (challenge === undefined) {
        return this.isCurrent(operation)
          ? this.updateState(QrLoginStatus.TEMPORARY_FAILURE, '二维码获取失败，请重试')
          : this.getState();
      }
      if (!this.isCurrent(operation)) {
        return this.getState();
      }
      this.cookies = workingCookies;
      this.token = challenge.token;
      this.expiresAt = challenge.expiresAt;
      this.state = {
        status: QrLoginStatus.READY,
        message: '请使用知乎 App 扫码',
        qrLink: challenge.link,
        expiresAt: challenge.expiresAt
      };
      return this.getState();
    } catch (error) {
      if (!this.isCurrent(operation) || this.isCancelled(error)) {
        return this.getState();
      }
      return this.updateState(QrLoginStatus.TEMPORARY_FAILURE, '二维码获取失败，请重试');
    } finally {
      this.finishOperation(operation);
    }
  }

  async pollOnce(now: number = Date.now()): Promise<QrLoginState> {
    if (this.state.status === QrLoginStatus.CREDENTIAL_READY || this.state.status === QrLoginStatus.EXPIRED ||
      this.state.status === QrLoginStatus.RISK_CONTROL || this.state.status === QrLoginStatus.CANCELLED) {
      return this.getState();
    }
    const operation = this.beginOperation();
    if (operation === undefined) {
      return this.busyState();
    }
    const token = this.token;
    const expiresAt = this.expiresAt;
    const workingCookies = copySessionCookies(this.cookies);
    try {
      if (token === undefined || expiresAt === undefined) {
        return this.updateState(QrLoginStatus.TEMPORARY_FAILURE, '二维码登录尚未初始化');
      }
      if (now > expiresAt) {
        return this.updateState(QrLoginStatus.EXPIRED, '二维码已过期，请刷新');
      }
      const response = await this.execute(operation, {
        url: `${ZHIHU_QR_CODE_URL}/${token}/scan_info`,
        method: ZhihuHttpMethod.GET,
        headers: createQrLoginHeaders(workingCookies, ZHIHU_QR_SIGNIN_URL, true)
      });
      const result = this.classifyPollResponse(response, workingCookies, expiresAt);
      if (!this.isCurrent(operation)) {
        return this.getState();
      }
      this.cookies = result.cookies;
      this.state = result.state;
      return this.getState();
    } catch (error) {
      if (!this.isCurrent(operation) || this.isCancelled(error)) {
        return this.getState();
      }
      return this.updateState(QrLoginStatus.TEMPORARY_FAILURE, '二维码状态查询失败，可重试');
    } finally {
      this.finishOperation(operation);
    }
  }

  cancel(): void {
    this.operationGeneration += 1;
    const operation = this.activeOperation;
    this.activeOperation = undefined;
    operation?.cancel();
    this.cookies = [];
    this.token = undefined;
    this.expiresAt = undefined;
    this.state = {
      status: QrLoginStatus.CANCELLED,
      message: '二维码登录已取消'
    };
  }

  getCandidateCookies(): Array<SessionCookie> {
    return this.state.status === QrLoginStatus.CREDENTIAL_READY ? copySessionCookies(this.cookies) : [];
  }

  getState(): QrLoginState {
    return {
      status: this.state.status,
      message: this.state.message,
      qrLink: this.state.qrLink,
      expiresAt: this.state.expiresAt,
      riskControlUrl: this.state.riskControlUrl
    };
  }

  private async prefetch(operation: ActiveQrLoginOperation,
    initialCookies: Array<SessionCookie>): Promise<Array<SessionCookie>> {
    let workingCookies = copySessionCookies(initialCookies);
    const signin = await this.execute(operation, {
      url: ZHIHU_QR_SIGNIN_URL,
      method: ZhihuHttpMethod.GET,
      headers: desktopHeaders(ZHIHU_HOME_URL)
    });
    workingCookies = mergeCookies(workingCookies, signin.cookies);
    workingCookies = await this.bestEffort(operation, workingCookies, {
      url: ZHIHU_QR_UDID_URL,
      method: ZhihuHttpMethod.POST,
      headers: createQrLoginHeaders(workingCookies, ZHIHU_SIGNIN_REFERER_URL),
      body: '{}'
    });
    workingCookies = await this.bestEffort(operation, workingCookies, {
      url: ZHIHU_QR_CAPTCHA_URL,
      method: ZhihuHttpMethod.GET,
      headers: createQrLoginHeaders(workingCookies, ZHIHU_SIGNIN_REFERER_URL)
    });
    return workingCookies;
  }

  private async bestEffort(operation: ActiveQrLoginOperation, cookies: Array<SessionCookie>,
    request: QrLoginRequest): Promise<Array<SessionCookie>> {
    try {
      const response = await this.execute(operation, request);
      return mergeCookies(cookies, response.cookies);
    } catch (error) {
      if (this.isCancelled(error)) {
        throw new HttpFailure(HttpFailureKind.CANCELLED);
      }
      // Android Lite 同样把 UDID/Captcha 预热视为非阻塞；主二维码请求仍决定是否继续。
      return copySessionCookies(cookies);
    }
  }

  private async execute(operation: ActiveQrLoginOperation,
    request: QrLoginRequest): Promise<QrLoginResponse> {
    const transport = this.transportFactory.create();
    operation.attach(transport);
    try {
      const pending: Array<Promise<QrLoginResponse>> = [
        transport.request(request),
        operation.cancellation
      ];
      return await Promise.race(pending);
    } finally {
      operation.release(transport);
    }
  }

  private classifyPollResponse(response: QrLoginResponse, initialCookies: Array<SessionCookie>,
    expiresAt: number): QrPollResult {
    let payload: QrScanPayload;
    try {
      payload = JSON.parse(response.body) as QrScanPayload;
    } catch (_error) {
      return {
        state: this.stateValue(QrLoginStatus.TEMPORARY_FAILURE, '二维码状态无法识别，可重试', expiresAt),
        cookies: copySessionCookies(initialCookies)
      };
    }
    const risk = response.statusCode === 403 &&
      (payload.error?.code === 40352 || payload.error?.need_login === true);
    if (risk) {
      return {
        state: {
          status: QrLoginStatus.RISK_CONTROL,
          message: '知乎要求完成网络环境验证',
          riskControlUrl: safeRiskControlUrl(payload.error?.redirect)
        },
        cookies: copySessionCookies(initialCookies)
      };
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {
        state: this.stateValue(QrLoginStatus.TEMPORARY_FAILURE, '二维码状态请求失败，可重试', expiresAt),
        cookies: copySessionCookies(initialCookies)
      };
    }
    const bodyCookies = parseCookieAssignments([payload.cookie, payload.cookies]
      .filter((value: string | undefined): boolean => value !== undefined)
      .join(';'), true);
    let workingCookies = mergeCookies(initialCookies, response.cookies);
    workingCookies = mergeCookies(workingCookies, bodyCookies);
    if (payload.z_c0 !== undefined && payload.z_c0.length > 0) {
      workingCookies = upsertCookie(workingCookies, { name: 'z_c0', value: payload.z_c0 });
    }
    if (expiredScanPayload(payload)) {
      return {
        state: this.stateValue(QrLoginStatus.EXPIRED, '二维码已过期，请刷新', expiresAt),
        cookies: workingCookies
      };
    }
    const hasZC0 = workingCookies.some((cookie: SessionCookie) =>
      cookie.name === 'z_c0' && cookie.value.length > 0);
    if (hasZC0) {
      return {
        state: this.stateValue(QrLoginStatus.CREDENTIAL_READY, '扫码结果待账号验证', expiresAt),
        cookies: workingCookies
      };
    }
    if (payload.status === 1 || successfulScanPayload(payload)) {
      return {
        state: this.stateValue(QrLoginStatus.WAITING_CONFIRMATION, '请在知乎 App 中确认登录', expiresAt),
        cookies: workingCookies
      };
    }
    return {
      state: this.stateValue(QrLoginStatus.READY, '等待扫码', expiresAt),
      cookies: workingCookies
    };
  }

  private updateState(status: QrLoginStatus, message: string): QrLoginState {
    this.state = this.stateValue(status, message, this.expiresAt);
    return this.getState();
  }

  private stateValue(status: QrLoginStatus, message: string, expiresAt?: number): QrLoginState {
    return {
      status: status,
      message: message,
      expiresAt: expiresAt
    };
  }

  private beginOperation(): ActiveQrLoginOperation | undefined {
    if (this.activeOperation !== undefined) {
      return undefined;
    }
    this.operationGeneration += 1;
    const operation = new ActiveQrLoginOperation(this.operationGeneration);
    this.activeOperation = operation;
    return operation;
  }

  private finishOperation(operation: ActiveQrLoginOperation): void {
    operation.settle();
    if (this.activeOperation === operation) {
      this.activeOperation = undefined;
    }
  }

  private isCurrent(operation: ActiveQrLoginOperation): boolean {
    return this.activeOperation === operation && operation.generation === this.operationGeneration;
  }

  private isCancelled(error: Error | Object): boolean {
    return error instanceof HttpFailure && error.kind === HttpFailureKind.CANCELLED;
  }

  private busyState(): QrLoginState {
    return {
      status: QrLoginStatus.BUSY,
      message: '二维码登录请求正在处理中'
    };
  }
}
