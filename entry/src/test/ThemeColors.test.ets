import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_THEME_COLOR,
  hexToRgb,
  hsvToRgb,
  normalizeThemeColor,
  onThemeColor,
  resolveThemeColorForDark,
  rgbToHex,
  rgbToHsv,
  themeColorContainerColor,
  HsvColor,
  RgbColor
} from 'data';

export default function themeColorsTest(): void {
  describe('themeColorsTest', () => {
    it('normalizeAcceptsLowercaseAndTrims', 0, () => {
      expect(normalizeThemeColor('  #0066ff ')).assertEqual('#0066FF');
    });

    it('normalizeRejectsInvalidValues', 0, () => {
      expect(normalizeThemeColor(undefined)).assertEqual(DEFAULT_THEME_COLOR);
      expect(normalizeThemeColor('')).assertEqual(DEFAULT_THEME_COLOR);
      expect(normalizeThemeColor('#06F')).assertEqual(DEFAULT_THEME_COLOR);
      expect(normalizeThemeColor('#GGGGGG')).assertEqual(DEFAULT_THEME_COLOR);
      expect(normalizeThemeColor('0066FF')).assertEqual(DEFAULT_THEME_COLOR);
    });

    it('hexToRgbParsesChannels', 0, () => {
      const rgb: RgbColor = hexToRgb('#0066FF');
      expect(rgb.r).assertEqual(0);
      expect(rgb.g).assertEqual(102);
      expect(rgb.b).assertEqual(255);
    });

    it('rgbHexRoundTripForAllPresets', 0, () => {
      const presets: string[] = ['#0066FF', '#D22222', '#F44836', '#F2821E', '#7BB736', '#16C24B',
        '#16A8C2', '#29B6F6', '#3F51B5', '#5538E9', '#9C27B0', '#39C5BB'];
      for (const hex of presets) {
        expect(rgbToHex(hexToRgb(hex))).assertEqual(hex);
      }
    });

    it('hsvRoundTripForAllPresets', 0, () => {
      const presets: string[] = ['#0066FF', '#D22222', '#F44836', '#F2821E', '#7BB736', '#16C24B',
        '#16A8C2', '#29B6F6', '#3F51B5', '#5538E9', '#9C27B0', '#39C5BB'];
      for (const hex of presets) {
        const hsv: HsvColor = rgbToHsv(hexToRgb(hex));
        expect(rgbToHex(hsvToRgb(hsv))).assertEqual(hex);
      }
    });

    it('hsvOfPureRedIsOrigin', 0, () => {
      const hsv: HsvColor = rgbToHsv({ r: 255, g: 0, b: 0 });
      expect(hsv.h).assertEqual(0);
      expect(hsv.s).assertEqual(1);
      expect(hsv.v).assertEqual(1);
      expect(rgbToHex(hsvToRgb({ h: 0, s: 1, v: 1 }))).assertEqual('#FF0000');
    });

    it('darkResolveLightensSeed', 0, () => {
      // #0066FF 向白提亮 35%：r=89(0x59) g=156(0x9C) b=255，观感对齐原深色品牌色 #5B9DFF。
      expect(resolveThemeColorForDark('#0066FF')).assertEqual('#599CFF');
    });

    it('containerDerivesWithAlpha', 0, () => {
      expect(themeColorContainerColor('#0066FF')).assertEqual('#1F0066FF');
    });

    it('onColorFollowsBrightness', 0, () => {
      expect(onThemeColor('#0066FF')).assertEqual('#FFFFFF');
      expect(onThemeColor('#39C5BB')).assertEqual('#14181F');
      expect(onThemeColor('#FFFFFF')).assertEqual('#14181F');
    });
  });
}
