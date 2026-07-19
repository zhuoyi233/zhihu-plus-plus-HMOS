import { describe, expect, it } from '@ohos/hypium';
import { isApiAvailable } from '../main/ets/compat/ApiLevel';

export default function apiLevelTest(): void {
  describe('apiLevelTest', () => {
    it('acceptsApi20Baseline', 0, () => {
      expect(isApiAvailable(20, 20)).assertTrue();
    });

    it('rejectsApi24FeatureOnApi20', 0, () => {
      expect(isApiAvailable(20, 24)).assertFalse();
    });
  });
}
