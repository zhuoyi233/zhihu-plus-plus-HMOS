import { ZhihuHttpClient, ZhihuHttpResponse } from './ZhihuHttpClient';

const PROBE_URL = 'https://www.zhihu.com/api/v4/questions/19550228?include=title';

export interface HttpProbeResult {
  statusCode: number;
  body: string;
}

export class HttpProbeClient {
  private readonly httpClient: ZhihuHttpClient;

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    this.httpClient = httpClient;
  }

  async requestPublicQuestion(): Promise<HttpProbeResult> {
    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: PROBE_URL,
      accept: 'application/json'
    });
    return {
      statusCode: response.statusCode,
      body: response.body
    };
  }

  cancel(): void {
    this.httpClient.cancel();
  }
}
