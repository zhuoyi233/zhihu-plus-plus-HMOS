import { describe, expect, it } from '@ohos/hypium';
import {
  COOKIE_FIELD_MAX_COUNT,
  COOKIE_HEADER_MAX_LENGTH,
  COOKIE_VALUE_MAX_LENGTH,
  decodeCookieSession,
  encodeCookieSession,
  parseCookieAssignments,
  redactSensitiveText,
  removeExpiredCookies,
  safeSessionSummary,
  SessionCookie,
  toCookieHeader,
  upsertCookie
} from 'data';

export default function cookieSessionTest(): void {
  describe('cookieSessionTest', () => {
    it('parsesAssignmentsAndSkipsAttributes', 0, () => {
      const cookies = parseCookieAssignments('z_c0=abc==; Path=/; Domain=.zhihu.com; _xsrf=def; HttpOnly');
      expect(cookies.length).assertEqual(2);
      expect(cookies[0].name).assertEqual('z_c0');
      expect(cookies[0].value).assertEqual('abc==');
      expect(cookies[1].name).assertEqual('_xsrf');
    });

    it('usesLastValueForDuplicateCookieNames', 0, () => {
      const cookies = parseCookieAssignments('z_c0=old; d_c0=device; z_c0=new');
      expect(cookies.length).assertEqual(2);
      expect(toCookieHeader(cookies, 0)).assertEqual('z_c0=new; d_c0=device');
    });

    it('removesExpiredCookiesAndBuildsHeader', 0, () => {
      const cookies: Array<SessionCookie> = [
        { name: 'alive', value: '1', expiresAt: 2000 },
        { name: 'expired', value: '2', expiresAt: 999 },
        { name: 'session', value: '3' }
      ];
      expect(removeExpiredCookies(cookies, 1000).length).assertEqual(2);
      expect(toCookieHeader(cookies, 1000)).assertEqual('alive=1; session=3');
    });

    it('preservesExistingZC0OnBlankUpdate', 0, () => {
      const original: Array<SessionCookie> = [{ name: 'z_c0', value: 'existing' }];
      const updated = upsertCookie(original, { name: 'z_c0', value: '' });
      expect(updated.length).assertEqual(1);
      expect(updated[0].value).assertEqual('existing');
    });

    it('rejectsHeaderInjectionCharacters', 0, () => {
      expect(parseCookieAssignments('safe=value\r\nInjected: yes').length).assertEqual(0);
      const original: Array<SessionCookie> = [{ name: 'safe', value: 'value' }];
      expect(upsertCookie(original, { name: 'bad name', value: 'other' }).length).assertEqual(1);
      expect(toCookieHeader([{ name: 'safe', value: 'value\r\nInjected: yes' }], 0)).assertEqual('');
    });

    it('rejectsOversizedCookieHeadersFieldsAndValues', 0, () => {
      expect(parseCookieAssignments(`z_c0=${'x'.repeat(COOKIE_HEADER_MAX_LENGTH)}`).length).assertEqual(0);
      expect(parseCookieAssignments(`z_c0=${'x'.repeat(COOKIE_VALUE_MAX_LENGTH + 1)}`).length).assertEqual(0);
      const fields: Array<string> = [];
      for (let index = 0; index <= COOKIE_FIELD_MAX_COUNT; index += 1) {
        fields.push(`c${index}=v`);
      }
      expect(parseCookieAssignments(fields.join(';')).length).assertEqual(0);
    });

    it('roundTripsSessionPayload', 0, () => {
      const original: Array<SessionCookie> = [{ name: 'd_c0', value: 'token' }];
      const decoded = decodeCookieSession(encodeCookieSession(original, 1234));
      expect(decoded.savedAt).assertEqual(1234);
      expect(decoded.cookies[0].value).assertEqual('token');
    });

    it('rejectsMalformedPersistedCookieEntries', 0, () => {
      let rejectedNullCookie = false;
      let rejectedInvalidName = false;
      let rejectedNonStringValue = false;
      try {
        decodeCookieSession('{"version":1,"savedAt":1234,"cookies":[null]}');
      } catch (_) {
        rejectedNullCookie = true;
      }
      try {
        decodeCookieSession(
          '{"version":1,"savedAt":1234,"cookies":[{"name":"bad name","value":"secret"}]}'
        );
      } catch (_) {
        rejectedInvalidName = true;
      }
      try {
        decodeCookieSession(
          '{"version":1,"savedAt":1234,"cookies":[{"name":"z_c0","value":1}]}'
        );
      } catch (_) {
        rejectedNonStringValue = true;
      }
      expect(rejectedNullCookie).assertTrue();
      expect(rejectedInvalidName).assertTrue();
      expect(rejectedNonStringValue).assertTrue();
      const deletions = parseCookieAssignments('z_c0=; Max-Age=0', true);
      expect(deletions.length).assertEqual(1);
      expect(deletions[0].value).assertEqual('');
    });

    it('redactsSecretsFromLogs', 0, () => {
      const redacted = redactSensitiveText('Cookie: z_c0=secret; d_c0=hidden');
      expect(redacted.includes('secret')).assertFalse();
      expect(redacted.includes('hidden')).assertFalse();
      const summary = safeSessionSummary('restored', [{ name: 'd_c0', value: 'hidden' }]);
      expect(summary).assertEqual('restored: count=1, names=[d_c0]');
      expect(summary.includes('hidden')).assertFalse();
    });
  });
}
