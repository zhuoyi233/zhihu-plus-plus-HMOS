/**
 * P4-7 系统分享的纯 ArkTS 合同。
 *
 * 页面只描述需要分享的知乎内容或应用临时文件；平台适配层负责把已验证的数据转换为 Want。
 * 不允许调用方传入 Cookie、请求头、HTML 或任意 file URI。
 */

export const MAX_SHARE_TITLE_LENGTH: number = 120;
export const MAX_SHARE_SUMMARY_LENGTH: number = 1000;
export const MAX_SHARE_URL_LENGTH: number = 2048;
export const SHARE_TEMPORARY_DIRECTORY: string = 'p4-share';
export const SHARE_PANEL_GRACE_MILLIS: number = 30 * 60 * 1000;
export const SHARE_TEMPORARY_MAX_AGE_MILLIS: number = 24 * 60 * 60 * 1000;

export enum SharePayloadKind {
  TEXT = 'text',
  IMAGE = 'image',
  FILE = 'file'
}

export enum ShareImageSourceKind {
  TRUSTED_URL = 'trusted_url',
  TEMPORARY_FILE = 'temporary_file'
}

export enum ShareDispatchKind {
  TEXT_LINK = 'text_link',
  REMOTE_IMAGE_LINK = 'remote_image_link',
  TEMPORARY_FILE = 'temporary_file'
}

export enum ShareFailureKind {
  INVALID_PAYLOAD = 'invalid_payload',
  NO_HANDLER = 'no_handler',
  FILE_UNAVAILABLE = 'file_unavailable',
  PERMISSION_DENIED = 'permission_denied',
  CANCELLED = 'cancelled',
  TEMPORARY_FAILURE = 'temporary_failure'
}

export enum ShareOutcome {
  OPENED = 'opened',
  CANCELLED = 'cancelled'
}

export interface ShareTextPayload {
  readonly kind: SharePayloadKind.TEXT;
  readonly title: string;
  readonly summary: string;
  readonly contentUrl: string;
}

export interface ShareTemporaryFile {
  /** 应用沙箱 cache 下 p4-share 目录中的绝对路径，而不是 URI。 */
  readonly path: string;
  readonly mimeType: string;
  readonly createdAtMillis: number;
}

export interface ShareImagePayload {
  readonly kind: SharePayloadKind.IMAGE;
  readonly title: string;
  readonly summary: string;
  readonly sourceKind: ShareImageSourceKind;
  readonly trustedImageUrl?: string;
  readonly temporaryFile?: ShareTemporaryFile;
}

export interface ShareFilePayload {
  readonly kind: SharePayloadKind.FILE;
  readonly title: string;
  readonly summary: string;
  readonly temporaryFile: ShareTemporaryFile;
}

export type SharePayload = ShareTextPayload | ShareImagePayload | ShareFilePayload;

export interface ShareRuntimePolicy {
  /** UIAbilityContext.cacheDir；调用方不得把用户输入拼接到该目录。 */
  readonly cacheDir: string;
  readonly nowMillis: number;
}

export interface PreparedSharePayload {
  readonly kind: SharePayloadKind;
  readonly dispatchKind: ShareDispatchKind;
  readonly title: string;
  readonly summary: string;
  readonly mimeType: string;
  /** 只会是受信知乎 HTTPS URL 或已经通过专用 cache 目录检查的临时文件路径。 */
  readonly source: string;
}

export interface TemporaryShareLifecycle {
  readonly path: string;
  readonly createdAtMillis: number;
  readonly panelOpenedAtMillis?: number;
  readonly cleanupAfterMillis: number;
}

export interface ShareService {
  share(payload: SharePayload): Promise<ShareOutcome>;
}

export class ShareFailure extends Error {
  readonly kind: ShareFailureKind;

  constructor(kind: ShareFailureKind) {
    super(shareFailureMessage(kind));
    this.name = 'ShareFailure';
    this.kind = kind;
  }
}

export function prepareSharePayload(payload: SharePayload, policy: ShareRuntimePolicy): PreparedSharePayload {
  const title = normalizeTitle(payload.title);
  const summary = normalizeSummary(payload.summary);
  if (payload.kind === SharePayloadKind.TEXT) {
    const contentUrl = normalizeTrustedContentUrl(payload.contentUrl);
    return {
      kind: SharePayloadKind.TEXT,
      dispatchKind: ShareDispatchKind.TEXT_LINK,
      title: title,
      summary: summary,
      mimeType: 'text/plain',
      source: contentUrl
    };
  }
  if (payload.kind === SharePayloadKind.IMAGE) {
    return prepareImagePayload(payload, policy, title, summary);
  }
  return prepareFilePayload(payload, policy, title, summary);
}

export function createTemporaryShareLifecycle(file: ShareTemporaryFile): TemporaryShareLifecycle {
  if (!isFiniteTimestamp(file.createdAtMillis)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return {
    path: file.path,
    createdAtMillis: file.createdAtMillis,
    cleanupAfterMillis: file.createdAtMillis + SHARE_TEMPORARY_MAX_AGE_MILLIS
  };
}

export function markSharePanelOpened(
  lifecycle: TemporaryShareLifecycle,
  openedAtMillis: number
): TemporaryShareLifecycle {
  if (!isFiniteTimestamp(openedAtMillis) || openedAtMillis < lifecycle.createdAtMillis) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  const graceExpiry = openedAtMillis + SHARE_PANEL_GRACE_MILLIS;
  const hardExpiry = lifecycle.createdAtMillis + SHARE_TEMPORARY_MAX_AGE_MILLIS;
  return {
    path: lifecycle.path,
    createdAtMillis: lifecycle.createdAtMillis,
    panelOpenedAtMillis: openedAtMillis,
    cleanupAfterMillis: Math.min(graceExpiry, hardExpiry)
  };
}

export function shouldCleanupTemporaryShareFile(lifecycle: TemporaryShareLifecycle, nowMillis: number): boolean {
  return isFiniteTimestamp(nowMillis) && nowMillis >= lifecycle.cleanupAfterMillis;
}

export function toShareFailure(error: Error): ShareFailure {
  if (error instanceof ShareFailure) {
    return error;
  }
  const normalized = error.message.toLowerCase();
  if (normalized.includes('cancel')) {
    return new ShareFailure(ShareFailureKind.CANCELLED);
  }
  if (normalized.includes('permission') || normalized.includes('denied')) {
    return new ShareFailure(ShareFailureKind.PERMISSION_DENIED);
  }
  if (normalized.includes('not found') || normalized.includes('no handler') || normalized.includes('ability')) {
    return new ShareFailure(ShareFailureKind.NO_HANDLER);
  }
  if (normalized.includes('file') || normalized.includes('uri')) {
    return new ShareFailure(ShareFailureKind.FILE_UNAVAILABLE);
  }
  return new ShareFailure(ShareFailureKind.TEMPORARY_FAILURE);
}

function prepareImagePayload(
  payload: ShareImagePayload,
  policy: ShareRuntimePolicy,
  title: string,
  summary: string
): PreparedSharePayload {
  if (payload.sourceKind === ShareImageSourceKind.TRUSTED_URL) {
    if (payload.temporaryFile !== undefined || payload.trustedImageUrl === undefined) {
      throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
    }
    return {
      kind: SharePayloadKind.IMAGE,
      dispatchKind: ShareDispatchKind.REMOTE_IMAGE_LINK,
      title: title,
      summary: summary,
      mimeType: 'text/plain',
      source: normalizeTrustedImageUrl(payload.trustedImageUrl)
    };
  }
  if (payload.trustedImageUrl !== undefined || payload.temporaryFile === undefined) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  const file = normalizeTemporaryShareFile(payload.temporaryFile, policy, true);
  return {
    kind: SharePayloadKind.IMAGE,
    dispatchKind: ShareDispatchKind.TEMPORARY_FILE,
    title: title,
    summary: summary,
    mimeType: file.mimeType,
    source: file.path
  };
}

function prepareFilePayload(
  payload: ShareFilePayload,
  policy: ShareRuntimePolicy,
  title: string,
  summary: string
): PreparedSharePayload {
  const file = normalizeTemporaryShareFile(payload.temporaryFile, policy, false);
  return {
    kind: SharePayloadKind.FILE,
    dispatchKind: ShareDispatchKind.TEMPORARY_FILE,
    title: title,
    summary: summary,
    mimeType: file.mimeType,
    source: file.path
  };
}

function normalizeTemporaryShareFile(
  file: ShareTemporaryFile,
  policy: ShareRuntimePolicy,
  requireImageMime: boolean
): ShareTemporaryFile {
  if (!isFiniteTimestamp(file.createdAtMillis) || file.createdAtMillis > policy.nowMillis ||
    policy.nowMillis - file.createdAtMillis > SHARE_TEMPORARY_MAX_AGE_MILLIS) {
    throw new ShareFailure(ShareFailureKind.FILE_UNAVAILABLE);
  }
  const expectedDirectory = normalizeCacheDir(policy.cacheDir) + '/' + SHARE_TEMPORARY_DIRECTORY + '/';
  if (!file.path.startsWith(expectedDirectory) || !isSafeShareFileName(file.path.substring(expectedDirectory.length))) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  if (requireImageMime ? !isAllowedImageMime(file.mimeType) : !isAllowedFileMime(file.mimeType)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return file;
}

function normalizeTitle(value: string): string {
  const normalized = value.trim();
  if (!isSafeText(normalized, MAX_SHARE_TITLE_LENGTH)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return normalized;
}

function normalizeSummary(value: string): string {
  const normalized = value.trim();
  if (!isSafeText(normalized, MAX_SHARE_SUMMARY_LENGTH)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return normalized;
}

function normalizeTrustedContentUrl(value: string): string {
  if (!isSafeHttpsUrl(value, /^(?:www\.zhihu\.com|zhuanlan\.zhihu\.com)$/)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  const contentMatch = /^https:\/\/(?:www\.zhihu\.com\/(?:question\/[1-9][0-9]{0,29}(?:\/answer\/[1-9][0-9]{0,29})?|answer\/[1-9][0-9]{0,29}|pin\/[1-9][0-9]{0,29}|people\/[A-Za-z0-9-]{1,100}|zvideo\/[1-9][0-9]{0,29})|zhuanlan\.zhihu\.com\/p\/[1-9][0-9]{0,29})(?:[?#][A-Za-z0-9%&=._~!$'()*+,;:@/?-]*)?$/;
  if (!contentMatch.test(value)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return value;
}

function normalizeTrustedImageUrl(value: string): string {
  if (!isSafeHttpsUrl(value, /^(?:pic|pica|picx|pic[0-9]+)\.zhimg\.com$/) ||
    !/^https:\/\/(?:pic|pica|picx|pic[0-9]+)\.zhimg\.com\/[A-Za-z0-9%&=._~!$'()*+,;:@/?-]+$/.test(value)) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return value;
}

function isSafeHttpsUrl(value: string, hostPattern: RegExp): boolean {
  if (value.length === 0 || value.length > MAX_SHARE_URL_LENGTH || /[\r\n\t ]/.test(value) ||
    value.includes('@') || value.includes('\\')) {
    return false;
  }
  const match = /^https:\/\/([^/?#:]+)(?::[0-9]+)?\//.exec(value);
  return match !== null && match[1] !== undefined && hostPattern.test(match[1]) && !value.includes('..');
}

function isSafeText(value: string, maximumLength: number): boolean {
  if (value.length === 0 || value.length > maximumLength || /[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(value)) {
    return false;
  }
  return !/<\/?[A-Za-z][^>]*>/.test(value) &&
    !/(?:cookie|set-cookie|authorization)\s*:/i.test(value) &&
    !/(?:cookie|authorization)=/i.test(value);
}

function normalizeCacheDir(value: string): string {
  const normalized = value.replace(/\\/g, '/').replace(/\/+$/g, '');
  if (!/^\/[A-Za-z0-9._/-]+$/.test(normalized) || normalized.includes('..')) {
    throw new ShareFailure(ShareFailureKind.INVALID_PAYLOAD);
  }
  return normalized;
}

function isSafeShareFileName(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value) && !value.includes('..');
}

function isAllowedImageMime(value: string): boolean {
  return value === 'image/jpeg' || value === 'image/png' || value === 'image/webp' || value === 'image/gif';
}

function isAllowedFileMime(value: string): boolean {
  return isAllowedImageMime(value) || value === 'text/plain' || value === 'application/pdf';
}

function isFiniteTimestamp(value: number): boolean {
  return Number.isFinite(value) && value >= 0 && Math.floor(value) === value;
}

function shareFailureMessage(kind: ShareFailureKind): string {
  if (kind === ShareFailureKind.NO_HANDLER) {
    return '没有可用的分享应用';
  }
  if (kind === ShareFailureKind.FILE_UNAVAILABLE) {
    return '分享文件已不可用';
  }
  if (kind === ShareFailureKind.PERMISSION_DENIED) {
    return '分享权限不足';
  }
  if (kind === ShareFailureKind.CANCELLED) {
    return '已取消分享';
  }
  if (kind === ShareFailureKind.INVALID_PAYLOAD) {
    return '分享内容不受支持';
  }
  return '暂时无法打开分享面板';
}
