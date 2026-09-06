import { RecentFollowingUser } from '../domain/ChannelFeedModels';
import { decodeRecentFollowingUsers } from '../domain/ZhihuChannelFeedDecoder';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';
import { RecentFollowingUsersRepository } from './RecentFollowingUsersRepository';

export const RECENT_FOLLOWING_USERS_URL = 'https://api.zhihu.com/moments/recent?type=raw';

export class DefaultRecentFollowingUsersRepository implements RecentFollowingUsersRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async loadRecentUsers(): Promise<Array<RecentFollowingUser>> {
    const generation = this.generation;
    const response = await this.httpClient.execute({
      url: RECENT_FOLLOWING_USERS_URL,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (generation !== this.generation) {
      return [];
    }
    return decodeRecentFollowingUsers(response.body);
  }
}
