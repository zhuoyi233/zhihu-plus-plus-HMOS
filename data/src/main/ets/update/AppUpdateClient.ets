import { http } from '@kit.NetworkKit';
import { AppUpdateCheckResult } from './AppUpdateModels';
import { decodeLatestRelease, resolveAppUpdateCheck } from './AppUpdateParser';

/**
 * GitHub Release 更新检测客户端。
 *
 * 刻意不经过 ZhihuHttpClient：更新检测直连 api.github.com，
 * 不携带任何知乎 Cookie、UA 伪装或 ZSE 签名头，避免把知乎会话侧信息发给第三方。
 */

export const GITHUB_LATEST_RELEASE_API: string =
  'https://api.github.com/repos/zhuoyi233/zhihu-plus-plus-HMOS/releases/latest';

const APP_UPDATE_CONNECT_TIMEOUT_MS = 8000;
const APP_UPDATE_READ_TIMEOUT_MS = 10000;

export class AppUpdateClient {
  private readonly requestHandle: http.HttpRequest = http.createHttp();

  async checkLatestRelease(localVersionName: string): Promise<AppUpdateCheckResult> {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'zhihu-plus-plus-hmos'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: APP_UPDATE_CONNECT_TIMEOUT_MS,
      readTimeout: APP_UPDATE_READ_TIMEOUT_MS,
      usingCache: false
    };
    let body = '';
    try {
      const response = await this.requestHandle.request(GITHUB_LATEST_RELEASE_API, options);
      if (Number(response.responseCode) !== 200 || typeof response.result !== 'string') {
        return resolveAppUpdateCheck(localVersionName, undefined,
          `检查更新失败：GitHub 响应码 ${response.responseCode}`);
      }
      body = response.result;
    } catch (error) {
      const detail = error instanceof Error ? error.message : '网络不可用';
      return resolveAppUpdateCheck(localVersionName, undefined, `检查更新失败：${detail}`);
    }
    const release = decodeLatestRelease(body);
    if (release === undefined) {
      return resolveAppUpdateCheck(localVersionName, undefined, '检查更新失败：响应结构无法识别');
    }
    return resolveAppUpdateCheck(localVersionName, release, '');
  }

  destroy(): void {
    this.requestHandle.destroy();
  }
}
