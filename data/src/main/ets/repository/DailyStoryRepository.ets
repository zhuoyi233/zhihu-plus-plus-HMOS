import { AppDestination } from 'core';

export interface DailyStoryRepository {
  getDestination(storyId: string): Promise<AppDestination | undefined>;
  cancel(): void;
}
