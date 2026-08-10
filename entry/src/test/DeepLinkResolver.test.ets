import { describe, expect, it } from '@ohos/hypium';
import { DeepLinkType, resolveZhihuLink } from 'core';

export default function deepLinkResolverTest(): void {
  describe('deepLinkResolverTest', () => {
    it('resolvesQuestionAndAnswerUrls', 0, () => {
      const answer = resolveZhihuLink('https://www.zhihu.com/question/1/answer/2040633177593619876');
      const question = resolveZhihuLink('https://zhihu.com/question/631983014/');

      expect(answer?.type).assertEqual(DeepLinkType.ANSWER);
      expect(answer?.id).assertEqual('2040633177593619876');
      expect(question?.type).assertEqual(DeepLinkType.QUESTION);
      expect(question?.id).assertEqual('631983014');
    });

    it('keepsLargeContentIdsAsStrings', 0, () => {
      const article = resolveZhihuLink('https://zhuanlan.zhihu.com/p/1981671287999981270');
      const pin = resolveZhihuLink('https://www.zhihu.com/appview/pin/2059710318939301395');
      const appViewAnswer = resolveZhihuLink('https://www.zhihu.com/appview/answer/2040633177593619876');
      const appViewArticle = resolveZhihuLink('https://www.zhihu.com/appview/p/1981671287999981270');

      expect(article?.id).assertEqual('1981671287999981270');
      expect(pin?.id).assertEqual('2059710318939301395');
      expect(appViewAnswer?.type).assertEqual(DeepLinkType.ANSWER);
      expect(appViewArticle?.type).assertEqual(DeepLinkType.ARTICLE);
    });

    it('resolvesPeopleVideoAndSearchUrls', 0, () => {
      const person = resolveZhihuLink('https://www.zhihu.com/people/scanmenge');
      const video = resolveZhihuLink('https://www.zhihu.com/video/123456789');
      const search = resolveZhihuLink('https://www.zhihu.com/search?q=HarmonyOS%20ArkTS');

      expect(person?.type).assertEqual(DeepLinkType.PERSON);
      expect(person?.id).assertEqual('scanmenge');
      expect(video?.type).assertEqual(DeepLinkType.VIDEO);
      expect(search?.query).assertEqual('HarmonyOS ArkTS');
    });

    it('unwrapsZhihuRedirectTargets', 0, () => {
      const destination = resolveZhihuLink(
        'https://link.zhihu.com/?target=https%3A%2F%2Fwww.zhihu.com%2Fquestion%2F48509984'
      );

      expect(destination?.type).assertEqual(DeepLinkType.QUESTION);
      expect(destination?.id).assertEqual('48509984');
    });

    it('resolvesZhihuSchemeRoutes', 0, () => {
      const answer = resolveZhihuLink('zhihu://answers/2040633177593619876');
      const article = resolveZhihuLink('zhihu://articles/1981671287999981270');
      const question = resolveZhihuLink('zhihu://questions/631983014');
      const pin = resolveZhihuLink('zhihu://pin/2059710318939301395');
      const home = resolveZhihuLink('zhihu://feed');
      const search = resolveZhihuLink('zhihu://search?q=ArkTS');

      expect(answer?.type).assertEqual(DeepLinkType.ANSWER);
      expect(article?.type).assertEqual(DeepLinkType.ARTICLE);
      expect(question?.type).assertEqual(DeepLinkType.QUESTION);
      expect(pin?.type).assertEqual(DeepLinkType.PIN);
      expect(home?.type).assertEqual(DeepLinkType.MAIN_TABS);
      expect(search?.query).assertEqual('ArkTS');
    });

    it('rejectsUnknownOrMalformedLinks', 0, () => {
      expect(resolveZhihuLink('https://www.zhihu.com.evil.example/question/1')).assertUndefined();
      expect(resolveZhihuLink('https://user@www.zhihu.com/question/1')).assertUndefined();
      expect(resolveZhihuLink('https://www.zhihu.com:8443/question/1')).assertUndefined();
      expect(resolveZhihuLink('https://www.zhihu.com/question/not-a-number')).assertUndefined();
      expect(resolveZhihuLink('zhihu://answers/not-a-number')).assertUndefined();
      expect(resolveZhihuLink('javascript:alert(1)')).assertUndefined();
    });
  });
}
