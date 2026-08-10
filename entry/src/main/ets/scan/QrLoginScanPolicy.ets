import { url } from '@kit.ArkTS';

export enum QrScanDecision {
  ZHIHU_DESKTOP_LOGIN = 'zhihu_desktop_login',
  UNSUPPORTED = 'unsupported',
  INVALID = 'invalid'
}

export interface QrScanAssessment {
  decision: QrScanDecision;
  message: string;
}

const MAX_QR_VALUE_LENGTH: number = 4096;

export function assessQrScanValue(input: string): QrScanAssessment {
  const value = input.trim();
  if (value.length === 0 || value.length > MAX_QR_VALUE_LENGTH) {
    return {
      decision: QrScanDecision.INVALID,
      message: value.length === 0 ? '二维码内容为空' : '二维码内容过长，已拒绝处理'
    };
  }

  let parsed: url.URL;
  try {
    parsed = url.URL.parseURL(value);
  } catch (_error) {
    return {
      decision: QrScanDecision.UNSUPPORTED,
      message: '已识别二维码，但不是可处理的知乎登录链接'
    };
  }

  const segments = parsed.pathname.split('/');
  const isZhihuDesktopLogin = parsed.protocol.toLowerCase() === 'https:' &&
    parsed.hostname.toLowerCase() === 'www.zhihu.com' &&
    parsed.port.length === 0 &&
    parsed.username.length === 0 &&
    parsed.password.length === 0 &&
    segments.length === 5 &&
    segments[0].length === 0 &&
    segments[1] === 'account' &&
    segments[2] === 'scan' &&
    segments[3] === 'login' &&
    segments[4].length > 0;

  if (isZhihuDesktopLogin) {
    return {
      decision: QrScanDecision.ZHIHU_DESKTOP_LOGIN,
      message: '知乎电脑端登录二维码格式有效；P0 仅验证识别，不提交确认请求'
    };
  }

  return {
    decision: QrScanDecision.UNSUPPORTED,
    message: '已识别二维码，但不是知乎电脑端登录二维码'
  };
}
