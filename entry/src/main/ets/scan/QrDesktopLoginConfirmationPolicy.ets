import { assessQrScanValue, parseAbsoluteUrl, QrScanDecision } from 'core';

/**
 * 二维码入口须沿用 core 的严格识别策略，不能以 ArkWeb 的导航地址替代扫码结果。
 * 不接受扫描器附带的首尾空白，避免“已验证的规范化值”和实际加载地址不一致。
 */
export function isConfirmedQrDesktopLoginUrl(url: string): boolean {
  return url === url.trim() &&
    assessQrScanValue(url).decision === QrScanDecision.ZHIHU_DESKTOP_LOGIN;
}

/**
 * 确认页允许初始精确二维码链接，以及确认过程中知乎主站内的 HTTPS 主框架跳转。
 * 资源子请求不属于页面导航，交由 ArkWeb 正常处理；任何外部 scheme、非主站或带
 * 用户信息/端口的主框架导航都会被拦截。
 */
export function shouldBlockQrDesktopLoginNavigation(url: string, isMainFrame: boolean,
  confirmedEntryUrl: string | undefined): boolean {
  if (!isMainFrame) {
    return false;
  }
  if (confirmedEntryUrl === undefined || !isConfirmedQrDesktopLoginUrl(confirmedEntryUrl)) {
    return true;
  }
  if (url === confirmedEntryUrl) {
    return false;
  }
  if (url !== url.trim()) {
    return true;
  }
  const parsed = parseAbsoluteUrl(url);
  return parsed === undefined || parsed.protocol.toLowerCase() !== 'https:' ||
    parsed.hostname.toLowerCase() !== 'www.zhihu.com' || parsed.port.length > 0 || parsed.hasUserInfo;
}
