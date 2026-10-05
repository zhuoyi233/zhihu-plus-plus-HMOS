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
    // 手动挡（生效挡位非 ADAPTIVE）时，HDS 会在滚动模糊未激活的原始态把标题栏按钮区域
    // （返回键圆底）的材质高光渲染成黑色，滚动后恢复正常（API 26 真机实测；ADAPTIVE 挡
    // 无此问题，SystemMaterialParams 亦无颜色参数可控）——手动挡移除按钮区材质规避，
    // 挡位材质保留在底栏与胶囊；自适应挡保持按钮区材质原样。
    const effectiveLevel = resolveImmersiveMaterialLevel(materialMode, materialSupport);
    const style: TitleBarStyleOptions = {
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
      }
    };
    if (effectiveLevel === ImmersiveMaterialMode.ADAPTIVE) {
      style.systemMaterialEffect = {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      };
    }
    return style;
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
    // API 23 上 HDS 不渲染静止态 originalStyle 的背景色，仅滚动效果机制激活后才有底色；
    // 因此保留 COMMON_BLUR 滚动效果、把静止态底色从透明改为同一模糊色，
    // 使首帧（含聊天页自动定位到底部时）顶栏即有沉浸底色。
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(10)
    },
    originalStyle: {
      backgroundStyle: {
        // API 23 上 sys.color.ohos_id_color_navigation_background_blur 解析为透明，
        // 须用与 API 26 滚动态一致的具体半透明色（随深浅色切换）。
        backgroundColor: $r('app.color.immersive_title_background')
      }
    },
    scrollEffectStyle: {
      backgroundStyle: {
        backgroundColor: $r('app.color.immersive_title_background')
      }
    }
  };
}
