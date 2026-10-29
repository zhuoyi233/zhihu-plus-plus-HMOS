import { LengthMetrics } from '@kit.ArkUI';
import { BlurStrategy, hdsMaterial, ScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';
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

/** 连续阅读的 API 23 背景由页面渐变模糊层承载，HDS 只绘制标题内容，避免双重底色形成白色硬边。 */
export function getContinuousAnswerTitleBarStyle(materialMode: ImmersiveMaterialMode,
  materialSupport: ImmersiveMaterialSupportState): TitleBarStyleOptions {
  if (HarmonyOSCapabilities.supportsImmersiveTitleBarStyle()) {
    return getPersistentImmersiveTitleBarStyle(materialMode, materialSupport);
  }
  return {
    blurStrategy: BlurStrategy.DISABLE,
    scrollEffectOpts: { enableScrollEffect: false, scrollEffectType: ScrollEffectType.COMMON_BLUR },
    originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent } },
    scrollEffectStyle: { backgroundStyle: { backgroundColor: Color.Transparent } }
  };
}

/**
 * 顶级页签（首页/关注/热榜/日报/我的）根顶栏样式，对齐华为原生应用（花粉俱乐部/应用市场）
 * 的「沉浸光感标题栏」实现：材质层 + 渐变模糊 + 内容区从顶栏下方穿过。
 *
 * 分两条路径：
 * 1. 设备支持沉浸光感（`getSystemMaterialTypes()` 含 IMMERSIVE，旗舰真机走这条）：
 *    `systemMaterialEffect` 提供薄玻璃材质，模糊用 IMMERSIVE_GRADIENT_BLUR 渐变。
 * 2. 不支持（含模拟器，实测 `getSystemMaterialTypes()` 返回空数组）：材质会退化成
 *    灰白实色、渐变模糊几乎不出模糊，正文清晰透出顶栏。改走 COMMON_BLUR 均匀模糊
 *    + 半透明主题底兜底；`blurStrategy` 必须显式 ENABLE（ADAPTIVE 会把模糊压得很弱）。
 *
 * 模糊带只在滚动后出现：`maskExtraHeight`（遮罩超出标题栏的额外高度）放在
 * `scrollEffectStyle` 里给 40vp，`originalStyle` 保持 0——未滑动时首屏内容清晰，
 * 滑动出现滚动效果后顶栏下方多出一条由深到浅的渐变模糊带（对齐华为原生应用：
 * 滑动几像素就把标题栏下方约 40vp 的内容糊掉，停下保持、退回顶部又恢复清晰）。
 * 过渡终点取 10vp，使这条带子在第一下轻微滑动内就基本成形。
 * 两条路径都不改变内容让位（状态栏 + 56vp），切换设备不会出现布局跳动。
 */
const ROOT_CHROME_SCROLL_MASK_EXTRA_HEIGHT: number = 40;

export function getRootChromeTitleBarStyle(materialMode: ImmersiveMaterialMode,
  materialSupport: ImmersiveMaterialSupportState): TitleBarStyleOptions {
  if (materialSupport === ImmersiveMaterialSupportState.SUPPORTED) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(10)
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterialLevelFor(resolveImmersiveMaterialLevel(materialMode, materialSupport))
      },
      originalStyle: {
        backgroundStyle: {
          backgroundColor: $r('app.color.immersive_title_background'),
          maskExtraHeight: 0
        }
      },
      scrollEffectStyle: {
        backgroundStyle: {
          // 滚动态用更透的底色（60%）：内容颜色能透上来，标题栏里的搜索胶囊才呈玻璃感。
          // 该底色只用于材质路径；API 23 兜底路径仍用 70% 的 root_chrome_background。
          backgroundColor: $r('app.color.root_chrome_glass_background'),
          maskExtraHeight: ROOT_CHROME_SCROLL_MASK_EXTRA_HEIGHT
        }
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
    blurStrategy: BlurStrategy.ENABLE,
    originalStyle: {
      backgroundStyle: {
        backgroundColor: $r('app.color.root_chrome_background'),
        maskExtraHeight: 0
      }
    },
    scrollEffectStyle: {
      backgroundStyle: {
        backgroundColor: $r('app.color.root_chrome_background'),
        maskExtraHeight: ROOT_CHROME_SCROLL_MASK_EXTRA_HEIGHT
      }
    }
  };
}

/**
 * 聊天类页面（私信会话）的标题栏：消息列表首帧就定位到末尾，内容必然落在标题栏下方，
 * 若沿用半透明沉浸底，消息正文会透出与标题互相压字。这里固定用不透明页面底色，
 * 列表仍保留 contentStartOffset，滚动时消息滑入不透明顶栏之后。
 */
export function getChatTitleBarStyle(): TitleBarStyleOptions {
  if (HarmonyOSCapabilities.supportsImmersiveTitleBarStyle()) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: false,
        scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
      },
      originalStyle: {
        backgroundStyle: { backgroundColor: $r('app.color.page_background') },
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
  }
  // API 23 的 HDS 不渲染静止态 originalStyle 底色，需保留滚动效果机制并在两态都给同一不透明色。
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(10)
    },
    originalStyle: {
      backgroundStyle: { backgroundColor: $r('app.color.page_background') }
    },
    scrollEffectStyle: {
      backgroundStyle: { backgroundColor: $r('app.color.page_background') }
    }
  };
}

/** 回答 Native 列表嵌套在候选树中，HDS 无法可靠观察其滚动；由正文几何显式选择材质态。 */
export function getAnswerTitleBarStyle(materialMode: ImmersiveMaterialMode,
  materialSupport: ImmersiveMaterialSupportState, materialVisible: boolean): TitleBarStyleOptions {
  const style = getPersistentImmersiveTitleBarStyle(materialMode, materialSupport);
  // 不再让 HDS 的第二套滚动阈值改变身份折叠。模拟器/无材质设备用实色保持文字可读。
  style.blurStrategy = BlurStrategy.ENABLE;
  style.scrollEffectOpts = { enableScrollEffect: false, scrollEffectType: ScrollEffectType.COMMON_BLUR };
  const background: ResourceColor = !materialVisible ? Color.Transparent :
    (materialSupport === ImmersiveMaterialSupportState.SUPPORTED
      ? $r('app.color.immersive_title_background') : $r('app.color.page_background'));
  style.originalStyle = { backgroundStyle: { backgroundColor: background } };
  style.scrollEffectStyle = { backgroundStyle: { backgroundColor: background } };
  return style;
}
