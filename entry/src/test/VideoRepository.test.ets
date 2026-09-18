import { describe, expect, it } from '@ohos/hypium';
import {
  DefaultVideoRepository,
  isTrustedZhihuVideoUrl,
  PreparedZhihuHttpRequest,
  selectHighestQualityZhihuVideoUrl,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class VideoSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'd_c0', value: 'video-device-cookie' },
      { name: '_xsrf', value: 'video-xsrf' }
    ];
  }
}

class VideoTransport implements ZhihuHttpTransport {
  private readonly requests: Array<PreparedZhihuHttpRequest>;

  constructor(requests: Array<PreparedZhihuHttpRequest>) {
    this.requests = requests;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    const response: ZhihuHttpResponse = {
      statusCode: 200,
      body: '{"video_play":{"playlist":{"mp4":[' +
        '{"bitrate":720,"url":["https://vdn1.vzuu.com/video-720.mp4"]},' +
        '{"bitrate":1080,"url":["https://vdn2.vzuu.com/video-1080.mp4"]}]}}}'
    };
    return Promise.resolve(response);
  }

  destroy(): void {
  }
}

class VideoTransportFactory implements ZhihuHttpTransportFactory {
  requests: Array<PreparedZhihuHttpRequest> = [];

  create(): ZhihuHttpTransport {
    return new VideoTransport(this.requests);
  }
}

export default function videoRepositoryTest(): void {
  describe('videoRepositoryTest', () => {
    it('selectsHighestTrustedMp4AndRejectsUntrustedHosts', 0, () => {
      const selected = selectHighestQualityZhihuVideoUrl('{"video_play":{"playlist":{"mp4":[' +
        '{"bitrate":9999,"url":["https://evil.example/video.mp4"]},' +
        '{"bitrate":720,"url":["https://vdn1.vzuu.com/720.mp4"]},' +
        '{"bitrate":1080,"url":["https://video.zhimg.com/1080.mp4"]}]}}}');
      expect(selected).assertEqual('https://video.zhimg.com/1080.mp4');
      expect(isTrustedZhihuVideoUrl('https://vdn1.vzuu.com/video.mp4')).assertTrue();
      expect(isTrustedZhihuVideoUrl('https://vzuu.com.evil.example/video.mp4')).assertFalse();
    });

    it('postsSignedPlaybackContextWithWebPlayerHeaders', 0, async () => {
      const factory = new VideoTransportFactory();
      const repository = new DefaultVideoRepository(new ZhihuHttpClient(new VideoSessionProvider(), factory));
      const url = await repository.resolvePlaybackUrl({
        videoId: '1944534197600511075',
        contentId: '1944534197600511075',
        contentType: 'answer'
      });

      expect(url).assertEqual('https://vdn2.vzuu.com/video-1080.mp4');
      expect(factory.requests.length).assertEqual(1);
      expect(factory.requests[0].url).assertEqual(
        'https://www.zhihu.com/api/v4/video/play_info?r=1944534197600511075');
      const headers = JSON.stringify(factory.requests[0].headers);
      expect(headers.includes('"x-app-za":"OS=webplayer"')).assertTrue();
      expect(headers.includes('"x-referer":""')).assertTrue();
      expect(headers.includes('"x-xsrftoken":"video-xsrf"')).assertTrue();
      expect(factory.requests[0].body?.includes('"content_type_str":"answer"')).assertTrue();
    });
  });
}
