import { AppUpdateCheckResult, AppUpdateCheckStatus, AppUpdateRelease } from './AppUpdateModels';

/**
 * 更新检测的纯函数解析：tag 版本名提取、语义化版本比较与 GitHub Release JSON 解码。
 * 全部无副作用，便于 Hypium 单元测试覆盖。
 */

export function parseHmosTagVersion(tag: string): string | undefined {
  const trimmed = tag.trim();
  let candidate = trimmed;
  if (candidate.startsWith('HMOSv')) {
    candidate = candidate.substring('HMOSv'.length);
  } else if (candidate.startsWith('v')) {
    candidate = candidate.substring(1);
  }
  return isVersionName(candidate) ? candidate : undefined;
}

export function isVersionName(value: string): boolean {
  if (value.length === 0) {
    return false;
  }
  const segments = value.split('.');
  for (const segment of segments) {
    if (!/^\d+$/.test(segment)) {
      return false;
    }
  }
  return true;
}

/** 按数字段比较版本名；left 较新返回 1，相同返回 0，right 较新返回 -1。缺失段按 0 处理。 */
export function compareVersionNames(left: string, right: string): number {
  const leftSegments = left.split('.');
  const rightSegments = right.split('.');
  const total = Math.max(leftSegments.length, rightSegments.length);
  for (let index = 0; index < total; index += 1) {
    const leftValue = index < leftSegments.length ? Number(leftSegments[index]) : 0;
    const rightValue = index < rightSegments.length ? Number(rightSegments[index]) : 0;
    if (leftValue > rightValue) {
      return 1;
    }
    if (leftValue < rightValue) {
      return -1;
    }
  }
  return 0;
}

/** 解析 GitHub /releases/latest 响应体；结构不符合预期时返回 undefined。 */
export function decodeLatestRelease(payload: string): AppUpdateRelease | undefined {
  let parsed: Object | undefined = undefined;
  try {
    parsed = JSON.parse(payload) as Object;
  } catch (_error) {
    return undefined;
  }
  const record = parsed as Record<string, Object>;
  const tagNameValue = record['tag_name'];
  if (typeof tagNameValue !== 'string') {
    return undefined;
  }
  const versionName = parseHmosTagVersion(tagNameValue);
  if (versionName === undefined) {
    return undefined;
  }
  const htmlUrlValue = record['html_url'];
  const releaseTitleValue = record['name'];
  const publishedAtValue = record['published_at'];
  const release: AppUpdateRelease = {
    tagName: tagNameValue,
    versionName: versionName,
    releaseTitle: typeof releaseTitleValue === 'string' && releaseTitleValue.length > 0
      ? releaseTitleValue
      : tagNameValue,
    htmlUrl: typeof htmlUrlValue === 'string' ? htmlUrlValue : '',
    publishedAt: typeof publishedAtValue === 'string' ? publishedAtValue : ''
  };
  return release;
}

/** 结合本机版本得出检测结论：本机不比远端新时视为已是最新。 */
export function resolveAppUpdateCheck(localVersionName: string, release: AppUpdateRelease | undefined,
  message: string): AppUpdateCheckResult {
  if (release === undefined) {
    const result: AppUpdateCheckResult = {
      status: AppUpdateCheckStatus.FAILED,
      release: undefined,
      message: message
    };
    return result;
  }
  const upToDate = compareVersionNames(release.versionName, localVersionName) <= 0;
  const result: AppUpdateCheckResult = {
    status: upToDate ? AppUpdateCheckStatus.UP_TO_DATE : AppUpdateCheckStatus.UPDATE_AVAILABLE,
    release: release,
    message: ''
  };
  return result;
}
