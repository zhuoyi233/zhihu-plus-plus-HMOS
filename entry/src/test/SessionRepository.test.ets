import { describe, expect, it } from '@ohos/hypium';
import {
  AppSessionOwner,
  LoginVerificationResult,
  LoginVerificationStatus,
  SessionCookie,
  SessionPersistence,
  SessionRepository,
  SessionStatus,
  SessionVerifier
} from 'data';

class MemorySessionPersistence implements SessionPersistence {
  cookies: Array<SessionCookie> = [];
  saveCount: number = 0;
  clearCount: number = 0;
  loadCount: number = 0;
  failSave: boolean = false;
  failClear: boolean = false;

  save(cookies: Array<SessionCookie>, _now?: number): Promise<void> {
    this.saveCount += 1;
    if (this.failSave) {
      return Promise.reject(new Error('sensitive persistence detail'));
    }
    this.cookies = cookies.slice();
    return Promise.resolve();
  }

  load(_now?: number): Promise<Array<SessionCookie>> {
    this.loadCount += 1;
    return Promise.resolve(this.cookies.slice());
  }

  clear(): Promise<void> {
    this.clearCount += 1;
    if (this.failClear) {
      return Promise.reject(new Error('partial clear detail'));
    }
    this.cookies = [];
    return Promise.resolve();
  }
}

class FixedSessionVerifier implements SessionVerifier {
  result: LoginVerificationResult = {
    status: LoginVerificationStatus.AUTHENTICATED,
    message: 'verified',
    profile: { id: 'test-id', name: '测试账号', userType: 'people' }
  };
  verifyCount: number = 0;
  cancelCount: number = 0;

  verify(_cookies: Array<SessionCookie>): Promise<LoginVerificationResult> {
    this.verifyCount += 1;
    return Promise.resolve(this.result);
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class BlockingSessionVerifier extends FixedSessionVerifier {
  readonly started: Promise<void>;
  private startedResolver?: () => void;
  private resultResolver?: (result: LoginVerificationResult) => void;

  constructor() {
    super();
    this.started = new Promise<void>((resolve: () => void) => {
      this.startedResolver = resolve;
    });
  }

  verify(_cookies: Array<SessionCookie>): Promise<LoginVerificationResult> {
    this.verifyCount += 1;
    this.startedResolver?.();
    return new Promise<LoginVerificationResult>((resolve: (result: LoginVerificationResult) => void) => {
      this.resultResolver = resolve;
    });
  }

  release(): void {
    this.resultResolver?.(this.result);
  }
}

class BlockingSessionPersistence extends MemorySessionPersistence {
  private loadResolver?: (cookies: Array<SessionCookie>) => void;
  private released: boolean = false;

  load(_now?: number): Promise<Array<SessionCookie>> {
    this.loadCount += 1;
    if (this.released) {
      return Promise.resolve(this.cookies.slice());
    }
    return new Promise<Array<SessionCookie>>((resolve: (cookies: Array<SessionCookie>) => void) => {
      this.loadResolver = resolve;
    });
  }

  releaseLoad(): void {
    this.released = true;
    this.loadResolver?.(this.cookies.slice());
  }
}

function loginCookies(): Array<SessionCookie> {
  return [
    { name: 'z_c0', value: 'login-token' },
    { name: 'd_c0', value: 'device-token' }
  ];
}

export default function sessionRepositoryTest(): void {
  describe('sessionRepositoryTest', () => {
    it('loadsAuthenticatedSessionIntoSynchronousProvider', 0, async () => {
      const persistence = new MemorySessionPersistence();
      persistence.cookies = loginCookies();
      const repository = new SessionRepository(persistence, new FixedSessionVerifier());

      const state = await repository.load();

      expect(state.status).assertEqual(SessionStatus.AUTHENTICATED);
      expect(state.profile?.name).assertEqual('测试账号');
      expect(repository.getCookies().length).assertEqual(2);
      const externalCopy = repository.getCookies();
      externalCopy[0].value = 'changed';
      expect(repository.getCookies()[0].value).assertEqual('login-token');
      const externalState = repository.getState();
      if (externalState.profile !== undefined) {
        externalState.profile.name = 'changed';
      }
      expect(repository.getState().profile?.name).assertEqual('测试账号');
    });

    it('doesNotPublishRestoredCookiesBeforeIdentityVerification', 0, async () => {
      const persistence = new MemorySessionPersistence();
      persistence.cookies = loginCookies();
      const verifier = new BlockingSessionVerifier();
      const repository = new SessionRepository(persistence, verifier);

      const loading = repository.load();
      await verifier.started;
      expect(repository.getCookies().length).assertEqual(0);
      verifier.release();
      const state = await loading;

      expect(state.status).assertEqual(SessionStatus.AUTHENTICATED);
      expect(repository.getCookies().length).assertEqual(2);
    });

    it('validatesBeforeSavingManualCookieAndPreservesOldSessionOnFailure', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const verifier = new FixedSessionVerifier();
      const repository = new SessionRepository(persistence, verifier);
      await repository.loginWithCookies(loginCookies());
      verifier.result = {
        status: LoginVerificationStatus.REJECTED,
        message: 'Cookie 已失效或被知乎拒绝'
      };

      const state = await repository.loginWithCookieHeader('z_c0=rejected; d_c0=rejected-device');

      expect(state.status).assertEqual(SessionStatus.ERROR);
      expect(state.hasRetainedCredentials).assertTrue();
      expect(persistence.saveCount).assertEqual(1);
      expect(repository.getCookies()[0].value).assertEqual('login-token');
    });

    it('doesNotPublishVerifiedCookieWhenEncryptedSaveFails', 0, async () => {
      const persistence = new MemorySessionPersistence();
      persistence.failSave = true;
      const repository = new SessionRepository(persistence, new FixedSessionVerifier());

      const state = await repository.loginWithCookies(loginCookies());

      expect(state.status).assertEqual(SessionStatus.ERROR);
      expect(state.message).assertEqual('Cookie 已验证，但加密保存失败');
      expect(repository.getCookies().length).assertEqual(0);
      expect(state.message.includes('sensitive persistence detail')).assertFalse();
    });

    it('clearsExplicitlyRejectedRestoredSessionButRetainsTemporaryFailure', 0, async () => {
      const rejectedStore = new MemorySessionPersistence();
      rejectedStore.cookies = loginCookies();
      const rejectedVerifier = new FixedSessionVerifier();
      rejectedVerifier.result = {
        status: LoginVerificationStatus.REJECTED,
        message: 'Cookie 已失效或被知乎拒绝',
        rejectionStatus: 401
      };
      const rejectedRepository = new SessionRepository(rejectedStore, rejectedVerifier);
      const expired = await rejectedRepository.load();
      expect(expired.status).assertEqual(SessionStatus.EXPIRED);
      expect(expired.hasRetainedCredentials).assertFalse();
      expect(rejectedStore.clearCount).assertEqual(1);

      const temporaryStore = new MemorySessionPersistence();
      temporaryStore.cookies = loginCookies();
      const temporaryVerifier = new FixedSessionVerifier();
      temporaryVerifier.result = {
        status: LoginVerificationStatus.TEMPORARY_FAILURE,
        message: '网络连接失败，请稍后重试'
      };
      const temporaryRepository = new SessionRepository(temporaryStore, temporaryVerifier);
      const failed = await temporaryRepository.load();
      expect(failed.status).assertEqual(SessionStatus.ERROR);
      expect(failed.hasRetainedCredentials).assertTrue();
      expect(temporaryStore.clearCount).assertEqual(0);
      expect(temporaryRepository.getCookies().length).assertEqual(0);
    });

    it('retains403CredentialsWithoutPublishingThemToHttp', 0, async () => {
      const persistence = new MemorySessionPersistence();
      persistence.cookies = loginCookies();
      const verifier = new FixedSessionVerifier();
      verifier.result = {
        status: LoginVerificationStatus.REJECTED,
        message: '知乎拒绝了本次验证请求，可能需要稍后重试或完成风控',
        rejectionStatus: 403
      };
      const repository = new SessionRepository(persistence, verifier);

      const state = await repository.load();

      expect(state.status).assertEqual(SessionStatus.ERROR);
      expect(state.hasRetainedCredentials).assertTrue();
      expect(persistence.clearCount).assertEqual(0);
      expect(persistence.cookies.length).assertEqual(2);
      expect(repository.getCookies().length).assertEqual(0);
      expect(state.message).assertEqual('知乎拒绝了本次验证请求，可能需要稍后重试或完成风控；本地会话已保留');
      expect(state.message.includes('Cookie 已失效')).assertFalse();
    });

    it('keepsExistingAuthenticatedMemoryStateOnTemporaryRestoreFailure', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const verifier = new FixedSessionVerifier();
      const repository = new SessionRepository(persistence, verifier);
      await repository.loginWithCookies(loginCookies());
      const replacementCookies: Array<SessionCookie> = [
        { name: 'z_c0', value: 'replacement-login' },
        { name: 'd_c0', value: 'replacement-device' }
      ];
      persistence.cookies = replacementCookies;
      verifier.result = {
        status: LoginVerificationStatus.TEMPORARY_FAILURE,
        message: '网络连接失败，请稍后重试'
      };

      const state = await repository.load();

      expect(state.status).assertEqual(SessionStatus.AUTHENTICATED);
      expect(repository.getCookies()[0].value).assertEqual('login-token');
      expect(persistence.cookies[0].value).assertEqual('replacement-login');
    });

    it('removesRuntimeCredentialsEvenWhenPersistentLogoutFails', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const repository = new SessionRepository(persistence, new FixedSessionVerifier());
      await repository.loginWithCookies(loginCookies());
      persistence.failClear = true;

      const state = await repository.logout();

      expect(state.status).assertEqual(SessionStatus.ERROR);
      expect(state.hasRetainedCredentials).assertTrue();
      expect(state.profile).assertUndefined();
      expect(repository.getCookies().length).assertEqual(0);
      expect(persistence.cookies.length).assertEqual(2);
    });

    it('serializesLoadAndLogoutOperations', 0, async () => {
      const persistence = new BlockingSessionPersistence();
      persistence.cookies = loginCookies();
      const repository = new SessionRepository(persistence, new FixedSessionVerifier());

      const loading = repository.load();
      const loggingOut = repository.logout();
      expect(persistence.clearCount).assertEqual(0);
      persistence.releaseLoad();
      await loading;
      const finalState = await loggingOut;

      expect(persistence.clearCount).assertEqual(1);
      expect(finalState.status).assertEqual(SessionStatus.GUEST);
      expect(repository.getCookies().length).assertEqual(0);
    });

    it('cancelledQueuedLoginDoesNotCancelRestoreOrSaveLater', 0, async () => {
      const persistence = new MemorySessionPersistence();
      persistence.cookies = loginCookies();
      const verifier = new BlockingSessionVerifier();
      const repository = new SessionRepository(persistence, verifier);

      const restoring = repository.load();
      await verifier.started;
      const login = repository.beginLoginWithCookieHeader('z_c0=queued; d_c0=queued-device');
      login.cancel();

      expect(verifier.cancelCount).assertEqual(0);
      verifier.release();
      await restoring;
      const cancelledState = await login.result;

      expect(verifier.verifyCount).assertEqual(1);
      expect(persistence.saveCount).assertEqual(0);
      expect(cancelledState.status).assertEqual(SessionStatus.AUTHENTICATED);
      expect(repository.getCookies()[0].value).assertEqual('login-token');
    });

    it('cancelsOnlyTheMatchingActiveLoginVerification', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const verifier = new BlockingSessionVerifier();
      const repository = new SessionRepository(persistence, verifier);

      const login = repository.beginLoginWithCookies(loginCookies());
      await verifier.started;
      login.cancel();
      expect(verifier.cancelCount).assertEqual(1);
      verifier.release();
      const state = await login.result;

      expect(state.status).assertEqual(SessionStatus.GUEST);
      expect(persistence.saveCount).assertEqual(0);
      expect(repository.getCookies().length).assertEqual(0);
    });

    it('ownsOneRepositoryAndRunsDeferredRestoreOnce', 0, async () => {
      const persistence = new MemorySessionPersistence();
      persistence.cookies = loginCookies();
      const verifier = new FixedSessionVerifier();
      let factoryRuns = 0;
      const owner = new AppSessionOwner((): SessionRepository => {
        factoryRuns += 1;
        return new SessionRepository(persistence, verifier);
      });

      const firstRepository = owner.getRepository();
      const secondRepository = owner.getRepository();
      const firstRestore = owner.restoreDeferred();
      const secondRestore = owner.restoreDeferred();
      await firstRestore;
      await secondRestore;

      expect(firstRepository === secondRepository).assertTrue();
      expect(factoryRuns).assertEqual(1);
      expect(persistence.loadCount).assertEqual(1);
      expect(verifier.verifyCount).assertEqual(1);
    });

    it('doesNotCreateOrClearRepositoryWhenAbilityIsDestroyed', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const verifier = new FixedSessionVerifier();
      let factoryRuns = 0;
      const owner = new AppSessionOwner((): SessionRepository => {
        factoryRuns += 1;
        return new SessionRepository(persistence, verifier);
      });

      owner.cancelInFlightVerification();
      expect(factoryRuns).assertEqual(0);
      const repository = owner.getRepository();
      await repository.loginWithCookies(loginCookies());
      await owner.restoreDeferred();
      owner.cancelInFlightVerification();
      await owner.restoreDeferred();

      expect(verifier.cancelCount).assertEqual(1);
      expect(persistence.clearCount).assertEqual(0);
      expect(persistence.loadCount).assertEqual(2);
      expect(repository.getCookies().length).assertEqual(2);
    });
  });
}
