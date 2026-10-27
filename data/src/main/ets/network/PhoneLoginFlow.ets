/** 手机号登录流程的纯逻辑守卫。
 *
 * 抽出来是为了让“按钮可用性 / 发送冷却 / 已发码身份 / 迟到回调”这些容易出错的规则
 * 可以在宿主测试里覆盖，不必依赖 ArkUI 组件状态。
 */

/** 短信验证码位数（对齐上游与知乎接口）。 */
export const PHONE_CODE_LENGTH: number = 6;
/** 重新发送冷却秒数（按到期时间计算，切换地区或号码不清零）。 */
export const PHONE_RESEND_COOLDOWN_SECONDS: number = 60;

/** 发送验证码按钮的可用条件。 */
export interface PhoneDigitsGuard {
  readonly agreementChecked: boolean;
  readonly numberValid: boolean;
  readonly cooldownSeconds: number;
  readonly busy: boolean;
}

/** 登录按钮的可用条件。 */
export interface PhoneSignInGuard {
  readonly agreementChecked: boolean;
  readonly numberValid: boolean;
  readonly codeLength: number;
  /** 当前地区+号码与“上一次成功发送验证码”的身份一致。 */
  readonly requestedIdentityMatches: boolean;
  readonly busy: boolean;
}

export function canRequestPhoneDigits(guard: PhoneDigitsGuard): boolean {
  return guard.agreementChecked && guard.numberValid &&
    guard.cooldownSeconds <= 0 && !guard.busy;
}

export function canSignInWithPhone(guard: PhoneSignInGuard): boolean {
  return guard.agreementChecked && guard.numberValid &&
    guard.codeLength === PHONE_CODE_LENGTH && guard.requestedIdentityMatches && !guard.busy;
}

/**
 * 已发码身份键：地区 + 完整 username。
 * 美国切换加拿大同用 +1 也必须视为不同身份，因此不能只用区号。
 */
export function phoneLoginIdentityKey(regionId: string, username: string): string {
  if (username.length === 0) {
    return '';
  }
  return `${regionId}|${username}`;
}

/** 身份变化（含同码地区切换）后旧验证码与图形验证码状态必须失效。 */
export function shouldResetPhoneDigits(previousIdentity: string, nextIdentity: string): boolean {
  return previousIdentity !== nextIdentity;
}

/** 按到期时间计算剩余冷却秒数；返回 0 表示可再次发送。 */
export function phoneCooldownRemainingSeconds(deadlineMs: number, nowMs: number): number {
  if (deadlineMs <= 0 || nowMs >= deadlineMs) {
    return 0;
  }
  return Math.ceil((deadlineMs - nowMs) / 1000);
}

/**
 * 请求代次守卫：每次发起请求取一个新 token，迟到的回调（页面退出、身份已变更、
 * 更新的请求已开始）用 isCurrent 判断后直接丢弃，不修改状态也不触发登录成功回调。
 */
export class PhoneLoginRequestGeneration {
  private current: number = 0;

  begin(): number {
    this.current += 1;
    return this.current;
  }

  invalidate(): void {
    this.current += 1;
  }

  isCurrent(token: number): boolean {
    return token > 0 && token === this.current;
  }
}

/** 校验结果是否可用于发送（供 UI 直接把策略结果映射成按钮状态）。 */
export function resolutionAllowsSend(numberValid: boolean, agreementChecked: boolean,
  cooldownSeconds: number, busy: boolean): boolean {
  const guard: PhoneDigitsGuard = {
    agreementChecked: agreementChecked,
    numberValid: numberValid,
    cooldownSeconds: cooldownSeconds,
    busy: busy
  };
  return canRequestPhoneDigits(guard);
}
