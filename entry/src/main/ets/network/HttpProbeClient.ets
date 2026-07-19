import { http } from '@kit.NetworkKit';

const PROBE_URL = 'https://www.zhihu.com/api/v4/questions/19550228?include=title';

export enum HttpFailureKind {
  CLIENT = 'client',
  SERVER = 'server'
}

export interface HttpProbeResult {
  statusCode: number;
  body: string;
  cookies: string;
}

interface ProbeRequestHeaders {
  Accept: string;
  'User-Agent': string;
}

export function classifyHttpStatus(statusCode: number): HttpFailureKind | undefined {
  if (statusCode >= 400 && statusCode < 500) {
    return HttpFailureKind.CLIENT;
  }
  if (statusCode >= 500) {
    return HttpFailureKind.SERVER;
  }
  return undefined;
}

export class HttpProbeClient {
  private currentRequest?: http.HttpRequest;
  private cancelled: boolean = false;

  async requestPublicQuestion(): Promise<HttpProbeResult> {
    const request = http.createHttp();
    this.currentRequest = request;
    this.cancelled = false;

    const headers: ProbeRequestHeaders = {
      'Accept': 'application/json',
      'User-Agent': 'ZhihuPlusPlusHarmonyOS-P0/0.1'
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
      const response = await request.request(PROBE_URL, options);
      const statusCode = Number(response.responseCode);
      const failureKind = classifyHttpStatus(statusCode);
      if (failureKind !== undefined) {
        throw new Error(`HTTP ${statusCode} (${failureKind})`);
      }
      const result: HttpProbeResult = {
        statusCode: statusCode,
        body: response.result as string,
        cookies: response.cookies
      };
      return result;
    } catch (error) {
      if (this.cancelled) {
        throw new Error('请求已取消');
      }
      const message = error instanceof Error ? error.message : '网络请求失败';
      throw new Error(message);
    } finally {
      if (this.currentRequest === request) {
        this.currentRequest = undefined;
      }
      request.destroy();
    }
  }

  cancel(): void {
    this.cancelled = true;
    this.currentRequest?.destroy();
    this.currentRequest = undefined;
  }
}
