import { parseAbsoluteUrl, ParsedAbsoluteUrl } from 'core';

/**
 * 知乎图床主机白名单（正文图片、头像、卡片封面共用）。
 *
 * 只接受采样确认过的 `pic*.zhimg.com` / `pica.zhimg.com` / `picx.zhimg.com` 子域：
 * 通配 `*.zhimg.com` 会把 `video.zhimg.com`、上传 OSS 等其他语义主机一并放行，
 * 不能作为「图片资源可信」的判断依据。新增主机必须先有样本与回归用例。
 */
const TRUSTED_IMAGE_HOST_PATTERN: RegExp = /^(?:pic|picx|pic[0-9]{1,2}|pica)\.zhimg\.com$/;

/** 与深链输入上限对齐：超长 URL 直接判为不可信。 */
const MAX_IMAGE_URL_LENGTH: number = 8192;

/**
 * 图片展示/预览/保存的统一判定：HTTPS、无用户信息、无自定义端口、主机在上述白名单内。
 * 展示与保存必须使用同一函数，避免出现「能看不能存」或相反的不一致。
 */
export function isTrustedReaderImageUrl(value: string): boolean {
  if (value.length === 0 || value.length > MAX_IMAGE_URL_LENGTH) {
    return false;
  }
  const parsed: ParsedAbsoluteUrl | undefined = parseAbsoluteUrl(value);
  if (parsed === undefined) {
    return false;
  }
  return parsed.protocol === 'https:' && parsed.port.length === 0 && !parsed.hasUserInfo &&
    TRUSTED_IMAGE_HOST_PATTERN.test(parsed.hostname);
}

/**
 * 图片展示源筛选：可信则返回归一化后的 HTTPS 地址，否则返回空串，由调用方回退占位/说明文本。
 *
 * 协议相对地址（`//host/path`）只在校验前补 `https:`，不把任意 HTTP 目标静默升级：
 * 补全后仍需通过白名单、端口与用户信息校验。
 */
export function trustedReaderImageUrl(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const absolute = trimmed.startsWith('//') ? `https:${trimmed}` : trimmed;
  return isTrustedReaderImageUrl(absolute) ? absolute : '';
}
