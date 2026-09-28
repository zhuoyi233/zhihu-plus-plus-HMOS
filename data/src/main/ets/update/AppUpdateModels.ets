/**
 * 应用更新检测的领域模型：结果状态与 GitHub Release 摘要。
 */

export enum AppUpdateCheckStatus {
  UP_TO_DATE = 'up_to_date',
  UPDATE_AVAILABLE = 'update_available',
  FAILED = 'failed'
}

export interface AppUpdateRelease {
  /** GitHub tag 名（如 HMOSv0.2.1）。 */
  tagName: string;
  /** 从 tag 解析出的版本名（如 0.2.1）。 */
  versionName: string;
  /** Release 标题，缺失时回退为 tag 名。 */
  releaseTitle: string;
  /** Release 页面地址，用于跳转下载。 */
  htmlUrl: string;
  /** 发布时间（ISO 8601），缺失时为空串。 */
  publishedAt: string;
}

export interface AppUpdateCheckResult {
  status: AppUpdateCheckStatus;
  /** UPDATE_AVAILABLE / UP_TO_DATE 时携带解析出的 Release，FAILED 时为 undefined。 */
  release: AppUpdateRelease | undefined;
  /** 失败或异常时的用户可读说明，成功时为空串。 */
  message: string;
}

/** 按 tag 拉取的 Release 详情（含 Markdown 描述原文），用于“新版本更新”页。 */
export interface AppReleaseDetail {
  /** GitHub tag 名（如 HMOSv0.5.0）。 */
  tagName: string;
  /** 从 tag 解析出的版本名（如 0.5.0）。 */
  versionName: string;
  /** Release 标题，缺失时回退为 tag 名。 */
  releaseTitle: string;
  /** Release 页面地址，用于跳转查看完整发布说明。 */
  htmlUrl: string;
  /** 发布时间（ISO 8601），缺失时为空串。 */
  publishedAt: string;
  /** Release 描述原文（Markdown），缺失时为空串。 */
  body: string;
}

export enum AppReleaseDetailStatus {
  OK = 'ok',
  /** 该版本没有对应的 GitHub Release（如本地开发构建）。 */
  NOT_FOUND = 'not_found',
  FAILED = 'failed'
}

export interface AppReleaseDetailResult {
  status: AppReleaseDetailStatus;
  /** OK 时携带 Release 详情，NOT_FOUND / FAILED 时为 undefined。 */
  detail: AppReleaseDetail | undefined;
  /** 失败或异常时的用户可读说明，成功时为空串。 */
  message: string;
}
