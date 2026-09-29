/** P4 页面只能依赖这些窄接口；系统 Kit 的具体对象不得穿过组合根。 */

export * from './ShareContracts';

export interface PickedImage {
  readonly uri: string;
  readonly displayName?: string;
  readonly mimeType?: string;
}

export interface ImagePicker {
  pickImages(maxCount: number): Promise<Array<PickedImage>>;
}

export interface QrScanner {
  scanSingleQrCode(): Promise<string | undefined>;
}

export interface MediaPlaybackSource {
  readonly url: string;
  readonly title: string;
}

export interface MediaPlaybackService {
  play(source: MediaPlaybackSource): Promise<void>;
  pause(): void;
  release(): void;
}

export interface SpeechService {
  speak(text: string): Promise<void>;
  pause(): void;
  resume(): void;
  stop(): void;
}
