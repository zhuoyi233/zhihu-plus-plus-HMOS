import {
  ContentRepository, DefaultContentRepository, DefaultFollowRepository, DefaultLinkCardMetaRepository,
  DefaultSegmentReactionRepository, DefaultVoteRepository, FollowRepository, LinkCardMetaRepository,
  SessionCookieProvider, VoteRepository, ZhihuHttpClient
} from 'data';

/** 每个连续阅读会话独占请求槽，账号失效时取消不会影响其他路由的新会话。 */
export class ContinuousAnswerRepositories {
  readonly question: ContentRepository;
  readonly answerA: ContentRepository;
  readonly answerB: ContentRepository;
  readonly vote: VoteRepository;
  readonly follow: FollowRepository;
  readonly segment: DefaultSegmentReactionRepository;
  readonly linkCard: DefaultLinkCardMetaRepository;

  constructor(session?: SessionCookieProvider) {
    this.question = new DefaultContentRepository(new ZhihuHttpClient(session));
    this.answerA = new DefaultContentRepository(new ZhihuHttpClient(session));
    this.answerB = new DefaultContentRepository(new ZhihuHttpClient(session));
    this.vote = new DefaultVoteRepository(new ZhihuHttpClient(session));
    this.follow = new DefaultFollowRepository(new ZhihuHttpClient(session));
    this.segment = new DefaultSegmentReactionRepository(new ZhihuHttpClient(session));
    this.linkCard = new DefaultLinkCardMetaRepository(new ZhihuHttpClient(session));
  }

  cancel(): void {
    this.question.cancel();
    this.answerA.cancel();
    this.answerB.cancel();
    this.vote.cancel();
    this.follow.cancel();
    this.segment.cancel();
    this.linkCard.cancel();
  }
}
