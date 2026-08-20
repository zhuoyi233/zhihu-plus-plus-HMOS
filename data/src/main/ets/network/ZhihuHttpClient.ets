import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SessionCookie, toCookieHeader } from '../session/CookieSession';
import { HttpFailure, HttpFailureKind, httpFailureFromStatus, httpFailureFromTransport } from './HttpFailure';
import { createZse96Header, ZHIHU_WEB_ZSE93 } from './ZhihuFetchSignature';

export const ZHIHU_USER_AGENT =
  'Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/540.0 (KHTML, like Gecko) ' +
    'Ubuntu/10.10 Chrome/9.1.0.0 Safari/540.0';
export const ZHIHU_CONNECT_TIMEOUT_MS = 10000;
export const ZHIHU_READ_TIMEOUT_MS = 15000;
export const ZHIHU_RESPONSE_LIMIT_BYTES = 1024 * 1024;

export enum ZhihuHttpMethod {
  GET = 'GET',
  POST = 'POST',
  PUT = 'PUT',
  DELETE = 'DELETE'
}

export interface SessionCookieProvider {
  getCookies(): Array<SessionCookie>;
}

export interface ZhihuRequestHeaders {
  Accept: string;
  'User-Agent': string;
  Cookie?: string;
  Referer?: string;
  'x-requested-with'?: string;
  'x-zse-93'?: string;
  'x-zse-96'?: string;
  'x-xsrftoken'?: string;
  'Content-Type'?: string;
}

export interface ZhihuHttpRequest {
  url: string;
  method?: ZhihuHttpMethod;
  body?: string;
  accept?: string;
  useSession?: boolean;
  signWithZse?: boolean;
  /** 仅发布等网页写接口需要；令客户端从受保护会话 Cookie 提取 `_xsrf`。 */
  includeXsrfToken?: boolean;
  /** 仅接受站内路径，防止调用方借 Referer 写入任意外部地址。 */
  refererPath?: string;
  contentType?: string;
}

export interface PreparedZhihuHttpRequest {
  url: string;
  method: ZhihuHttpMethod;
  body?: string;
  headers: ZhihuRequestHeaders;
  connectTimeout: number;
  readTimeout: number;
  maxRedirects: number;
  maxLimit: number;
}

export interface ZhihuHttpResponse {
  statusCode: number;
  body: string;
}

export interface ZhihuHttpTransport {
  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse>;
  destroy(): void;
}

export interface ZhihuHttpTransportFactory {
  create(): ZhihuHttpTransport;
}

const TRUSTED_ZHIHU_HOSTS: Array<string> = [
  'www.zhihu.com',
  'api.zhihu.com',
  'news-at.zhihu.com',
  'daily.zhihu.com'
];

export function isTrustedZhihuRequestUrl(url: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]+)(?:[/?#]|$)/.exec(url);
  if (match === null || match[1].toLowerCase() !== 'https') {
    return false;
  }
  const authority = match[2];
  if (authority.includes('@') || authority.includes(':')) {
    return false;
  }
  return TRUSTED_ZHIHU_HOSTS.includes(authority.toLowerCase());
}

export function isSessionCapableZhihuRequestUrl(url: string): boolean {
  if (!isTrustedZhihuRequestUrl(url)) {
    return false;
  }
  return /^https:\/\/(?:www|api)\.zhihu\.com(?:[/?#]|$)/.test(url);
}

export function isSafeZhihuRefererPath(value: string | undefined): boolean {
  return typeof value === 'string' && /^\/(?:[A-Za-z0-9._~-]+\/)*[A-Za-z0-9._~-]*$/.test(value);
}

export function sessionCookieValue(cookies: Array<SessionCookie>, name: string): string | undefined {
  const cookie = cookies.find((candidate: SessionCookie) => candidate.name === name && candidate.value.length > 0);
  return cookie?.value;
}

export function prepareZhihuHttpRequest(
  request: ZhihuHttpRequest,
  cookies: Array<SessionCookie> = [],
  now: number = Date.now()
): PreparedZhihuHttpRequest {
  if (!isTrustedZhihuRequestUrl(request.url)) {
    throw new HttpFailure(HttpFailureKind.CLIENT);
  }
  if (request.refererPath !== undefined && !isSafeZhihuRefererPath(request.refererPath)) {
    throw new HttpFailure(HttpFailureKind.CLIENT);
  }
  if ((request.useSession === true || request.signWithZse === true || request.includeXsrfToken === true) &&
    !isSessionCapableZhihuRequestUrl(request.url)) {
    throw new HttpFailure(HttpFailureKind.CLIENT);
  }
  let cookieHeader: string | undefined = undefined;
  if (request.useSession === true || request.signWithZse === true || request.includeXsrfToken === true) {
    cookieHeader = toCookieHeader(cookies, now);
    if (cookieHeader.length === 0) {
      throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
    }
  }
  let zse96: string | undefined = undefined;
  if (request.signWithZse === true) {
    const dc0 = sessionCookieValue(cookies, 'd_c0');
    if (dc0 === undefined) {
      throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
    }
    zse96 = createZse96Header(request.url, dc0, request.body);
  }
  const xsrf = request.includeXsrfToken === true ? sessionCookieValue(cookies, '_xsrf') : undefined;
  if (request.includeXsrfToken === true && xsrf === undefined) {
    throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
  }
  const accept = request.accept ?? 'application/json, text/plain, */*';
  const bodyContentType = request.contentType ?? 'application/json';
  const referer = request.refererPath === undefined
    ? 'https://www.zhihu.com/'
    : `https://www.zhihu.com${request.refererPath}`;
  let headers: ZhihuRequestHeaders;
  if (zse96 !== undefined && request.body !== undefined) {
    headers = {
      'Accept': accept,
      'User-Agent': ZHIHU_USER_AGENT,
      'Cookie': cookieHeader,
      'Referer': referer,
      'x-requested-with': 'fetch',
      'x-zse-93': ZHIHU_WEB_ZSE93,
      'x-zse-96': zse96,
      'x-xsrftoken': xsrf,
      'Content-Type': bodyContentType
    };
  } else if (zse96 !== undefined) {
    headers = {
      'Accept': accept,
      'User-Agent': ZHIHU_USER_AGENT,
      'Cookie': cookieHeader,
      'Referer': referer,
      'x-requested-with': 'fetch',
      'x-zse-93': ZHIHU_WEB_ZSE93,
      'x-zse-96': zse96,
      'x-xsrftoken': xsrf
    };
  } else if (cookieHeader !== undefined && request.body !== undefined) {
    headers = {
      'Accept': accept,
      'User-Agent': ZHIHU_USER_AGENT,
      'Cookie': cookieHeader,
      'Referer': referer,
      'x-requested-with': 'fetch',
      'x-xsrftoken': xsrf,
      'Content-Type': bodyContentType
    };
  } else if (cookieHeader !== undefined) {
    headers = {
      'Accept': accept,
      'User-Agent': ZHIHU_USER_AGENT,
      'Cookie': cookieHeader,
      'Referer': referer,
      'x-requested-with': 'fetch',
      'x-xsrftoken': xsrf
    };
  } else if (request.body !== undefined) {
    headers = {
      'Accept': accept,
      'User-Agent': ZHIHU_USER_AGENT,
      'Content-Type': bodyContentType
    };
  } else {
    headers = {
      'Accept': accept,
      'User-Agent': ZHIHU_USER_AGENT
    };
  }
  return {
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

class NetworkKitHttpTransport implements ZhihuHttpTransport {
  private readonly requestHandle: http.HttpRequest = http.createHttp();

  async request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    let method = http.RequestMethod.GET;
    if (request.method === ZhihuHttpMethod.POST) {
      method = http.RequestMethod.POST;
    } else if (request.method === ZhihuHttpMethod.PUT) {
      method = http.RequestMethod.PUT;
    } else if (request.method === ZhihuHttpMethod.DELETE) {
      method = http.RequestMethod.DELETE;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: request.headers,
      extraData: request.body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: request.connectTimeout,
      readTimeout: request.readTimeout,
      maxRedirects: request.maxRedirects,
      maxLimit: request.maxLimit,
      usingCache: false
    };
    return this.requestHandle.request(request.url, options).then((response): ZhihuHttpResponse => {
      if (typeof response.result !== 'string') {
        throw new Error('HTTP response body must be text');
      }
      return {
        statusCode: Number(response.responseCode),
        body: response.result
      };
    }).catch((error: BusinessError): never => {
      throw httpFailureFromTransport(error.code);
    });
  }

  destroy(): void {
    this.requestHandle.destroy();
  }
}

class NetworkKitHttpTransportFactory implements ZhihuHttpTransportFactory {
  create(): ZhihuHttpTransport {
    return new NetworkKitHttpTransport();
  }
}

class ActiveZhihuRequest {
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

export class ZhihuHttpClient {
  private readonly cookieProvider?: SessionCookieProvider;
  private readonly transportFactory: ZhihuHttpTransportFactory;
  private activeRequest?: ActiveZhihuRequest;

  constructor(cookieProvider?: SessionCookieProvider, transportFactory?: ZhihuHttpTransportFactory) {
    this.cookieProvider = cookieProvider;
    this.transportFactory = transportFactory ?? new NetworkKitHttpTransportFactory();
  }

  async execute(request: ZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    if (this.activeRequest !== undefined) {
      throw new HttpFailure(HttpFailureKind.BUSY);
    }
    if (!isTrustedZhihuRequestUrl(request.url)) {
      throw new HttpFailure(HttpFailureKind.CLIENT);
    }
    if (request.refererPath !== undefined && !isSafeZhihuRefererPath(request.refererPath)) {
      throw new HttpFailure(HttpFailureKind.CLIENT);
    }
    if ((request.useSession === true || request.signWithZse === true || request.includeXsrfToken === true) &&
      !isSessionCapableZhihuRequestUrl(request.url)) {
      throw new HttpFailure(HttpFailureKind.CLIENT);
    }
    let activeRequest: ActiveZhihuRequest | undefined = undefined;
    try {
      const cookies = request.useSession === true || request.signWithZse === true || request.includeXsrfToken === true
        ? this.cookieProvider?.getCookies() ?? []
        : [];
      const preparedRequest = prepareZhihuHttpRequest(request, cookies);
      const transport = this.transportFactory.create();
      activeRequest = new ActiveZhihuRequest(transport);
      this.activeRequest = activeRequest;
      const pendingRequests: Array<Promise<ZhihuHttpResponse>> = [
        transport.request(preparedRequest),
        activeRequest.cancellation
      ];
      const response = await Promise.race(pendingRequests);
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
