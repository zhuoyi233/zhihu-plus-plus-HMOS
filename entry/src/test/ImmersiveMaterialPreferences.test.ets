import { describe, expect, it } from '@ohos/hypium';
import {
  decodeImmersiveMaterialMode,
  decodeImmersiveMaterialModeText,
  DEFAULT_IMMERSIVE_MATERIAL_MODE,
  ImmersiveMaterialMode
} from 'data';

export default function immersiveMaterialPreferencesTest(): void {
  describe('immersiveMaterialPreferencesTest', () => {
    it('decodesPersistedModes', 0, () => {
      expect(decodeImmersiveMaterialMode(ImmersiveMaterialMode.ADAPTIVE))
        .assertEqual(ImmersiveMaterialMode.ADAPTIVE);
      expect(decodeImmersiveMaterialMode(ImmersiveMaterialMode.EXQUISITE))
        .assertEqual(ImmersiveMaterialMode.EXQUISITE);
      expect(decodeImmersiveMaterialMode(ImmersiveMaterialMode.GENTLE))
        .assertEqual(ImmersiveMaterialMode.GENTLE);
      expect(decodeImmersiveMaterialMode(ImmersiveMaterialMode.SMOOTH))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
      expect(decodeImmersiveMaterialModeText('exquisite')).assertEqual(ImmersiveMaterialMode.EXQUISITE);
    });

    it('fallsBackUnknownStringsAndWrongTypesToAdaptive', 0, () => {
      // 未知字符串（含旧版本可能写入的非法值）统一回退自适应。
      expect(decodeImmersiveMaterialModeText('off')).assertEqual(DEFAULT_IMMERSIVE_MATERIAL_MODE);
      expect(decodeImmersiveMaterialModeText('EXQUISITE')).assertEqual(DEFAULT_IMMERSIVE_MATERIAL_MODE);
      expect(decodeImmersiveMaterialModeText('')).assertEqual(DEFAULT_IMMERSIVE_MATERIAL_MODE);
      expect(decodeImmersiveMaterialModeText(undefined)).assertEqual(DEFAULT_IMMERSIVE_MATERIAL_MODE);
      // 错误类型（number、boolean）同样回退自适应；缺失键由 store.get 以默认值兜底。
      expect(decodeImmersiveMaterialMode(2)).assertEqual(DEFAULT_IMMERSIVE_MATERIAL_MODE);
      expect(decodeImmersiveMaterialMode(true)).assertEqual(DEFAULT_IMMERSIVE_MATERIAL_MODE);
    });
  });
}
