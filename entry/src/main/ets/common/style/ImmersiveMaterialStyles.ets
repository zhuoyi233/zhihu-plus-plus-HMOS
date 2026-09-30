import { ImmersiveMaterialMode } from 'data';

/**
 * 沉浸光感统一策略（纯映射）：用户挡位 + 设备能力 → 实际生效挡位。
 * 本文件不导入 @kit.UIDesignKit（本地单测 host 对 HMS kit 无桩，导入会破坏测试装载），
 * HDS 枚举转换见 HdsMaterialLevels.ets。策略表见 docs/immersive-material-settings-plan.md §4。
 */

/** 设备沉浸材质能力三态：支持 / 不支持 / 查询失败。 */
export enum ImmersiveMaterialSupportState {
  SUPPORTED = 'supported',
  UNSUPPORTED = 'unsupported',
  UNKNOWN = 'unknown'
}

/** AppStorage 广播值（字符串）→ 能力三态；未知值按查询失败处理。 */
export function decodeImmersiveMaterialSupport(value: string | undefined): ImmersiveMaterialSupportState {
  if (value === ImmersiveMaterialSupportState.SUPPORTED) {
    return ImmersiveMaterialSupportState.SUPPORTED;
  }
  if (value === ImmersiveMaterialSupportState.UNSUPPORTED) {
    return ImmersiveMaterialSupportState.UNSUPPORTED;
  }
  return ImmersiveMaterialSupportState.UNKNOWN;
}

/**
 * 实际生效挡位：自适应恒为 ADAPTIVE（系统按设备能力自选）；
 * 精美/轻柔仅在设备支持 IMMERSIVE 时生效，不支持或查询失败回落 SMOOTH；流畅恒为 SMOOTH。
 * 设备能力由调用方提供（启动时查询一次并广播），勿在 build 中反复查询设备。
 * 查询失败只影响本次生效策略，不改变用户保存的选择。
 */
export function resolveImmersiveMaterialLevel(mode: ImmersiveMaterialMode,
  support: ImmersiveMaterialSupportState): ImmersiveMaterialMode {
  if (mode === ImmersiveMaterialMode.EXQUISITE || mode === ImmersiveMaterialMode.GENTLE) {
    return support === ImmersiveMaterialSupportState.SUPPORTED ? mode : ImmersiveMaterialMode.SMOOTH;
  }
  return mode;
}

/** 四挡显示名（设置页段控与文档共用一张表）。 */
export function immersiveMaterialModeLabel(mode: ImmersiveMaterialMode): string {
  if (mode === ImmersiveMaterialMode.EXQUISITE) {
    return '精美';
  }
  if (mode === ImmersiveMaterialMode.GENTLE) {
    return '轻柔';
  }
  if (mode === ImmersiveMaterialMode.SMOOTH) {
    return '流畅';
  }
  return '自适应';
}

/** 四挡说明文案（设置页控件下方展示当前选项说明）。 */
export function immersiveMaterialModeDescription(mode: ImmersiveMaterialMode): string {
  if (mode === ImmersiveMaterialMode.EXQUISITE) {
    return '更精美的材质效果，性能开销较高';
  }
  if (mode === ImmersiveMaterialMode.GENTLE) {
    return '使用轻柔的材质效果';
  }
  if (mode === ImmersiveMaterialMode.SMOOTH) {
    return '优先保证流畅，减少材质性能开销';
  }
  return '根据设备性能自动选择材质效果';
}

/** 段控选项顺序：自适应 / 精美 / 轻柔 / 流畅。 */
export function allImmersiveMaterialModes(): ImmersiveMaterialMode[] {
  return [ImmersiveMaterialMode.ADAPTIVE, ImmersiveMaterialMode.EXQUISITE,
    ImmersiveMaterialMode.GENTLE, ImmersiveMaterialMode.SMOOTH];
}

/** 挡位在段控选项中的下标；未知值回退自适应（下标 0）。 */
export function immersiveMaterialModeIndex(mode: ImmersiveMaterialMode): number {
  const index = allImmersiveMaterialModes().indexOf(mode);
  return index >= 0 ? index : 0;
}

/** 生效策略提示：选择精美/轻柔但设备不支持或查询失败时给出降级说明；其余返回空串。 */
export function immersiveMaterialEffectiveNotice(mode: ImmersiveMaterialMode,
  support: ImmersiveMaterialSupportState): string {
  if (mode !== ImmersiveMaterialMode.EXQUISITE && mode !== ImmersiveMaterialMode.GENTLE) {
    return '';
  }
  if (support === ImmersiveMaterialSupportState.UNSUPPORTED) {
    return '当前设备暂不支持所选效果，已使用兼容效果';
  }
  if (support === ImmersiveMaterialSupportState.UNKNOWN) {
    return '暂时无法确认设备支持情况，已使用兼容效果';
  }
  return '';
}
