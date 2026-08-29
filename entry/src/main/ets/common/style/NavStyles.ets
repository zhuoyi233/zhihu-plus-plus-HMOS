import { LengthMetrics } from '@kit.ArkUI';
import { hdsMaterial, ScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { HarmonyOSCapabilities } from '../platform/HarmonyOSCapabilities';

export function getImmersiveTitleBarStyle(): TitleBarStyleOptions {
  if (HarmonyOSCapabilities.supportsImmersiveMaterial()) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(10)
      },
      originalStyle: {
        backgroundStyle: {
          backgroundColor: $r('sys.color.ohos_id_color_background_transparent')
        },
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r('app.color.primary_text'),
            subTitleColor: $r('app.color.secondary_text')
          },
          backIconStyle: { iconColor: $r('app.color.primary_text') },
          subIconStyle: { iconColor: $r('app.color.primary_text') },
          menuStyle: { iconColor: $r('app.color.primary_text') }
        }
      },
      scrollEffectStyle: {
        backgroundStyle: {
          backgroundColor: $r('app.color.surface_background')
        },
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r('app.color.primary_text'),
            subTitleColor: $r('app.color.secondary_text')
          },
          backIconStyle: { iconColor: $r('app.color.primary_text') },
          subIconStyle: { iconColor: $r('app.color.primary_text') },
          menuStyle: { iconColor: $r('app.color.primary_text') }
        }
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
  }
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(10)
    },
    originalStyle: {
      backgroundStyle: {
        backgroundColor: $r('sys.color.ohos_id_color_background_transparent')
      }
    },
    scrollEffectStyle: {
      backgroundStyle: {
        backgroundColor: $r('sys.color.ohos_id_color_navigation_background_blur')
      }
    }
  };
}
