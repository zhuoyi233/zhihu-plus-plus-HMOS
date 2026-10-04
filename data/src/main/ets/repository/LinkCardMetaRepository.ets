import { DeepLinkType, JsonNullValue, JsonNumberValue, JsonObjectValue, JsonValue,
  parseStrictJson, resolveZhihuLink } from 'core';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';

/** 推荐阅读卡片的知乎站内资源类型（对齐网页卡片底部 meta 行的类型标注）。 */
export enum LinkCardResourceKind {
  ANSWER = 'answer',
  ARTICLE = 'article',
  QUESTION = 'question',
  PIN = 'pin'
}

/** 推荐阅读卡片的站内资源元数据：网页卡片底部展示的赞同/评论计数与资源类型。 */
export interface LinkCardMeta {
  kind: LinkCardResourceKind;
  /** 赞同数（回答/文章）或喜欢数（想法）；问题不返回。 */
  voteupCount?: number;
  /** 评论数；问题不返回。 */
  commentCount?: number;
  /** 回答数；仅问题资源返回。 */
  answerCount?: number;
}

/**
 * 推荐阅读卡片元数据仓库：把卡片链接解析为知乎站内资源后，
 * 以最小 include 拉取赞同/评论计数（对齐上游 fetchPinLinkCardPreview 的
 * "解析目标 → 拉内容详情"思路，但只取计数避免下载正文）。
 * 非站内资源（外链）返回 undefined，由调用方回退为展示链接地址。
 */
export interface LinkCardMetaRepository {
  getMeta(url: string): Promise<LinkCardMeta | undefined>;
}

const ANSWER_META_INCLUDE = 'voteup_count,comment_count';
const ARTICLE_META_INCLUDE = 'voteup_count,comment_count';
const QUESTION_META_INCLUDE = 'answer_count';

function nonNegativeCount(value: JsonValue | undefined): number | undefined {
  if (value === undefined || value instanceof JsonNullValue || !(value instanceof JsonNumberValue)) {
    return undefined;
  }
  return value.value >= 0 ? value.value : undefined;
}

export class DefaultLinkCardMetaRepository implements LinkCardMetaRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getMeta(url: string): Promise<LinkCardMeta | undefined> {
    const destination = resolveZhihuLink(url);
    if (destination === undefined) {
      return undefined;
    }
    let endpoint: string;
    switch (destination.type) {
      case DeepLinkType.ANSWER:
        endpoint = `https://www.zhihu.com/api/v4/answers/${destination.id}?include=${ANSWER_META_INCLUDE}`;
        break;
      case DeepLinkType.ARTICLE:
        endpoint = `https://www.zhihu.com/api/v4/articles/${destination.id}?include=${ARTICLE_META_INCLUDE}`;
        break;
      case DeepLinkType.QUESTION:
        endpoint = `https://www.zhihu.com/api/v4/questions/${destination.id}?include=${QUESTION_META_INCLUDE}`;
        break;
      case DeepLinkType.PIN:
        // 想法的 like_count/comment_count 是基础字段，无需 include。
        endpoint = `https://www.zhihu.com/api/v4/pins/${destination.id}`;
        break;
      default:
        return undefined;
    }
    const requestGeneration = this.generation;
    const response = await this.httpClient.execute({
      url: endpoint,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      return undefined;
    }
    return decodeLinkCardMeta(response.body, destination.type);
  }
}

export function decodeLinkCardMeta(body: string, type: DeepLinkType): LinkCardMeta | undefined {
  let parsed: JsonValue;
  try {
    parsed = parseStrictJson(body);
  } catch (_error) {
    return undefined;
  }
  if (!(parsed instanceof JsonObjectValue)) {
    return undefined;
  }
  const voteupCount = nonNegativeCount(parsed.get('voteup_count'));
  const commentCount = nonNegativeCount(parsed.get('comment_count'));
  const answerCount = nonNegativeCount(parsed.get('answer_count'));
  if (type === DeepLinkType.QUESTION) {
    return { kind: LinkCardResourceKind.QUESTION, answerCount: answerCount };
  }
  if (type === DeepLinkType.PIN) {
    // 想法接口的喜欢数字段是 like_count（对应 PinDetail.likeCount）。
    return { kind: LinkCardResourceKind.PIN, voteupCount: nonNegativeCount(parsed.get('like_count')),
      commentCount: commentCount };
  }
  const kind = type === DeepLinkType.ANSWER ? LinkCardResourceKind.ANSWER : LinkCardResourceKind.ARTICLE;
  return { kind: kind, voteupCount: voteupCount, commentCount: commentCount };
}
