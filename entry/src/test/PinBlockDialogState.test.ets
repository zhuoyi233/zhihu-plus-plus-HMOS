import { describe, expect, it } from '@ohos/hypium';
import {
  emptyPinBlockDialogView,
  PIN_KEYWORD_INVALID_MESSAGE,
  PinBlockDialogKind,
  PinBlockDialogState,
  PinBlockDialogViewState,
  PinBlockSubmitter
} from '../main/ets/pages/PinBlockDialogState';

/** 可控提交器：记录调用次数，并允许测试自行决定何时、以何种结果完成。 */
class ControlledSubmitter {
  calls: Array<string> = [];
  private pending: Array<(success: boolean) => void> = [];
  private immediate?: boolean;

  constructor(immediate?: boolean) {
    this.immediate = immediate;
  }

  readonly submit: PinBlockSubmitter = (kind: PinBlockDialogKind, value: string): Promise<boolean> => {
    this.calls.push(`${kind}:${value}`);
    if (this.immediate !== undefined) {
      return Promise.resolve(this.immediate);
    }
    return new Promise<boolean>((resolve: (success: boolean) => void): void => {
      this.pending.push(resolve);
    });
  };

  resolve(success: boolean): void {
    const next = this.pending.shift();
    if (next !== undefined) {
      next(success);
    }
  }

  pendingCount(): number {
    return this.pending.length;
  }
}

export default function pinBlockDialogStateTest(): void {
  describe('pinBlockDialogStateTest', () => {
    it('startsClosedWithoutInput', 0, () => {
      const state = new PinBlockDialogState();
      const view = state.snapshot();
      expect(view.kind).assertEqual(PinBlockDialogKind.NONE);
      expect(view.input).assertEqual('');
      expect(view.errorMessage).assertEqual('');
      expect(view.submitting).assertFalse();
    });

    it('cancelsWithoutSubmittingOrKeepingKeyword', 0, async () => {
      const submitter = new ControlledSubmitter(true);
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('广告');
      expect(state.snapshot().input).assertEqual('广告');
      state.cancel();
      await state.submit(submitter.submit, '屏蔽');

      expect(submitter.calls.length).assertEqual(0);
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.NONE);
      expect(state.snapshot().input).assertEqual('');
    });

    it('submitsOnlyOnceWhilePending', 0, async () => {
      const submitter = new ControlledSubmitter();
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('广告');

      const first = state.submit(submitter.submit, '屏蔽');
      const second = state.submit(submitter.submit, '屏蔽');
      expect(state.snapshot().submitting).assertTrue();
      expect(submitter.calls.length).assertEqual(1);
      expect(submitter.calls[0]).assertEqual('keyword:广告');

      // 提交中再改输入不会改写正在提交的值。
      state.updateInput('另一个词');
      expect(state.snapshot().input).assertEqual('广告');

      submitter.resolve(true);
      await first;
      await second;
      expect(submitter.calls.length).assertEqual(1);
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.NONE);
      expect(state.snapshot().input).assertEqual('');
    });

    it('keepsKeywordAndShowsErrorWhenSubmitFails', 0, async () => {
      const submitter = new ControlledSubmitter();
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('  广告  ');

      const pending = state.submit(submitter.submit, '屏蔽');
      expect(submitter.calls[0]).assertEqual('keyword:广告');
      submitter.resolve(false);
      await pending;

      const view = state.snapshot();
      expect(view.kind).assertEqual(PinBlockDialogKind.KEYWORD);
      expect(view.input).assertEqual('广告');
      expect(view.errorMessage).assertEqual('屏蔽失败，请重试');
      expect(view.submitting).assertFalse();
    });

    it('rejectsInvalidKeywordWithoutSubmitting', 0, async () => {
      const submitter = new ControlledSubmitter(true);
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('   ');

      await state.submit(submitter.submit, '屏蔽');
      expect(submitter.calls.length).assertEqual(0);
      expect(state.snapshot().errorMessage).assertEqual(PIN_KEYWORD_INVALID_MESSAGE);
      expect(state.snapshot().submitting).assertFalse();

      // 重新输入会清掉上一次的就地错误。
      state.updateInput('正常词');
      expect(state.snapshot().errorMessage).assertEqual('');
    });

    it('closesUserConfirmationAfterSuccess', 0, async () => {
      const submitter = new ControlledSubmitter(true);
      const state = new PinBlockDialogState();
      state.openUser();
      await state.submit(submitter.submit, '屏蔽');
      expect(submitter.calls[0]).assertEqual('user:');
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.NONE);
      expect(state.snapshot().submitting).assertFalse();
    });

    it('ignoresLateResultAfterPageLeft', 0, async () => {
      const submitter = new ControlledSubmitter();
      const states: Array<PinBlockDialogViewState> = [];
      const state = new PinBlockDialogState((next: PinBlockDialogViewState): void => {
        states.push(next);
      });
      state.openKeyword();
      state.updateInput('广告');

      const pending = state.submit(submitter.submit, '屏蔽');
      const publishedBeforeDispose = states.length;
      state.dispose();
      submitter.resolve(true);
      await pending;

      // 已离开的页面不再收到任何回调，界面保持离开时的样子。
      expect(states.length).assertEqual(publishedBeforeDispose);
    });

    it('cancelIsIgnoredWhileSubmitting', 0, async () => {
      const submitter = new ControlledSubmitter();
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('广告');

      const pending = state.submit(submitter.submit, '屏蔽');
      state.cancel();
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.KEYWORD);
      expect(state.snapshot().submitting).assertTrue();

      submitter.resolve(false);
      await pending;
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.KEYWORD);
    });

    it('dropsLateFailureAfterDialogClosedForReappear', 0, async () => {
      const submitter = new ControlledSubmitter();
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('广告');

      const pending = state.submit(submitter.submit, '屏蔽');
      // 页面重新可见：强制回到关闭态，即便提交还在进行中。
      state.resetForReappear();
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.NONE);
      expect(state.snapshot().submitting).assertFalse();

      submitter.resolve(false);
      await pending;
      // 迟到的失败结果不会把已关闭的弹层重新打开。
      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.NONE);
      expect(state.snapshot().errorMessage).assertEqual('');
    });

    it('ignoresStaleResultWhenReopenedWithNewInput', 0, async () => {
      const submitter = new ControlledSubmitter();
      const state = new PinBlockDialogState();
      state.openKeyword();
      state.updateInput('广告');

      const pending = state.submit(submitter.submit, '屏蔽');
      state.openKeyword();
      state.updateInput('新词');
      submitter.resolve(false);
      await pending;

      expect(state.snapshot().kind).assertEqual(PinBlockDialogKind.KEYWORD);
      expect(state.snapshot().input).assertEqual('新词');
      expect(state.snapshot().errorMessage).assertEqual('');
      expect(state.snapshot().submitting).assertFalse();
    });

    it('returnsFreshEmptyView', 0, () => {
      const view = emptyPinBlockDialogView();
      expect(view.kind).assertEqual(PinBlockDialogKind.NONE);
      expect(view.input).assertEqual('');
      expect(view.errorMessage).assertEqual('');
      expect(view.submitting).assertFalse();
    });
  });
}
