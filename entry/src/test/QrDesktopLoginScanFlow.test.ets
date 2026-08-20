import { describe, expect, it } from '@ohos/hypium';
import { QrScanner } from '../main/ets/platform/P4PlatformServices';
import {
  QrDesktopLoginScanController,
  QrDesktopLoginScanPhase,
  QrDesktopLoginScanViewState
} from '../main/ets/scan/QrDesktopLoginScanFlow';

class Deferred<T> {
  readonly promise: Promise<T>;
  private resolveAction?: (value: T) => void;
  private rejectAction?: (reason: Error) => void;

  constructor() {
    this.promise = new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void): void => {
      this.resolveAction = resolve;
      this.rejectAction = reject;
    });
  }

  resolve(value: T): void {
    this.resolveAction?.(value);
    this.resolveAction = undefined;
    this.rejectAction = undefined;
  }

  reject(reason: Error): void {
    this.rejectAction?.(reason);
    this.resolveAction = undefined;
    this.rejectAction = undefined;
  }
}

class FakeQrScanner implements QrScanner {
  calls: number = 0;
  private readonly response: Promise<string | undefined>;

  constructor(response: Promise<string | undefined>) {
    this.response = response;
  }

  scanSingleQrCode(): Promise<string | undefined> {
    this.calls += 1;
    return this.response;
  }
}

function createController(states: Array<QrDesktopLoginScanViewState>): QrDesktopLoginScanController {
  return new QrDesktopLoginScanController((state: QrDesktopLoginScanViewState): void => {
    states.push(state);
  });
}

export default function qrDesktopLoginScanFlowTest(): void {
  describe('qrDesktopLoginScanFlowTest', () => {
    it('requiresExplicitConfirmationBeforeOneTimeHandoff', 0, async () => {
      const states: Array<QrDesktopLoginScanViewState> = [];
      const controller = createController(states);
      const scanner = new FakeQrScanner(Promise.resolve(
        'https://www.zhihu.com/account/scan/login/safe-token'
      ));

      await controller.scan(scanner);

      const waiting = states[states.length - 1];
      expect(waiting.phase).assertEqual(QrDesktopLoginScanPhase.AWAITING_CONFIRMATION);
      expect(waiting.message.includes('safe-token')).assertFalse();
      expect(controller.takeConfirmedUrl()).assertUndefined();
      const handoff = controller.confirm();
      expect(handoff?.source).assertEqual('www.zhihu.com');
      expect(handoff?.requiresExplicitConfirmation).assertTrue();
      expect(controller.takeConfirmedUrl()).assertEqual('https://www.zhihu.com/account/scan/login/safe-token');
      expect(controller.takeConfirmedUrl()).assertUndefined();
    });

    it('treatsScannerCancellationAsNormalAndClearsAnyHandoff', 0, async () => {
      const states: Array<QrDesktopLoginScanViewState> = [];
      const controller = createController(states);
      const scanner = new FakeQrScanner(Promise.resolve(undefined));

      await controller.scan(scanner);

      expect(states[states.length - 1].phase).assertEqual(QrDesktopLoginScanPhase.CANCELLED);
      expect(controller.confirm()).assertUndefined();
      expect(controller.takeConfirmedUrl()).assertUndefined();
    });

    it('mapsServiceFailureWithoutExposingUpstreamError', 0, async () => {
      const states: Array<QrDesktopLoginScanViewState> = [];
      const controller = createController(states);
      const scanner = new FakeQrScanner(Promise.reject(new Error('sensitive upstream response')));

      await controller.scan(scanner);

      const state = states[states.length - 1];
      expect(state.phase).assertEqual(QrDesktopLoginScanPhase.ERROR);
      expect(state.message.includes('sensitive upstream response')).assertFalse();
    });

    it('ignoresLateResultsAfterBackgroundAndAllowsFreshForegroundScan', 0, async () => {
      const states: Array<QrDesktopLoginScanViewState> = [];
      const controller = createController(states);
      const delayed = new Deferred<string | undefined>();
      const scanner = new FakeQrScanner(delayed.promise);

      const pending = controller.scan(scanner);
      controller.setForeground(false);
      delayed.resolve('https://www.zhihu.com/account/scan/login/late-token');
      await pending;

      expect(states[states.length - 1].phase).assertEqual(QrDesktopLoginScanPhase.READY);
      expect(controller.confirm()).assertUndefined();
      controller.setForeground(true);
      const freshScanner = new FakeQrScanner(Promise.resolve(undefined));
      await controller.scan(freshScanner);
      expect(freshScanner.calls).assertEqual(1);
    });

    it('doesNotStartDuplicateSystemScans', 0, async () => {
      const states: Array<QrDesktopLoginScanViewState> = [];
      const controller = createController(states);
      const delayed = new Deferred<string | undefined>();
      const scanner = new FakeQrScanner(delayed.promise);

      const first = controller.scan(scanner);
      const second = controller.scan(scanner);
      delayed.resolve(undefined);
      await first;
      await second;

      expect(scanner.calls).assertEqual(1);
    });
  });
}
