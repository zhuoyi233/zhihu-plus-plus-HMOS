import { JsonObjectValue, JsonStringValue, JsonValue, parseStrictJson } from 'core';
import {
  effectiveSegmentMeta,
  SegmentInfoMark,
  SegmentInfoMeta,
  SegmentInfoParagraph
} from '../domain/DomainModels';
import { HttpFailure, HttpFailureKind } from '../network/HttpFailure';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { normalizeContentId } from './DefaultContentRepository';

/** 划线互动的内容类型（对应 segment_reaction 接口的 {type}s 路径段）。 */
export type SegmentContentType = 'answer' | 'article';

export enum SegmentReactionRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

/** 划线互动的重试策略：单飞客户端在"已有请求进行中"时会硬拒绝（BUSY），点赞这类用户
 * 显式意图不能因此静默失败，需要在短窗口内重试等待占位释放。 */
export interface SegmentReactionRetryPolicy {
  /** 总尝试次数（含首次），至少 1。 */
  maxAttempts: number;
  /** 两次尝试之间的等待毫秒数。 */
  delayMs: number;
}

const DEFAULT_SEGMENT_REACTION_RETRY_POLICY: SegmentReactionRetryPolicy = { maxAttempts: 3, delayMs: 250 };

function waitForRetry(delayMs: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => resolve(), delayMs);
  });
}

/** BUSY（单飞占位被占）与通用可重试失败（429/5xx/超时/网络）都值得短窗口重试；取消与参数错误不重试。 */
function isRetryableSegmentFailure(failure: HttpFailure): boolean {
  return failure.kind === HttpFailureKind.BUSY || failure.retryable;
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
  private readonly retryPolicy: SegmentReactionRetryPolicy;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient, retryPolicy?: SegmentReactionRetryPolicy) {
    this.httpClient = httpClient;
    this.retryPolicy = retryPolicy ?? DEFAULT_SEGMENT_REACTION_RETRY_POLICY;
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

  /**
   * 执行一次划线互动请求，BUSY/可重试失败在短窗口内重试。
   * 点赞/取消都是"用户点一下就要有结果"的动作：单飞占位被别的请求占用时直接失败会让
   * 整个点赞功能看起来失效（第一次点刚好撞上占位就再也点不动），因此这里必须重试等待。
   */
  private async execute(url: string, method: ZhihuHttpMethod, body?: string): Promise<ZhihuHttpResponse> {
    const attempts = Math.max(1, this.retryPolicy.maxAttempts);
    let lastFailure: HttpFailure | undefined = undefined;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      if (attempt > 0) {
        await waitForRetry(this.retryPolicy.delayMs);
      }
      try {
        return await this.executeOnce(url, method, body);
      } catch (error) {
        if (error instanceof HttpFailure && isRetryableSegmentFailure(error)) {
          lastFailure = error;
          continue;
        }
        // ArkTS 限制 throw 任意类型：非 HttpFailure 一律包装成具体 Error 再抛。
        throw error instanceof Error ? error : new HttpFailure(HttpFailureKind.BUSY);
      }
    }
    throw lastFailure ?? new HttpFailure(HttpFailureKind.BUSY);
  }

  private async executeOnce(url: string, method: ZhihuHttpMethod, body?: string): Promise<ZhihuHttpResponse> {
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
