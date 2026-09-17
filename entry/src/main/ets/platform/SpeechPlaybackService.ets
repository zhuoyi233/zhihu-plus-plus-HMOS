import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { normalizeSpeechPreferences, SpeechPreferences } from 'data';

export enum SpeechPlaybackStatus {
  IDLE = 'idle',
  INITIALIZING = 'initializing',
  SPEAKING = 'speaking',
  ERROR = 'error'
}

export interface SpeechPlaybackSnapshot {
  status: SpeechPlaybackStatus;
  requestId: string;
  contentId: string;
  title: string;
  message: string;
}

const INITIAL_SNAPSHOT: SpeechPlaybackSnapshot = {
  status: SpeechPlaybackStatus.IDLE,
  requestId: '',
  contentId: '',
  title: '',
  message: ''
};

function errorMessage(error: Object): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return '语音引擎初始化失败';
}

export class SpeechPlaybackService {
  private engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private enginePerson: number = -1;
  private engineLanguage: string = '';
  private engineStyle: string = '';
  private requestSequence: number = 0;
  private activeRequestId: string = '';
  private operationGeneration: number = 0;
  private snapshot: SpeechPlaybackSnapshot = INITIAL_SNAPSHOT;

  getSnapshot(): SpeechPlaybackSnapshot {
    return {
      status: this.snapshot.status,
      requestId: this.snapshot.requestId,
      contentId: this.snapshot.contentId,
      title: this.snapshot.title,
      message: this.snapshot.message
    };
  }

  async speak(contentId: string, title: string, text: string, preferences: SpeechPreferences): Promise<void> {
    const normalizedText = text.trim().slice(0, 10000);
    if (normalizedText.length === 0) {
      this.publish(SpeechPlaybackStatus.ERROR, '', contentId, title, '当前内容没有可朗读的文字');
      return;
    }
    const normalized = normalizeSpeechPreferences(preferences);
    this.stop();
    const generation = this.operationGeneration;
    this.publish(SpeechPlaybackStatus.INITIALIZING, '', contentId, title, '正在准备语音引擎…');
    try {
      const engine = await this.ensureEngine(normalized);
      if (generation !== this.operationGeneration) {
        return;
      }
      this.requestSequence += 1;
      const requestId = `zhplus${Date.now()}${this.requestSequence}`;
      this.activeRequestId = requestId;
      const extraParams: Record<string, Object> = {
        'speed': normalized.speed,
        'volume': 1,
        'pitch': normalized.pitch,
        'languageContext': normalized.language,
        'audioType': 'pcm',
        'soundChannel': 3,
        'playType': 1,
        'queueMode': 1
      };
      engine.speak(normalizedText, { requestId: requestId, extraParams: extraParams });
      this.publish(SpeechPlaybackStatus.SPEAKING, requestId, contentId, title, '正在朗读');
    } catch (error) {
      if (generation !== this.operationGeneration) {
        return;
      }
      const detail: Object = error instanceof Error ? error : new Error('语音引擎初始化失败');
      this.publish(SpeechPlaybackStatus.ERROR, '', contentId, title, errorMessage(detail));
    }
  }

  stop(): void {
    this.operationGeneration += 1;
    if (this.engine !== undefined && this.activeRequestId.length > 0) {
      try {
        this.engine.stop();
      } catch (_error) {
      }
    }
    this.activeRequestId = '';
    if (this.snapshot.status !== SpeechPlaybackStatus.IDLE) {
      this.publish(SpeechPlaybackStatus.IDLE, '', '', '', '');
    }
  }

  shutdown(): void {
    this.stop();
    try {
      this.engine?.shutdown();
    } catch (_error) {
    }
    this.engine = undefined;
    this.enginePerson = -1;
    this.engineLanguage = '';
    this.engineStyle = '';
  }

  private async ensureEngine(preferences: SpeechPreferences): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.engine !== undefined && this.enginePerson === preferences.person &&
      this.engineLanguage === preferences.language && this.engineStyle === preferences.style) {
      return this.engine;
    }
    if (this.engine !== undefined) {
      this.engine.shutdown();
      this.engine = undefined;
    }
    const extraParams: Record<string, Object> = {
      'style': preferences.style,
      'locate': 'CN',
      'name': 'ZhihuPlusReading'
    };
    const engine = await textToSpeech.createEngine({
      language: preferences.language,
      person: preferences.person,
      online: 1,
      extraParams: extraParams
    });
    engine.setListener(this.createListener());
    this.engine = engine;
    this.enginePerson = preferences.person;
    this.engineLanguage = preferences.language;
    this.engineStyle = preferences.style;
    return engine;
  }

  private createListener(): textToSpeech.SpeakListener {
    return {
      onStart: (requestId: string, _response: textToSpeech.StartResponse): void => {
        if (requestId === this.activeRequestId) {
          this.publish(SpeechPlaybackStatus.SPEAKING, requestId, this.snapshot.contentId,
            this.snapshot.title, '正在朗读');
        }
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
        if (requestId === this.activeRequestId && response.type === 1) {
          this.activeRequestId = '';
          this.publish(SpeechPlaybackStatus.IDLE, '', '', '', '');
        }
      },
      onStop: (requestId: string, _response: textToSpeech.StopResponse): void => {
        if (requestId === this.activeRequestId) {
          this.activeRequestId = '';
          this.publish(SpeechPlaybackStatus.IDLE, '', '', '', '');
        }
      },
      onError: (requestId: string, errorCode: number, errorText: string): void => {
        if (requestId === this.activeRequestId || this.activeRequestId.length === 0) {
          this.activeRequestId = '';
          this.publish(SpeechPlaybackStatus.ERROR, requestId, this.snapshot.contentId,
            this.snapshot.title, `朗读失败（${errorCode}）：${errorText}`);
        }
      }
    };
  }

  private publish(status: SpeechPlaybackStatus, requestId: string, contentId: string,
    title: string, message: string): void {
    this.snapshot = {
      status: status,
      requestId: requestId,
      contentId: contentId,
      title: title,
      message: message
    };
    AppStorage.setOrCreate('speechPlaybackSnapshot', this.getSnapshot());
    const tick = (AppStorage.get<number>('speechPlaybackTick') ?? 0) + 1;
    AppStorage.setOrCreate('speechPlaybackTick', tick);
  }
}

let speechPlaybackService: SpeechPlaybackService | undefined = undefined;

export function getSpeechPlaybackService(): SpeechPlaybackService {
  if (speechPlaybackService === undefined) {
    speechPlaybackService = new SpeechPlaybackService();
  }
  return speechPlaybackService;
}
