import { describe, expect, it } from '@ohos/hypium';
import {
  clearAnswerEditSeed,
  stageAnswerEditSeed,
  takeAnswerEditSeed
} from '../main/ets/pages/AnswerEditSeedStore';

const ANSWER_ID: string = '701';
const ANSWER_HTML: string = '<p>只用于内存编辑种子</p>';

export default function answerEditSeedStoreTest(): void {
  describe('answerEditSeedStoreTest', () => {
    it('allowsOnlyMatchingAnswerToConsumeOneTransientSeed', 0, () => {
      clearAnswerEditSeed();

      expect(stageAnswerEditSeed(ANSWER_ID, ANSWER_HTML, true)).assertTrue();
      expect(takeAnswerEditSeed('702')).assertUndefined();
      const consumed = takeAnswerEditSeed(ANSWER_ID);

      expect(consumed === undefined).assertFalse();
      if (consumed !== undefined) {
        expect(consumed.answerId).assertEqual(ANSWER_ID);
        expect(consumed.html).assertEqual(ANSWER_HTML);
        expect(consumed.tocEnabled).assertTrue();
      }
      expect(takeAnswerEditSeed(ANSWER_ID)).assertUndefined();
    });

    it('clearsInvalidSeedInsteadOfRetainingUntrustedRouteValues', 0, () => {
      clearAnswerEditSeed();

      expect(stageAnswerEditSeed('not-an-id', ANSWER_HTML)).assertFalse();
      expect(takeAnswerEditSeed(ANSWER_ID)).assertUndefined();
      expect(stageAnswerEditSeed(ANSWER_ID, 'x'.repeat(1024 * 1024 + 1))).assertFalse();
      expect(takeAnswerEditSeed(ANSWER_ID)).assertUndefined();
    });
  });
}
