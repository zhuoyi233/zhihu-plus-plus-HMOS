import { describe, expect, it } from '@ohos/hypium';
import { AnswerTitleGeometry } from '../main/ets/pages/AnswerTitleGeometry';

export default function answerTitleGeometryTest(): void {
  describe('answerTitleGeometryTest', () => {
    it('restoresBodyMeasurementAfterOffscreenImmersiveRoundTrip', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('doc', 'body', 180);
      expect(geometry.resolve('doc', 'body', 400, 94, 94, false, true).compact).assertTrue();
      geometry.measure('doc', 'immersive', 40);
      geometry.resolve('doc', 'immersive', 400, 0, 0, false, true);
      const restored = geometry.resolve('doc', 'body', 400, 94, 94, false, true);
      expect(restored.compact).assertTrue();
      expect(restored.authorVisible).assertTrue();
      geometry.retain([]);
      expect(geometry.measured('doc', 'body')).assertFalse();
      expect(geometry.measured('doc', 'immersive')).assertFalse();
    });

    it('doesNotGuessIdentityBeforeLayout', 0, () => {
      const geometry = new AnswerTitleGeometry();
      const state = geometry.resolve('a:1', 'body', 900, 94, 94, false, true);
      expect(state.authorVisible).assertFalse();
      expect(state.compact).assertFalse();
    });
    it('waitsUntilBothTitleAndAuthorLeaveViewport', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 126);
      expect(geometry.resolve('a:1', 'body', 100, 94, 94, false, true).authorVisible).assertFalse();
      expect(geometry.resolve('a:1', 'body', 142, 94, 94, false, true).authorVisible).assertFalse();
      expect(geometry.resolve('a:1', 'body', 144, 94, 94, false, true).authorVisible).assertTrue();
    });
    it('separatesPersistentCompactionMaterialAndAuthor', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'persistent', 40);
      const slightly = geometry.resolve('a:1', 'persistent', 2, 94, 94, true, true);
      expect(slightly.materialVisible).assertTrue();
      expect(slightly.compact).assertFalse();
      expect(slightly.authorVisible).assertFalse();
      const compact = geometry.resolve('a:1', 'persistent', 10, 94, 94, true, true);
      expect(compact.compact).assertTrue(); expect(compact.authorVisible).assertFalse();
      expect(geometry.resolve('a:1', 'persistent', 58, 94, 94, true, true).authorVisible).assertTrue();
    });
    it('distinguishesAbsentAuthorFromUnmeasuredIdentity', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 56);
      const state = geometry.resolve('a:1', 'body', 80, 94, 94, false, false);
      expect(state.compact).assertTrue(); expect(state.authorVisible).assertFalse();
      geometry.measure('b:1', 'persistent', 0);
      expect(geometry.resolve('b:1', 'persistent', 18, 94, 94, true, false).authorVisible).assertFalse();
    });
    it('normalizesPaddingOnceAndUsesActualVisibleViewportTop', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 100);
      expect(geometry.resolve('a:1', 'body', 118, 94, 94, false, true).authorVisible).assertTrue();
      // 栏隐藏时同一身份区仍在阅读区内，不在隐藏状态中提前重复摘要。
      expect(geometry.resolve('a:1', 'body', 118, 94, 0, false, true).authorVisible).assertFalse();
      expect(geometry.resolve('a:1', 'body', 212, 94, 0, false, true).authorVisible).assertTrue();
    });
    it('hysteresisStaysOutsideVisibleIdentityAndResetsAtTop', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 100);
      expect(geometry.resolve('a:1', 'body', 118, 94, 94, false, true).authorVisible).assertTrue();
      expect(geometry.resolve('a:1', 'body', 117, 94, 94, false, true).authorVisible).assertTrue();
      expect(geometry.resolve('a:1', 'body', 115, 94, 94, false, true).authorVisible).assertFalse();
      expect(geometry.resolve('a:1', 'body', 117, 94, 94, false, true).authorVisible).assertFalse();
      expect(geometry.resolve('a:1', 'body', 0, 94, 94, false, true).compact).assertFalse();
    });
    it('remeasurementUpdatesWithoutAnotherScroll', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 60);
      expect(geometry.resolve('a:1', 'body', 100, 94, 94, false, true).authorVisible).assertTrue();
      geometry.measure('a:1', 'body', 150);
      expect(geometry.resolve('a:1', 'body', 100, 94, 94, false, true).authorVisible).assertFalse();
    });
    it('doesNotReuseWrongModeOrOldDocumentGeneration', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 60);
      expect(geometry.resolve('a:1', 'persistent', 100, 94, 94, true, true).authorVisible).assertFalse();
      expect(geometry.resolve('a:2', 'body', 100, 94, 94, false, true).authorVisible).assertFalse();
      geometry.retain(['a:2']);
      expect(geometry.resolve('a:1', 'body', 100, 94, 94, false, true).compact).assertFalse();
    });
    it('candidateRetainsOwnMeasurementAndPositionOnCommit', 0, () => {
      const geometry = new AnswerTitleGeometry();
      geometry.measure('a:1', 'body', 50); geometry.measure('b:2', 'body', 150);
      expect(geometry.resolve('a:1', 'body', 100, 94, 94, false, true).authorVisible).assertTrue();
      expect(geometry.resolve('b:2', 'body', 100, 94, 94, false, true).authorVisible).assertFalse();
      geometry.retain(['b:2']);
      expect(geometry.resolve('b:2', 'body', 168, 94, 94, false, true).authorVisible).assertTrue();
    });
  });
}
