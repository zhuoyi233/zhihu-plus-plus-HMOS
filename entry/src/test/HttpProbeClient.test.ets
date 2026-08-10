import { describe, expect, it } from '@ohos/hypium';
import {
  classifyHttpStatus,
  classifyTransportErrorCode,
  describeHttpFailure,
  HttpFailureKind
} from '../main/ets/network/HttpFailure';

export default function httpProbeClientTest(): void {
  describe('httpProbeClientTest', () => {
    it('acceptsSuccessfulStatus', 0, () => {
      expect(classifyHttpStatus(200)).assertUndefined();
    });

    it('classifiesClientFailure', 0, () => {
      expect(classifyHttpStatus(401)).assertEqual(HttpFailureKind.AUTHENTICATION);
      expect(classifyHttpStatus(403)).assertEqual(HttpFailureKind.AUTHENTICATION);
      expect(classifyHttpStatus(429)).assertEqual(HttpFailureKind.RATE_LIMITED);
      expect(classifyHttpStatus(422)).assertEqual(HttpFailureKind.CLIENT);
    });

    it('classifiesServerFailure', 0, () => {
      expect(classifyHttpStatus(503)).assertEqual(HttpFailureKind.SERVER);
    });

    it('classifiesTimeoutResponsesAndTransportErrors', 0, () => {
      expect(classifyHttpStatus(408)).assertEqual(HttpFailureKind.TIMEOUT);
      expect(classifyHttpStatus(504)).assertEqual(HttpFailureKind.TIMEOUT);
      expect(classifyTransportErrorCode(2300028)).assertEqual(HttpFailureKind.TIMEOUT);
      expect(classifyTransportErrorCode(2300007)).assertEqual(HttpFailureKind.NETWORK);
      expect(describeHttpFailure(HttpFailureKind.CANCELLED)).assertEqual('请求已取消');
    });
  });
}
