import { describe, expect, it } from '@ohos/hypium';
import { DomainDecodeFailureKind } from 'data';
import {
  DOMAIN_FIXTURE_SPECS,
  DomainFixtureSpec,
  DomainFixtureTarget
} from '../main/ets/fixtures/DomainFixtureValidator';

export default function domainFixtureGateTest(): void {
  describe('domainFixtureGateTest', () => {
    it('declaresEightUniqueRawfileFixtures', 0, () => {
      const names = DOMAIN_FIXTURE_SPECS.map((spec: DomainFixtureSpec): string => spec.fileName);
      expect(names.length).assertEqual(8);
      expect(new Set<string>(names).size).assertEqual(8);
      expect(names.includes('user.json')).assertTrue();
      expect(names.includes('question.json')).assertTrue();
      expect(names.includes('answer.json')).assertTrue();
      expect(names.includes('article.json')).assertTrue();
      expect(names.includes('feed-page.json')).assertTrue();
      expect(names.includes('feed-page-mixed.json')).assertTrue();
      expect(names.includes('empty-fields.json')).assertTrue();
      expect(names.includes('error-response.json')).assertTrue();
    });

    it('assignsEveryFixtureOneDistinctDecoderContract', 0, () => {
      const targets = DOMAIN_FIXTURE_SPECS.map((spec: DomainFixtureSpec): DomainFixtureTarget => spec.target);
      expect(new Set<DomainFixtureTarget>(targets).size).assertEqual(8);
      expect(targets.includes(DomainFixtureTarget.USER)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.QUESTION)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.ANSWER)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.ARTICLE)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.FEED_PAGE)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.MIXED_FEED_PAGE)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.EMPTY_FEED_PAGE)).assertTrue();
      expect(targets.includes(DomainFixtureTarget.ERROR_RESPONSE)).assertTrue();
    });

    it('expectsOnlyErrorEnvelopeToFailWithUpstreamCategory', 0, () => {
      const failingSpecs = DOMAIN_FIXTURE_SPECS.filter((spec: DomainFixtureSpec): boolean =>
        spec.expectedFailure !== undefined);
      expect(failingSpecs.length).assertEqual(1);
      expect(failingSpecs[0].fileName).assertEqual('error-response.json');
      expect(failingSpecs[0].expectedFailure).assertEqual(DomainDecodeFailureKind.UPSTREAM_ERROR);
      expect(DOMAIN_FIXTURE_SPECS.filter((spec: DomainFixtureSpec): boolean =>
        spec.expectedFailure === undefined).length).assertEqual(7);
    });
  });
}
