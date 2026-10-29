import { describe, expect, it } from '@ohos/hypium';
import { AnswerPanePreparation } from '../main/ets/pages/AnswerPanePreparation';

export default function answerPanePreparationTest(): void {
  describe('answerPanePreparationTest', () => {
    it('waitsForBothParsingAndRestoredViewportInEitherOrder', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['a:1', 'b:2']);
      const first = preparation.wait('b:2');
      preparation.documentPrepared('b:2');
      expect(preparation.ready('b:2')).assertFalse();
      preparation.viewportPrepared('b:2', true);
      expect(await first).assertTrue();
      const other = preparation.wait('a:1');
      preparation.viewportPrepared('a:1', true);
      expect(preparation.ready('a:1')).assertFalse();
      preparation.documentPrepared('a:1');
      expect(await other).assertTrue();
      preparation.reset();
    });

    it('retainsPreparedInstanceWhenCandidateBecomesCurrent', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['a:1', 'b:2']);
      preparation.documentPrepared('b:2'); preparation.viewportPrepared('b:2', true);
      preparation.retain(['b:2']);
      expect(preparation.ready('b:2')).assertTrue();
      expect(await preparation.wait('b:2')).assertTrue();
      expect(preparation.has('a:1')).assertFalse();
      preparation.reset();
    });

    it('rejectsOldGenerationCallbacksForSameAnswer', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['a:1', 'b:2']);
      const old = preparation.wait('b:2');
      preparation.retain(['a:1', 'b:3']);
      expect(await old).assertFalse();
      expect(preparation.documentPrepared('b:2')).assertFalse();
      expect(preparation.viewportPrepared('b:2', true)).assertFalse();
      expect(preparation.ready('b:3')).assertFalse();
      const fresh = preparation.wait('b:3');
      preparation.documentPrepared('b:3'); preparation.viewportPrepared('b:3', true);
      expect(await fresh).assertTrue();
      preparation.reset();
    });

    it('resetUnblocksWaitAndDropsAllReadiness', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['b:2']);
      const waiting = preparation.wait('b:2');
      preparation.reset(); preparation.reset();
      expect(await waiting).assertFalse();
      expect(preparation.has('b:2')).assertFalse();
      expect(preparation.viewportPrepared('b:2', true)).assertFalse();
    });

    it('replacementWaitCancelsPreviousWaiter', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['b:2', 'c:3']);
      const old = preparation.wait('b:2');
      const next = preparation.wait('c:3');
      expect(await old).assertFalse();
      preparation.documentPrepared('c:3'); preparation.viewportPrepared('c:3', true);
      expect(await next).assertTrue();
      preparation.reset();
    });

    it('viewportInvalidationRequiresFreshLayout', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['b:2']);
      preparation.documentPrepared('b:2'); preparation.viewportPrepared('b:2', true);
      preparation.viewportPrepared('b:2', false);
      expect(preparation.ready('b:2')).assertFalse();
      const waiting = preparation.wait('b:2');
      preparation.viewportPrepared('b:2', true);
      expect(await waiting).assertTrue();
      preparation.reset();
    });

    it('timeoutAndCancelCannotLeaveAwaitingGestureLocked', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['b:2']);
      expect(await preparation.wait('b:2', 1)).assertFalse();
      const retry = preparation.wait('b:2');
      preparation.cancelWait();
      expect(await retry).assertFalse();
      preparation.documentPrepared('b:2'); preparation.viewportPrepared('b:2', true);
      expect(await preparation.wait('b:2')).assertTrue();
      preparation.reset();
    });

    it('currentDocumentCallbacksCannotCompleteCandidateWait', 0, async () => {
      const preparation = new AnswerPanePreparation();
      preparation.retain(['a:1', 'b:2']);
      preparation.documentPrepared('a:1'); preparation.viewportPrepared('a:1', true);
      expect(preparation.ready('b:2')).assertFalse();
      expect(await preparation.wait('not-mounted', 1)).assertFalse();
      preparation.reset();
    });
  });
}
