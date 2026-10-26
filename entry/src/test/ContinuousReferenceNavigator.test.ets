import { describe, expect, it } from '@ohos/hypium';
import {
  ContinuousReferenceHost, ContinuousReferenceNavigator, ContinuousReferenceRect
} from '../main/ets/pages/ContinuousReferenceNavigator';

class LazyReferenceHost implements ContinuousReferenceHost {
  keys: Array<string> = ['a:source', 'a:ref', 'b:source', 'b:ref'];
  visibleKey: string = 'a:source';
  y: number = 250;
  height: number = 400;
  viewport: number = 800;
  sourceHeight: number = 400;
  jumps: Array<string> = [];
  moves: number = 0;
  indexOf(key: string): number { return this.keys.indexOf(key); }
  rectAt(index: number): ContinuousReferenceRect {
    return { y: this.y, height: this.keys[index] === this.visibleKey ? this.height : 0 };
  }
  scrollToRow(index: number): void {
    this.visibleKey = this.keys[index];
    this.jumps.push(this.visibleKey);
    this.y = 116;
    this.height = this.visibleKey.endsWith('source') ? this.sourceHeight : 100;
  }
  scrollBy(delta: number): void { this.y -= delta; this.moves++; }
  viewportHeight(): number { return this.viewport; }
  readingLine(): number { return 116; }
  onSettled(): void {}
}

function waitForLayout(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 600); });
}

export default function continuousReferenceNavigatorTest(): void {
  describe('continuousReferenceNavigatorTest', () => {
    it('returnsToStableSourceAfterLazyIndicesAndBlockHeightChange', 0, async () => {
      const host = new LazyReferenceHost();
      host.y = -284;
      host.height = 800;
      const navigator = new ContinuousReferenceNavigator(host);
      navigator.open('a', 5, 'a:source', 'a:ref');
      await waitForLayout();
      host.keys.unshift('new:placeholder');
      host.sourceHeight = 1600;
      host.viewport = 1000;
      navigator.back('a', 5, '');
      await waitForLayout();
      expect(host.visibleKey).assertEqual('a:source');
      // 原阅读线位于块内 50%、视口内 14.5%；重排后仍保持同一相对位置。
      expect(Math.abs(host.y - (145 - 800)) < 1).assertTrue();
      expect(navigator.isNavigating()).assertFalse();
      navigator.clear();
    });

    it('keepsSameNumberedReferencesSeparateAcrossAnswers', 0, async () => {
      const host = new LazyReferenceHost();
      const navigator = new ContinuousReferenceNavigator(host);
      navigator.open('a', 1, 'a:source', 'a:ref');
      await waitForLayout();
      host.visibleKey = 'b:source';
      host.y = 350;
      host.height = 400;
      navigator.open('b', 1, 'b:source', 'b:ref');
      await waitForLayout();
      navigator.back('a', 1, '');
      await waitForLayout();
      expect(host.visibleKey).assertEqual('a:source');
      expect(host.y).assertEqual(250);
      navigator.clear();
    });

    it('fallsBackToTheMatchingBodyWhenNoReturnWasRecorded', 0, async () => {
      const host = new LazyReferenceHost();
      host.visibleKey = 'b:ref';
      const navigator = new ContinuousReferenceNavigator(host);
      navigator.back('b', 7, 'b:source');
      await waitForLayout();
      expect(host.visibleKey).assertEqual('b:source');
      expect(host.y).assertEqual(116);
      navigator.clear();
    });

    it('stopsDelayedCorrectionAndClearsOldSessionBookmarks', 0, async () => {
      const host = new LazyReferenceHost();
      const navigator = new ContinuousReferenceNavigator(host);
      navigator.open('a', 5, 'a:source', 'a:ref');
      navigator.cancel();
      host.y = 600;
      const moves = host.moves;
      await waitForLayout();
      expect(host.y).assertEqual(600);
      expect(host.moves).assertEqual(moves);
      navigator.clear();
      navigator.back('a', 5, '');
      expect(navigator.isNavigating()).assertFalse();
      expect(host.visibleKey).assertEqual('a:ref');
    });
  });
}
