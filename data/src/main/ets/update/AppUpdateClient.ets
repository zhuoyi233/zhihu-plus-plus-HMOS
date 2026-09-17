import { http } from '@kit.NetworkKit';
import { AppUpdateCheckResult, AppUpdateRelease } from './AppUpdateModels';
import { decodeLatestRelease, decodeLatestReleaseAtom, resolveAppUpdateCheck } from './AppUpdateParser';

/**
 * GitHub Release 更新检测客户端。
 *
 * 刻意不经过 ZhihuHttpClient：更新检测直连 api.github.com，
 * 不携带任何知乎 Cookie、UA 伪装或 ZSE 签名头，避免把知乎会话侧信息发给第三方。
 */

export const GITHUB_LATEST_RELEASE_API: string =
  'https://api.github.com/repos/zhuoyi233/zhihu-plus-plus-HMOS/releases/latest';
export const GITHUB_RELEASES_ATOM: string =
  'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases.atom';

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
    let primaryFailure = '';
    try {
      const response = await this.requestHandle.request(GITHUB_LATEST_RELEASE_API, options);
      if (Number(response.responseCode) === 200 && typeof response.result === 'string') {
        const release = decodeLatestRelease(response.result);
        if (release !== undefined) {
          return resolveAppUpdateCheck(localVersionName, release, '');
        }
        primaryFailure = 'GitHub API 响应结构无法识别';
      } else if (Number(response.responseCode) === 403 || Number(response.responseCode) === 429) {
        primaryFailure = `GitHub API 匿名请求已限流（${response.responseCode}）`;
      } else {
        primaryFailure = `GitHub API 响应码 ${response.responseCode}`;
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : '网络不可用';
      primaryFailure = detail;
    }

    const fallback = await this.requestAtomFallback();
    if (fallback !== undefined) {
      return resolveAppUpdateCheck(localVersionName, fallback, '');
    }
    return resolveAppUpdateCheck(localVersionName, undefined,
      `检查更新失败：${primaryFailure}；Releases 备用源也不可用`);
  }

  private async requestAtomFallback(): Promise<AppUpdateRelease | undefined> {
    try {
      const response = await this.requestHandle.request(GITHUB_RELEASES_ATOM, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/atom+xml',
          'User-Agent': 'zhihu-plus-plus-hmos'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: APP_UPDATE_CONNECT_TIMEOUT_MS,
        readTimeout: APP_UPDATE_READ_TIMEOUT_MS,
        usingCache: false
      });
      if (Number(response.responseCode) !== 200 || typeof response.result !== 'string') {
        return undefined;
      }
      return decodeLatestReleaseAtom(response.result);
    } catch (_error) {
      return undefined;
    }
  }

  destroy(): void {
    this.requestHandle.destroy();
  }
}
