import { describe, expect, it } from '@ohos/hypium';
import {
  defaultPhoneLoginRegion,
  findPhoneLoginRegion,
  matchPhoneLoginRegions,
  PHONE_LOGIN_REGIONS,
  PhoneLoginRegion,
  regionDialText,
  regionEntryLabel,
  regionsSharingLongestPrefix
} from 'data';

function prefixOf(id: string): string {
  const region: PhoneLoginRegion | undefined = findPhoneLoginRegion(id);
  return region === undefined ? '' : region.dialPrefix;
}

/** 白名单来源：知乎官网验证码登录下拉框 2026-10-27 快照（182 项 / 180 个不同前缀）。 */
export default function phoneLoginRegionsTest(): void {  describe('phoneLoginRegionsTest', () => {
    it('containsFullOfficialRegionList', 0, () => {
      expect(PHONE_LOGIN_REGIONS.length).assertEqual(182);
      const prefixes: Set<string> = new Set<string>();
      PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion): void => {
        prefixes.add(region.dialPrefix);
      });
      // 美国/加拿大同用 +1，俄罗斯/哈萨克斯坦同用 +7，因此前缀数比条目数少 2。
      expect(prefixes.size).assertEqual(180);
    });

    it('keepsOfficialOrderAndEndpoints', 0, () => {
      const firstNames: string = PHONE_LOGIN_REGIONS.slice(0, 13)
        .map((region: PhoneLoginRegion): string => region.displayName)
        .join(',');
      expect(firstNames).assertEqual(
        '中国,美国,日本,中国香港,中国澳门,中国台湾,马来西亚,澳大利亚,加拿大,英国,新加坡,德国,俄罗斯');
      const last: PhoneLoginRegion = PHONE_LOGIN_REGIONS[PHONE_LOGIN_REGIONS.length - 1];
      expect(last.displayName).assertEqual('毛里塔尼亚');
      expect(last.dialPrefix).assertEqual('222');
      const secondLast: PhoneLoginRegion = PHONE_LOGIN_REGIONS[PHONE_LOGIN_REGIONS.length - 2];
      expect(secondLast.displayName).assertEqual('塞尔维亚共和国');
      expect(secondLast.dialPrefix).assertEqual('381');
      // order 必须是连续的 1..182，供列表定位使用。
      PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion, index: number): void => {
        expect(region.order).assertEqual(index + 1);
      });
    });

    it('defaultsToChinaMainland', 0, () => {
      const region: PhoneLoginRegion = defaultPhoneLoginRegion();
      expect(region.id).assertEqual('CN');
      expect(region.displayName).assertEqual('中国');
      expect(regionDialText(region)).assertEqual('+86');
      expect(regionEntryLabel(region)).assertEqual('中国 +86');
    });

    it('keepsSharedPrefixRegionsDistinct', 0, () => {
      const us: PhoneLoginRegion | undefined = findPhoneLoginRegion('US');
      const ca: PhoneLoginRegion | undefined = findPhoneLoginRegion('CA');
      if (us === undefined || ca === undefined) {
        expect(false).assertTrue();
        return;
      }
      expect(us.dialPrefix).assertEqual('1');
      expect(ca.dialPrefix).assertEqual('1');
      expect(us.id === ca.id).assertFalse();
      const ru: PhoneLoginRegion | undefined = findPhoneLoginRegion('RU');
      const kz: PhoneLoginRegion | undefined = findPhoneLoginRegion('KZ');
      if (ru === undefined || kz === undefined) {
        expect(false).assertTrue();
        return;
      }
      expect(ru.dialPrefix).assertEqual('7');
      expect(kz.dialPrefix).assertEqual('7');
      expect(ru.id === kz.id).assertFalse();
    });

    it('keepsFourDigitDialPrefixes', 0, () => {
      expect(prefixOf('BS')).assertEqual('1242');
      expect(prefixOf('GU')).assertEqual('1671');
      expect(prefixOf('JM')).assertEqual('1876');
      expect(prefixOf('DO')).assertEqual('1809');
    });

    it('resolvesLongestPrefixBeforeShortOne', 0, () => {
      const bahamas: Array<PhoneLoginRegion> = regionsSharingLongestPrefix('12425551234');
      expect(bahamas.length).assertEqual(1);
      expect(bahamas[0].id).assertEqual('BS');
      const nanp: Array<PhoneLoginRegion> = regionsSharingLongestPrefix('14165551234');
      expect(nanp.length).assertEqual(2);
      const ids: string = nanp.map((region: PhoneLoginRegion): string => region.id).join(',');
      expect(ids).assertEqual('US,CA');
      expect(regionsSharingLongestPrefix('999').length).assertEqual(0);
    });

    it('searchesByChineseNameRegionIdAndAlias', 0, () => {
      const hongKong: Array<PhoneLoginRegion> = matchPhoneLoginRegions('香港');
      expect(hongKong.length > 0).assertTrue();
      expect(hongKong[0].id).assertEqual('HK');
      expect(matchPhoneLoginRegions('Hong Kong')[0].id).assertEqual('HK');
      expect(matchPhoneLoginRegions('japan')[0].id).assertEqual('JP');
      expect(matchPhoneLoginRegions('us')[0].id).assertEqual('US');
      const china: Array<PhoneLoginRegion> = matchPhoneLoginRegions('中国');
      const chinaIds: string = china.map((region: PhoneLoginRegion): string => region.id).join(',');
      expect(chinaIds.includes('CN')).assertTrue();
      expect(chinaIds.includes('HK')).assertTrue();
      expect(chinaIds.includes('MO')).assertTrue();
      expect(chinaIds.includes('TW')).assertTrue();
    });

    it('searchesByDialPrefixWithoutPlus', 0, () => {
      const empty: Array<PhoneLoginRegion> = matchPhoneLoginRegions('   ');
      expect(empty.length).assertEqual(182);
      const one: Array<PhoneLoginRegion> = matchPhoneLoginRegions('1');
      // 搜索 "1" 必须返回多个匹配项（美国、加拿大、巴哈马、关岛等），而不是只返回美国。
      expect(one.length > 3).assertTrue();
      const ids: string = one.map((region: PhoneLoginRegion): string => region.id).join(',');
      expect(ids.includes('US')).assertTrue();
      expect(ids.includes('CA')).assertTrue();
      expect(ids.includes('BS')).assertTrue();
      const us: Array<PhoneLoginRegion> = matchPhoneLoginRegions('+1');
      expect(us.length).assertEqual(one.length);
      const cn: Array<PhoneLoginRegion> = matchPhoneLoginRegions('86');
      const cnIds: string = cn.map((region: PhoneLoginRegion): string => region.id).join(',');
      expect(cnIds.includes('CN')).assertTrue();
    });

    it('returnsEmptyResultForUnknownQuery', 0, () => {
      expect(matchPhoneLoginRegions('不存在的地区').length).assertEqual(0);
      expect(matchPhoneLoginRegions('9999').length).assertEqual(0);
    });

    it('formatsRegionLabelsForSharedPrefixes', 0, () => {
      const us: PhoneLoginRegion | undefined = findPhoneLoginRegion('US');
      const ca: PhoneLoginRegion | undefined = findPhoneLoginRegion('CA');
      if (us === undefined || ca === undefined) {
        return;
      }
      // 同码地区入口文案必须可区分。
      expect(regionEntryLabel(us) === regionEntryLabel(ca)).assertFalse();
      expect(regionEntryLabel(ca)).assertEqual('加拿大 +1');
    });
  });
}
