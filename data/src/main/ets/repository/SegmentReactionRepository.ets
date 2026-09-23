import { JsonObjectValue, JsonStringValue, JsonValue, parseStrictJson } from 'core';
import {
  effectiveSegmentMeta,
  SegmentInfoMark,
  SegmentInfoMeta,
  SegmentInfoParagraph
} from '../domain/DomainModels';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { normalizeContentId } from './DefaultContentRepository';

/** 划线互动的内容类型（对应 segment_reaction 接口的 {type}s 路径段）。 */
export type SegmentContentType = 'answer' | 'article';

export enum SegmentReactionRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class SegmentReactionRepositoryFailure extends Error {
  readonly kind: SegmentReactionRepositoryFailureKind;

  constructor(kind: SegmentReactionRepositoryFailureKind) {
    super(kind === SegmentReactionRepositoryFailureKind.INVALID_ID ? '内容 ID 无效' : '划线互动请求已取消');
    this.name = 'SegmentReactionRepositoryFailure';
    this.kind = kind;
  }
}

export interface SegmentReactionRepository {
  /**
   * 切换某条划线的点赞状态。点赞/取消均按上游语义乐观更新计数并返回最新元信息，
   * 调用方据此刷新正文高亮。contentType 为 answer/article，contentId 为内容数字 ID。
   */
  toggleSegmentLike(
    contentType: SegmentContentType,
    contentId: string,
    paragraph: SegmentInfoParagraph,
    markIndex: number
  ): Promise<SegmentInfoMeta>;
}

export class DefaultSegmentReactionRepository implements SegmentReactionRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async toggleSegmentLike(
    contentType: SegmentContentType,
    contentId: string,
    paragraph: SegmentInfoParagraph,
    markIndex: number
  ): Promise<SegmentInfoMeta> {
    const mark = paragraph.marks[markIndex];
    if (mark === undefined) {
      throw new SegmentReactionRepositoryFailure(SegmentReactionRepositoryFailureKind.INVALID_ID);
    }
    const meta = effectiveSegmentMeta(mark);
    if (meta === undefined) {
      throw new SegmentReactionRepositoryFailure(SegmentReactionRepositoryFailureKind.INVALID_ID);
    }
    const url = `https://www.zhihu.com/api/v4/reaction/${contentType}s/${normalizeContentId(contentId)}/segment_reaction`;
    if (meta.isLike) {
      await this.execute(url, ZhihuHttpMethod.DELETE, buildSegmentUnlikeBody(meta));
      return {
        segIds: meta.segIds,
        isLike: false,
        likeCount: Math.max(0, meta.likeCount - 1),
        commentCount: meta.commentCount,
        myCommentCount: meta.myCommentCount,
        isSpan: meta.isSpan
      };
    }
    const response = await this.execute(url, ZhihuHttpMethod.POST, buildSegmentLikeBody(paragraph, mark, meta));
    const payloadSegIds = readPayloadSegIds(response.body);
    return {
      segIds: payloadSegIds.length > 0 ? payloadSegIds : meta.segIds,
      isLike: true,
      likeCount: meta.likeCount + 1,
      commentCount: meta.commentCount,
      myCommentCount: meta.myCommentCount,
      isSpan: meta.isSpan
    };
  }

  private async execute(url: string, method: ZhihuHttpMethod, body?: string): Promise<ZhihuHttpResponse> {
    const requestGeneration = this.generation;
    const response = await this.httpClient.execute({
      url: url,
      method: method,
      body: body,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new SegmentReactionRepositoryFailure(SegmentReactionRepositoryFailureKind.CANCELLED);
    }
    return response;
  }
}

/** 点赞请求体：seg_id 仅在有值时附带；position 用段落 pid 与起止偏移（对齐上游 buildSegmentLikeBody）。 */
function buildSegmentLikeBody(paragraph: SegmentInfoParagraph, mark: SegmentInfoMark, meta: SegmentInfoMeta): string {
  const segIdField = meta.segIds.length > 0 ? `"seg_id":${JSON.stringify(meta.segIds.join(','))},` : '';
  return `{${segIdField}"content":${JSON.stringify(paragraph.text)},` +
    `"position":{"start":{"paragraph_id":${JSON.stringify(paragraph.pid)},"offset":${mark.startIndex}},` +
    `"end":{"paragraph_id":${JSON.stringify(paragraph.pid)},"offset":${mark.endIndex}}}}`;
}

/** 取消点赞请求体（对齐上游 buildSegmentUnlikeBody）。 */
function buildSegmentUnlikeBody(meta: SegmentInfoMeta): string {
  return `{"seg_ids":${JSON.stringify(meta.segIds.join(','))}}`;
}

/** 解析 204/JSON 响应中的 payload.segId（逗号分隔的新划线标识），无则回退空列表。 */
function readPayloadSegIds(body: string): Array<string> {
  if (body.length === 0) {
    return [];
  }
  let parsed: JsonValue | undefined;
  try {
    parsed = parseStrictJson(body);
  } catch (_error) {
    return [];
  }
  if (!(parsed instanceof JsonObjectValue)) {
    return [];
  }
  const payload = parsed.get('payload');
  if (!(payload instanceof JsonObjectValue)) {
    return [];
  }
  const segIdValue = payload.get('segId');
  if (segIdValue instanceof JsonStringValue) {
    return segIdValue.value.split(',').filter((part: string): boolean => part.length > 0);
  }
  return [];
}
