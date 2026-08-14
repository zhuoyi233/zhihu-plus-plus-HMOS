import { describe, expect, it } from '@ohos/hypium';
import {
  LoginSessionGateway,
  QrLoginGateway,
  QrLoginState,
  QrLoginStatus,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  completesUserAuthentication,
  LoginController,
  LoginPhase,
  LoginPollScheduler
} from '../main/ets/pages/LoginController';

interface ScheduledPoll {
  id: number;
  delayMs: number;
  task: () => Promise<void>;
}

class FakePollScheduler implements LoginPollScheduler {
  private nextId: number = 1;
  readonly tasks: Array<ScheduledPoll> = [];
  readonly cancelled: Array<number> = [];

  schedule(task: () => Promise<void>, delayMs: number): number {
    const id = this.nextId;
    this.nextId += 1;
    this.tasks.push({ id: id, delayMs: delayMs, task: task });
    return id;
  }

  cancel(taskId: number): void {
    this.cancelled.push(taskId);
    const index = this.tasks.findIndex((task: ScheduledPoll): boolean => task.id === taskId);
    if (index >= 0) {
      this.tasks.splice(index, 1);
    }
  }

  runNext(): Promise<void> {
    const task = this.tasks.shift();
    if (task === undefined) {
      return Promise.resolve();
    }
    return task.task();
  }
}

class Deferred<T> {
  readonly promise: Promise<T>;
  private resolver?: (value: T) => void;

  constructor() {
    this.promise = new Promise<T>((resolve: (value: T) => void): void => {
      this.resolver = resolve;
    });
  }

  resolve(value: T): void {
    this.resolver?.(value);
    this.resolver = undefined;
  }
}

class FakeSessionLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;
  private readonly cancelAction: () => void;
  private cancelled: boolean = false;

  constructor(result: Promise<SessionState>, cancelAction: () => void) {
    this.result = result;
    this.cancelAction = cancelAction;
  }

  cancel(): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.cancelAction();
  }
}

class FakeSessionRepository implements LoginSessionGateway {
  state: SessionState = guestState();
  manualResult: SessionState = authenticatedState('manual-user');
  manualDeferred?: Deferred<SessionState>;
  qrResult: SessionState = authenticatedState('qr-user');
  logoutResult: SessionState = guestState('已退出登录');
  retryResult: SessionState = guestState();
  lastCookieHeader: string = '';
  lastQrCookies: Array<SessionCookie> = [];
  cancelCount: number = 0;
  retryCount: number = 0;

  getState(): SessionState {
    return this.copyState(this.state);
  }

  retryRetainedSession(): Promise<SessionState> {
    this.retryCount += 1;
    this.state = this.copyState(this.retryResult);
    return Promise.resolve(this.copyState(this.state));
  }

  beginLoginWithCookieHeader(rawCookie: string): SessionLoginOperation {
    this.lastCookieHeader = rawCookie;
    let result: Promise<SessionState>;
    if (this.manualDeferred !== undefined) {
      result = this.manualDeferred.promise.then((state: SessionState): SessionState => {
        this.state = this.copyState(state);
        return this.copyState(this.state);
      });
    } else {
      this.state = this.copyState(this.manualResult);
      result = Promise.resolve(this.copyState(this.state));
    }
    return new FakeSessionLoginOperation(result, (): void => {
      this.cancelCount += 1;
    });
  }

  beginLoginWithCookies(cookies: Array<SessionCookie>): SessionLoginOperation {
    this.lastQrCookies = cookies.slice();
    this.state = this.copyState(this.qrResult);
    return new FakeSessionLoginOperation(Promise.resolve(this.copyState(this.state)), (): void => {
      this.cancelCount += 1;
    });
  }

  logout(): Promise<SessionState> {
    this.state = this.copyState(this.logoutResult);
    return Promise.resolve(this.copyState(this.state));
  }

  private copyState(state: SessionState): SessionState {
    return {
      status: state.status,
      message: state.message,
      hasRetainedCredentials: state.hasRetainedCredentials,
      profile: state.profile === undefined ? undefined : {
        id: state.profile.id,
        name: state.profile.name,
        urlToken: state.profile.urlToken,
        userType: state.profile.userType,
        avatarUrl: state.profile.avatarUrl
      }
    };
  }
}

class FakeQrClient implements QrLoginGateway {
  startState: QrLoginState = qrState(QrLoginStatus.READY, '请扫码', 'https://www.zhihu.com/qr');
  currentState: QrLoginState = qrState(QrLoginStatus.IDLE, '未开始');
  startDeferred?: Deferred<QrLoginState>;
  readonly pollStates: Array<QrLoginState> = [];
  candidateCookies: Array<SessionCookie> = [];
  startCount: number = 0;
  pollCount: number = 0;
  cancelCount: number = 0;
  mergedRiskCookies: number = 0;

  start(_initialCookies?: Array<SessionCookie>, _now?: number): Promise<QrLoginState> {
    this.startCount += 1;
    this.currentState = this.startState;
    return this.startDeferred?.promise ?? Promise.resolve(this.startState);
  }

  pollOnce(_now?: number): Promise<QrLoginState> {
    this.pollCount += 1;
    const state = this.pollStates.shift();
    return Promise.resolve(state ?? qrState(QrLoginStatus.TEMPORARY_FAILURE, '没有响应'));
  }

  cancel(): void {
    this.cancelCount += 1;
  }

  getState(): QrLoginState {
    return this.currentState;
  }

  getCandidateCookies(): Array<SessionCookie> {
    return this.candidateCookies.slice();
  }

  mergeCookiesAfterRiskControl(cookies: Array<SessionCookie>): void {
    this.mergedRiskCookies += cookies.length;
    if (this.currentState.status === QrLoginStatus.RISK_CONTROL) {
      this.currentState = {
        status: QrLoginStatus.READY,
        message: '验证完成，等待扫码',
        qrLink: this.currentState.qrLink,
        expiresAt: this.currentState.expiresAt
      };
    }
  }
}

export default function loginControllerTest(): void {
  describe('loginControllerTest', () => {
    it('reflectsAuthenticatedSessionAndLogsOut', 0, async () => {
      const session = new FakeSessionRepository();
      session.state = authenticatedState('existing-user');
      const qr = new FakeQrClient();
      const controller = new LoginController(session, qr);

      controller.activate();
      expect(controller.snapshot().phase).assertEqual(LoginPhase.AUTHENTICATED);
      expect(completesUserAuthentication(LoginPhase.GUEST, controller.snapshot().phase)).assertFalse();
      expect(controller.snapshot().profileName).assertEqual('existing-user');
      expect(controller.snapshot().logoutEnabled).assertTrue();
      expect(controller.snapshot().qrStartEnabled).assertFalse();

      await controller.startQrLogin();
      expect(qr.startCount).assertEqual(0);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.AUTHENTICATED);

      await controller.logout();
      expect(controller.snapshot().phase).assertEqual(LoginPhase.GUEST);
      expect(controller.snapshot().logoutEnabled).assertFalse();
    });

    it('doesNotPublishManualCookieInObservableState', 0, async () => {
      const session = new FakeSessionRepository();
      const controller = new LoginController(session, new FakeQrClient());
      controller.activate();

      const secret = 'z_c0=manual-secret; d_c0=device-secret';
      const login = controller.loginWithCookieHeader(secret);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.VERIFYING_COOKIE);
      expect(JSON.stringify(controller.snapshot()).includes('manual-secret')).assertFalse();
      await login;

      expect(session.lastCookieHeader).assertEqual(secret);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.AUTHENTICATED);
      expect(completesUserAuthentication(LoginPhase.VERIFYING_COOKIE, controller.snapshot().phase)).assertTrue();
    });

    it('retriesRetainedSessionWithoutRequiringCookieInput', 0, async () => {
      const session = new FakeSessionRepository();
      session.state = {
        status: SessionStatus.ERROR,
        message: '网络请求超时；本地会话已保留',
        hasRetainedCredentials: true
      };
      session.retryResult = authenticatedState('restored-user');
      const controller = new LoginController(session, new FakeQrClient());

      controller.activate();
      expect(controller.snapshot().phase).assertEqual(LoginPhase.ERROR);
      expect(controller.snapshot().retainedSessionRetryEnabled).assertTrue();
      await controller.retryRetainedSession();

      expect(session.retryCount).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.AUTHENTICATED);
      expect(controller.snapshot().profileName).assertEqual('restored-user');
    });

    it('pollsQrAtFixedIntervalAndKeepsQrVisibleWhileWaiting', 0, async () => {
      const scheduler = new FakePollScheduler();
      const qr = new FakeQrClient();
      qr.pollStates.push(qrState(QrLoginStatus.WAITING_CONFIRMATION, '请确认'));
      const controller = new LoginController(new FakeSessionRepository(), qr, undefined, scheduler);
      controller.activate();

      await controller.startQrLogin();
      expect(controller.snapshot().phase).assertEqual(LoginPhase.QR_READY);
      expect(scheduler.tasks.length).assertEqual(1);
      expect(scheduler.tasks[0].delayMs).assertEqual(500);

      await scheduler.runNext();
      expect(controller.snapshot().phase).assertEqual(LoginPhase.QR_WAITING_CONFIRMATION);
      expect(controller.snapshot().qrLink).assertEqual('https://www.zhihu.com/qr');
      expect(scheduler.tasks.length).assertEqual(1);
    });

    it('acceptsQrLoginOnlyAfterRepositoryAuthentication', 0, async () => {
      const scheduler = new FakePollScheduler();
      const session = new FakeSessionRepository();
      const qr = new FakeQrClient();
      qr.candidateCookies = [{ name: 'z_c0', value: 'candidate' }, { name: 'd_c0', value: 'device' }];
      qr.pollStates.push(qrState(QrLoginStatus.CREDENTIAL_READY, '待验证'));
      const controller = new LoginController(session, qr, undefined, scheduler);
      controller.activate();

      await controller.startQrLogin();
      await scheduler.runNext();

      expect(session.lastQrCookies.length).assertEqual(2);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.AUTHENTICATED);
      expect(controller.snapshot().profileName).assertEqual('qr-user');
      expect(completesUserAuthentication(LoginPhase.QR_VERIFYING_ACCOUNT, controller.snapshot().phase)).assertTrue();
    });

    it('doesNotTreatCredentialReadyAsLoginWhenIdentityFails', 0, async () => {
      const scheduler = new FakePollScheduler();
      const session = new FakeSessionRepository();
      session.qrResult = {
        status: SessionStatus.ERROR,
        message: '身份验证失败',
        hasRetainedCredentials: false
      };
      const qr = new FakeQrClient();
      qr.candidateCookies = [{ name: 'z_c0', value: 'candidate' }];
      qr.pollStates.push(qrState(QrLoginStatus.CREDENTIAL_READY, '待验证'));
      const controller = new LoginController(session, qr, undefined, scheduler);
      controller.activate();

      await controller.startQrLogin();
      await scheduler.runNext();

      expect(controller.snapshot().phase).assertEqual(LoginPhase.ERROR);
      expect(controller.snapshot().profileName).assertUndefined();
      expect(controller.snapshot().logoutEnabled).assertFalse();
    });

    it('stopsPollingForExpiryAndRiskControl', 0, async () => {
      const expiredScheduler = new FakePollScheduler();
      const expiredQr = new FakeQrClient();
      expiredQr.startState = qrState(QrLoginStatus.EXPIRED, '二维码已过期');
      const expired = new LoginController(new FakeSessionRepository(), expiredQr, undefined, expiredScheduler);
      expired.activate();
      await expired.startQrLogin();
      expect(expired.snapshot().phase).assertEqual(LoginPhase.QR_EXPIRED);
      expect(expiredScheduler.tasks.length).assertEqual(0);

      const riskScheduler = new FakePollScheduler();
      const riskQr = new FakeQrClient();
      riskQr.startState = {
        status: QrLoginStatus.RISK_CONTROL,
        message: '需要验证网络环境',
        riskControlUrl: 'https://www.zhihu.com/account/risk_control/'
      };
      const risk = new LoginController(new FakeSessionRepository(), riskQr, undefined, riskScheduler);
      risk.activate();
      await risk.startQrLogin();
      expect(risk.snapshot().phase).assertEqual(LoginPhase.RISK_CONTROL);
      expect(risk.snapshot().riskControlUrl).assertEqual('https://www.zhihu.com/account/risk_control/');
      expect(riskScheduler.tasks.length).assertEqual(0);
    });

    it('continuesQrAfterRiskControlMergesCookiesAndResumesPolling', 0, async () => {
      const scheduler = new FakePollScheduler();
      const qr = new FakeQrClient();
      qr.startState = {
        status: QrLoginStatus.RISK_CONTROL,
        message: '需要验证网络环境',
        qrLink: 'https://www.zhihu.com/qr',
        riskControlUrl: 'https://www.zhihu.com/account/risk_control/'
      };
      const controller = new LoginController(new FakeSessionRepository(), qr, undefined, scheduler);
      controller.activate();
      await controller.startQrLogin();
      expect(controller.snapshot().phase).assertEqual(LoginPhase.RISK_CONTROL);

      await controller.continueQrAfterRiskControl([
        { name: 'z_c0', value: 'verified-token' },
        { name: 'd_c0', value: 'device-token' }
      ]);
      expect(qr.mergedRiskCookies).assertEqual(2);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.QR_READY);
      expect(controller.snapshot().qrLink).assertEqual('https://www.zhihu.com/qr');
      expect(scheduler.tasks.length).assertEqual(1);
    });

    it('verifiesCapturedLoginCookiesThroughController', 0, async () => {
      const session = new FakeSessionRepository();
      const controller = new LoginController(session, new FakeQrClient());
      controller.activate();

      const cookies: Array<SessionCookie> = [
        { name: 'z_c0', value: 'web-token' },
        { name: 'd_c0', value: 'device-token' }
      ];
      const login = controller.loginWithCookies(cookies);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.VERIFYING_COOKIE);
      await login;

      expect(session.lastQrCookies.length).assertEqual(2);
      expect(session.lastQrCookies[0].name).assertEqual('z_c0');
      expect(session.lastQrCookies[0].value).assertEqual('web-token');
      expect(controller.snapshot().phase).assertEqual(LoginPhase.AUTHENTICATED);
      expect(completesUserAuthentication(LoginPhase.VERIFYING_COOKIE, controller.snapshot().phase)).assertTrue();
    });

    it('cancelsNetworkAndRejectsLateQrResultWhenBackgroundedOrLeft', 0, async () => {
      const scheduler = new FakePollScheduler();
      const session = new FakeSessionRepository();
      const qr = new FakeQrClient();
      const deferred = new Deferred<QrLoginState>();
      qr.startDeferred = deferred;
      const controller = new LoginController(session, qr, undefined, scheduler);
      controller.activate();

      const starting = controller.startQrLogin();
      controller.setForeground(false);
      expect(controller.snapshot().phase).assertEqual(LoginPhase.PAUSED);
      expect(controller.snapshot().manualLoginEnabled).assertFalse();
      expect(controller.snapshot().qrStartEnabled).assertFalse();
      deferred.resolve(qrState(QrLoginStatus.READY, '过期结果', 'https://www.zhihu.com/stale'));
      await starting;
      expect(controller.snapshot().phase).assertEqual(LoginPhase.PAUSED);
      expect(controller.snapshot().qrLink).assertUndefined();
      expect(qr.cancelCount > 0).assertTrue();
      expect(session.cancelCount).assertEqual(0);

      controller.setForeground(true);
      controller.deactivate();
      expect(scheduler.tasks.length).assertEqual(0);
      expect(qr.cancelCount > 1).assertTrue();
      expect(session.cancelCount).assertEqual(0);

      const verifyingSession = new FakeSessionRepository();
      const verification = new Deferred<SessionState>();
      verifyingSession.manualDeferred = verification;
      const verifyingController = new LoginController(verifyingSession, new FakeQrClient());
      verifyingController.activate();
      const manualLogin = verifyingController.loginWithCookieHeader('z_c0=pending-test-value');
      verifyingController.setForeground(false);
      expect(verifyingSession.cancelCount).assertEqual(1);
      verification.resolve(authenticatedState('late-user'));
      await manualLogin;
      expect(verifyingController.snapshot().phase).assertEqual(LoginPhase.PAUSED);
    });
  });
}

function guestState(message: string = '当前为游客模式'): SessionState {
  return {
    status: SessionStatus.GUEST,
    message: message,
    hasRetainedCredentials: false
  };
}

function authenticatedState(name: string): SessionState {
  return {
    status: SessionStatus.AUTHENTICATED,
    message: `已登录：${name}`,
    hasRetainedCredentials: true,
    profile: {
      id: `${name}-id`,
      name: name,
      userType: 'people'
    }
  };
}

function qrState(status: QrLoginStatus, message: string, qrLink?: string): QrLoginState {
  return {
    status: status,
    message: message,
    qrLink: qrLink,
    expiresAt: qrLink === undefined ? undefined : 2000000
  };
}
