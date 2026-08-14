import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import {
  parseCookieJarEntries,
  SessionCookie,
  toCookieHeader,
  upsertCookie
} from './CookieSession';

const GUEST_PREFERENCES_NAME = 'guest_device';
const GUEST_COOKIE_KEY = 'guest_device_cookies_v1';
const SIGNIN_URL = 'https://www.zhihu.com/signin?next=%2F';
const UDID_URL = 'https://www.zhihu.com/udid';
const GUEST_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
const REQUEST_TIMEOUT_MS = 10000;
const RESPONSE_LIMIT_BYTES = 1024 * 1024;

function copyCookies(cookies: Array<SessionCookie>): Array<SessionCookie> {
  return cookies.map((cookie: SessionCookie): SessionCookie => ({
    name: cookie.name,
    value: cookie.value,
    expiresAt: cookie.expiresAt
  }));
}

function mergeCookies(current: Array<SessionCookie>, incoming: Array<SessionCookie>): Array<SessionCookie> {
  let merged = copyCookies(current);
  incoming.forEach((cookie: SessionCookie): void => {
    merged = upsertCookie(merged, cookie);
  });
  return merged;
}

/**
 * 游客态设备 Cookie 管理器。
 *
 * 知乎 equation 端点对无 Cookie 的请求会触发 unhuman 安全验证；登录态下公式请求
 * 已携带会话 Cookie，但游客态 SessionRepository 为空。本管理器在游客态懒获取知乎
 * 下发的设备指纹 Cookie（/signin 与 /udid，主要是 d_c0），供公式等只读资源请求
 * 携带，降低被风控的概率。
 *
 * 这些 Cookie 仅设备指纹，不含登录凭据 z_c0，泄露不能冒用账号；因此用明文
 * Preferences 持久化即可，与登录会话的加密存储分离，不污染登录态。
 */
export class GuestDeviceCookieManager {
  private readonly context: common.Context;
  private cookies: Array<SessionCookie> = [];
  private ready: boolean = false;
  private pending?: Promise<Array<SessionCookie>>;

  constructor(context: common.Context) {
    this.context = context;
  }

  async getCookieHeader(): Promise<string> {
    const cookies = await this.getCookies();
    return toCookieHeader(cookies, Date.now());
  }

  async getCookies(): Promise<Array<SessionCookie>> {
    if (this.ready) {
      return copyCookies(this.cookies);
    }
    if (this.pending === undefined) {
      this.pending = this.load();
    }
    const cookies = await this.pending;
    this.cookies = copyCookies(cookies);
    this.ready = true;
    this.pending = undefined;
    return copyCookies(this.cookies);
  }

  private async load(): Promise<Array<SessionCookie>> {
    const stored = await this.readStored();
    if (stored.length > 0) {
      return stored;
    }
    const fetched = await this.fetchGuestDeviceCookies();
    if (fetched.length > 0) {
      await this.writeStored(fetched);
    }
    return fetched;
  }

  private async fetchGuestDeviceCookies(): Promise<Array<SessionCookie>> {
    let cookies: Array<SessionCookie> = [];
    cookies = mergeCookies(cookies, await this.request(SIGNIN_URL, http.RequestMethod.GET, ''));
    cookies = mergeCookies(cookies, await this.request(UDID_URL, http.RequestMethod.POST, '{}'));
    return cookies;
  }

  private async request(url: string, method: http.RequestMethod, body: string): Promise<Array<SessionCookie>> {
    let request: http.HttpRequest | undefined = undefined;
    try {
      request = http.createHttp();
      const response = await request.request(url, {
        method: method,
        header: {
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': GUEST_USER_AGENT,
          'Content-Type': 'application/json;charset=UTF-8'
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        usingCache: false,
        maxLimit: RESPONSE_LIMIT_BYTES,
        maxRedirects: 3
      });
      if (Number(response.responseCode) < 200 || Number(response.responseCode) >= 300) {
        return [];
      }
      return parseCookieJarEntries(typeof response.cookies === 'string' ? response.cookies : '');
    } catch (_error) {
      return [];
    } finally {
      request?.destroy();
    }
  }

  private async readStored(): Promise<Array<SessionCookie>> {
    try {
      const store = await preferences.getPreferences(this.context, GUEST_PREFERENCES_NAME);
      const value = await store.get(GUEST_COOKIE_KEY, '');
      if (typeof value !== 'string' || value.length === 0) {
        return [];
      }
      return parseCookieJarEntries(value);
    } catch (_error) {
      return [];
    }
  }

  private async writeStored(cookies: Array<SessionCookie>): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, GUEST_PREFERENCES_NAME);
      await store.put(GUEST_COOKIE_KEY, toCookieHeader(cookies, Date.now()));
      await store.flush();
    } catch (_error) {
    }
  }
}

let guestDeviceCookieManager: GuestDeviceCookieManager | undefined = undefined;

export function getGuestDeviceCookieManager(context: common.Context): GuestDeviceCookieManager {
  if (guestDeviceCookieManager === undefined) {
    guestDeviceCookieManager = new GuestDeviceCookieManager(context.getApplicationContext());
  }
  return guestDeviceCookieManager;
}
