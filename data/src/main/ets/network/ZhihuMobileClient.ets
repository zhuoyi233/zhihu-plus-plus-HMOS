import { SessionCookie, toCookieHeader } from '../session/CookieSession';
import { HttpFailure, HttpFailureKind, httpFailureFromStatus, httpFailureFromTransport } from './HttpFailure';
import { PreparedZhihuHttpRequest, SessionCookieProvider, ZhihuHttpMethod,
  ZhihuRequestHeaders, ZhihuHttpResponse, ZhihuHttpTransport, ZhihuHttpTransportFactory,
  NetworkKitHttpTransportFactory, ZHIHU_CONNECT_TIMEOUT_MS, ZHIHU_READ_TIMEOUT_MS,
  ZHIHU_RESPONSE_LIMIT_BYTES } from './ZhihuHttpClient';

/**
 * 移动端协议（api.zhihu.com）请求头，对齐上游 `AccountData.ANDROID_HEADERS`
 * 与 `mobileHomeFeedHttpClient` 的 UserAgent：仅固定 UA + 版本头 + 会话 Cookie，
 * 不做 web ZSE 签名（上游通知 v3 / 私信接口均不带 x-zse-96）。
 */
export const ZHIHU_MOBILE_USER_AGENT =
  'com.zhihu.android/Futureve/10.61.0 Mozilla/5.0 (Linux; Android 12; sdk_gphone64_arm64 ' +
  'Build/SE1A.220630.001.A1; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 ' +
  'Chrome/57.0.1000.10 Mobile Safari/537.36';

const ZHIHU_MOBILE_API_VERSION = '3.1.8';
const ZHIHU_MOBILE_APP_VERSION = '10.61.0';
const ZHIHU_MOBILE_APP_ZA =
  'OS=Android&Release=12&Model=sdk_gphone64_arm64&VersionName=10.61.0&VersionCode=26107&' +
  'Product=com.zhihu.android&Width=1440&Height=2952&Installer=%E7%81%B0%E5%BA%A6&' +
  'DeviceType=AndroidPhone&Brand=google';

export interface ZhihuMobileHttpRequest {
  url: string;
  method?: ZhihuHttpMethod;
  /** 已按协议加密/编码完成的请求体（如 encryptZhihuMessageBody 的结果）。 */
  body?: string;
  accept?: string;
  contentType?: string;
  /** 移动端加密协议版本声明（如发私信的 `101_1_1.0`）。 */
  xZse93?: string;
  /** 推荐流允许访客访问；通知和私信保持默认必须携带会话。 */
  useSession?: boolean;
}

export function isMobileApiRequestUrl(url: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  const match = /^https:\/\/([^/?#]+)(?:[/?#]|$)/.exec(url);
  if (match === null) {
    return false;
  }
  const authority = match[1];
  return authority === 'api.zhihu.com';
}

export function prepareZhihuMobileHttpRequest(request: ZhihuMobileHttpRequest,
  cookies: Array<SessionCookie>): PreparedZhihuHttpRequest {
  if (!isMobileApiRequestUrl(request.url)) {
    throw new HttpFailure(HttpFailureKind.CLIENT);
  }
  const cookieHeader = toCookieHeader(cookies, Date.now());
  if (request.useSession !== false && cookieHeader.length === 0) {
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
  }
  let headers: ZhihuRequestHeaders = {
    'Accept': request.accept ?? 'application/json',
    'User-Agent': ZHIHU_MOBILE_USER_AGENT,
    'x-api-version': ZHIHU_MOBILE_API_VERSION,
    'x-app-version': ZHIHU_MOBILE_APP_VERSION,
    'x-app-za': ZHIHU_MOBILE_APP_ZA
  };
  if (cookieHeader.length > 0 && request.body === undefined) {
    headers = {
      'Accept': request.accept ?? 'application/json',
      'User-Agent': ZHIHU_MOBILE_USER_AGENT,
      'Cookie': cookieHeader,
      'x-api-version': ZHIHU_MOBILE_API_VERSION,
      'x-app-version': ZHIHU_MOBILE_APP_VERSION,
      'x-app-za': ZHIHU_MOBILE_APP_ZA
    };
  }
  if (request.body !== undefined) {
    headers = {
      'Accept': request.accept ?? 'application/json',
      'User-Agent': ZHIHU_MOBILE_USER_AGENT,
      'Cookie': cookieHeader,
      'x-api-version': ZHIHU_MOBILE_API_VERSION,
      'x-app-version': ZHIHU_MOBILE_APP_VERSION,
      'x-app-za': ZHIHU_MOBILE_APP_ZA,
      'Content-Type': request.contentType ?? 'application/x-www-form-urlencoded',
      'x-zse-93': request.xZse93
    };
  }  return {
    url: request.url,
    method: request.method ?? ZhihuHttpMethod.GET,
    body: request.body,
    headers: headers,
    connectTimeout: ZHIHU_CONNECT_TIMEOUT_MS,
    readTimeout: ZHIHU_READ_TIMEOUT_MS,
    maxRedirects: 0,
    maxLimit: ZHIHU_RESPONSE_LIMIT_BYTES
  };
}

class ActiveMobileRequest {
  readonly transport: ZhihuHttpTransport;
  readonly cancellation: Promise<ZhihuHttpResponse>;
  private rejectCancellation?: () => void;
  private destroyed: boolean = false;

  constructor(transport: ZhihuHttpTransport) {
    this.transport = transport;
    this.cancellation = new Promise<ZhihuHttpResponse>((_resolve, reject) => {
      this.rejectCancellation = (): void => reject(new HttpFailure(HttpFailureKind.CANCELLED));
    });
  }

  cancel(): void {
    this.rejectCancellation?.();
    this.destroy();
  }

  settle(): void {
    this.rejectCancellation = undefined;
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    try {
      this.transport.destroy();
    } catch (_error) {
    }
  }
}

/**
 * 移动端协议 HTTP 客户端（api.zhihu.com 专用）。单飞 + 取消语义与 `ZhihuHttpClient`
 * 一致；仅使用上游 Android 客户端同款 UA/版本头 + 会话 Cookie，无 web ZSE 签名。
 */
export class ZhihuMobileHttpClient {
  private readonly cookieProvider?: SessionCookieProvider;
  private readonly transportFactory: ZhihuHttpTransportFactory;
  private activeRequest?: ActiveMobileRequest;

  constructor(cookieProvider?: SessionCookieProvider, transportFactory?: ZhihuHttpTransportFactory) {
    this.cookieProvider = cookieProvider;
    this.transportFactory = transportFactory ?? new NetworkKitHttpTransportFactory();
  }

  async execute(request: ZhihuMobileHttpRequest): Promise<ZhihuHttpResponse> {
    if (this.activeRequest !== undefined) {
      throw new HttpFailure(HttpFailureKind.BUSY);
    }
    if (!isMobileApiRequestUrl(request.url)) {
      throw new HttpFailure(HttpFailureKind.CLIENT);
    }
    let activeRequest: ActiveMobileRequest | undefined = undefined;
    try {
      const cookies = this.cookieProvider?.getCookies() ?? [];
      const preparedRequest = prepareZhihuMobileHttpRequest(request, cookies);
      const transport = this.transportFactory.create();
      const active: ActiveMobileRequest = new ActiveMobileRequest(transport);
      activeRequest = active;
      this.activeRequest = active;
      const pending: Array<Promise<ZhihuHttpResponse>> = [
        transport.request(preparedRequest),
        active.cancellation
      ];
      const response = await Promise.race(pending);
      const failure = httpFailureFromStatus(response.statusCode);
      if (failure !== undefined) {
        throw failure;
      }
      return response;
    } catch (error) {
      if (error instanceof HttpFailure) {
        throw new HttpFailure(error.kind, error.status, error.transportCode);
      }
      throw httpFailureFromTransport();
    } finally {
      if (activeRequest !== undefined) {
        if (this.activeRequest === activeRequest) {
          this.activeRequest = undefined;
        }
        activeRequest.destroy();
        activeRequest.settle();
      }
    }
  }

  cancel(): void {
    const activeRequest = this.activeRequest;
    if (activeRequest === undefined) {
      return;
    }
    this.activeRequest = undefined;
    activeRequest.cancel();
  }
}
