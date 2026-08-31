import { LengthMetrics } from '@kit.ArkUI';
import { hdsMaterial, ScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { HarmonyOSCapabilities } from '../platform/HarmonyOSCapabilities';

export function getImmersiveTitleBarStyle(): TitleBarStyleOptions {
  // 标题栏沉浸样式（材质层+渐变模糊滚动效果）仅 API 26+ 渲染正常；
  // 23 真机渲染白色遮挡条（见 HarmonyOSCapabilities.supportsImmersiveTitleBarStyle）。
  if (HarmonyOSCapabilities.supportsImmersiveTitleBarStyle()) {
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
        // ADAPTIVE 跟随系统材质策略（自 6.1.0(23) 起可用），由系统按设备能力自选
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
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
