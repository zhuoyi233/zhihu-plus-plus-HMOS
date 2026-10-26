export interface ContinuousReferenceRect {
  y: number;
  height: number;
}

export interface ContinuousReferenceHost {
  indexOf: (key: string) => number;
  rectAt: (index: number) => ContinuousReferenceRect;
  scrollToRow: (index: number) => void;
  scrollBy: (delta: number) => void;
  viewportHeight: () => number;
  readingLine: () => number;
  onSettled: () => void;
}

interface ReferenceAnchor {
  answerId: string;
  key: string;
  fraction: number;
  viewportFraction: number;
}

/** 脚注往返不保存 LazyForEach 的估计总偏移；按稳定行身份落定，再校准块内位置。 */
export class ContinuousReferenceNavigator {
  private readonly host: ContinuousReferenceHost;
  private readonly returns: Map<string, ReferenceAnchor> = new Map();
  private target?: ReferenceAnchor;
  private timer: number = -1;
  private stable: number = 0;
  private attempt: number = 0;

  constructor(host: ContinuousReferenceHost) {
    this.host = host;
  }

  isNavigating(): boolean {
    return this.target !== undefined;
  }

  open(answerId: string, numero: number, sourceKey: string, referenceKey: string): void {
    if (this.host.indexOf(referenceKey) < 0) { return; }
    const index = this.host.indexOf(sourceKey);
    const height = this.host.viewportHeight();
    if (index >= 0 && height > 0) {
      const rect = this.host.rectAt(index);
      if (rect.height > 0) {
        const line = Math.max(rect.y, Math.min(this.host.readingLine(), rect.y + rect.height));
        this.returns.set(`${answerId}:${numero}`, {
          answerId: answerId, key: sourceKey,
          fraction: Math.max(0, Math.min(1, (line - rect.y) / rect.height)),
          viewportFraction: line / height
        });
      }
    }
    this.start(this.topAnchor(answerId, referenceKey));
  }

  back(answerId: string, numero: number, fallbackKey: string): void {
    const anchor = this.returns.get(`${answerId}:${numero}`);
    if (anchor !== undefined && this.host.indexOf(anchor.key) >= 0) {
      this.start(anchor);
    } else if (fallbackKey.length > 0) {
      this.start(this.topAnchor(answerId, fallbackKey));
    }
  }

  cancel(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); }
    this.timer = -1;
    this.target = undefined;
  }

  clear(): void {
    this.cancel();
    this.returns.clear();
  }

  removeAnswer(answerId: string): void {
    const stale: Array<string> = [];
    this.returns.forEach((anchor: ReferenceAnchor, key: string): void => {
      if (anchor.answerId === answerId) { stale.push(key); }
    });
    stale.forEach((key: string): void => { this.returns.delete(key); });
    if (this.target?.answerId === answerId) { this.cancel(); }
  }

  private topAnchor(answerId: string, key: string): ReferenceAnchor {
    return { answerId: answerId, key: key, fraction: 0,
      viewportFraction: this.host.readingLine() / Math.max(1, this.host.viewportHeight()) };
  }

  private start(anchor: ReferenceAnchor): void {
    this.cancel();
    this.target = anchor;
    this.stable = 0;
    this.attempt = 0;
    this.tick();
  }

  private tick(): void {
    const target = this.target;
    if (target === undefined) { return; }
    const index = this.host.indexOf(target.key);
    if (index < 0 || this.attempt++ >= 24) {
      this.finish();
      return;
    }
    const rect = this.host.rectAt(index);
    if (rect.height <= 0) {
      this.stable = 0;
      this.host.scrollToRow(index);
    } else {
      const expectedY = target.viewportFraction * this.host.viewportHeight() - target.fraction * rect.height;
      const delta = rect.y - expectedY;
      if (Math.abs(delta) > 1) {
        this.stable = 0;
        this.host.scrollBy(delta);
      } else if (++this.stable >= 3) {
        this.finish();
        return;
      }
    }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.tick();
    }, 100);
  }

  private finish(): void {
    this.cancel();
    this.host.onSettled();
  }
}
