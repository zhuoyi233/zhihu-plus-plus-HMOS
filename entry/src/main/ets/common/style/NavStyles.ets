import { LengthMetrics } from '@kit.ArkUI';
import { hdsMaterial, ScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { ImmersiveMaterialMode } from 'data';
import { HarmonyOSCapabilities } from '../platform/HarmonyOSCapabilities';
import {
  ImmersiveMaterialSupportState,
  resolveImmersiveMaterialLevel
} from './ImmersiveMaterialStyles';
import { hdsMaterialLevelFor } from './HdsMaterialLevels';

export function getImmersiveTitleBarStyle(materialMode: ImmersiveMaterialMode,
  materialSupport: ImmersiveMaterialSupportState): TitleBarStyleOptions {
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
          // 滚动态使用随深浅模式切换的半透明底，保留材质透光与标题可读性。
          backgroundColor: $r('app.color.immersive_title_background')
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
        // materialType 恒为 ADAPTIVE；materialLevel 由调用方传入响应式挡位经统一策略解析
        //（勿在本函数内直接 AppStorage.get，否则无法建立更新依赖）。
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterialLevelFor(resolveImmersiveMaterialLevel(materialMode, materialSupport))
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

/**
 * 详情页与评论页使用的常驻沉浸标题栏：正文从首帧起就在材质层下方滚动，
 * 因此不等待滚动阈值，直接让 originalStyle 使用与滚动态相同的半透明主题背景。
 */
export function getPersistentImmersiveTitleBarStyle(materialMode: ImmersiveMaterialMode,
  materialSupport: ImmersiveMaterialSupportState): TitleBarStyleOptions {
  if (HarmonyOSCapabilities.supportsImmersiveTitleBarStyle()) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: false,
        scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
      },
      originalStyle: {
        backgroundStyle: {
          backgroundColor: $r('app.color.immersive_title_background')
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
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterialLevelFor(resolveImmersiveMaterialLevel(materialMode, materialSupport))
      }
    };
  }
  return {
    scrollEffectOpts: {
      enableScrollEffect: false,
      scrollEffectType: ScrollEffectType.COMMON_BLUR
    },
    originalStyle: {
      backgroundStyle: {
        backgroundColor: $r('sys.color.ohos_id_color_navigation_background_blur')
      }
    }
  };
}
