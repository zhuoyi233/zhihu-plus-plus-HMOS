import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  classifyHttpStatus,
  classifyTransportErrorCode,
  describeHttpFailure,
  HttpFailureKind
} from './HttpFailure';

const PROBE_URL = 'https://www.zhihu.com/api/v4/questions/19550228?include=title';

export interface HttpProbeResult {
  statusCode: number;
  body: string;
}

interface ProbeRequestHeaders {
  Accept: string;
  'User-Agent': string;
}

export class HttpProbeClient {
  private currentRequest?: http.HttpRequest;
  private cancelledRequest?: http.HttpRequest;

  async requestPublicQuestion(): Promise<HttpProbeResult> {
    if (this.currentRequest !== undefined) {
      throw new Error('已有 HTTP 探针请求正在进行');
    }
    const request = http.createHttp();
    this.currentRequest = request;

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
        throw new Error(describeHttpFailure(failureKind, statusCode));
      }
      const result: HttpProbeResult = {
        statusCode: statusCode,
        body: response.result as string
      };
      return result;
    } catch (error) {
      if (this.cancelledRequest === request) {
        throw new Error(describeHttpFailure(HttpFailureKind.CANCELLED));
      }
      if (error instanceof Error && error.message.startsWith('HTTP ')) {
        throw error;
      }
      const failureKind = classifyTransportErrorCode((error as BusinessError).code);
      throw new Error(describeHttpFailure(failureKind));
    } finally {
      if (this.currentRequest === request) {
        this.currentRequest = undefined;
      }
      if (this.cancelledRequest === request) {
        this.cancelledRequest = undefined;
      }
      request.destroy();
    }
  }

  cancel(): void {
    this.cancelledRequest = this.currentRequest;
    this.cancelledRequest?.destroy();
    this.currentRequest = undefined;
  }
}
