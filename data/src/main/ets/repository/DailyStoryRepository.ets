import { P1Destination } from 'core';

export interface DailyStoryRepository {
  getDestination(storyId: string): Promise<P1Destination | undefined>;
  cancel(): void;
}
