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
