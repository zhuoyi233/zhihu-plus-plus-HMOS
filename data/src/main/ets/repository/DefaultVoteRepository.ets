import {
  JsonBooleanValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonValue,
  parseStrictJson
} from 'core';
import { ContentVoteState } from '../domain/DomainModels';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { normalizeContentId } from './DefaultContentRepository';
import { ContentThankResult, ContentVoteResult, VoteRepository } from './VoteRepository';

export enum VoteRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class VoteRepositoryFailure extends Error {
  readonly kind: VoteRepositoryFailureKind;

  constructor(kind: VoteRepositoryFailureKind) {
    super(kind === VoteRepositoryFailureKind.INVALID_ID ? '内容 ID 无效' : '互动请求已取消');
    this.name = 'VoteRepositoryFailure';
    this.kind = kind;
  }
}

export function buildAnswerVoteUrl(id: string): string {
  return `https://www.zhihu.com/api/v4/answers/${normalizeContentId(id)}/voters`;
}

export function buildArticleVoteUrl(id: string): string {
  return `https://www.zhihu.com/api/v4/articles/${normalizeContentId(id)}/voters`;
}

export function buildAnswerThankUrl(id: string): string {
  return `https://www.zhihu.com/api/v4/answers/${normalizeContentId(id)}/thank`;
}

export function buildAnswerVoteBody(state: ContentVoteState): string {
  return JSON.stringify({ type: state });
}

/** 与上游 ArticleViewModel 一致：文章投票只区分赞同（1）与非赞同（0）。 */
export function buildArticleVoteBody(state: ContentVoteState): string {
  return JSON.stringify({ voting: state === ContentVoteState.UP ? 1 : 0 });
}

export class DefaultVoteRepository implements VoteRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async voteAnswer(id: string, state: ContentVoteState): Promise<ContentVoteResult> {
    const response = await this.execute(
      buildAnswerVoteUrl(id),
      ZhihuHttpMethod.POST,
      buildAnswerVoteBody(state)
    );
    return { voteupCount: readOptionalCount(response.body, 'voteup_count') };
  }

  async voteArticle(id: string, state: ContentVoteState): Promise<ContentVoteResult> {
    const response = await this.execute(
      buildArticleVoteUrl(id),
      ZhihuHttpMethod.POST,
      buildArticleVoteBody(state)
    );
    return { voteupCount: readOptionalCount(response.body, 'voteup_count') };
  }

  async thankAnswer(id: string, thanked: boolean): Promise<ContentThankResult> {
    const response = await this.execute(
      buildAnswerThankUrl(id),
      thanked ? ZhihuHttpMethod.POST : ZhihuHttpMethod.DELETE,
      thanked ? '{}' : undefined
    );
    return {
      thanksCount: readOptionalCount(response.body, 'thanks_count'),
      thanked: readOptionalBoolean(response.body, 'is_thanked')
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
      throw new VoteRepositoryFailure(VoteRepositoryFailureKind.CANCELLED);
    }
    return response;
  }
}

function readOptionalCount(body: string, field: string): number | undefined {
  const value = readField(body, field);
  if (value instanceof JsonNumberValue && Number.isSafeInteger(value.value) && value.value >= 0) {
    return value.value;
  }
  return undefined;
}

function readOptionalBoolean(body: string, field: string): boolean | undefined {
  const value = readField(body, field);
  return value instanceof JsonBooleanValue ? value.value : undefined;
}

function readField(body: string, field: string): JsonValue | undefined {
  let parsed: JsonValue | undefined;
  try {
    parsed = parseStrictJson(body);
  } catch (_error) {
    return undefined;
  }
  if (!(parsed instanceof JsonObjectValue)) {
    return undefined;
  }
  return parsed.get(field);
}
