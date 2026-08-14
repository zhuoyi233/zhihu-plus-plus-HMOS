import { describe, expect, it } from '@ohos/hypium';
import {
  CommentContentKind,
  CommentItem,
  CommentPage,
  CommentRepository,
  CommentSortOrder,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus,
  SubmitCommentInput
} from 'data';
import {
  CommentController,
  CommentPhase,
  mergeComments
} from '../main/ets/pages/CommentState';

const ROOT_CURSOR =
  'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score&limit=20&offset=20';

class UnusedLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class TestSessionGateway implements LoginSessionGateway {
  private status: SessionStatus;

  constructor(status: SessionStatus) {
    this.status = status;
  }

  setStatus(status: SessionStatus): void {
    this.status = status;
  }

  getState(): SessionState {
    return {
      status: this.status,
      message: this.status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: this.status === SessionStatus.AUTHENTICATED,
      profile: this.status === SessionStatus.AUTHENTICATED ? {
        id: 'user-1',
        name: '测试用户',
        urlToken: 'alice-token',
        userType: 'people',
        avatarUrl: undefined
      } : undefined
    };
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new UnusedLoginOperation(this.getState());
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new UnusedLoginOperation(this.getState());
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }
}

interface RootRequestRecord {
  orderBy?: CommentSortOrder;
  cursor?: string;
}

interface LikedRecord {
  id: string;
  liked: boolean;
}

class ControlledCommentRepository implements CommentRepository {
  readonly rootRequests: Array<RootRequestRecord> = [];
  readonly childRequests: Array<string | undefined> = [];
  readonly submitted: Array<SubmitCommentInput> = [];
  readonly deleted: Array<string> = [];
  readonly liked: Array<LikedRecord> = [];
  cancelCount: number = 0;
  failRoot: boolean = false;
  failChild: boolean = false;
  failSubmit: boolean = false;
  failDelete: boolean = false;
  failLike: boolean = false;
  private rootPage?: CommentPage;
  private childPage?: CommentPage;

  setRootPage(page: CommentPage): void {
    this.rootPage = page;
  }

  setChildPage(page: CommentPage): void {
    this.childPage = page;
  }

  getRootCommentsPage(_contentType: string, _contentId: string, orderBy?: CommentSortOrder,
    cursor?: string): Promise<CommentPage> {
    this.rootRequests.push({ orderBy: orderBy, cursor: cursor });
    if (this.failRoot) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.rootPage ?? emptyPage());
  }

  getChildCommentsPage(_rootCommentId: string, cursor?: string): Promise<CommentPage> {
    this.childRequests.push(cursor);
    if (this.failChild) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.childPage ?? emptyPage());
  }

  submitComment(input: SubmitCommentInput): Promise<CommentItem> {
    this.submitted.push(input);
    if (this.failSubmit) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(comment('5001', '新评论', true));
  }

  deleteComment(commentId: string): Promise<void> {
    this.deleted.push(commentId);
    if (this.failDelete) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  likeComment(commentId: string, liked: boolean): Promise<void> {
    this.liked.push({ id: commentId, liked: liked });
    if (this.failLike) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

function comment(id: string, name: string, isAuthor: boolean = false): CommentItem {
  return {
    id: id,
    contentHtml: `<p>评论 ${id}</p>`,
    createdAt: 1700000000,
    liked: false,
    likeCount: 3,
    collapsed: false,
    reviewing: false,
    isDelete: false,
    isAuthor: isAuthor,
    isAuthorTop: false,
    author: { id: `user-${id}`, urlToken: `u${id}`, name: name, avatarUrl: '', headline: '' },
    commentTags: [],
    childCommentCount: 0,
    childComments: []
  };
}

function emptyPage(): CommentPage {
  return {
    items: [],
    cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
  };
}

export default function commentStateTest(): void {
  describe('commentStateTest', () => {
    it('requiresLoginAndOffersLoginWhenGuest', 0, async () => {
      const repository = new ControlledCommentRepository();
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.GUEST));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CommentPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(repository.rootRequests.length).assertEqual(0);
    });

    it('loadsRootCommentsAndDeduplicatesItems', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三'), comment('1', '张三'), comment('2', '李四')],
        cursor: { isEnd: false, isStart: true, next: ROOT_CURSOR, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(repository.rootRequests[0].orderBy).assertEqual(CommentSortOrder.SCORE);
      expect(repository.rootRequests[0].cursor).assertUndefined();
      expect(controller.snapshot().phase).assertEqual(CommentPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().canLoadMore).assertTrue();
    });

    it('loadsMoreWithCursorAndMergesWithoutDuplicates', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三'), comment('2', '李四')],
        cursor: { isEnd: false, isStart: true, next: ROOT_CURSOR, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setRootPage({
        items: [comment('2', '李四'), comment('3', '王五')],
        cursor: { isEnd: true, isStart: false, page: 0, total: 0 }
      });
      await controller.loadMore();
      expect(repository.rootRequests[1].cursor).assertEqual(ROOT_CURSOR);
      expect(controller.snapshot().items.length).assertEqual(3);
      expect(controller.snapshot().canLoadMore).assertFalse();
    });

    it('mapsNetworkFailureToErrorPhaseAndRetries', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.failRoot = true;
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CommentPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertFalse();
      repository.failRoot = false;
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      await controller.retry();
      expect(controller.snapshot().phase).assertEqual(CommentPhase.READY);
    });

    it('switchesSortOrderAndReloads', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(repository.rootRequests.length).assertEqual(1);
      await controller.changeSortOrder(CommentSortOrder.TIME);
      expect(repository.rootRequests.length).assertEqual(2);
      expect(repository.rootRequests[1].orderBy).assertEqual(CommentSortOrder.TIME);
      await controller.changeSortOrder(CommentSortOrder.TIME);
      expect(repository.rootRequests.length).assertEqual(2);
    });

    it('opensAndClosesChildCommentsPreservingRootList', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setChildPage({
        items: [comment('10', '子一'), comment('11', '子二')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      await controller.openChildComments(comment('1', '张三'));
      expect(controller.snapshot().activeRoot?.id).assertEqual('1');
      expect(repository.childRequests[0]).assertUndefined();
      expect(controller.snapshot().items.length).assertEqual(2);
      controller.closeChildComments();
      expect(controller.snapshot().activeRoot).assertUndefined();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().items[0].id).assertEqual('1');
    });

    it('submitsRootCommentPrependsAndClearsReplyTarget', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      const submitted = await controller.submitComment('新评论内容');
      expect(submitted).assertTrue();
      expect(repository.submitted.length).assertEqual(1);
      expect(repository.submitted[0].content).assertEqual('新评论内容');
      expect(repository.submitted[0].replyToCommentId).assertUndefined();
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().items[0].id).assertEqual('5001');
      expect(controller.snapshot().submitting).assertFalse();
    });

    it('rejectsBlankCommentWithoutNetworkCall', 0, async () => {
      const repository = new ControlledCommentRepository();
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      const submitted = await controller.submitComment('   ');
      expect(submitted).assertFalse();
      expect(repository.submitted.length).assertEqual(0);
    });

    it('submitsReplyToRootWithReplyTarget', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三'), comment('2', '李四')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      controller.setReplyTarget(comment('2', '李四'));
      const submitted = await controller.submitComment('回复内容');
      expect(submitted).assertTrue();
      expect(repository.submitted[0].replyToCommentId).assertEqual('2');
      expect(controller.snapshot().replyTarget).assertUndefined();
    });

    it('submitsReplyToChildInChildMode', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setChildPage({
        items: [comment('10', '子一')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      await controller.openChildComments(comment('1', '张三'));
      controller.setReplyTarget(comment('10', '子一'));
      const submitted = await controller.submitComment('子回复');
      expect(submitted).assertTrue();
      expect(repository.submitted[0].replyToCommentId).assertEqual('10');
      expect(controller.snapshot().items[0].id).assertEqual('5001');
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('submissionFailureShowsErrorWithoutMutatingList', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.failSubmit = true;
      const submitted = await controller.submitComment('内容');
      expect(submitted).assertFalse();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().actionMessage).assertEqual('评论发送失败，请重试');
      expect(controller.snapshot().submitting).assertFalse();
    });

    it('deletesOwnCommentOptimisticallyAndRollsBackOnFailure', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三', true), comment('2', '李四', true)],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();

      repository.failDelete = true;
      const failed = await controller.deleteComment('1');
      expect(failed).assertFalse();
      expect(repository.deleted[0]).assertEqual('1');
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().items[0].id).assertEqual('1');

      repository.failDelete = false;
      const removed = await controller.deleteComment('2');
      expect(removed).assertTrue();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().items[0].id).assertEqual('1');
    });

    it('togglesLikeOptimisticallyAndRollsBackOnFailure', 0, async () => {
      const repository = new ControlledCommentRepository();
      repository.setRootPage({
        items: [comment('1', '张三')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository,
        new TestSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();

      await controller.toggleLike(controller.snapshot().items[0]);
      expect(controller.snapshot().items[0].liked).assertTrue();
      expect(controller.snapshot().items[0].likeCount).assertEqual(4);
      expect(repository.liked.length).assertEqual(1);
      expect(repository.liked[0].liked).assertTrue();
      expect(repository.liked[0].id).assertEqual('1');

      repository.failLike = true;
      await controller.toggleLike(controller.snapshot().items[0]);
      expect(controller.snapshot().items[0].liked).assertTrue();
      expect(controller.snapshot().items[0].likeCount).assertEqual(4);
      expect(controller.snapshot().actionMessage).assertEqual('点赞操作失败，请重试');
      expect(controller.snapshot().likeBusy).assertFalse();
    });

    it('loginGateBlocksInteractionsForGuest', 0, async () => {
      const repository = new ControlledCommentRepository();
      const session = new TestSessionGateway(SessionStatus.AUTHENTICATED);
      repository.setRootPage({
        items: [comment('1', '张三', true)],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CommentController(CommentContentKind.ANSWER, '456', repository, session);
      controller.activate();
      await controller.loadInitial();
      session.setStatus(SessionStatus.GUEST);

      const submitted = await controller.submitComment('内容');
      expect(submitted).assertFalse();
      expect(repository.submitted.length).assertEqual(0);
      expect(controller.snapshot().actionRequiresLogin).assertTrue();

      controller.setReplyTarget(undefined);
      await controller.toggleLike(controller.snapshot().items[0]);
      expect(repository.liked.length).assertEqual(0);
      expect(controller.snapshot().actionRequiresLogin).assertTrue();

      const deleted = await controller.deleteComment('1');
      expect(deleted).assertFalse();
      expect(repository.deleted.length).assertEqual(0);
    });

    it('mergesCommentsDeduplicatedByIdentity', 0, () => {
      const merged = mergeComments([comment('1', 'a'), comment('2', 'b')],
        [comment('2', 'b'), comment('3', 'c')]);
      expect(merged.length).assertEqual(3);
      expect(merged[0].id).assertEqual('1');
      expect(merged[1].id).assertEqual('2');
      expect(merged[2].id).assertEqual('3');
    });
  });
}
