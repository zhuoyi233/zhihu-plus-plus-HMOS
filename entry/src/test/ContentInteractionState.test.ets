import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDetailKind,
  ContentVoteState,
  FollowMutationResult,
  FollowRepository,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus,
  VoteRepository,
  ContentVoteResult,
  ContentThankResult
} from 'data';
import {
  ContentVoteController,
  FollowController,
  INTERACTION_FAILED_MESSAGE,
  INTERACTION_LOGIN_REQUIRED_MESSAGE
} from '../main/ets/pages/ContentInteractionState';
import { LoadedContentDetail } from '../main/ets/pages/ContentDetailState';

class UnusedSessionOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

interface VoteCallRecord {
  id: string;
  state: ContentVoteState;
}

interface ThankCallRecord {
  id: string;
  thanked: boolean;
}

interface FollowCallRecord {
  identifier: string;
  follow: boolean;
}

class FixedSessionGateway implements LoginSessionGateway {
  private state: SessionState;

  constructor(status: SessionStatus) {
    this.state = {
      status: status,
      message: status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED
    };
  }

  getState(): SessionState {
    return {
      status: this.state.status,
      message: this.state.message,
      hasRetainedCredentials: this.state.hasRetainedCredentials
    };
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new UnusedSessionOperation(this.getState());
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new UnusedSessionOperation(this.getState());
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }
}

class FakeVoteRepository implements VoteRepository {
  readonly voteCalls: Array<VoteCallRecord> = [];
  readonly thankCalls: Array<ThankCallRecord> = [];
  voteResult: ContentVoteResult = {};
  thankResult: ContentThankResult = {};
  voteFailure?: HttpFailure;
  thankFailure?: HttpFailure;
  cancelCount: number = 0;

  async voteAnswer(id: string, state: ContentVoteState): Promise<ContentVoteResult> {
    this.voteCalls.push({ id: id, state: state });
    if (this.voteFailure !== undefined) {
      throw this.voteFailure;
    }
    return this.voteResult;
  }

  async voteArticle(id: string, state: ContentVoteState): Promise<ContentVoteResult> {
    this.voteCalls.push({ id: id, state: state });
    if (this.voteFailure !== undefined) {
      throw this.voteFailure;
    }
    return this.voteResult;
  }

  async thankAnswer(id: string, thanked: boolean): Promise<ContentThankResult> {
    this.thankCalls.push({ id: id, thanked: thanked });
    if (this.thankFailure !== undefined) {
      throw this.thankFailure;
    }
    return this.thankResult;
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class FakeFollowRepository implements FollowRepository {
  readonly calls: Array<FollowCallRecord> = [];
  result: FollowMutationResult = {};
  failure?: HttpFailure;
  cancelCount: number = 0;

  async followUser(urlToken: string, follow: boolean): Promise<FollowMutationResult> {
    this.calls.push({ identifier: urlToken, follow: follow });
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return this.result;
  }

  async followQuestion(id: string, follow: boolean): Promise<FollowMutationResult> {
    this.calls.push({ identifier: id, follow: follow });
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return this.result;
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

export default function contentInteractionStateTest(): void {
  describe('contentInteractionStateTest', () => {
    it('appliesInitialVoteStateFromLoadedAnswer', 0, () => {
      const repository = new FakeVoteRepository();
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.UP, 10, true, 3));

      const state = controller.snapshot();
      expect(state.voteState).assertEqual(ContentVoteState.UP);
      expect(state.voteupCount).assertEqual(10);
      expect(state.thanked).assertTrue();
      expect(state.thanksCount).assertEqual(3);
      expect(state.pending).assertFalse();
    });

    it('optimisticallyVotesUpAndAppliesServerCountOnSuccess', 0, async () => {
      const repository = new FakeVoteRepository();
      repository.voteResult = { voteupCount: 42 };
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.NEUTRAL, 10, false, 0));

      const pending = controller.toggleVote(true);
      const optimistic = controller.snapshot();
      expect(optimistic.voteState).assertEqual(ContentVoteState.UP);
      expect(optimistic.voteupCount).assertEqual(11);
      expect(optimistic.pending).assertTrue();

      await pending;
      const settled = controller.snapshot();
      expect(settled.voteState).assertEqual(ContentVoteState.UP);
      expect(settled.voteupCount).assertEqual(42);
      expect(settled.pending).assertFalse();
      expect(repository.voteCalls.length).assertEqual(1);
      expect(repository.voteCalls[0].state).assertEqual(ContentVoteState.UP);
    });

    it('rollsBackVoteOnFailureWithFixedMessage', 0, async () => {
      const repository = new FakeVoteRepository();
      repository.voteFailure = new HttpFailure(HttpFailureKind.SERVER, 500);
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ARTICLE, '3'
      );
      controller.activate();
      controller.applyInitial(articleContent(ContentVoteState.NEUTRAL, 20, false, 0));

      await controller.toggleVote(true);
      const state = controller.snapshot();
      expect(state.voteState).assertEqual(ContentVoteState.NEUTRAL);
      expect(state.voteupCount).assertEqual(20);
      expect(state.pending).assertFalse();
      expect(state.errorMessage).assertEqual(INTERACTION_FAILED_MESSAGE);
      expect(state.requiresLogin).assertFalse();
    });

    it('gatesVoteBehindLoginWithoutSendingRequest', 0, async () => {
      const repository = new FakeVoteRepository();
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.GUEST),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.NEUTRAL, 10, false, 0));

      await controller.toggleVote(true);
      const state = controller.snapshot();
      expect(state.requiresLogin).assertTrue();
      expect(state.errorMessage).assertEqual(INTERACTION_LOGIN_REQUIRED_MESSAGE);
      expect(repository.voteCalls.length).assertEqual(0);
    });

    it('treats401AsLoginRequiredAndRollsBack', 0, async () => {
      const repository = new FakeVoteRepository();
      repository.voteFailure = new HttpFailure(HttpFailureKind.AUTHENTICATION, 401);
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.UP, 10, false, 0));

      await controller.toggleVote(false);
      const state = controller.snapshot();
      expect(state.voteState).assertEqual(ContentVoteState.UP);
      expect(state.voteupCount).assertEqual(10);
      expect(state.requiresLogin).assertTrue();
      expect(state.errorMessage).assertEqual(INTERACTION_LOGIN_REQUIRED_MESSAGE);
    });

    it('togglesThankOptimisticallyAndRollsBackOnFailure', 0, async () => {
      const repository = new FakeVoteRepository();
      repository.thankResult = { thanksCount: 7, thanked: true };
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.NEUTRAL, 10, false, 0));

      const pending = controller.toggleThanks();
      const optimistic = controller.snapshot();
      expect(optimistic.thanked).assertTrue();
      expect(optimistic.thanksCount).assertEqual(1);
      await pending;
      const settled = controller.snapshot();
      expect(settled.thanked).assertTrue();
      expect(settled.thanksCount).assertEqual(7);
      expect(repository.thankCalls.length).assertEqual(1);
      expect(repository.thankCalls[0].thanked).assertTrue();

      repository.thankFailure = new HttpFailure(HttpFailureKind.NETWORK);
      await controller.toggleThanks();
      const rolledBack = controller.snapshot();
      expect(rolledBack.thanked).assertTrue();
      expect(rolledBack.thanksCount).assertEqual(7);
      expect(rolledBack.errorMessage).assertEqual(INTERACTION_FAILED_MESSAGE);
    });

    it('ignoresVoteWhilePendingAndKeepsSingleRequest', 0, async () => {
      const repository = new FakeVoteRepository();
      repository.voteResult = { voteupCount: 42 };
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.NEUTRAL, 10, false, 0));

      const first = controller.toggleVote(true);
      const second = controller.toggleVote(false);
      const third = controller.toggleThanks();
      await first;
      await second;
      await third;
      expect(repository.voteCalls.length).assertEqual(1);
      expect(repository.thankCalls.length).assertEqual(0);
      expect(controller.snapshot().voteupCount).assertEqual(42);
    });

    it('ignoresLateResultsAfterDeactivate', 0, async () => {
      const repository = new FakeVoteRepository();
      repository.voteResult = { voteupCount: 42 };
      const controller = new ContentVoteController(
        repository, new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        ContentDetailKind.ANSWER, '2'
      );
      controller.activate();
      controller.applyInitial(answerContent(ContentVoteState.NEUTRAL, 10, false, 0));

      const pending = controller.toggleVote(true);
      controller.deactivate();
      await pending;

      expect(repository.cancelCount).assertEqual(1);
      expect(controller.snapshot().voteupCount).assertEqual(11);
      expect(controller.snapshot().pending).assertTrue();
    });

    it('followsOptimisticallyAndRollsBackOnFailure', 0, async () => {
      const repository = new FakeFollowRepository();
      repository.result = { followerCount: 99 };
      const controller = new FollowController(
        repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED),
        (follow: boolean): Promise<FollowMutationResult> => repository.followUser('alice-token', follow)
      );
      controller.activate();
      controller.applyInitial(false, 5);

      const pending = controller.toggleFollow();
      const optimistic = controller.snapshot();
      expect(optimistic.following).assertTrue();
      expect(optimistic.followerCount).assertEqual(6);
      expect(optimistic.pending).assertTrue();
      await pending;
      const settled = controller.snapshot();
      expect(settled.following).assertTrue();
      expect(settled.followerCount).assertEqual(99);
      expect(settled.pending).assertFalse();

      repository.failure = new HttpFailure(HttpFailureKind.SERVER, 500);
      await controller.toggleFollow();
      const rolledBack = controller.snapshot();
      expect(rolledBack.following).assertTrue();
      expect(rolledBack.followerCount).assertEqual(99);
      expect(rolledBack.errorMessage).assertEqual(INTERACTION_FAILED_MESSAGE);

      expect(repository.calls.length).assertEqual(2);
      expect(repository.calls[0].follow).assertTrue();
      expect(repository.calls[1].follow).assertFalse();
    });

    it('gatesQuestionFollowBehindLoginWithoutSendingRequest', 0, async () => {
      const repository = new FakeFollowRepository();
      const controller = new FollowController(
        repository,
        new FixedSessionGateway(SessionStatus.GUEST),
        (follow: boolean): Promise<FollowMutationResult> => repository.followQuestion('123', follow)
      );
      controller.activate();
      controller.applyInitial(false, 8);

      await controller.toggleFollow();
      const state = controller.snapshot();
      expect(state.requiresLogin).assertTrue();
      expect(state.errorMessage).assertEqual(INTERACTION_LOGIN_REQUIRED_MESSAGE);
      expect(repository.calls.length).assertEqual(0);
    });
  });
}

function answerContent(voteState: ContentVoteState, voteupCount: number, thanked: boolean,
  thanksCount: number): LoadedContentDetail {
  return {
    kind: ContentDetailKind.ANSWER,
    value: {
      id: '2',
      questionId: '1',
      contentHtml: '<p>正文</p>',
      excerpt: '摘要',
      url: 'https://www.zhihu.com/question/1/answer/2',
      voteupCount: voteupCount,
      commentCount: 2,
      createdAt: 1,
      updatedAt: 2,
      voteState: voteState,
      thanksCount: thanksCount,
      isThanked: thanked
    }
  };
}

function articleContent(voteState: ContentVoteState, voteupCount: number, thanked: boolean,
  thanksCount: number): LoadedContentDetail {
  return {
    kind: ContentDetailKind.ARTICLE,
    value: {
      id: '3',
      title: '文章',
      contentHtml: '<p>正文</p>',
      excerpt: '摘要',
      url: 'https://zhuanlan.zhihu.com/p/3',
      voteupCount: voteupCount,
      commentCount: 2,
      createdAt: 1,
      updatedAt: 2,
      voteState: voteState,
      thanksCount: thanksCount,
      isThanked: thanked
    }
  };
}
