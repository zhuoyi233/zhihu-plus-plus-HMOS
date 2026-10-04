import { hilog } from '@kit.PerformanceAnalysisKit';
import { sessionCookieValue, SessionCookieProvider, ZhihuHttpClient, ZhihuHttpMethod } from '../network/ZhihuHttpClient';

export const LASTREAD_TOUCH_URL = 'https://www.zhihu.com/lastread/touch';
/** 上报类型白名单：对齐上游 lastread/touch 仅支持回答/文章/想法。 */
const LASTREAD_TOUCH_KIND_PATTERN = /^(?:answer|article|pin)$/;
const LASTREAD_TOUCH_ACTION_PATTERN = /^(?:read|touch)$/;
const LASTREAD_TOUCH_ID_PATTERN = /^[1-9][0-9]{0,29}$/;
const MULTIPART_BOUNDARY_PATTERN = /^[0-9a-f]{16}$/;

/** lastread/touch 单条载荷：对齐上游 [type, id, action] 三元组。 */
export interface LastReadTouchEntry {
  kind: string;
  id: string;
  action: string;
}

/** 服务端接收的紧凑三元组数组，如 [["answer","123","read"]]。 */
export function buildLastReadTouchPayload(entries: Array<LastReadTouchEntry>): string {
  const tuples = entries.map((entry: LastReadTouchEntry): string => {
    if (!LASTREAD_TOUCH_KIND_PATTERN.test(entry.kind) || !LASTREAD_TOUCH_ID_PATTERN.test(entry.id) ||
      !LASTREAD_TOUCH_ACTION_PATTERN.test(entry.action)) {
      throw new Error('Last read touch entry is invalid');
    }
    return `["${entry.kind}","${entry.id}","${entry.action}"]`;
  });
  return `[${tuples.join(',')}]`;
}

/** 手工构造 multipart/form-data（对齐上游 MultiPartFormDataContent 的单字段 items 表单）。 */
export function buildLastReadTouchMultipart(entries: Array<LastReadTouchEntry>, boundary: string): string {
  if (!MULTIPART_BOUNDARY_PATTERN.test(boundary)) {
    throw new Error('Last read touch boundary is invalid');
  }
  const payload = buildLastReadTouchPayload(entries);
  return `--${boundary}\r\nContent-Disposition: form-data; name="items"\r\n\r\n${payload}\r\n--${boundary}--\r\n`;
}

export function lastReadTouchContentTypeOf(boundary: string): string {
  if (!MULTIPART_BOUNDARY_PATTERN.test(boundary)) {
    throw new Error('Last read touch boundary is invalid');
  }
  return `multipart/form-data; boundary=${boundary}`;
}

/** 上次阅读上报通道：对齐上游 lastread/touch（点击 read、feed 曝光批量 touch）。 */
export interface LastReadTouchRepository {
  report(entries: Array<LastReadTouchEntry>): Promise<void>;
}

/** 对齐上游 lastread/touch：首页点击上报 read、feed 曝光批量上报 touch，驱动知乎"上次阅读"卡片。 */
export class DefaultLastReadTouchRepository implements LastReadTouchRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly cookieProvider?: SessionCookieProvider;

  constructor(httpClient: ZhihuHttpClient, cookieProvider?: SessionCookieProvider) {
    this.httpClient = httpClient;
    this.cookieProvider = cookieProvider;
  }

  /** entries 为空或游客态时静默跳过；失败向上抛出由调用方兜底。 */
  async report(entries: Array<LastReadTouchEntry>): Promise<void> {
    if (entries.length === 0) {
      return;
    }
    if (this.cookieProvider !== undefined &&
      sessionCookieValue(this.cookieProvider.getCookies(), 'd_c0') === undefined) {
      return;
    }
    const boundary = randomBoundary();
    await this.httpClient.execute({
      url: LASTREAD_TOUCH_URL,
      method: ZhihuHttpMethod.POST,
      body: buildLastReadTouchMultipart(entries, boundary),
      accept: 'application/json',
      contentType: lastReadTouchContentTypeOf(boundary),
      useSession: true,
      signWithZse: true
    });
    hilog.info(0xD001, 'LastReadTouch', 'reported action=%{public}s count=%{public}d',
      entries[0].action, entries.length);
  }
}

function randomBoundary(): string {
  let value = '';
  for (let i = 0; i < 16; i++) {
    value += Math.floor(Math.random() * 16).toString(16);
  }
  return value;
}
