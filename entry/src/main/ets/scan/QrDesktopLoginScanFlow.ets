import { assessQrScanValue, QrScanDecision } from 'core';
import { QrScanner } from '../platform/P4PlatformServices';

export enum QrDesktopLoginScanPhase {
  READY = 'ready',
  SCANNING = 'scanning',
  AWAITING_CONFIRMATION = 'awaiting_confirmation',
  HANDOFF_READY = 'handoff_ready',
  CANCELLED = 'cancelled',
  ERROR = 'error'
}

/** 页面状态永远不包含扫码 URL 或登录 token。 */
export interface QrDesktopLoginScanViewState {
  readonly phase: QrDesktopLoginScanPhase;
  readonly message: string;
  readonly scanEnabled: boolean;
  readonly confirmEnabled: boolean;
  readonly cancelEnabled: boolean;
}

/**
 * 专用确认请求的 CSRF/风控合同尚未冻结。
 * 该对象只传递固定来源和用户意图；实际 URL 只留在控制器内存，后续受限 ArkWeb
 * 适配器必须在明确确认后单次取用它，且不得持久化、记录或用于任意导航。
 */
export interface QrDesktopLoginHandoff {
  readonly source: string;
  readonly requiresExplicitConfirmation: boolean;
}

export class QrDesktopLoginScanController {
  private readonly onStateChanged: (state: QrDesktopLoginScanViewState) => void;
  private generation: number = 0;
  private foreground: boolean = true;
  private phase: QrDesktopLoginScanPhase = QrDesktopLoginScanPhase.READY;
  private scannedUrl: string | undefined = undefined;

  constructor(onStateChanged: (state: QrDesktopLoginScanViewState) => void) {
    this.onStateChanged = onStateChanged;
    this.emit('请扫描电脑端显示的知乎登录二维码');
  }

  async scan(scanner: QrScanner): Promise<void> {
    if (!this.foreground || this.phase === QrDesktopLoginScanPhase.SCANNING) {
      return;
    }
    this.scannedUrl = undefined;
    this.phase = QrDesktopLoginScanPhase.SCANNING;
    const currentGeneration = this.nextGeneration();
    this.emit('正在打开系统扫码界面…');
    try {
      const value = await scanner.scanSingleQrCode();
      if (!this.isCurrent(currentGeneration)) {
        return;
      }
      if (value === undefined) {
        this.phase = QrDesktopLoginScanPhase.CANCELLED;
        this.emit('已取消扫码，未发送任何登录请求');
        return;
      }
      const assessment = assessQrScanValue(value);
      if (assessment.decision !== QrScanDecision.ZHIHU_DESKTOP_LOGIN) {
        this.phase = QrDesktopLoginScanPhase.ERROR;
        this.emit(assessment.message);
        return;
      }
      this.scannedUrl = value;
      this.phase = QrDesktopLoginScanPhase.AWAITING_CONFIRMATION;
      this.emit('已识别知乎电脑端登录二维码，请确认是否登录电脑');
    } catch (_error) {
      if (!this.isCurrent(currentGeneration)) {
        return;
      }
      this.phase = QrDesktopLoginScanPhase.ERROR;
      this.emit('扫码服务暂不可用，请稍后重试');
    }
  }

  confirm(): QrDesktopLoginHandoff | undefined {
    if (this.phase !== QrDesktopLoginScanPhase.AWAITING_CONFIRMATION || this.scannedUrl === undefined) {
      return undefined;
    }
    this.phase = QrDesktopLoginScanPhase.HANDOFF_READY;
    this.emit('已完成用户确认；当前不会自动提交登录请求');
    return {
      source: 'www.zhihu.com',
      requiresExplicitConfirmation: true
    };
  }

  /** 受限确认页只能在 confirm 之后调用一次，调用后立即清除内存中的扫码 URL。 */
  takeConfirmedUrl(): string | undefined {
    if (this.phase !== QrDesktopLoginScanPhase.HANDOFF_READY) {
      return undefined;
    }
    const value = this.scannedUrl;
    this.scannedUrl = undefined;
    return value;
  }

  cancel(): void {
    this.nextGeneration();
    this.scannedUrl = undefined;
    this.phase = QrDesktopLoginScanPhase.CANCELLED;
    this.emit('已取消电脑端登录确认，未发送任何登录请求');
  }

  setForeground(foreground: boolean): void {
    if (this.foreground === foreground) {
      return;
    }
    this.foreground = foreground;
    this.nextGeneration();
    this.scannedUrl = undefined;
    this.phase = QrDesktopLoginScanPhase.READY;
    this.emit(foreground ? '已返回前台，请重新扫描二维码' : '应用已进入后台，已清除扫码结果');
  }

  private nextGeneration(): number {
    this.generation += 1;
    return this.generation;
  }

  private isCurrent(generation: number): boolean {
    return this.foreground && generation === this.generation;
  }

  private emit(message: string): void {
    this.onStateChanged({
      phase: this.phase,
      message: message,
      scanEnabled: this.foreground && this.phase !== QrDesktopLoginScanPhase.SCANNING &&
        this.phase !== QrDesktopLoginScanPhase.AWAITING_CONFIRMATION &&
        this.phase !== QrDesktopLoginScanPhase.HANDOFF_READY,
      confirmEnabled: this.phase === QrDesktopLoginScanPhase.AWAITING_CONFIRMATION,
      cancelEnabled: this.phase === QrDesktopLoginScanPhase.SCANNING ||
        this.phase === QrDesktopLoginScanPhase.AWAITING_CONFIRMATION
    });
  }
}
