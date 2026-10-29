import { describe, expect, it } from '@ohos/hypium';
import { SystemBarVisibility, SystemBarVisibilityPort } from '../main/ets/platform/SystemBarVisibility';

class PendingSystemBarPort implements SystemBarVisibilityPort {
  calls: Array<boolean> = [];
  completions: Array<() => void> = [];
  failures: Array<(error: Error) => void> = [];
  throws: boolean = false;
  apply(hidden: boolean): Promise<void> {
    this.calls.push(hidden);
    if (this.throws) { throw new Error('window unavailable'); }
    return new Promise<void>((resolve, reject): void => {
      this.completions.push(resolve); this.failures.push(reject);
    });
  }
}
async function settle(): Promise<void> { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); }

export default function systemBarVisibilityTest(): void {
  describe('systemBarVisibilityTest', () => {
    it('deduplicatesOnlyAfterSuccess', 0, async () => {
      const port = new PendingSystemBarPort(); let shown = 0;
      const state = new SystemBarVisibility((): void => { shown += 1; });
      state.bind(port); state.request(false);
      expect(port.calls.length).assertEqual(1);
      expect(state.isShown()).assertFalse();
      port.completions[0](); await settle(); state.request(false);
      expect(port.calls.length).assertEqual(1); expect(shown).assertEqual(1);
      expect(state.isShown()).assertTrue();
    });
    it('retriesSameTargetAfterRejectedOrSynchronousFailure', 0, async () => {
      const port = new PendingSystemBarPort(); const state = new SystemBarVisibility((): void => {});
      state.bind(port); port.failures[0](new Error('failed')); await settle();
      state.request(false); expect(port.calls.length).assertEqual(2);
      port.failures[1](new Error('failed')); await settle(); port.throws = true;
      state.request(false); expect(port.calls.length).assertEqual(3);
      port.throws = false; state.request(false); expect(port.calls.length).assertEqual(4);
      port.completions[2](); await settle(); expect(state.isShown()).assertTrue();
    });
    it('serializesRapidHideAndShowAndDropsIntermediateTargets', 0, async () => {
      const port = new PendingSystemBarPort(); let shown = 0;
      const state = new SystemBarVisibility((): void => { shown += 1; }); state.bind(port);
      state.request(true); state.request(false); state.request(true);
      expect(port.calls.length).assertEqual(1); port.completions[0](); await settle();
      expect(port.calls.length).assertEqual(2); expect(port.calls[1]).assertTrue();
      expect(shown).assertEqual(0); state.request(false);
      port.completions[1](); await settle(); expect(port.calls[2]).assertFalse();
      port.completions[2](); await settle(); expect(shown).assertEqual(1);
    });
    it('convergesToChangedTargetAfterFailure', 0, async () => {
      const port = new PendingSystemBarPort(); const state = new SystemBarVisibility((): void => {});
      state.bind(port); state.request(true); port.failures[0](new Error('failed')); await settle();
      expect(port.calls.length).assertEqual(2); expect(port.calls[1]).assertTrue();
      port.completions[1](); await settle(); state.request(true); expect(port.calls.length).assertEqual(2);
    });
    it('rejectsOldWindowSuccessAndFailure', 0, async () => {
      const old = new PendingSystemBarPort(); const current = new PendingSystemBarPort(); let shown = 0;
      const state = new SystemBarVisibility((): void => { shown += 1; });
      state.bind(old); state.bind(current); old.completions[0](); await settle();
      expect(shown).assertEqual(0); expect(state.isShown()).assertFalse();
      current.completions[0](); await settle(); expect(shown).assertEqual(1);
      state.request(true); const next = new PendingSystemBarPort(); state.bind(next);
      current.failures[1](new Error('old')); await settle();
      expect(next.calls.length).assertEqual(1); expect(next.calls[0]).assertTrue();
      next.completions[0](); await settle(); state.request(true); expect(next.calls.length).assertEqual(1);
    });
    it('reappliesSameTargetAfterWindowReplacementAndDetach', 0, async () => {
      const old = new PendingSystemBarPort(); const next = new PendingSystemBarPort(); let shown = 0;
      const state = new SystemBarVisibility((): void => { shown += 1; });
      state.bind(old); old.completions[0](); await settle(); state.detach(); state.request(true);
      expect(old.calls.length).assertEqual(1); state.bind(next); expect(next.calls[0]).assertTrue();
      state.detach(); next.completions[0](); await settle(); expect(shown).assertEqual(1);
      state.request(false); const reopened = new PendingSystemBarPort(); state.bind(reopened);
      expect(reopened.calls[0]).assertFalse(); reopened.completions[0](); await settle();
      expect(shown).assertEqual(2);
    });
  });
}
