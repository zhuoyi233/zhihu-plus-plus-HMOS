import { describe, expect, it } from '@ohos/hypium';
import {
  classifyHttpStatus,
  classifyTransportErrorCode,
  describeHttpFailure,
  HttpFailure,
  HttpFailureKind
} from 'data';

export default function httpProbeClientTest(): void {
  describe('httpProbeClientTest', () => {
    it('acceptsSuccessfulStatus', 0, () => {
      expect(classifyHttpStatus(200)).assertUndefined();
    });

    it('classifiesClientFailure', 0, () => {
      expect(classifyHttpStatus(302)).assertEqual(HttpFailureKind.CLIENT);
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
      expect(classifyTransportErrorCode(2300047)).assertEqual(HttpFailureKind.CLIENT);
      expect(classifyTransportErrorCode(2300007)).assertEqual(HttpFailureKind.NETWORK);
      expect(describeHttpFailure(HttpFailureKind.CANCELLED)).assertEqual('请求已取消');
    });

    it('exposesStructuredFailureWithoutTransportMessage', 0, () => {
      const failure = new HttpFailure(HttpFailureKind.TIMEOUT, undefined, 2300028);
      expect(failure.kind).assertEqual(HttpFailureKind.TIMEOUT);
      expect(failure.status).assertUndefined();
      expect(failure.transportCode).assertEqual(2300028);
      expect(failure.retryable).assertTrue();
      expect(failure.message).assertEqual('请求超时');
      expect(new HttpFailure(HttpFailureKind.AUTHENTICATION, 403).retryable).assertFalse();
      expect(new HttpFailure(HttpFailureKind.CLIENT, 302).retryable).assertFalse();
    });
  });
}
