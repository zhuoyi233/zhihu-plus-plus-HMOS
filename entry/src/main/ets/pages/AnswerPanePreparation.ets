/** 按文档实例键汇合解析和视口事件；移除、重置及超时均解除等待。 */
export class AnswerPanePreparation {
  private readonly mounted: Set<string> = new Set();
  private readonly parsed: Set<string> = new Set();
  private readonly viewports: Set<string> = new Set();
  private waitingKey: string = '';
  private waiter?: (ready: boolean) => void;
  private timer: number = -1;

  retain(keys: string[]): void {
    const retained = new Set<string>(keys);
    for (const key of Array.from(this.mounted)) {
      if (!retained.has(key)) {
        this.mounted.delete(key);
        this.parsed.delete(key);
        this.viewports.delete(key);
      }
    }
    for (const key of keys) { this.mounted.add(key); }
    if (this.waitingKey.length > 0 && !this.mounted.has(this.waitingKey)) { this.finish(false); }
  }

  has(key: string): boolean { return this.mounted.has(key); }

  ready(key: string): boolean {
    return this.mounted.has(key) && this.parsed.has(key) && this.viewports.has(key);
  }

  documentPrepared(key: string): boolean {
    if (!this.mounted.has(key)) { return false; }
    this.parsed.add(key);
    if (key === this.waitingKey && this.ready(key)) { this.finish(true); }
    return true;
  }

  viewportPrepared(key: string, ready: boolean): boolean {
    if (!this.mounted.has(key)) { return false; }
    if (ready) { this.viewports.add(key); } else { this.viewports.delete(key); }
    if (key === this.waitingKey && this.ready(key)) { this.finish(true); }
    return true;
  }

  wait(key: string, timeoutMs: number = 8000): Promise<boolean> {
    this.finish(false);
    if (!this.mounted.has(key)) { return Promise.resolve(false); }
    if (this.ready(key)) { return Promise.resolve(true); }
    return new Promise<boolean>((resolve: (ready: boolean) => void): void => {
      this.waitingKey = key;
      this.waiter = resolve;
      this.timer = setTimeout((): void => this.finish(false), timeoutMs);
    });
  }

  cancelWait(): void { this.finish(false); }

  reset(): void {
    this.finish(false);
    this.mounted.clear();
    this.parsed.clear();
    this.viewports.clear();
  }

  private finish(ready: boolean): void {
    if (this.timer >= 0) { clearTimeout(this.timer); }
    this.timer = -1;
    const waiter = this.waiter;
    this.waiter = undefined;
    this.waitingKey = '';
    waiter?.(ready);
  }
}
