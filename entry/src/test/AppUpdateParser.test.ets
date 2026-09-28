import { describe, expect, it } from '@ohos/hypium';
import {
  AppUpdateCheckStatus,
  AppUpdateRelease,
  AUTO_UPDATE_CHECK_INTERVAL_MS,
  compareVersionNames,
  decodeLatestRelease,
  decodeLatestReleaseAtom,
  isUpdateAnnouncementVisible,
  parseHmosTagVersion,
  resolveAppUpdateCheck,
  shouldAutoCheckForUpdate,
  updateDownloadSources
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

    it('decodesAssetSha256FromCatalogAndGithubDigest', 0, () => {
      const catalogPayload = '{"tag_name":"HMOSv0.5.4","html_url":"https://github.com/zhuoyi233/' +
        'zhihu-plus-plus-HMOS/releases/tag/HMOSv0.5.4","assets":[{"name":' +
        '"ZhihuPlusPlus-HMOS-v0.5.4-unsigned.hap","browser_download_url":"https://github.com/zhuoyi233/' +
        'zhihu-plus-plus-HMOS/releases/download/HMOSv0.5.4/ZhihuPlusPlus-HMOS-v0.5.4-unsigned.hap",' +
        '"size":7505067,"sha256":"dfa153323ab7ba85a17096b63e5f13eb6f10966460f2f6f218d8e9357a167384"}]}';
      const fromCatalog = decodeLatestRelease(catalogPayload);
      expect(fromCatalog?.assetSha256).assertEqual('dfa153323ab7ba85a17096b63e5f13eb6f10966460f2f6f218d8e9357a167384');

      const apiPayload = '{"tag_name":"HMOSv0.5.4","html_url":"https://github.com/zhuoyi233/' +
        'zhihu-plus-plus-HMOS/releases/tag/HMOSv0.5.4","assets":[{"name":' +
        '"ZhihuPlusPlus-HMOS-v0.5.4-unsigned.hap","browser_download_url":"https://github.com/zhuoyi233/' +
        'zhihu-plus-plus-HMOS/releases/download/HMOSv0.5.4/ZhihuPlusPlus-HMOS-v0.5.4-unsigned.hap",' +
        '"digest":"sha256:dfa153323ab7ba85a17096b63e5f13eb6f10966460f2f6f218d8e9357a167384"}]}';
      const fromApi = decodeLatestRelease(apiPayload);
      expect(fromApi?.assetSha256).assertEqual('dfa153323ab7ba85a17096b63e5f13eb6f10966460f2f6f218d8e9357a167384');

      const withoutHash = decodeLatestRelease('{"tag_name":"HMOSv0.2.2","assets":[{"name":' +
        '"ZhihuPlusPlus-HMOS-v0.2.2-unsigned.hap","browser_download_url":"https://github.com/zhuoyi233/' +
        'zhihu-plus-plus-HMOS/releases/download/HMOSv0.2.2/ZhihuPlusPlus-HMOS-v0.2.2-unsigned.hap"}]}');
      expect(withoutHash?.assetSha256).assertEqual('');
    });

    it('buildsEighteenSourcesOnlyForPublishedUnsignedHap', 0, () => {
      const url = 'https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/download/' +
        'HMOSv0.5.4/ZhihuPlusPlus-HMOS-v0.5.4-unsigned.hap';
      const sources = updateDownloadSources(url);
      expect(sources.length).assertEqual(18);
      expect(sources[0].url).assertEqual('https://cdn.gh-proxy.org/' + url);
      expect(sources[11].resumable).assertTrue();
      expect(sources[12].resumable).assertFalse();
      expect(sources[17].url).assertEqual(url);
      expect(sources[17].official).assertTrue();
      expect(updateDownloadSources('https://example.com/app.hap').length).assertEqual(0);
    });

    it('rejectsMalformedReleasePayloads', 0, () => {
      expect(decodeLatestRelease('not-json')).assertEqual(undefined);
      expect(decodeLatestRelease('{"name":"no tag"}')).assertEqual(undefined);
      expect(decodeLatestRelease('{"tag_name":"nightly"}')).assertEqual(undefined);
    });

    it('decodesLatestReleaseFromAtomFallback', 0, () => {
      const payload = '<?xml version="1.0"?><feed><entry>' +
        '<updated>2026-09-06T12:41:08Z</updated>' +
        '<link rel="alternate" type="text/html" ' +
        'href="https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/tag/HMOSv0.4.0"/>' +
        '<title>HMOSv0.4.0</title></entry></feed>';
      const release = decodeLatestReleaseAtom(payload);
      expect(release?.versionName).assertEqual('0.4.0');
      expect(release?.tagName).assertEqual('HMOSv0.4.0');
      expect(release?.publishedAt).assertEqual('2026-09-06T12:41:08Z');
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

    it('throttlesAutoCheckByInterval', 0, () => {
      expect(shouldAutoCheckForUpdate(0, 1000)).assertTrue();
      expect(shouldAutoCheckForUpdate(1000, 1000 + AUTO_UPDATE_CHECK_INTERVAL_MS)).assertTrue();
      expect(shouldAutoCheckForUpdate(1000, 1000 + AUTO_UPDATE_CHECK_INTERVAL_MS - 1)).assertFalse();
      expect(shouldAutoCheckForUpdate(5000, 1000)).assertFalse();
    });

    it('gatesUpdateAnnouncementVisibility', 0, () => {
      expect(isUpdateAnnouncementVisible('0.3.3', '')).assertTrue();
      expect(isUpdateAnnouncementVisible('0.3.3', '0.3.2')).assertTrue();
      expect(isUpdateAnnouncementVisible('0.3.3', '0.3.3')).assertFalse();
      expect(isUpdateAnnouncementVisible('', '')).assertFalse();
    });
  });
}
