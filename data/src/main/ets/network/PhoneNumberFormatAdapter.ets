/**
 * i18n.PhoneNumberFormat 适配器：把本地号码写法转成 E.164。
 *
 * 只在真机/模拟器运行时真正调用系统能力；宿主测试通过注入假实现覆盖策略分支，
 * 避免系统空桩让用例假通过（API 23 模拟器需人工核对真实格式化结果）。
 */

import { i18n } from '@kit.LocalizationKit';
import { PhoneNumberFormatPort } from './PhoneLoginNumberPolicy';

export class I18nPhoneNumberFormatPort implements PhoneNumberFormatPort {
  toE164(formatRegion: string, nationalNumber: string): string {
    if (formatRegion.length === 0 || nationalNumber.length === 0) {
      return '';
    }
    const options: i18n.PhoneNumberFormatOptions = { type: 'E164' };
    const formatter: i18n.PhoneNumberFormat = new i18n.PhoneNumberFormat(formatRegion, options);
    return formatter.format(nationalNumber);
  }
}

const SHARED_PORT: PhoneNumberFormatPort = new I18nPhoneNumberFormatPort();

/** 共享的格式化端口（构造本身不触碰系统 i18n，仅 format 调用时才构造格式化器）。 */
export function defaultPhoneNumberFormatPort(): PhoneNumberFormatPort {
  return SHARED_PORT;
}
