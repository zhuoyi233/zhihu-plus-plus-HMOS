import { ChannelFeedPage, ChannelFeedSource } from '../domain/ChannelFeedModels';

export interface ChannelFeedRepository {
  /**
   * `reset` 仅用于日报的日期跳转：目标日期必须作为首个游标重新读取，
   * 不能和当前列表的分页去重集合混用。
   */
  loadPage(source: ChannelFeedSource, cursor?: string, reset?: boolean): Promise<ChannelFeedPage>;
  cancel(): void;
}
