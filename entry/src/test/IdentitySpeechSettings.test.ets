import { describe, expect, it } from '@ohos/hypium';
import {
  decodeIdentityAccounts,
  defaultSpeechPreferences,
  identityCookiesFromResponse,
  normalizeSpeechPreferences,
  prepareZhihuHttpRequest,
  SessionCookie,
  ZhihuIdentityAccount
} from 'data';

export default function identitySpeechSettingsTest(): void {
  describe('identitySpeechSettingsTest', () => {
    it('decodesIdentityAccountsFromUpstreamWireShape', 0, () => {
      const accounts: Array<ZhihuIdentityAccount> = decodeIdentityAccounts('{"data":[' +
        '{"id":"main","url_token":"main-user","name":"主账号","avatar_url":"https://pic.zhimg.com/a.jpg",' +
        '"is_active":true,"can_create_sub_account":true,"account_type":1,"sub_account_control_status":0},' +
        '{"id":"sub","name":"马甲号","is_active":false,"account_type":2}' +
        ']}');

      expect(accounts.length).assertEqual(2);
      expect(accounts[0].id).assertEqual('main');
      expect(accounts[0].urlToken).assertEqual('main-user');
      expect(accounts[0].isActive).assertTrue();
      expect(accounts[0].canCreateSubAccount).assertTrue();
      expect(accounts[1].accountType).assertEqual(2);
    });

    it('dropsMalformedIdentityRows', 0, () => {
      const accounts = decodeIdentityAccounts('{"data":[' +
        '{"id":"","name":"无效"},{"id":"valid","name":"有效"},{"id":"missing-name"}' +
        ']}');
      expect(accounts.length).assertEqual(1);
      expect(accounts[0].id).assertEqual('valid');
    });

    it('mergesIdentityCookiesWithoutDroppingDeviceCookies', 0, () => {
      const existing: Array<SessionCookie> = [
        { name: 'd_c0', value: 'device' },
        { name: 'z_c0', value: 'old' }
      ];
      const cookies = identityCookiesFromResponse('{"cookie":{"z_c0":"new","_xsrf":"token"}}', existing);
      expect(cookies.find((cookie: SessionCookie): boolean => cookie.name === 'd_c0')?.value).assertEqual('device');
      expect(cookies.find((cookie: SessionCookie): boolean => cookie.name === 'z_c0')?.value).assertEqual('new');
      expect(cookies.find((cookie: SessionCookie): boolean => cookie.name === '_xsrf')?.value).assertEqual('token');
    });

    it('rejectsIdentityCredentialResponseWithoutZc0', 0, () => {
      expect(() => identityCookiesFromResponse('{"cookie":{"_xsrf":"token"}}', []))
        .assertThrowError('服务器未返回有效的 z_c0 Cookie');
    });

    it('preparesIdentityRequestsWithScopedOfficialMobileHeaders', 0, () => {
      const request = prepareZhihuHttpRequest({
        url: 'https://api.zhihu.com/people/account/list',
        useSession: true,
        useIdentityHeaders: true
      }, [{ name: 'z_c0', value: 'login' }], 0);
      const serializedHeaders = JSON.stringify(request.headers);
      expect(serializedHeaders.includes('"x-api-version":"3.0.93"')).assertTrue();
      expect(serializedHeaders.includes('"x-app-bundleid":"com.zhihu.android"')).assertTrue();
      expect(serializedHeaders.includes('"User-Agent":"com.zhihu.android/')).assertTrue();
      expect(request.headers.Cookie).assertEqual('z_c0=login');
    });

    it('normalizesSpeechPreferencesToSupportedRangeAndVoices', 0, () => {
      const low = normalizeSpeechPreferences({ speed: 0, pitch: -1, person: 21,
        language: 'zh-CN', style: 'interaction-broadcast' });
      expect(low.speed).assertEqual(0.5);
      expect(low.pitch).assertEqual(0.5);
      expect(low.person).assertEqual(21);

      const high = normalizeSpeechPreferences({ speed: 3, pitch: 2.04, person: 8,
        language: 'en-US', style: 'interaction-broadcast' });
      expect(high.speed).assertEqual(2);
      expect(high.pitch).assertEqual(2);
      expect(high.person).assertEqual(8);
      expect(high.language).assertEqual('en-US');
      expect(defaultSpeechPreferences().speed).assertEqual(1);
    });
  });
}
