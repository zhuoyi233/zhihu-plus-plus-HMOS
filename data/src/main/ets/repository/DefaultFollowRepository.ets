import {
  JsonNumberValue,
  JsonObjectValue,
  JsonValue,
  parseStrictJson
} from 'core';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { normalizeContentId } from './DefaultContentRepository';
import { normalizePeopleIdentifier } from './DefaultPeopleRepository';
import { FollowMutationResult, FollowRepository } from './FollowRepository';

export enum FollowRepositoryFailureKind {
  INVALID_IDENTIFIER = 'invalid_identifier',
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class FollowRepositoryFailure extends Error {
  readonly kind: FollowRepositoryFailureKind;

  constructor(kind: FollowRepositoryFailureKind) {
    super(kind === FollowRepositoryFailureKind.INVALID_IDENTIFIER
      ? '用户标识无效'
      : kind === FollowRepositoryFailureKind.INVALID_ID ? '内容 ID 无效' : '关注请求已取消');
    this.name = 'FollowRepositoryFailure';
    this.kind = kind;
  }
}

export function buildMemberFollowUrl(urlToken: string): string {
  const identifier = normalizePeopleIdentifier(urlToken);
  return `https://www.zhihu.com/api/v4/members/${encodeURIComponent(identifier)}/followers`;
}

export function buildQuestionFollowUrl(id: string): string {
  return `https://www.zhihu.com/api/v4/questions/${normalizeContentId(id)}/followers`;
}

export class DefaultFollowRepository implements FollowRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async followUser(urlToken: string, follow: boolean): Promise<FollowMutationResult> {
    const response = await this.execute(
      buildMemberFollowUrl(urlToken),
      follow ? ZhihuHttpMethod.POST : ZhihuHttpMethod.DELETE
    );
    return { followerCount: readFollowerCount(response.body) };
  }

  async followQuestion(id: string, follow: boolean): Promise<FollowMutationResult> {
    const response = await this.execute(
      buildQuestionFollowUrl(id),
      follow ? ZhihuHttpMethod.POST : ZhihuHttpMethod.DELETE
    );
    return { followerCount: readFollowerCount(response.body) };
  }

  private async execute(url: string, method: ZhihuHttpMethod): Promise<ZhihuHttpResponse> {
    const requestGeneration = this.generation;
    const response = await this.httpClient.execute({
      url: url,
      method: method,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new FollowRepositoryFailure(FollowRepositoryFailureKind.CANCELLED);
    }
    return response;
  }
}

function readFollowerCount(body: string): number | undefined {
  let parsed: JsonValue | undefined;
  try {
    parsed = parseStrictJson(body);
  } catch (_error) {
    return undefined;
  }
  if (!(parsed instanceof JsonObjectValue)) {
    return undefined;
  }
  const value: JsonValue | undefined = parsed.get('follower_count');
  if (value instanceof JsonNumberValue && Number.isSafeInteger(value.value) && value.value >= 0) {
    return value.value;
  }
  return undefined;
}
