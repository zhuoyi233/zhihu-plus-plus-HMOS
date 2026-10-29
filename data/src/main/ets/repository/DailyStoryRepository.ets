import { AppDestination } from 'core';
import { DailyStoryPayload } from '../domain/DailyStoryDetailDecoder';

/**
 * 日报正文仓库。
 *
 * `getStory` 是新链路（原生日报页）的唯一正文入口：一次打开只发一次正文请求，
 * 返回载荷同时携带原文目标，调用方不再先 `getDestination` 再取正文。
 * `getDestination` 保留给关闭新链路时的旧列表直跳路径。
 */
export interface DailyStoryRepository {
  getStory(storyId: string): Promise<DailyStoryPayload>;
  getDestination(storyId: string): Promise<AppDestination | undefined>;
  cancel(): void;
}
