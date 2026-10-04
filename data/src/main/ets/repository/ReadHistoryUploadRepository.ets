import { hilog } from '@kit.PerformanceAnalysisKit';
import { sessionCookieValue, SessionCookieProvider, ZhihuHttpClient, ZhihuHttpMethod } from '../network/ZhihuHttpClient';
import { ReadHistoryUploadRepository } from './ReadHistoryUploadContracts';

export const READ_HISTORY_ADD_URL = 'https://www.zhihu.com/api/v4/read_history/add';

/** 上报单元：与在线历史删除的 OnlineHistoryDeletePair 同构（token 为内容 id，type 为小写类名）。 */
export interface ReadHistoryAddPair {
  contentToken: string;
  contentType: string;
}

/** 个人主页上报单元：对齐上游 addReadHistory(person.id, "profile")。
 * people id 允许 [A-Za-z0-9_-]（与 people 解码器 identifier 规则一致），不限于纯数字。 */
export function readHistoryProfilePairOf(personId: string): ReadHistoryAddPair {
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(personId)) {
    throw new Error('Read history person id is invalid');
  }
  return { contentToken: personId, contentType: 'profile' };
}

/** contentKey 形如 "answer:123456"；与在线历史 `${kind}:${id}` 约定一致。profile 走 addProfile。 */
export function readHistoryAddPairOf(contentKey: string): ReadHistoryAddPair {
  const separator = contentKey.indexOf(':');
  if (separator <= 0 || separator !== contentKey.lastIndexOf(':')) {
    throw new Error('Read history content key is invalid');
  }
  const contentType = contentKey.substring(0, separator);
  const contentToken = contentKey.substring(separator + 1);
  if (!/^(?:question|answer|article|pin)$/.test(contentType) || !/^[1-9][0-9]{0,29}$/.test(contentToken)) {
    throw new Error('Read history content key is invalid');
  }
  return { contentToken: contentToken, contentType: contentType };
}

export function buildReadHistoryAddBody(pair: ReadHistoryAddPair): string {
  return `{"content_token":"${pair.contentToken}","content_type":"${pair.contentType}"}`;
}

/** 对齐上游 addReadHistory：打开内容即单条上报云端阅读历史，服务端负责记账 read_time。 */
export class DefaultReadHistoryUploadRepository implements ReadHistoryUploadRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly cookieProvider?: SessionCookieProvider;

  constructor(httpClient: ZhihuHttpClient, cookieProvider?: SessionCookieProvider) {
    this.httpClient = httpClient;
    this.cookieProvider = cookieProvider;
  }

  async add(contentKey: string): Promise<void> {
    await this.execute(readHistoryAddPairOf(contentKey));
  }

  async addProfile(personId: string): Promise<void> {
    await this.execute(readHistoryProfilePairOf(personId));
  }

  private async execute(pair: ReadHistoryAddPair): Promise<void> {
    if (this.cookieProvider !== undefined &&
      sessionCookieValue(this.cookieProvider.getCookies(), 'd_c0') === undefined) {
      hilog.info(0xD001, 'ReadHistoryUpload', 'skip guest');
      return;
    }
    await this.httpClient.execute({
      url: READ_HISTORY_ADD_URL,
      method: ZhihuHttpMethod.POST,
      body: buildReadHistoryAddBody(pair),
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    hilog.info(0xD001, 'ReadHistoryUpload', 'accepted type=%{public}s', pair.contentType);
  }
}
