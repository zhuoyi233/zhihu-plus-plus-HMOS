import { vibrator } from '@kit.SensorServiceKit';

/**
 * Confirm 级震感（对齐上游 HapticFeedbackType.Confirm，用于双击赞成等轻确认操作）。
 * 模拟器或无振动器件会直接抛错/拒绝，静默降级不影响业务流程。
 */
export function performConfirmHaptic(): void {
  const effect: vibrator.VibratePreset = {
    type: 'preset',
    effectId: vibrator.HapticFeedback.EFFECT_SOFT,
    count: 1
  };
  const attribute: vibrator.VibrateAttribute = {
    usage: 'touch'
  };
  try {
    vibrator.startVibration(effect, attribute).catch((_error: Object): void => {
    });
  } catch (_error) {
  }
}
