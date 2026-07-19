import { describe, expect, it } from '@ohos/hypium';
import { md5Hex } from '../main/ets/network/Md5';
import { encryptZseV4 } from '../main/ets/network/ZseSigner';
import { createZse96Header } from '../main/ets/network/ZhihuFetchSignature';

export default function zseSignerTest(): void {
  describe('zseSignerTest', () => {
    it('matchesMd5Vectors', 0, () => {
      expect(md5Hex('')).assertEqual('d41d8cd98f00b204e9800998ecf8427e');
      expect(md5Hex('abc')).assertEqual('900150983cd24fb0d6963f7d28e17f72');
      expect(md5Hex('hello')).assertEqual('5d41402abc4b2a76b9719d911017c592');
      expect(md5Hex('你好')).assertEqual('7eca689f0d3389d9dea66ae112e5cfd7');
      expect(md5Hex('😀')).assertEqual('2a02eac39d716a70ecf37579185927b6');
    });

    it('matchesAndroidCipherVectors', 0, () => {
      expect(encryptZseV4('hello')).assertEqual('+6xPvLM9SJjT+GToL9YAivj/');
      expect(encryptZseV4('world')).assertEqual('+65CcmGtmyq0DMsf4jUsBidi');
    });

    it('matchesAndroidHeaderVector', 0, () => {
      const header = createZse96Header(
        'https://www.zhihu.com/api/v4/me?include=account_status',
        'fixed-d_c0-token',
        '{"hello":"world"}'
      );
      expect(header).assertEqual(
        '2.0_XAY8F0Fc/7DSnpGxJblUS2S4BuUCOnxIL4t+Dzd/+=mp3=CL74Cwu=t0WDQ/iOYG'
      );
    });
  });
}
