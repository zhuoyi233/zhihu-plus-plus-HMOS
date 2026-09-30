import { preferences } from '@kit.ArkData';

/**
 * 沉浸光感挡位（用户选择）：存储值即枚举值，对应 HDS 的 ADAPTIVE / EXQUISITE / GENTLE /
 * SMOOTH 四挡（映射由 UI 层完成）。数据层只保存产品选项，不引入 @kit.UIDesignKit。
 */
export enum ImmersiveMaterialMode {
  ADAPTIVE = 'adaptive',
  EXQUISITE = 'exquisite',
  GENTLE = 'gentle',
  SMOOTH = 'smooth'
}

/** 默认自适应（官方推荐值）：缺失、旧版本未存储、错误类型、未知字符串统一回退。 */
export const DEFAULT_IMMERSIVE_MATERIAL_MODE: ImmersiveMaterialMode = ImmersiveMaterialMode.ADAPTIVE;

/** AppStorage 广播值（字符串）→ 挡位；未知值回退自适应。 */
export function decodeImmersiveMaterialModeText(value: string | undefined): ImmersiveMaterialMode {
  if (value === ImmersiveMaterialMode.EXQUISITE) {
    return ImmersiveMaterialMode.EXQUISITE;
  }
  if (value === ImmersiveMaterialMode.GENTLE) {
    return ImmersiveMaterialMode.GENTLE;
  }
  if (value === ImmersiveMaterialMode.SMOOTH) {
    return ImmersiveMaterialMode.SMOOTH;
  }
  return DEFAULT_IMMERSIVE_MATERIAL_MODE;
}

/** 偏好存储原始值 → 挡位；非字符串（含缺失）按未存储处理。 */
export function decodeImmersiveMaterialMode(value: preferences.ValueType): ImmersiveMaterialMode {
  if (typeof value === 'string') {
    return decodeImmersiveMaterialModeText(value);
  }
  return DEFAULT_IMMERSIVE_MATERIAL_MODE;
}
