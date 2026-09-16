import {
  JsonArrayValue,
  JsonBooleanValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson
} from 'core';
import { ZhihuHttpClient, ZhihuHttpMethod } from '../network/ZhihuHttpClient';
import { copySessionCookies, SessionCookie, upsertCookie } from './CookieSession';
import { SessionRepository, SessionState } from './SessionRepository';

export interface ZhihuIdentityAccount {
  id: string;
  urlToken: string;
  name: string;
  avatarUrl: string;
  isActive: boolean;
  canCreateSubAccount: boolean;
  accountType: number;
  subAccountControlStatus: number;
}

export interface IdentityManagementState {
  accounts: Array<ZhihuIdentityAccount>;
  currentAccountId: string;
}

function stringField(value: JsonObjectValue, key: string): string {
  const field = value.get(key);
  return field instanceof JsonStringValue ? field.value : '';
}

function numberField(value: JsonObjectValue, key: string): number {
  const field = value.get(key);
  return field instanceof JsonNumberValue ? field.value : 0;
}

function booleanField(value: JsonObjectValue, key: string): boolean {
  const field = value.get(key);
  return field instanceof JsonBooleanValue ? field.value : false;
}

export function decodeIdentityAccounts(body: string): Array<ZhihuIdentityAccount> {
  const root = parseStrictJson(body);
  if (!(root instanceof JsonObjectValue)) {
    throw new Error('身份列表响应格式错误');
  }
  const data = root.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw new Error('身份列表响应缺少 data');
  }
  const accounts: Array<ZhihuIdentityAccount> = [];
  data.items.forEach((item: JsonValue): void => {
    if (!(item instanceof JsonObjectValue)) {
      return;
    }
    const id = stringField(item, 'id');
    const name = stringField(item, 'name');
    if (id.length === 0 || name.length === 0) {
      return;
    }
    accounts.push({
      id: id,
      urlToken: stringField(item, 'url_token'),
      name: name,
      avatarUrl: stringField(item, 'avatar_url'),
      isActive: booleanField(item, 'is_active'),
      canCreateSubAccount: booleanField(item, 'can_create_sub_account'),
      accountType: numberField(item, 'account_type'),
      subAccountControlStatus: numberField(item, 'sub_account_control_status')
    });
  });
  return accounts;
}

export function identityCookiesFromResponse(body: string, existing: Array<SessionCookie>): Array<SessionCookie> {
  const root = parseStrictJson(body);
  if (!(root instanceof JsonObjectValue)) {
    throw new Error('身份凭据响应格式错误');
  }
  const cookieValue = root.get('cookie');
  if (!(cookieValue instanceof JsonObjectValue)) {
    throw new Error('服务器未返回新账号 Cookie');
  }
  let result = copySessionCookies(existing);
  cookieValue.entries.forEach((entry): void => {
    if (entry.value instanceof JsonStringValue && entry.value.value.length > 0) {
      result = upsertCookie(result, { name: entry.name, value: entry.value.value });
    }
  });
  if (!result.some((cookie: SessionCookie): boolean => cookie.name === 'z_c0' && cookie.value.length > 0)) {
    throw new Error('服务器未返回有效的 z_c0 Cookie');
  }
  return result;
}

export class IdentityManagementClient {
  private readonly session: SessionRepository;
  private readonly http: ZhihuHttpClient;

  constructor(session: SessionRepository, http?: ZhihuHttpClient) {
    this.session = session;
    this.http = http ?? new ZhihuHttpClient(session);
  }

  async listAccounts(): Promise<IdentityManagementState> {
    const response = await this.http.execute({
      url: 'https://api.zhihu.com/people/account/list',
      useSession: true,
      useIdentityHeaders: true
    });
    const accounts = decodeIdentityAccounts(response.body);
    const activeAccount = accounts.find((account: ZhihuIdentityAccount): boolean => account.isActive);
    return {
      accounts: accounts,
      currentAccountId: activeAccount?.id ?? this.session.getState().profile?.id ?? ''
    };
  }

  async switchAccount(accountId: string): Promise<SessionState> {
    if (accountId.trim().length === 0) {
      throw new Error('目标账号不能为空');
    }
    const response = await this.http.execute({
      url: 'https://api.zhihu.com/account/switch',
      method: ZhihuHttpMethod.POST,
      body: JSON.stringify({ target_user_id: accountId }),
      contentType: 'application/json',
      useSession: true,
      useIdentityHeaders: true
    });
    return await this.replaceSession(response.body);
  }

  async createSubAccount(): Promise<SessionState> {
    const response = await this.http.execute({
      url: 'https://api.zhihu.com/account/sub/register',
      method: ZhihuHttpMethod.POST,
      useSession: true,
      useIdentityHeaders: true
    });
    return await this.replaceSession(response.body);
  }

  cancel(): void {
    this.http.cancel();
  }

  private async replaceSession(body: string): Promise<SessionState> {
    const cookies = identityCookiesFromResponse(body, this.session.getCookies());
    return await this.session.beginLoginWithCookies(cookies).result;
  }
}
