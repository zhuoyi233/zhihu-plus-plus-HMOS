import { RecentFollowingUser } from '../domain/ChannelFeedModels';

/** 关注推荐页顶部“最近更新的关注用户”一行，行为对齐上游 RecentMomentsViewModel。 */
export interface RecentFollowingUsersRepository {
  loadRecentUsers(): Promise<Array<RecentFollowingUser>>;
  cancel(): void;
}
