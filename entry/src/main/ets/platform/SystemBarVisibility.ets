/** 每个窗口串行应用目标；只有成功才去重，旧窗口完成不能改写新窗口状态。 */
export interface SystemBarVisibilityPort {
  apply(hidden: boolean): Promise<void>;
}

export class SystemBarVisibility {
  private port: SystemBarVisibilityPort | undefined = undefined;
  private generation: number = 0;
  private desired: boolean = false;
  private applied: boolean | undefined = undefined;
  private pending: boolean = false;
  private onShown: () => void;

  constructor(onShown: () => void) { this.onShown = onShown; }

  bind(port: SystemBarVisibilityPort): void {
    this.generation += 1;
    this.port = port;
    this.applied = undefined;
    this.pending = false;
    this.flush();
  }

  detach(): void {
    this.generation += 1;
    this.port = undefined;
    this.applied = undefined;
    this.pending = false;
  }

  request(hidden: boolean): void {
    this.desired = hidden;
    this.flush();
  }

  retry(): void { this.flush(); }

  isShown(): boolean { return !this.desired && this.applied === false && !this.pending; }

  private flush(): void {
    const port = this.port;
    if (port === undefined || this.pending || this.applied === this.desired) { return; }
    const generation = this.generation;
    const hidden = this.desired;
    this.pending = true;
    try {
      port.apply(hidden).then((): void => this.finish(generation, hidden, true))
        .catch((_error: Object): void => this.finish(generation, hidden, false));
    } catch (_error) {
      this.finish(generation, hidden, false);
    }
  }

  private finish(generation: number, hidden: boolean, succeeded: boolean): void {
    if (generation !== this.generation) { return; }
    this.pending = false;
    // 失败可能已有部分系统副作用，不能继续依赖上次成功值。
    this.applied = succeeded ? hidden : undefined;
    if (succeeded && !hidden && !this.desired) { this.onShown(); }
    // 目标在等待中改变时收敛到最新目标；同目标失败等下一次请求重试，避免忙循环。
    if (this.desired !== hidden) { this.flush(); }
  }
}
