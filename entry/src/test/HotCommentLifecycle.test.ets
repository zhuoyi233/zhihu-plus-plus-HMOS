import { describe, expect, it } from '@ohos/hypium';
import { CommentItem, CommentPage, CommentRepository, CommentSortOrder, SubmitCommentInput } from 'data';
import { HotCommentController, HotCommentPhase, HotCommentViewState } from '../main/ets/pages/HotCommentState';

class PendingComments implements CommentRepository {
  cancelCount: number = 0;
  requestedId: string = '';
  private resolvePage: (page: CommentPage) => void = (): void => {};
  private rejectPage: (error: Error) => void = (): void => {};
  getRootCommentsPage(_type: string, id: string, _sort?: CommentSortOrder): Promise<CommentPage> {
    this.requestedId = id;
    return new Promise<CommentPage>((resolve, reject): void => {
      this.resolvePage = resolve;
      this.rejectPage = reject;
    });
  }
  complete(items: Array<CommentItem> = []): void {
    this.resolvePage({ items: items, cursor: { isEnd: true, isStart: true, page: 1, total: items.length } });
  }
  fail(): void { this.rejectPage(new Error('network')); }
  cancel(): void { this.cancelCount += 1; }
  getChildCommentsPage(_id: string): Promise<CommentPage> { return Promise.reject(new Error('unused')); }
  submitComment(_input: SubmitCommentInput): Promise<CommentItem> { return Promise.reject(new Error('unused')); }
  deleteComment(_id: string): Promise<void> { return Promise.reject(new Error('unused')); }
  likeComment(_id: string, _liked: boolean): Promise<void> { return Promise.reject(new Error('unused')); }
}

class HotFixture {
  requests: Array<PendingComments> = [];
  state: HotCommentViewState = { answerId: '', phase: HotCommentPhase.IDLE, comments: [] };
  controller: HotCommentController = new HotCommentController((): CommentRepository => {
    const request = new PendingComments();
    this.requests.push(request);
    return request;
  }, (state: HotCommentViewState): void => { this.state = state; });
}

export default function hotCommentLifecycleTest(): void {
  describe('hotCommentLifecycleTest', () => {
    it('distinguishesLoadingEmptyAndFailureAndAllowsRetry', 0, async () => {
      const f = new HotFixture();
      const first = f.controller.load('1', '1:1', 'user');
      expect(f.state.phase).assertEqual(HotCommentPhase.LOADING);
      f.requests[0].fail(); await first;
      expect(f.state.phase).assertEqual(HotCommentPhase.ERROR);
      const retry = f.controller.load('1', '1:1', 'user', true);
      expect(f.requests.length).assertEqual(2);
      f.requests[1].complete(); await retry;
      expect(f.state.phase).assertEqual(HotCommentPhase.EMPTY);
    });

    it('sameDocumentNotificationsDoNotRefetchButNewGenerationDoes', 0, async () => {
      const f = new HotFixture();
      const first = f.controller.load('1', '1:1', 'user');
      await f.controller.load('1', '1:1', 'user');
      expect(f.requests.length).assertEqual(1);
      const refreshed = f.controller.load('1', '1:2', 'user');
      expect(f.requests[0].cancelCount).assertEqual(1);
      f.requests[0].complete(); await first;
      expect(f.state.phase).assertEqual(HotCommentPhase.LOADING);
      f.requests[1].complete(); await refreshed;
      expect(f.state.phase).assertEqual(HotCommentPhase.EMPTY);
    });

    it('rejectsOldAAfterSwitchingAToBToA', 0, async () => {
      const f = new HotFixture();
      const a1 = f.controller.load('1', '1:1', 'user');
      const b = f.controller.load('2', '2:2', 'user');
      const a2 = f.controller.load('1', '1:3', 'user');
      f.requests[0].fail(); f.requests[1].complete(); await a1; await b;
      expect(f.state.answerId).assertEqual('1');
      expect(f.state.phase).assertEqual(HotCommentPhase.LOADING);
      f.requests[2].complete(); await a2;
      expect(f.state.phase).assertEqual(HotCommentPhase.EMPTY);
    });

    it('accountChangeCannotAcceptOldAccountEvenForSameDocument', 0, async () => {
      const f = new HotFixture();
      const old = f.controller.load('1', '1:1', 'account-a');
      const current = f.controller.load('1', '1:1', 'account-b');
      f.requests[1].complete(); await current;
      f.requests[0].fail(); await old;
      expect(f.state.phase).assertEqual(HotCommentPhase.EMPTY);
      expect(f.requests[0].cancelCount).assertEqual(1);
    });

    it('resetOnCloseOrDisableDiscardsLateSuccessAndReopensFresh', 0, async () => {
      const f = new HotFixture();
      const old = f.controller.load('1', '1:1', 'user');
      f.controller.reset(); f.controller.reset();
      f.requests[0].complete(); await old;
      expect(f.state.phase).assertEqual(HotCommentPhase.IDLE);
      expect(f.requests[0].cancelCount).assertEqual(1);
      const reopened = f.controller.load('1', '1:1', 'user');
      expect(f.requests.length).assertEqual(2);
      f.requests[1].complete(); await reopened;
      expect(f.state.phase).assertEqual(HotCommentPhase.EMPTY);
    });

    it('retryCancelsOnlyItsPendingRequestAndIgnoresLateFailure', 0, async () => {
      const f = new HotFixture();
      const first = f.controller.load('1', '1:1', 'user');
      const retry = f.controller.load('1', '1:1', 'user', true);
      f.requests[0].fail(); await first;
      expect(f.state.phase).assertEqual(HotCommentPhase.LOADING);
      f.requests[1].complete(); await retry;
      f.controller.reset();
      expect(f.requests[1].cancelCount).assertEqual(0);
    });

    it('missingRepositoryIsFailureRatherThanEmptyAndCanRetry', 0, async () => {
      const controller = new HotCommentController((): CommentRepository | undefined => undefined,
        (_state: HotCommentViewState): void => {});
      await controller.load('1', '1:1', 'user');
      expect(controller.snapshot().phase).assertEqual(HotCommentPhase.ERROR);
      await controller.load('1', '1:1', 'user', true);
      expect(controller.snapshot().phase).assertEqual(HotCommentPhase.ERROR);
    });
  });
}
