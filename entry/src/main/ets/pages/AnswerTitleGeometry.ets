/** List 使用信息头 padding 让位，offset 从 0 起算；这里只补偿一次有效视口顶部。 */
export interface AnswerTitlePresentation {
  compact: boolean;
  authorVisible: boolean;
  materialVisible: boolean;
}

interface AnswerIdentityMeasurement {
  layout: string;
  height: number;
  presentation: AnswerTitlePresentation;
}

export class AnswerTitleGeometry {
  private readonly measurements: Map<string, Map<string, AnswerIdentityMeasurement>> = new Map();

  retain(keys: string[]): void {
    for (const key of Array.from(this.measurements.keys())) {
      if (!keys.includes(key)) { this.measurements.delete(key); }
    }
  }

  measured(key: string, layout: string): boolean {
    return this.measurements.get(key)?.has(layout) === true;
  }

  measure(key: string, layout: string, height: number): boolean {
    if (!Number.isFinite(height) || height < 0) { return false; }
    let layouts = this.measurements.get(key);
    if (layouts === undefined) {
      layouts = new Map<string, AnswerIdentityMeasurement>();
      this.measurements.set(key, layouts);
    }
    const previous = layouts.get(layout);
    if (previous?.height === height) { return false; }
    // 沉浸切换时信息头可能已离屏；保留普通模式实测，返回时不依赖再次挂载测量。
    layouts.set(layout, { layout: layout, height: height,
      presentation: previous?.presentation ?? this.empty() });
    return true;
  }

  resolve(key: string, layout: string, offset: number, contentInset: number, viewportTop: number,
    persistent: boolean, hasAuthor: boolean): AnswerTitlePresentation {
    const measured = this.measurements.get(key)?.get(layout);
    const valid = measured !== undefined;
    const previous = valid ? measured.presentation : this.empty();
    // 信息头起点 = List 的 16vp 顶部 padding + 可滚动让位；信息区下缘越过有效视口才接管身份。
    const bottom = valid ? 16 + contentInset + measured.height - offset - viewportTop : Number.POSITIVE_INFINITY;
    // 2vp 回差只放在已完全移出之后；回滚触及下缘即撤回摘要，不提前重复作者。
    const identityGone = bottom <= (previous.authorVisible || (!persistent && previous.compact) ? 0 : -2);
    const result: AnswerTitlePresentation = {
      compact: persistent ? offset >= (previous.compact ? 4 : 8) : identityGone,
      authorVisible: hasAuthor && identityGone,
      materialVisible: offset > 0
    };
    if (valid) { measured.presentation = result; }
    return result;
  }

  private empty(): AnswerTitlePresentation {
    return { compact: false, authorVisible: false, materialVisible: false };
  }
}
