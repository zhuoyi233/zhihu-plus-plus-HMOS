import { AppDestination } from 'core';
import { DailyStoryPayload, decodeDailyStoryDestination, decodeDailyStoryPayload } from '../domain/DailyStoryDetailDecoder';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';
import { DailyStoryRepository } from './DailyStoryRepository';

export const DAILY_STORY_DETAIL_BASE_URL = 'https://daily.zhihu.com/api/7/story';

export enum DailyStoryRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class DailyStoryRepositoryFailure extends Error {
  readonly kind: DailyStoryRepositoryFailureKind;

  constructor(kind: DailyStoryRepositoryFailureKind) {
    super(kind === DailyStoryRepositoryFailureKind.INVALID_ID ? '日报 ID 无效' : '日报正文请求已取消');
    this.name = 'DailyStoryRepositoryFailure';
    this.kind = kind;
  }
}

export function normalizeDailyStoryId(value: string): string {
  if (!/^[1-9][0-9]{0,29}$/.test(value)) {
    throw new DailyStoryRepositoryFailure(DailyStoryRepositoryFailureKind.INVALID_ID);
  }
  return value;
}

export function buildDailyStoryDetailUrl(storyId: string): string {
  return `${DAILY_STORY_DETAIL_BASE_URL}/${normalizeDailyStoryId(storyId)}`;
}

export class DefaultDailyStoryRepository implements DailyStoryRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  /**
   * 新链路正文入口：匿名、无 Cookie/ZSE、禁止重定向（沿用 ZhihuHttpClient 白名单与响应上限）；
   * 响应 ID 必须与请求 ID 一致，否则按解码失败处理，不展示其它日报的正文。
   */
  async getStory(storyId: string): Promise<DailyStoryPayload> {
    const normalized = normalizeDailyStoryId(storyId);
    const generation = this.generation;
    const response = await this.httpClient.execute({
      url: buildDailyStoryDetailUrl(normalized),
      accept: 'application/json'
    });
    if (generation !== this.generation) {
      throw new DailyStoryRepositoryFailure(DailyStoryRepositoryFailureKind.CANCELLED);
    }
    return decodeDailyStoryPayload(response.body, normalized);
  }

  async getDestination(storyId: string): Promise<AppDestination | undefined> {
    const generation = this.generation;
    const response = await this.httpClient.execute({
      url: buildDailyStoryDetailUrl(storyId),
      accept: 'application/json'
    });
    if (generation !== this.generation) {
      throw new DailyStoryRepositoryFailure(DailyStoryRepositoryFailureKind.CANCELLED);
    }
    return decodeDailyStoryDestination(response.body);
  }
}
