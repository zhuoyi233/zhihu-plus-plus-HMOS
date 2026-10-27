import { describe, expect, it } from '@ohos/hypium';
import {
  defaultPhoneNumberFormatPort,
  findPhoneLoginRegion,
  MAX_E164_DIGITS,
  normalizePhoneInputText,
  PHONE_INPUT_MAX_LENGTH,
  PhoneLoginRegion,
  PhoneNumberFormatPort,
  PhoneNumberIssue,
  PhoneNumberResolution,
  resolvePhoneNumber
} from 'data';

/**
 * 假格式化端口：模拟 i18n.PhoneNumberFormat 的 E164 行为。
 * 大多数地区去掉本地前导 0 后拼上地区码；意大利保留前导 0（真实规则如此）。
 * 真实系统格式化结果需在 API 23 模拟器上人工核对，宿主测试不依赖系统能力。
 */
class FakePhoneFormatPort implements PhoneNumberFormatPort {
  private readonly keepTrunkZero: Array<string> = ['IT'];
  private readonly unsupported: Array<string> = ['AC'];

  toE164(formatRegion: string, nationalNumber: string): string {
    const region: PhoneLoginRegion | undefined = findPhoneLoginRegion(formatRegion);
    if (region === undefined || this.unsupported.includes(formatRegion)) {
      throw new Error(`unsupported region ${formatRegion}`);
    }
    let local: string = nationalNumber;
    if (!this.keepTrunkZero.includes(formatRegion) && local.startsWith('0')) {
      local = local.substring(1);
    }
    return `+${region.dialPrefix}${local}`;
  }
}

function regionOf(id: string): PhoneLoginRegion {
  const region: PhoneLoginRegion | undefined = findPhoneLoginRegion(id);
  if (region === undefined) {
    throw new Error(`missing region ${id}`);
  }
  return region;
}

function resolve(raw: string, regionId: string, port?: PhoneNumberFormatPort): PhoneNumberResolution {
  return resolvePhoneNumber(raw, regionOf(regionId), port ?? new FakePhoneFormatPort());
}

export default function phoneLoginNumberPolicyTest(): void {
  describe('phoneLoginNumberPolicyTest', () => {
    it('keepsChinaMainlandLegacyRules', 0, () => {
      expect(resolve('13800138000', 'CN').username).assertEqual('+8613800138000');
      expect(resolve('138 0013 8000', 'CN').username).assertEqual('+8613800138000');
      expect(resolve('+86 138-0013-8000', 'CN').username).assertEqual('+8613800138000');
      // 13 位带 86 前缀的旧输入兼容
      expect(resolve('8613800138000', 'CN').username).assertEqual('+8613800138000');
      // 中国大陆仍是 “1 开头 11 位”，不再接受其他长度
      expect(resolve('23800138000', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_FORMAT);
      expect(resolve('1380013800', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_FORMAT);
    });

    it('normalizesFullWidthDigits', 0, () => {
      expect(normalizePhoneInputText('１３８００１３８０００')).assertEqual('13800138000');
      expect(normalizePhoneInputText('＋８６　１３８')).assertEqual('+86 138');
      expect(resolve('１３８００１３８０００', 'CN').username).assertEqual('+8613800138000');
    });

    it('acceptsHongKongEightDigits', 0, () => {
      expect(resolve('61234567', 'HK').username).assertEqual('+85261234567');
      expect(resolve('6123 4567', 'HK').username).assertEqual('+85261234567');
      // 港澳本地号为 8 位；客户端只做结构校验，号码段/位数由格式化结果与服务端判定。
      expect(resolve('612345', 'HK').username).assertEqual('+852612345');
      expect(resolve('612', 'HK').issue).assertEqual(PhoneNumberIssue.INVALID_FORMAT);
    });

    it('acceptsSharedPrefixNorthAmericaNumbers', 0, () => {
      expect(resolve('4165551234', 'US').username).assertEqual('+14165551234');
      expect(resolve('4165551234', 'CA').username).assertEqual('+14165551234');
      // 已经带上 +1 的完整输入不应被重复加前缀
      expect(resolve('+1 (416) 555-1234', 'CA').username).assertEqual('+14165551234');
      expect(resolve('14165551234', 'US').username).assertEqual('+14165551234');
    });

    it('appliesNationalTrunkPrefixRules', 0, () => {
      // 日本/英国国内前导 0 需要去掉
      expect(resolve('09012345678', 'JP').username).assertEqual('+819012345678');
      expect(resolve('020 7946 0958', 'GB').username).assertEqual('+442079460958');
      // 意大利的前导 0 是号码的一部分，必须保留
      expect(resolve('06 1234 5678', 'IT').username).assertEqual('+390612345678');
    });

    it('acceptsMatchingInternationalPaste', 0, () => {
      expect(resolve('+81 90-1234-5678', 'JP').username).assertEqual('+819012345678');
      expect(resolve('+886 912345678', 'TW').username).assertEqual('+886912345678');
      expect(resolve('+7 7012345678', 'RU').username).assertEqual('+77012345678');
      expect(resolve('+7 7012345678', 'KZ').username).assertEqual('+77012345678');
    });

    it('rejectsInternationalPasteForOtherRegion', 0, () => {
      const japanPaste: PhoneNumberResolution = resolve('+819012345678', 'CN');
      expect(japanPaste.valid).assertFalse();
      expect(japanPaste.issue).assertEqual(PhoneNumberIssue.REGION_MISMATCH);
      expect(japanPaste.message.includes('日本')).assertTrue();
      // +1242 属于巴哈马：美国不能凭短前缀 +1 直接认领
      const bahamasPaste: PhoneNumberResolution = resolve('+12425551234', 'US');
      expect(bahamasPaste.issue).assertEqual(PhoneNumberIssue.REGION_MISMATCH);
      expect(bahamasPaste.message.includes('巴哈马')).assertTrue();
    });

    it('neverDuplicatesCompoundDialPrefix', 0, () => {
      // 巴哈马：7 位本地号与“已带 1242”的写法必须得到同一个结果，且只出现一次 1242
      expect(resolve('5551234', 'BS').username).assertEqual('+12425551234');
      expect(resolve('12425551234', 'BS').username).assertEqual('+12425551234');
      expect(resolve('1242 555 1234', 'BS').username).assertEqual('+12425551234');
      expect(resolve('+12425551234', 'BS').username).assertEqual('+12425551234');
      expect(resolve('90001234', 'GU').username).assertEqual('+167190001234');
    });

    it('rejectsIllegalCharactersAndExtensions', 0, () => {
      expect(resolve('13800138000x123', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_CHARACTER);
      expect(resolve('13800138000#', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_CHARACTER);
      expect(resolve('138+00138000', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_CHARACTER);
      expect(resolve('abc', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_CHARACTER);
    });

    it('enforcesStructuralLengthLimits', 0, () => {
      expect(resolve('+8613800138000123', 'CN').issue).assertEqual(PhoneNumberIssue.TOO_LONG);
      expect(resolve('1'.repeat(PHONE_INPUT_MAX_LENGTH + 1), 'US').issue)
        .assertEqual(PhoneNumberIssue.TOO_LONG);
      expect(resolve('+86 138', 'CN').issue).assertEqual(PhoneNumberIssue.INVALID_FORMAT);
      expect(resolve('+999999', 'CN').issue).assertEqual(PhoneNumberIssue.UNKNOWN_PREFIX);
      expect(MAX_E164_DIGITS).assertEqual(15);
    });

    it('reportsEmptyInputSeparately', 0, () => {
      const empty: PhoneNumberResolution = resolve('   ', 'CN');
      expect(empty.valid).assertFalse();
      expect(empty.issue).assertEqual(PhoneNumberIssue.EMPTY);
      expect(empty.message.length).assertEqual(0);
      expect(empty.username.length).assertEqual(0);
    });

    it('fallsBackWhenFormattingUnavailable', 0, () => {
      // 格式化端口不支持该地区：本地号码不猜测删号，明确要求国际格式
      const local: PhoneNumberResolution = resolve('1234567', 'AC');
      expect(local.valid).assertFalse();
      expect(local.issue).assertEqual(PhoneNumberIssue.FORMAT_UNAVAILABLE);
      // 已带地区码的完整输入仍可用，并校验前缀
      expect(resolve('+2471234567', 'AC').username).assertEqual('+2471234567');
      // 显式不注入端口时同样走降级路径
      const noPort: PhoneNumberResolution = resolvePhoneNumber('1234567', regionOf('AC'));
      expect(noPort.issue).assertEqual(PhoneNumberIssue.FORMAT_UNAVAILABLE);
      expect(resolvePhoneNumber('+8613800138000', regionOf('CN')).username)
        .assertEqual('+8613800138000');
    });

    it('exposesInjectedPortForRuntimeUse', 0, () => {
      // 运行期端口是 i18n 适配器；宿主环境不得在构造时抛错（仅 format 时才触碰系统能力）。
      expect(defaultPhoneNumberFormatPort() !== undefined).assertTrue();
    });
  });
}
