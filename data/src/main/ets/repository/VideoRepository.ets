import {
  JsonArrayValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson
} from 'core';
import { ZhihuHttpClient, ZhihuHttpMethod } from '../network/ZhihuHttpClient';

export type VideoParentContentType = 'answer' | 'article' | 'question';

export interface VideoPlaybackRequest {
  readonly videoId: string;
  readonly contentId: string;
  readonly contentType: VideoParentContentType;
}

export interface VideoRepository {
  resolvePlaybackUrl(request: VideoPlaybackRequest): Promise<string | undefined>;
  cancel(): void;
}

function isSafeId(value: string): boolean {
  return /^[1-9][0-9]{0,29}$/.test(value);
}

export function isTrustedZhihuVideoUrl(value: string): boolean {
  const match = /^https:\/\/([A-Za-z0-9.-]+)(?::[0-9]{1,5})?(?:\/[A-Za-z0-9%&=._~!$'()*+,;:@/?-]*)?$/.exec(value);
  if (match === null || match[1].includes('..')) {
    return false;
  }
  const host = match[1].toLowerCase();
  return host === 'vzuu.com' || host.endsWith('.vzuu.com') ||
    host === 'zhimg.com' || host.endsWith('.zhimg.com') ||
    host === 'zhihu.com' || host.endsWith('.zhihu.com');
}

export function selectHighestQualityZhihuVideoUrl(body: string): string | undefined {
  let root: JsonObjectValue;
  try {
    const parsed = parseStrictJson(body);
    if (!(parsed instanceof JsonObjectValue)) {
      return undefined;
    }
    root = parsed;
  } catch (_error) {
    return undefined;
  }
  const videoPlay = root.get('video_play');
  if (!(videoPlay instanceof JsonObjectValue)) return undefined;
  const playlist = videoPlay.get('playlist');
  if (!(playlist instanceof JsonObjectValue)) return undefined;
  const mp4 = playlist.get('mp4');
  if (!(mp4 instanceof JsonArrayValue) || mp4.items.length > 100) return undefined;

  let bestUrl: string | undefined = undefined;
  let bestBitrate: number = -1;
  mp4.items.forEach((item: JsonValue): void => {
    if (!(item instanceof JsonObjectValue)) return;
    const bitrateValue = item.get('bitrate');
    const urlsValue = item.get('url');
    const bitrate = bitrateValue instanceof JsonNumberValue && Number.isFinite(bitrateValue.value)
      ? bitrateValue.value : 0;
    if (!(urlsValue instanceof JsonArrayValue) || urlsValue.items.length === 0) return;
    const firstUrl = urlsValue.items[0];
    if (!(firstUrl instanceof JsonStringValue) || !isTrustedZhihuVideoUrl(firstUrl.value)) return;
    if (bitrate > bestBitrate) {
      bestBitrate = bitrate;
      bestUrl = firstUrl.value;
    }
  });
  return bestUrl;
}

export class DefaultVideoRepository implements VideoRepository {
  private readonly httpClient: ZhihuHttpClient;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.httpClient.cancel();
  }

  async resolvePlaybackUrl(request: VideoPlaybackRequest): Promise<string | undefined> {
    if (!isSafeId(request.videoId) || !isSafeId(request.contentId)) {
      return undefined;
    }
    const body = JSON.stringify({
      content_id: request.contentId,
      content_type_str: request.contentType,
      video_id: request.videoId,
      scene_code: 'answer_detail_web',
      is_only_video: true
    });
    const response = await this.httpClient.execute({
      url: `https://www.zhihu.com/api/v4/video/play_info?r=${request.videoId}`,
      method: ZhihuHttpMethod.POST,
      body: body,
      contentType: 'application/json',
      accept: 'application/json',
      useSession: true,
      signWithZse: true,
      includeOptionalXsrfToken: true,
      useVideoPlayerHeaders: true
    });
    return selectHighestQualityZhihuVideoUrl(response.body);
  }
}
