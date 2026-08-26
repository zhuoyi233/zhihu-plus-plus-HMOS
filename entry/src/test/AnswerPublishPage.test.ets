import { describe, expect, it } from '@ohos/hypium';
import {
  LocalDraftImageReference,
  LoginSessionGateway,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  AnswerPublishObserver,
  AnswerPublishImageUploader,
  AnswerPublishPhase,
  AnswerPublishViewState
} from '../main/ets/pages/AnswerPublishState';
import {
  AnswerPublishPageController,
  AnswerPublishPageControllerFactory,
  AnswerPublishPageCoordinator,
  AnswerPublishPagePhase,
  AnswerPublishTraceIdFactory
} from '../main/ets/pages/AnswerPublishPage';

class FixedSessionOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class FixedSessionGateway implements LoginSessionGateway {
  private readonly state: SessionState;

  constructor(status: SessionStatus) {
    this.state = {
      status: status,
      message: status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED,
      profile: status === SessionStatus.AUTHENTICATED
        ? { id: 'member-1', name: '测试用户', userType: 'people', avatarUrl: '' }
        : undefined
    };
  }

  getState(): SessionState {
    return this.state;
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new FixedSessionOperation(this.state);
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new FixedSessionOperation(this.state);
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }
}

class FixedTraceIdFactory implements AnswerPublishTraceIdFactory {
  createTraceId(): string {
    return '1770000000000,01234567-89ab-4cde-8fab-0123456789ab';
  }
}

class FakeAnswerPageController implements AnswerPublishPageController {
  observer: AnswerPublishObserver = (_state: AnswerPublishViewState): void => {};
  activateCalls: number = 0;
  deactivateCalls: number = 0;
  openCalls: number = 0;
  saveCalls: number = 0;
  publishTraceIds: Array<string> = [];
  continueCalls: number = 0;
  private state: AnswerPublishViewState = {
    phase: AnswerPublishPhase.IDLE,
    generation: 0,
    questionId: '123',
    html: '',
    tocEnabled: false,
    localImageReferences: [],
    localDraftSaved: false,
    pending: false,
    requiresLogin: false,
    requiresVerification: false,
    canRetry: false
  };

  activate(): void {
    this.activateCalls += 1;
    this.emit();
  }

  deactivate(): void {
    this.deactivateCalls += 1;
  }

  open(): Promise<void> {
    this.openCalls += 1;
    this.state = this.withState({ phase: AnswerPublishPhase.READY });
    this.emit();
    return Promise.resolve();
  }

  updateContent(html: string, tocEnabled: boolean): void {
    this.state = this.withState({ html: html, tocEnabled: tocEnabled, phase: AnswerPublishPhase.READY });
    this.emit();
  }

  updateLocalImageReferences(_references: Array<LocalDraftImageReference>): void {
  }

  saveLocalDraft(_now?: number): Promise<void> {
    this.saveCalls += 1;
    return Promise.resolve();
  }

  uploadLocalImages(_uploader: AnswerPublishImageUploader, _now?: number): Promise<boolean> {
    return Promise.resolve(true);
  }

  publish(traceId: string, _now?: number): Promise<void> {
    this.publishTraceIds.push(traceId);
    return Promise.resolve();
  }

  continueEditingExistingAnswer(): void {
    this.continueCalls += 1;
  }

  snapshot(): AnswerPublishViewState {
    return this.state;
  }

  private withState(change: FakeAnswerPageStateChange): AnswerPublishViewState {
    return {
      phase: change.phase ?? this.state.phase,
      generation: this.state.generation,
      questionId: this.state.questionId,
      answerId: this.state.answerId,
      html: change.html ?? this.state.html,
      tocEnabled: change.tocEnabled ?? this.state.tocEnabled,
      localImageReferences: this.state.localImageReferences,
      localDraftSaved: this.state.localDraftSaved,
      pending: this.state.pending,
      requiresLogin: this.state.requiresLogin,
      requiresVerification: this.state.requiresVerification,
      canRetry: this.state.canRetry
    };
  }

  private emit(): void {
    this.observer(this.state);
  }
}

interface FakeAnswerPageStateChange {
  readonly phase?: AnswerPublishPhase;
  readonly html?: string;
  readonly tocEnabled?: boolean;
}

class FakeControllerFactory implements AnswerPublishPageControllerFactory {
  readonly controller: FakeAnswerPageController = new FakeAnswerPageController();
  createCalls: number = 0;
  questionId?: string;
  answerId?: string;

  create(questionId: string, answerId: string | undefined,
    observer: AnswerPublishObserver): Promise<AnswerPublishPageController | undefined> {
    this.createCalls += 1;
    this.questionId = questionId;
    this.answerId = answerId;
    this.controller.observer = observer;
    return Promise.resolve(this.controller);
  }
}

export default function answerPublishPageTest(): void {
  describe('answerPublishPageTest', () => {
    it('guestDoesNotCreateControllerOrDraftOrNetworkWork', 0, () => {
      const factory = new FakeControllerFactory();
      const coordinator = new AnswerPublishPageCoordinator(new FixedSessionGateway(SessionStatus.GUEST), factory,
        new FixedTraceIdFactory());

      coordinator.activate('123');
      coordinator.saveLocalDraft();
      coordinator.publish();

      expect(coordinator.snapshot().phase).assertEqual(AnswerPublishPagePhase.LOGIN_REQUIRED);
      expect(factory.createCalls).assertEqual(0);
      expect(factory.controller.openCalls).assertEqual(0);
      expect(factory.controller.saveCalls).assertEqual(0);
      expect(factory.controller.publishTraceIds.length).assertEqual(0);
    });

    it('authenticatedPageUsesOnlyInjectedControllerForEditingAndPublishing', 0, (done: Function) => {
      const factory = new FakeControllerFactory();
      const coordinator = new AnswerPublishPageCoordinator(new FixedSessionGateway(SessionStatus.AUTHENTICATED), factory,
        new FixedTraceIdFactory());

      coordinator.activate('123', '456');
      Promise.resolve().then((): void => {
        expect(factory.createCalls).assertEqual(1);
        expect(factory.questionId).assertEqual('123');
        expect(factory.answerId).assertEqual('456');
        expect(factory.controller.activateCalls).assertEqual(1);
        expect(factory.controller.openCalls).assertEqual(1);
        coordinator.updateContent('<p>回答</p>', true);
        coordinator.saveLocalDraft();
        coordinator.publish();
        expect(coordinator.snapshot().canPublish).assertTrue();
        expect(factory.controller.saveCalls).assertEqual(1);
        expect(factory.controller.publishTraceIds[0]).assertEqual('1770000000000,01234567-89ab-4cde-8fab-0123456789ab');
        done();
      });
    });

    it('deactivationReleasesInjectedController', 0, (done: Function) => {
      const factory = new FakeControllerFactory();
      const coordinator = new AnswerPublishPageCoordinator(new FixedSessionGateway(SessionStatus.AUTHENTICATED), factory,
        new FixedTraceIdFactory());

      coordinator.activate('123');
      Promise.resolve().then((): void => {
        coordinator.deactivate();
        expect(coordinator.snapshot().phase).assertEqual(AnswerPublishPagePhase.RELEASED);
        expect(factory.controller.deactivateCalls).assertEqual(1);
        done();
      });
    });
  });
}
