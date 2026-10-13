import { JsonNumberValue, JsonObjectValue, parseStrictJson } from 'core';
import { ZhihuHttpClient, ZhihuHttpMethod } from '../network/ZhihuHttpClient';
import { normalizePinId, PinRepositoryFailure, PinRepositoryFailureKind } from './DefaultPinRepository';
import { PinLikeRepository, PinLikeResult } from './PinLikeRepository';

export function buildPinLikeUrl(id: string): string {
  return `https://www.zhihu.com/api/v4/pins/${normalizePinId(id)}/voters/up`;
}

/** 对齐上游 PinScreen：POST 点赞，DELETE 取消，计数取 liked_count。 */
export class DefaultPinLikeRepository implements PinLikeRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async setLiked(id: string, liked: boolean): Promise<PinLikeResult> {
    const url = buildPinLikeUrl(id);
    const generation = this.generation;
    const response = await this.httpClient.execute({
      url: url,
      method: liked ? ZhihuHttpMethod.POST : ZhihuHttpMethod.DELETE,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (generation !== this.generation) {
      throw new PinRepositoryFailure(PinRepositoryFailureKind.CANCELLED);
    }
    let likeCount: number | undefined = undefined;
    try {
      const value = parseStrictJson(response.body);
      if (value instanceof JsonObjectValue) {
        const count = value.get('liked_count');
        if (count instanceof JsonNumberValue && Number.isSafeInteger(count.value) && count.value >= 0) {
          likeCount = count.value;
        }
      }
    } catch (_error) {
      // 接口成功但未返回有效计数时，保留控制器的乐观计数。
    }
    return { likeCount: likeCount };
  }
}
