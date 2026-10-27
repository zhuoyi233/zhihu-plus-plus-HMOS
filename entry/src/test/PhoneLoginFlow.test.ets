import { describe, expect, it } from '@ohos/hypium';
import {
  canRequestPhoneDigits,
  canSignInWithPhone,
  PHONE_CODE_LENGTH,
  PHONE_RESEND_COOLDOWN_SECONDS,
  PhoneDigitsGuard,
  phoneCooldownRemainingSeconds,
  phoneLoginIdentityKey,
  PhoneLoginRequestGeneration,
  PhoneSignInGuard,
  shouldResetPhoneDigits
} from 'data';

function digitsGuard(agreementChecked: boolean, numberValid: boolean, cooldownSeconds: number,
  busy: boolean): PhoneDigitsGuard {
  return {
    agreementChecked: agreementChecked,
    numberValid: numberValid,
    cooldownSeconds: cooldownSeconds,
    busy: busy
  };
}

function signInGuard(agreementChecked: boolean, numberValid: boolean, codeLength: number,
  requestedIdentityMatches: boolean, busy: boolean): PhoneSignInGuard {
  return {
    agreementChecked: agreementChecked,
    numberValid: numberValid,
    codeLength: codeLength,
    requestedIdentityMatches: requestedIdentityMatches,
    busy: busy
  };
}

export default function phoneLoginFlowTest(): void {
  describe('phoneLoginFlowTest', () => {
    it('requiresAgreementValidNumberAndIdleState', 0, () => {
      expect(canRequestPhoneDigits(digitsGuard(true, true, 0, false))).assertTrue();
      expect(canRequestPhoneDigits(digitsGuard(false, true, 0, false))).assertFalse();
      expect(canRequestPhoneDigits(digitsGuard(true, false, 0, false))).assertFalse();
      expect(canRequestPhoneDigits(digitsGuard(true, true, 30, false))).assertFalse();
      expect(canRequestPhoneDigits(digitsGuard(true, true, 0, true))).assertFalse();
    });

    it('requiresMatchingSentIdentityAndSixDigits', 0, () => {
      expect(PHONE_CODE_LENGTH).assertEqual(6);
      expect(canSignInWithPhone(signInGuard(true, true, 6, true, false))).assertTrue();
      expect(canSignInWithPhone(signInGuard(true, true, 5, true, false))).assertFalse();
      expect(canSignInWithPhone(signInGuard(true, true, 6, false, false))).assertFalse();
      expect(canSignInWithPhone(signInGuard(false, true, 6, true, false))).assertFalse();
      expect(canSignInWithPhone(signInGuard(true, false, 6, true, false))).assertFalse();
      expect(canSignInWithPhone(signInGuard(true, true, 6, true, true))).assertFalse();
    });

    it('treatsSharedPrefixRegionsAsDifferentIdentities', 0, () => {
      const us: string = phoneLoginIdentityKey('US', '+14165551234');
      const ca: string = phoneLoginIdentityKey('CA', '+14165551234');
      expect(us === ca).assertFalse();
      // 同码切换（US → CA）也需要失效旧验证码状态
      expect(shouldResetPhoneDigits(us, ca)).assertTrue();
      expect(shouldResetPhoneDigits(us, us)).assertFalse();
      expect(phoneLoginIdentityKey('CN', '').length).assertEqual(0);
    });

    it('computesCooldownFromDeadline', 0, () => {
      expect(PHONE_RESEND_COOLDOWN_SECONDS).assertEqual(60);
      const now: number = 1_000_000;
      expect(phoneCooldownRemainingSeconds(now + 60_000, now)).assertEqual(60);
      expect(phoneCooldownRemainingSeconds(now + 59_001, now)).assertEqual(60);
      expect(phoneCooldownRemainingSeconds(now + 1, now)).assertEqual(1);
      expect(phoneCooldownRemainingSeconds(now, now)).assertEqual(0);
      expect(phoneCooldownRemainingSeconds(now - 5_000, now)).assertEqual(0);
      expect(phoneCooldownRemainingSeconds(0, now)).assertEqual(0);
    });

    it('invalidatesLateResponsesByGeneration', 0, () => {
      const generation: PhoneLoginRequestGeneration = new PhoneLoginRequestGeneration();
      expect(generation.isCurrent(0)).assertFalse();
      const first: number = generation.begin();
      expect(generation.isCurrent(first)).assertTrue();
      const second: number = generation.begin();
      expect(generation.isCurrent(first)).assertFalse();
      expect(generation.isCurrent(second)).assertTrue();
      // 身份变更或页面退出调用 invalidate：在途回调必须被丢弃
      generation.invalidate();
      expect(generation.isCurrent(second)).assertFalse();
    });
  });
}
