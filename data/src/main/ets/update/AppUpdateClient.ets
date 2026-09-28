import { http } from '@kit.NetworkKit';
import { AppReleaseDetailResult, AppReleaseDetailStatus, AppUpdateCheckResult, AppUpdateRelease } from './AppUpdateModels';
import { decodeLatestRelease, decodeLatestReleaseAtom, decodeReleaseDetail, resolveAppUpdateCheck } from './AppUpdateParser';

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
export const GITHUB_RELEASE_BY_TAG_API: string =
  'https://gh-proxy.org/https://api.github.com/repos/zhuoyi233/zhihu-plus-plus-HMOS/releases/tags/';

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

  /**
   * 按版本名拉取对应 Release 的完整详情（含 Markdown 描述），供“新版本更新”页使用。
   * 经 gh-proxy.org 转发 GitHub JSON API，不携带任何知乎会话侧信息；
   * 描述原文只有 JSON API 提供（Atom 备源是 HTML），故此处不设备用源。
   */
  async fetchReleaseDetail(versionName: string): Promise<AppReleaseDetailResult> {
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
    try {
      const response = await this.requestHandle.request(`${GITHUB_RELEASE_BY_TAG_API}HMOSv${versionName}`, options);
      const responseCode = Number(response.responseCode);
      if (responseCode === 200 && typeof response.result === 'string') {
        const detail = decodeReleaseDetail(response.result);
        if (detail !== undefined) {
          const result: AppReleaseDetailResult = { status: AppReleaseDetailStatus.OK, detail: detail, message: '' };
          return result;
        }
        return failedReleaseDetailResult('GitHub Release 响应结构无法识别');
      }
      if (responseCode === 404) {
        const notFound: AppReleaseDetailResult = {
          status: AppReleaseDetailStatus.NOT_FOUND,
          detail: undefined,
          message: `GitHub 上没有 HMOSv${versionName} 对应的 Release`
        };
        return notFound;
      }
      if (responseCode === 403 || responseCode === 429) {
        return failedReleaseDetailResult(`GitHub API 匿名请求已限流（${responseCode}），请稍后重试`);
      }
      return failedReleaseDetailResult(`GitHub API 响应码 ${responseCode}`);
    } catch (error) {
      const detailMessage = error instanceof Error ? error.message : '网络不可用';
      return failedReleaseDetailResult(`获取发布说明失败：${detailMessage}`);
    }
  }

  destroy(): void {
    this.requestHandle.destroy();
  }
}

function failedReleaseDetailResult(message: string): AppReleaseDetailResult {
  const result: AppReleaseDetailResult = {
    status: AppReleaseDetailStatus.FAILED,
    detail: undefined,
    message: message
  };
  return result;
}
