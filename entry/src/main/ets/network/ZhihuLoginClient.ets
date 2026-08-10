import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SessionCookie, toCookieHeader } from '../session/CookieSession';
import { classifyTransportErrorCode, HttpFailureKind } from './HttpFailure';
import { createZse96Header, ZHIHU_WEB_ZSE93 } from './ZhihuFetchSignature';

export const ZHIHU_ME_URL = 'https://www.zhihu.com/api/v4/me';
const ZHIHU_USER_AGENT =
  'Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/540.0 (KHTML, like Gecko) ' +
    'Ubuntu/10.10 Chrome/9.1.0.0 Safari/540.0';

export enum LoginVerificationStatus {
  AUTHENTICATED = 'authenticated',
  INVALID_INPUT = 'invalid_input',
  REJECTED = 'rejected',
  INVALID_RESPONSE = 'invalid_response',
  TEMPORARY_FAILURE = 'temporary_failure'
}

export interface ZhihuProfile {
  id: string;
  name: string;
  urlToken?: string;
  userType: string;
  avatarUrl?: string;
}

export interface LoginVerificationResult {
  status: LoginVerificationStatus;
  message: string;
  profile?: ZhihuProfile;
}

interface ZhihuMeResponse {
  id?: string;
  name?: string;
  url_token?: string;
  user_type?: string;
  avatar_url?: string;
}

interface LoginRequestHeaders {
  Accept: string;
  Cookie: string;
  Referer: string;
  'User-Agent': string;
  'x-requested-with': string;
  'x-zse-93': string;
  'x-zse-96': string;
}

export function cookieValue(cookies: Array<SessionCookie>, name: string): string | undefined {
  const cookie = cookies.find((candidate: SessionCookie) => candidate.name === name && candidate.value.length > 0);
  return cookie?.value;
}

export function hasRequiredLoginCookies(cookies: Array<SessionCookie>): boolean {
  return cookieValue(cookies, 'z_c0') !== undefined && cookieValue(cookies, 'd_c0') !== undefined;
}

export function parseZhihuProfile(responseBody: string): ZhihuProfile | undefined {
  try {
    const payload = JSON.parse(responseBody) as ZhihuMeResponse;
    if (typeof payload.id !== 'string' || payload.id.length === 0 ||
      typeof payload.name !== 'string' || payload.name.length === 0) {
      return undefined;
    }
    return {
      id: payload.id,
      name: payload.name,
      urlToken: payload.url_token,
      userType: typeof payload.user_type === 'string' ? payload.user_type : '',
      avatarUrl: payload.avatar_url
    };
  } catch (_error) {
    return undefined;
  }
}

export function classifyLoginResponse(statusCode: number, responseBody: string): LoginVerificationResult {
  if (statusCode === 401 || statusCode === 403) {
    return {
      status: LoginVerificationStatus.REJECTED,
      message: 'Cookie 已失效或被知乎拒绝'
    };
  }
  if (statusCode === 429) {
    return {
      status: LoginVerificationStatus.TEMPORARY_FAILURE,
      message: '知乎请求过于频繁，请稍后重试'
    };
  }
  if (statusCode !== 200) {
    return {
      status: LoginVerificationStatus.TEMPORARY_FAILURE,
      message: `知乎服务暂时不可用（HTTP ${statusCode}）`
    };
  }

  const profile = parseZhihuProfile(responseBody);
  if (profile === undefined) {
    return {
      status: LoginVerificationStatus.INVALID_RESPONSE,
      message: '知乎返回了无法识别的账号信息'
    };
  }
  return {
    status: LoginVerificationStatus.AUTHENTICATED,
    message: `已验证账号：${profile.name}`,
    profile: profile
  };
}

export function classifyLoginTransportError(errorCode?: number): LoginVerificationResult {
  const failureKind = classifyTransportErrorCode(errorCode);
  return {
    status: LoginVerificationStatus.TEMPORARY_FAILURE,
    message: failureKind === HttpFailureKind.TIMEOUT
      ? '网络请求超时，请稍后重试'
      : '网络连接失败，请稍后重试'
  };
}

export class ZhihuLoginClient {
  async verify(cookies: Array<SessionCookie>): Promise<LoginVerificationResult> {
    if (!hasRequiredLoginCookies(cookies)) {
      return {
        status: LoginVerificationStatus.INVALID_INPUT,
        message: 'Cookie 必须同时包含 z_c0 和 d_c0'
      };
    }

    const dc0 = cookieValue(cookies, 'd_c0') as string;
    const request = http.createHttp();
    const headers: LoginRequestHeaders = {
      'Accept': 'application/json, text/plain, */*',
      'Cookie': toCookieHeader(cookies, Date.now()),
      'Referer': 'https://www.zhihu.com/',
      'User-Agent': ZHIHU_USER_AGENT,
      'x-requested-with': 'fetch',
      'x-zse-93': ZHIHU_WEB_ZSE93,
      'x-zse-96': createZse96Header(ZHIHU_ME_URL, dc0)
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000,
      usingCache: false
    };

    try {
      const response = await request.request(ZHIHU_ME_URL, options);
      return classifyLoginResponse(Number(response.responseCode), response.result as string);
    } catch (error) {
      return classifyLoginTransportError((error as BusinessError).code);
    } finally {
      request.destroy();
    }
  }
}
