import { ChannelFeedPage, ChannelFeedSource } from '../domain/ChannelFeedModels';

export interface ChannelFeedRepository {
  loadPage(source: ChannelFeedSource, cursor?: string): Promise<ChannelFeedPage>;
  cancel(): void;
}
