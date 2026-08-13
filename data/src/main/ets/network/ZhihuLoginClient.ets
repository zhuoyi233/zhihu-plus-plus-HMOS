import { SessionCookie } from '../session/CookieSession';
import { JsonObjectValue, JsonStringValue, parseStrictJson } from 'core';
import { HttpFailure, HttpFailureKind, httpFailureFromStatus, httpFailureFromTransport } from './HttpFailure';
import {
  sessionCookieValue,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpTransportFactory
} from './ZhihuHttpClient';

export const ZHIHU_ME_URL = 'https://www.zhihu.com/api/v4/me';

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
  rejectionStatus?: number;
  profile?: ZhihuProfile;
}

class LoginCookieProvider implements SessionCookieProvider {
  private cookies: Array<SessionCookie> = [];

  setCookies(cookies: Array<SessionCookie>): void {
    this.cookies = cookies.slice();
  }

  getCookies(): Array<SessionCookie> {
    return this.cookies.slice();
  }
}

export function hasRequiredLoginCookies(cookies: Array<SessionCookie>): boolean {
  return sessionCookieValue(cookies, 'z_c0') !== undefined && sessionCookieValue(cookies, 'd_c0') !== undefined;
}

export function parseZhihuProfile(responseBody: string): ZhihuProfile | undefined {
  try {
    const payload = parseStrictJson(responseBody);
    if (!(payload instanceof JsonObjectValue)) {
      return undefined;
    }
    const id = payload.get('id');
    const name = payload.get('name');
    const urlToken = payload.get('url_token');
    const userType = payload.get('user_type');
    const avatarUrl = payload.get('avatar_url');
    if (!(id instanceof JsonStringValue) || id.value.length === 0 ||
      !(name instanceof JsonStringValue) || name.value.length === 0) {
      return undefined;
    }
    return {
      id: id.value,
      name: name.value,
      urlToken: urlToken instanceof JsonStringValue ? urlToken.value : undefined,
      userType: userType instanceof JsonStringValue ? userType.value : '',
      avatarUrl: avatarUrl instanceof JsonStringValue ? avatarUrl.value : undefined
    };
  } catch (_error) {
    return undefined;
  }
}

export function classifyLoginResponse(statusCode: number, responseBody: string): LoginVerificationResult {
  const failure = httpFailureFromStatus(statusCode);
  if (failure !== undefined) {
    return classifyLoginFailure(failure);
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

export function classifyLoginFailure(failure: HttpFailure): LoginVerificationResult {
  if (failure.kind === HttpFailureKind.AUTHENTICATION) {
    if (failure.status === 403) {
      return {
        status: LoginVerificationStatus.REJECTED,
        message: '知乎拒绝了本次验证请求，可能需要稍后重试或完成风控',
        rejectionStatus: failure.status
      };
    }
    return {
      status: LoginVerificationStatus.REJECTED,
      message: 'Cookie 已失效或被知乎拒绝',
      rejectionStatus: failure.status
    };
  }
  if (failure.kind === HttpFailureKind.RATE_LIMITED) {
    return {
      status: LoginVerificationStatus.TEMPORARY_FAILURE,
      message: '知乎请求过于频繁，请稍后重试'
    };
  }
  if (failure.kind === HttpFailureKind.TIMEOUT) {
    return {
      status: LoginVerificationStatus.TEMPORARY_FAILURE,
      message: '网络请求超时，请稍后重试'
    };
  }
  if (failure.kind === HttpFailureKind.NETWORK) {
    return {
      status: LoginVerificationStatus.TEMPORARY_FAILURE,
      message: '网络连接失败，请稍后重试'
    };
  }
  if (failure.kind === HttpFailureKind.CANCELLED) {
    return {
      status: LoginVerificationStatus.TEMPORARY_FAILURE,
      message: '登录验证已取消'
    };
  }
  return {
    status: LoginVerificationStatus.TEMPORARY_FAILURE,
    message: failure.status === undefined
      ? '知乎服务暂时不可用'
      : `知乎服务暂时不可用（HTTP ${failure.status}）`
  };
}

export function classifyLoginTransportError(errorCode?: number): LoginVerificationResult {
  return classifyLoginFailure(httpFailureFromTransport(errorCode));
}

export class ZhihuLoginClient {
  private readonly cookieProvider: LoginCookieProvider = new LoginCookieProvider();
  private readonly httpClient: ZhihuHttpClient;

  constructor(transportFactory?: ZhihuHttpTransportFactory) {
    this.httpClient = new ZhihuHttpClient(this.cookieProvider, transportFactory);
  }

  async verify(cookies: Array<SessionCookie>): Promise<LoginVerificationResult> {
    if (!hasRequiredLoginCookies(cookies)) {
      return {
        status: LoginVerificationStatus.INVALID_INPUT,
        message: 'Cookie 必须同时包含 z_c0 和 d_c0'
      };
    }

    this.cookieProvider.setCookies(cookies);
    try {
      const response = await this.httpClient.execute({
        url: ZHIHU_ME_URL,
        accept: 'application/json, text/plain, */*',
        useSession: true,
        signWithZse: true
      });
      return classifyLoginResponse(response.statusCode, response.body);
    } catch (error) {
      if (error instanceof HttpFailure) {
        return classifyLoginFailure(error);
      }
      return classifyLoginTransportError();
    }
  }

  cancel(): void {
    this.httpClient.cancel();
  }
}
