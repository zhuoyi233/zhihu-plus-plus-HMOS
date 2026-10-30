/**
 * 想法详情页的屏蔽弹层状态（#119）。
 *
 * 屏蔽确认与关键词输入共用一个活动弹层：同一时刻只开一个，提交期间防重入，
 * 失败保留输入并就地提示，成功关闭并清空。规则写入仍由 BlockingActionController
 * 承担，这里只负责"弹层怎么进退"，不复制校验之外的数据逻辑。
 */
import { validateBlockingKeyword } from 'data';

/** 当前活动弹层：一次只允许一个。 */
export enum PinBlockDialogKind {
  NONE = 'none',
  USER = 'user',
  KEYWORD = 'keyword'
}

export interface PinBlockDialogViewState {
  readonly kind: PinBlockDialogKind;
  readonly input: string;
  readonly errorMessage: string;
  readonly submitting: boolean;
}

export type PinBlockDialogObserver = (state: PinBlockDialogViewState) => void;

/** 提交回调：返回 true 表示规则已写入（弹层关闭），false 表示失败（保留输入）。 */
export type PinBlockSubmitter = (kind: PinBlockDialogKind, value: string) => Promise<boolean>;

/** 关键词格式不合法时的就地提示（与 validateBlockingKeyword 的 1–200 字限制一致）。 */
export const PIN_KEYWORD_INVALID_MESSAGE: string = '关键词需为 1–200 个可见字符';

export function emptyPinBlockDialogView(): PinBlockDialogViewState {
  return {
    kind: PinBlockDialogKind.NONE,
    input: '',
    errorMessage: '',
    submitting: false
  };
}

export class PinBlockDialogState {
  private view: PinBlockDialogViewState = emptyPinBlockDialogView();
  private readonly observer: PinBlockDialogObserver;
  /** 页面已离开：后续迟到结果只更新本地状态，不再回调界面。 */
  private disposed: boolean = false;
  /** 弹层代数：关闭或重开后，之前发起的提交结果一律丢弃。 */
  private generation: number = 0;

  constructor(observer: PinBlockDialogObserver = (_state: PinBlockDialogViewState): void => {}) {
    this.observer = observer;
  }

  snapshot(): PinBlockDialogViewState {
    return {
      kind: this.view.kind,
      input: this.view.input,
      errorMessage: this.view.errorMessage,
      submitting: this.view.submitting
    };
  }

  openUser(): void {
    this.generation += 1;
    this.publish({
      kind: PinBlockDialogKind.USER,
      input: '',
      errorMessage: '',
      submitting: false
    });
  }

  openKeyword(): void {
    this.generation += 1;
    this.publish({
      kind: PinBlockDialogKind.KEYWORD,
      input: '',
      errorMessage: '',
      submitting: false
    });
  }

  /** 取消不写规则，也不保留输入；提交中忽略（按钮同时置灰）。 */
  cancel(): void {
    if (this.view.submitting) {
      return;
    }
    this.close();
  }

  /** 关键词输入：每次修改清除上一次的就地错误。 */
  updateInput(value: string): void {
    if (this.view.kind !== PinBlockDialogKind.KEYWORD || this.view.submitting) {
      return;
    }
    this.publish({
      kind: PinBlockDialogKind.KEYWORD,
      input: value,
      errorMessage: '',
      submitting: false
    });
  }

  /**
   * 提交：空关键词或格式不合法时只在弹层内提示，不写规则；
   * 提交中再次触发直接忽略（防重入）；失败保留输入，成功关闭并清空。
   */
  async submit(submitter: PinBlockSubmitter, actionLabel: string): Promise<void> {
    if (this.view.kind === PinBlockDialogKind.NONE || this.view.submitting) {
      return;
    }
    const kind = this.view.kind;
    let value = this.view.input;
    if (kind === PinBlockDialogKind.KEYWORD) {
      try {
        value = validateBlockingKeyword(this.view.input, false);
      } catch (_error) {
        this.publish({
          kind: PinBlockDialogKind.KEYWORD,
          input: this.view.input,
          errorMessage: PIN_KEYWORD_INVALID_MESSAGE,
          submitting: false
        });
        return;
      }
    }
    this.publish({
      kind: kind,
      input: value,
      errorMessage: '',
      submitting: true
    });
    const generation = this.generation;
    let success = false;
    try {
      success = await submitter(kind, value);
    } catch (_error) {
      success = false;
    }
    // 弹层在这期间已被取消、关闭或重开：迟到结果不再改写当前状态。
    if (generation !== this.generation) {
      return;
    }
    if (success) {
      this.close();
      return;
    }
    this.publish({
      kind: kind,
      input: value,
      errorMessage: `${actionLabel}失败，请重试`,
      submitting: false
    });
  }

  /** 页面消失：丢弃后续回调，避免迟到结果改写已离开的界面。 */
  dispose(): void {
    this.disposed = true;
  }

  /**
   * 页面重新可见：强制回到关闭态（忽略提交中标记），
   * 避免上一次未完成的弹层状态残留到新的交互里。
   */
  resetForReappear(): void {
    this.close();
  }

  private close(): void {
    this.generation += 1;
    this.publish(emptyPinBlockDialogView());
  }

  private publish(state: PinBlockDialogViewState): void {
    this.view = state;
    if (!this.disposed) {
      this.observer(this.view);
    }
  }
}
