import { describe, expect, it } from '@ohos/hypium';
import { classifyHttpStatus, HttpFailureKind } from '../main/ets/network/HttpProbeClient';

export default function httpProbeClientTest(): void {
  describe('httpProbeClientTest', () => {
    it('acceptsSuccessfulStatus', 0, () => {
      expect(classifyHttpStatus(200)).assertUndefined();
    });

    it('classifiesClientFailure', 0, () => {
      expect(classifyHttpStatus(401)).assertEqual(HttpFailureKind.CLIENT);
    });

    it('classifiesServerFailure', 0, () => {
      expect(classifyHttpStatus(503)).assertEqual(HttpFailureKind.SERVER);
    });
  });
}
