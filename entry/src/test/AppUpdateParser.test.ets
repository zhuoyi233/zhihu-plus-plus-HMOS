import { describe, expect, it } from '@ohos/hypium';
import {
  AppUpdateCheckStatus,
  AppUpdateRelease,
  compareVersionNames,
  decodeLatestRelease,
  parseHmosTagVersion,
  resolveAppUpdateCheck
} from 'data';

function releaseFixture(tag: string, version: string): AppUpdateRelease {
  const release: AppUpdateRelease = {
    tagName: tag,
    versionName: version,
    releaseTitle: tag,
    htmlUrl: 'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/tag/' + tag,
    publishedAt: '2026-08-29T00:00:00Z'
  };
  return release;
}

export default function appUpdateParserTest(): void {
  describe('appUpdateParserTest', () => {
    it('parsesHmosTagPrefixesToVersionNames', 0, () => {
      expect(parseHmosTagVersion('HMOSv0.2.1')).assertEqual('0.2.1');
      expect(parseHmosTagVersion('v0.2.1')).assertEqual('0.2.1');
      expect(parseHmosTagVersion('0.2.1')).assertEqual('0.2.1');
    });

    it('rejectsNonVersionTags', 0, () => {
      expect(parseHmosTagVersion('nightly')).assertEqual(undefined);
      expect(parseHmosTagVersion('HMOSv')).assertEqual(undefined);
      expect(parseHmosTagVersion('HMOSv0.2.1-beta')).assertEqual(undefined);
      expect(parseHmosTagVersion('')).assertEqual(undefined);
    });

    it('comparesVersionNamesByNumericSegments', 0, () => {
      expect(compareVersionNames('0.2.1', '0.2.1')).assertEqual(0);
      expect(compareVersionNames('0.2.2', '0.2.1')).assertEqual(1);
      expect(compareVersionNames('0.2', '0.2.1')).assertEqual(-1);
      expect(compareVersionNames('0.10.0', '0.9.5')).assertEqual(1);
      expect(compareVersionNames('1.0.0', '0.99.99')).assertEqual(1);
    });

    it('decodesLatestReleasePayload', 0, () => {
      const payload = '{"tag_name":"HMOSv0.2.2","name":"v0.2.2","html_url":' +
        '"https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/tag/HMOSv0.2.2",' +
        '"published_at":"2026-08-30T00:00:00Z"}';
      const release = decodeLatestRelease(payload);
      expect(release !== undefined).assertTrue();
      expect(release?.tagName).assertEqual('HMOSv0.2.2');
      expect(release?.versionName).assertEqual('0.2.2');
      expect(release?.htmlUrl).assertEqual(
        'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/tag/HMOSv0.2.2');
    });

    it('rejectsMalformedReleasePayloads', 0, () => {
      expect(decodeLatestRelease('not-json')).assertEqual(undefined);
      expect(decodeLatestRelease('{"name":"no tag"}')).assertEqual(undefined);
      expect(decodeLatestRelease('{"tag_name":"nightly"}')).assertEqual(undefined);
    });

    it('resolvesUpdateAvailabilityAgainstLocalVersion', 0, () => {
      const newer = resolveAppUpdateCheck('0.2.1', releaseFixture('HMOSv0.2.2', '0.2.2'), '');
      expect(newer.status).assertEqual(AppUpdateCheckStatus.UPDATE_AVAILABLE);

      const same = resolveAppUpdateCheck('0.2.1', releaseFixture('HMOSv0.2.1', '0.2.1'), '');
      expect(same.status).assertEqual(AppUpdateCheckStatus.UP_TO_DATE);

      const localNewer = resolveAppUpdateCheck('0.3.0', releaseFixture('HMOSv0.2.1', '0.2.1'), '');
      expect(localNewer.status).assertEqual(AppUpdateCheckStatus.UP_TO_DATE);

      const failed = resolveAppUpdateCheck('0.2.1', undefined, '网络不可用');
      expect(failed.status).assertEqual(AppUpdateCheckStatus.FAILED);
      expect(failed.message).assertEqual('网络不可用');
    });
  });
}
