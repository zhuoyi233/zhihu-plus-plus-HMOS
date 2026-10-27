/**
 * 手机号登录的统一号码策略。
 *
 * UI 按钮启用、短信发送、登录三处共用本策略，避免“UI 放行但网络层拒绝”的分裂。
 * 纯逻辑不直接依赖系统 i18n：格式化能力通过 {@link PhoneNumberFormatPort} 注入，
 * 宿主测试注入假实现，真机/模拟器使用 i18n.PhoneNumberFormat 适配器。
 *
 * 结构边界说明：最终发送值必须是 “+” 加数字且总位数不超过 15。这只表示号码结构合法，
 * 不代表该号码已分配或一定能收到短信。
 */

import {
  DEFAULT_PHONE_LOGIN_REGION_ID,
  PhoneLoginRegion,
  regionsSharingLongestPrefix
} from './PhoneLoginRegions';

/** 原始输入允许的最大长度（含分隔符），超出明确提示而不是静默截断。 */
export const PHONE_INPUT_MAX_LENGTH: number = 32;
/** E.164 结构上限：15 位数字（含国家/地区码）。 */
export const MAX_E164_DIGITS: number = 15;
/** 去掉国家/地区码后至少保留的本地号码位数。 */
export const MIN_NATIONAL_DIGITS: number = 4;
/** E.164 号码在地区码之后至少保留的位数（结构下限，不代表号码已分配）。 */
const MIN_E164_TAIL_DIGITS: number = 3;

/** 号码问题分类，供 UI 区分提示语气与后续本地化。 */
export enum PhoneNumberIssue {
  NONE = 'none',
  EMPTY = 'empty',
  TOO_LONG = 'too_long',
  INVALID_CHARACTER = 'invalid_character',
  UNKNOWN_PREFIX = 'unknown_prefix',
  REGION_MISMATCH = 'region_mismatch',
  INVALID_FORMAT = 'invalid_format',
  FORMAT_UNAVAILABLE = 'format_unavailable'
}

/** 号码解析结果。 */
export interface PhoneNumberResolution {
  /** 是否可用于发送短信/登录。 */
  readonly valid: boolean;
  /** 问题分类；valid 为 true 时是 NONE。 */
  readonly issue: PhoneNumberIssue;
  /** 面向用户的错误说明；valid 为 true 或输入为空时为空串。 */
  readonly message: string;
  /** 网络层要发送的 username（“+” 开头）；无效时为空串。 */
  readonly username: string;
  /** username 去掉 “+” 后的数字部分；无效时为空串。 */
  readonly e164Digits: string;
}

/**
 * 号码格式化端口：把某一地区的本地号码写法转成 E.164。
 * 实现方支持该地区时返回形如 “+819012345678” 的字符串；不支持时返回空串或抛错。
 */
export interface PhoneNumberFormatPort {
  toE164(formatRegion: string, nationalNumber: string): string;
}

const SEPARATOR_PATTERN: RegExp = /[\s\-()./\u2010-\u2015]/g;
const FULL_WIDTH_ZERO_CODE: number = 0xFF10;
const FULL_WIDTH_NINE_CODE: number = 0xFF19;
const FULL_WIDTH_PLUS_CODE: number = 0xFF0B;
const FULL_WIDTH_LEFT_PAREN_CODE: number = 0xFF08;
const FULL_WIDTH_RIGHT_PAREN_CODE: number = 0xFF09;
const IDEOGRAPHIC_SPACE_CODE: number = 0x3000;

function invalid(issue: PhoneNumberIssue, message: string): PhoneNumberResolution {
  return { valid: false, issue: issue, message: message, username: '', e164Digits: '' };
}

function validResolution(username: string, e164Digits: string): PhoneNumberResolution {
  return {
    valid: true,
    issue: PhoneNumberIssue.NONE,
    message: '',
    username: username,
    e164Digits: e164Digits
  };
}

/** 统一全角数字、全角加号/括号与全角空格；其余字符原样保留交由后续校验。 */
export function normalizePhoneInputText(raw: string): string {
  let result: string = '';
  for (let index = 0; index < raw.length; index += 1) {
    const code: number = raw.charCodeAt(index);
    if (code >= FULL_WIDTH_ZERO_CODE && code <= FULL_WIDTH_NINE_CODE) {
      result += String.fromCharCode(code - 0xFEE0);
    } else if (code === FULL_WIDTH_PLUS_CODE) {
      result += '+';
    } else if (code === FULL_WIDTH_LEFT_PAREN_CODE) {
      result += '(';
    } else if (code === FULL_WIDTH_RIGHT_PAREN_CODE) {
      result += ')';
    } else if (code === IDEOGRAPHIC_SPACE_CODE) {
      result += ' ';
    } else {
      result += raw.charAt(index);
    }
  }
  return result;
}

function stripSeparators(value: string): string {
  return value.replace(SEPARATOR_PATTERN, '');
}

function normalizeFormattedE164(value: string): string {
  const compact: string = stripSeparators(value.trim());
  if (!compact.startsWith('+') || !/^\+\d+$/.test(compact)) {
    return '';
  }
  return compact;
}

function isAcceptableE164(e164: string, dialPrefix: string): boolean {
  if (!/^\+\d+$/.test(e164)) {
    return false;
  }
  const digits: string = e164.substring(1);
  if (digits.length > MAX_E164_DIGITS) {
    return false;
  }
  if (digits.length < dialPrefix.length + MIN_E164_TAIL_DIGITS) {
    return false;
  }
  return digits.startsWith(dialPrefix);
}

/**
 * 解析用户输入，返回可直接发送的 username。
 *
 * - 以 “+” 开头：按国际格式解析，只接受与当前所选地区匹配的结果（更长的白名单前缀优先），
 *   不匹配时提示切换国家/地区，不默默改区号或重复加前缀。
 * - 不带 “+”：按所选地区的本地号码解释。中国大陆保留原有 “1 开头 11 位” 规则与
 *   13 位 “86” 前缀兼容；其他地区交给格式化端口处理地区特有的国内拨号前缀
 *   （如日本/英国的 0 需要去掉、意大利的 0 需要保留），不做全球统一的去零处理。
 */
export function resolvePhoneNumber(raw: string, region: PhoneLoginRegion,
  port?: PhoneNumberFormatPort): PhoneNumberResolution {
  const prepared: string = normalizePhoneInputText(raw).trim();
  if (prepared.length === 0) {
    return invalid(PhoneNumberIssue.EMPTY, '');
  }
  if (prepared.length > PHONE_INPUT_MAX_LENGTH) {
    return invalid(PhoneNumberIssue.TOO_LONG,
      `手机号输入过长（最多 ${PHONE_INPUT_MAX_LENGTH} 个字符），请检查是否输入了多余内容`);
  }
  const plusIndex: number = prepared.indexOf('+');
  if (plusIndex > 0) {
    return invalid(PhoneNumberIssue.INVALID_CHARACTER, '手机号中的 + 只能出现在开头');
  }
  const compact: string = stripSeparators(prepared);
  const international: boolean = compact.startsWith('+');
  const digits: string = international ? compact.substring(1) : compact;
  if (digits.length === 0 || !/^\d+$/.test(digits)) {
    return invalid(PhoneNumberIssue.INVALID_CHARACTER,
      '手机号只能包含数字、空格、连字符与括号，不支持分机号');
  }
  if (international) {
    return resolveInternational(digits, region);
  }
  return resolveNational(digits, region, port);
}

function resolveInternational(digits: string, region: PhoneLoginRegion): PhoneNumberResolution {
  if (digits.length > MAX_E164_DIGITS) {
    return invalid(PhoneNumberIssue.TOO_LONG, '国际格式手机号最多 15 位数字，请检查号码');
  }
  const candidates: Array<PhoneLoginRegion> = regionsSharingLongestPrefix(digits);
  if (candidates.length === 0) {
    return invalid(PhoneNumberIssue.UNKNOWN_PREFIX, '无法识别的国家/地区代码，请检查号码');
  }
  const matched: PhoneLoginRegion | undefined =
    candidates.find((candidate: PhoneLoginRegion): boolean => candidate.id === region.id);
  if (matched === undefined) {
    const first: PhoneLoginRegion = candidates[0];
    const suffix: string = candidates.length > 1 ? '等地区' : '';
    return invalid(PhoneNumberIssue.REGION_MISMATCH,
      `该号码属于${first.displayName}${suffix}（+${first.dialPrefix}），请先切换国家/地区`);
  }
  const national: string = digits.substring(matched.dialPrefix.length);
  if (national.length < MIN_NATIONAL_DIGITS) {
    return invalid(PhoneNumberIssue.INVALID_FORMAT, '手机号格式不正确');
  }
  return validResolution(`+${digits}`, digits);
}

function resolveNational(digits: string, region: PhoneLoginRegion,
  port?: PhoneNumberFormatPort): PhoneNumberResolution {
  if (region.id === DEFAULT_PHONE_LOGIN_REGION_ID) {
    let local: string = digits;
    if (local.startsWith(region.dialPrefix) && local.length === 13) {
      local = local.substring(region.dialPrefix.length);
    }
    if (!/^1\d{10}$/.test(local)) {
      return invalid(PhoneNumberIssue.INVALID_FORMAT, '手机号格式不正确');
    }
    return validResolution(`+${region.dialPrefix}${local}`, `${region.dialPrefix}${local}`);
  }

  if (digits.length > MAX_E164_DIGITS) {
    return invalid(PhoneNumberIssue.TOO_LONG, '手机号最多 15 位数字，请检查号码');
  }
  if (digits.length < MIN_NATIONAL_DIGITS) {
    return invalid(PhoneNumberIssue.INVALID_FORMAT, '手机号格式不正确');
  }
  // 用户可能连地区码一起输入（如巴哈马 1242 + 7 位本地号）：先剥离一次，
  // 交由格式化端口按该地区规则重新拼接，避免生成重复的国家/地区码。
  const duplicated: boolean = digits.startsWith(region.dialPrefix) &&
    digits.length - region.dialPrefix.length >= MIN_NATIONAL_DIGITS;
  const national: string = duplicated ? digits.substring(region.dialPrefix.length) : digits;

  if (port !== undefined && region.formatRegion.length > 0) {
    let formatted: string = '';
    try {
      formatted = normalizeFormattedE164(port.toE164(region.formatRegion, national));
    } catch (_error) {
      formatted = '';
    }
    if (formatted.length > 0 && isAcceptableE164(formatted, region.dialPrefix)) {
      return validResolution(formatted, formatted.substring(1));
    }
  }

  // 降级：格式化不可用时只接受已经带国家/地区码的完整输入，仍然校验前缀与长度，
  // 不猜测删号，并给出明确的国际格式输入路径。
  if (duplicated) {
    const fallback: string = `+${digits}`;
    if (isAcceptableE164(fallback, region.dialPrefix)) {
      return validResolution(fallback, digits);
    }
  }
  return invalid(PhoneNumberIssue.FORMAT_UNAVAILABLE,
    '该地区的本地号码暂无法自动转换，请改用以 + 开头的完整国际格式输入');
}
