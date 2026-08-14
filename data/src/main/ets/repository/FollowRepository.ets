export interface FollowMutationResult {
  /** 服务端返回的最新粉丝数；响应未提供时为 undefined，调用方沿用乐观值。 */
  readonly followerCount?: number;
}

export interface FollowRepository {
  /** 关注/取消关注用户（urlToken）。 */
  followUser(urlToken: string, follow: boolean): Promise<FollowMutationResult>;
  /** 关注/取消关注问题。 */
  followQuestion(id: string, follow: boolean): Promise<FollowMutationResult>;
  cancel(): void;
}
