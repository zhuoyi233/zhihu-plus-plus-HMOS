import { http } from '@kit.NetworkKit';
import { AppReleaseDetailResult, AppReleaseDetailStatus, AppUpdateCheckResult, AppUpdateRelease } from './AppUpdateModels';
import { decodeLatestRelease, decodeLatestReleaseAtom, decodeReleaseDetail, resolveAppUpdateCheck } from './AppUpdateParser';

/**
 * 更新元数据优先读取仓库静态 JSON，避开 GitHub 匿名 Release API 的请求配额。
 * 不经过 ZhihuHttpClient，也不携带知乎会话信息。
 */

export const GITHUB_RELEASES_ATOM: string =
  'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases.atom';

const APP_UPDATE_CONNECT_TIMEOUT_MS = 8000;
const APP_UPDATE_READ_TIMEOUT_MS = 10000;
const CATALOG_TTL_MS = 10 * 60 * 1000;
const REPOSITORY = 'zhuoyi233/zhihu-plus-plus-HMOS';

function catalogUrls(fileName: string): string[] {
  const path = `assets/update/${fileName}`;
  const cacheBucket = Math.floor(Date.now() / CATALOG_TTL_MS);
  return [
    `https://raw.githubusercontent.com/${REPOSITORY}/main/${path}?v=${cacheBucket}`,
    `https://cdn.jsdelivr.net/gh/${REPOSITORY}@main/${path}?v=${cacheBucket}`,
    `https://fastly.jsdelivr.net/gh/${REPOSITORY}@main/${path}?v=${cacheBucket}`
  ];
}

export class AppUpdateClient {
  private static latestJson: string = '';
  private static latestFetchedAt: number = 0;
  private static releasesJson: string = '';
  private static releasesFetchedAt: number = 0;
  private static bundledLatestJson: string = '';
  private static bundledReleasesJson: string = '';
  private readonly requestHandle: http.HttpRequest = http.createHttp();

  static seedBundledCatalog(latestJson: string, releasesJson: string): void {
    if (decodeLatestRelease(latestJson) !== undefined) {
      AppUpdateClient.bundledLatestJson = latestJson;
    }
    try {
      if (Array.isArray(JSON.parse(releasesJson))) {
        AppUpdateClient.bundledReleasesJson = releasesJson;
      }
    } catch (_error) {
      // 无效内置清单不覆盖网络数据。
    }
  }

  async checkLatestRelease(localVersionName: string, forceRefresh: boolean = false): Promise<AppUpdateCheckResult> {
    try {
      const json = await this.latestCatalog(forceRefresh);
      const release = decodeLatestRelease(json);
      if (release !== undefined) {
        this.enrichSha256FromBundled(release);
        return resolveAppUpdateCheck(localVersionName, release, '');
      }
    } catch (_error) {
      // 静态清单尚未随 main 部署或镜像不可用时，回退到不计 REST API 配额的 Atom。
    }
    const fallback = await this.requestAtomFallback();
    if (fallback !== undefined) {
      const bundled = decodeLatestRelease(AppUpdateClient.bundledLatestJson);
      if (bundled !== undefined && bundled.versionName === fallback.versionName) {
        return resolveAppUpdateCheck(localVersionName, bundled, '');
      }
      return resolveAppUpdateCheck(localVersionName, fallback, '');
    }
    const bundled = decodeLatestRelease(AppUpdateClient.bundledLatestJson);
    if (bundled !== undefined && bundled.versionName === localVersionName) {
      return resolveAppUpdateCheck(localVersionName, bundled, '');
    }
    return resolveAppUpdateCheck(localVersionName, undefined,
      '检查更新失败：静态更新源与 Releases 备用源均不可用');
  }

  /** 远端清单可能落后于最新发布而缺 sha256；版本一致时用随包内置清单补齐，供下载后校验。 */
  private enrichSha256FromBundled(release: AppUpdateRelease): void {
    if (release.assetSha256 !== undefined && release.assetSha256.length > 0) {
      return;
    }
    const bundled = decodeLatestRelease(AppUpdateClient.bundledLatestJson);
    if (bundled !== undefined && bundled.versionName === release.versionName &&
      bundled.assetSha256 !== undefined) {
      release.assetSha256 = bundled.assetSha256;
    }
  }

  private async requestStatic(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json', 'User-Agent': 'zhihu-plus-plus-hmos' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: APP_UPDATE_CONNECT_TIMEOUT_MS,
        readTimeout: APP_UPDATE_READ_TIMEOUT_MS,
        usingCache: true
      });
      if (Number(response.responseCode) !== 200 || typeof response.result !== 'string') {
        throw new Error(`静态源响应码 ${response.responseCode}`);
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }

  /** 三个静态分发入口并行，首个结构有效的响应获胜。 */
  private fetchStatic(fileName: string, valid: (json: string) => boolean): Promise<string> {
    const urls = catalogUrls(fileName);
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void): void => {
      let failures = 0;
      for (const url of urls) {
        void this.requestStatic(url).then((json: string): void => {
          if (valid(json)) {
            resolve(json);
          } else {
            failures += 1;
            if (failures === urls.length) {
              reject(new Error('静态更新数据格式错误'));
            }
          }
        }).catch((_error: Error): void => {
          failures += 1;
          if (failures === urls.length) {
            reject(new Error('静态更新源不可用'));
          }
        });
      }
    });
  }

  private async latestCatalog(forceRefresh: boolean): Promise<string> {
    if (!forceRefresh && AppUpdateClient.latestJson.length > 0 &&
      Date.now() - AppUpdateClient.latestFetchedAt < CATALOG_TTL_MS) {
      return AppUpdateClient.latestJson;
    }
    const json = await this.fetchStatic('version.json', (payload: string): boolean =>
      decodeLatestRelease(payload) !== undefined);
    AppUpdateClient.latestJson = json;
    AppUpdateClient.latestFetchedAt = Date.now();
    return json;
  }

  private async releasesCatalog(): Promise<string> {
    if (AppUpdateClient.releasesJson.length > 0 &&
      Date.now() - AppUpdateClient.releasesFetchedAt < CATALOG_TTL_MS) {
      return AppUpdateClient.releasesJson;
    }
    const json = await this.fetchStatic('releases.json', (payload: string): boolean => {
      try {
        return Array.isArray(JSON.parse(payload));
      } catch (_error) {
        return false;
      }
    });
    AppUpdateClient.releasesJson = json;
    AppUpdateClient.releasesFetchedAt = Date.now();
    return json;
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
   * 仅从静态历史清单或随包数据读取；不请求受匿名配额限制的 Release API。
   */
  async fetchReleaseDetail(versionName: string): Promise<AppReleaseDetailResult> {
    try {
      const catalog = JSON.parse(await this.releasesCatalog()) as Object[];
      for (const item of catalog) {
        const detail = decodeReleaseDetail(JSON.stringify(item));
        if (detail !== undefined && detail.versionName === versionName) {
          return { status: AppReleaseDetailStatus.OK, detail: detail, message: '' };
        }
      }
    } catch (_error) {
      // 静态文件尚未部署时使用旧兼容路径。
    }
    if (AppUpdateClient.bundledReleasesJson.length > 0) {
      const bundled = JSON.parse(AppUpdateClient.bundledReleasesJson) as Object[];
      for (const item of bundled) {
        const detail = decodeReleaseDetail(JSON.stringify(item));
        if (detail !== undefined && detail.versionName === versionName) {
          return { status: AppReleaseDetailStatus.OK, detail: detail, message: '' };
        }
      }
    }
    return failedReleaseDetailResult(`静态更新清单中暂无 HMOSv${versionName} 的发布说明`);
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
