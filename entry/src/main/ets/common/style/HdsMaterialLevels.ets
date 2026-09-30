import { hdsMaterial } from '@kit.UIDesignKit';
import { ImmersiveMaterialMode } from 'data';

/**
 * 产品挡位 → HDS MaterialLevel 转换（UI 消费方专用薄适配）。
 * 本文件依赖 @kit.UIDesignKit，仅供组件/样式代码导入；纯映射与单测
 * 见 ImmersiveMaterialStyles.ets（不得反向依赖本文件）。
 */
export function hdsMaterialLevelFor(mode: ImmersiveMaterialMode): hdsMaterial.MaterialLevel {
  if (mode === ImmersiveMaterialMode.EXQUISITE) {
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }
  if (mode === ImmersiveMaterialMode.GENTLE) {
    return hdsMaterial.MaterialLevel.GENTLE;
  }
  if (mode === ImmersiveMaterialMode.SMOOTH) {
    return hdsMaterial.MaterialLevel.SMOOTH;
  }
  return hdsMaterial.MaterialLevel.ADAPTIVE;
}
