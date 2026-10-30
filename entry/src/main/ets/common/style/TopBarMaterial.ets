/**
 * 顶栏统一几何与材质路径策略（纯映射，可单测）。
 *
 * 本文件不导入 `@kit.ArkUI` / `@kit.UIDesignKit`（本地单测 host 对 kit 无桩，导入会破坏测试装载），
 * 设备能力与材质对象创建结果由调用方提供，见 TopBarGlass.ets 与各顶栏组件。
 * 规则来源：docs/top-bars-immersive-material-plan.md §3.1、§4.1。
 */

/** 顶部圆按钮可见直径（vp）——所有顶栏按钮的唯一轮廓值。 */
export const TOP_BAR_BUTTON_DIAMETER_VP: number = 40;

/** 顶部圆按钮图标字号（fp）：随系统字号放大，不改变按钮轮廓。 */
export const TOP_BAR_ICON_FONT_SIZE: number = 20;

/** 圆按钮热区边长（vp）：可见 40vp，热区取 ≥44vp 的方形，不改变可见轮廓。 */
export const TOP_BAR_HIT_TARGET_VP: number = 44;

/** 顶栏内容行高（vp）。 */
export const TOP_BAR_CONTENT_ROW_HEIGHT_VP: number = 48;

/** 顶栏内容区域高度（vp）：HDS 标题栏自身高度，用于首屏让位计算。 */
export const TOP_BAR_AREA_HEIGHT_VP: number = 56;

/** 顶栏横向基础留白（vp），与 page_padding 同值。 */
export const TOP_BAR_HORIZONTAL_PADDING_VP: number = 12;

/** 标题与动作、动作与动作之间的间距（vp）。 */
export const TOP_BAR_ACTION_SPACING_VP: number = 8;

/** 首页搜索胶囊高度（vp）。 */
export const TOP_BAR_SEARCH_PILL_HEIGHT_VP: number = 40;

/**
 * HDS 材质画布分支的画布边长与裁剪窗边长（vp）。
 * 52/44 是阅读类顶栏返回键在真机已验证的一组几何（画布内部宽度补偿被裁剪窗吃掉），
 * 收敛到 40vp 可见轮廓需要 API 23 真机复核，本轮只在共享层集中，不擅自改值。
 */
export const TOP_BAR_CANVAS_DIAMETER_VP: number = 52;
export const TOP_BAR_CANVAS_CLIP_VP: number = 44;

/**
 * HDS 自带返回键在标题栏中占用的横向预留（vp）。
 * 顶栏改造后栈内页面统一改用自绘返回键，只有仍需 HDS 返回键的场景读这个值。
 */
export const TOP_BAR_HDS_BACK_RESERVE_VP: number = 64;

/** 顶部圆按钮的渲染路径：系统材质 / HDS 材质画布 / 普通模糊兜底，三者互斥。 */
export enum TopBarMaterialPath {
  SYSTEM_MATERIAL = 'systemMaterial',
  HDS_CANVAS = 'hdsCanvas',
  FALLBACK_BLUR = 'fallbackBlur'
}

/** 路径判定的输入：设备 HDS 沉浸材质能力 + API 26 系统材质对象是否创建成功。 */
export interface TopBarMaterialInputs {
  readonly hdsImmersiveSupported: boolean;
  readonly systemMaterialCreated: boolean;
}

/**
 * 互斥降级策略：设备无沉浸材质（含查询失败）一律走普通模糊兜底；
 * 有沉浸材质时，API 26+ 优先系统材质，更低版本保留已验证的 HDS 材质画布分支。
 * 同一控件只走一条路径，不同时叠加系统材质与模糊兜底。
 */
export function resolveTopBarMaterialPath(inputs: TopBarMaterialInputs): TopBarMaterialPath {
  if (!inputs.hdsImmersiveSupported) {
    return TopBarMaterialPath.FALLBACK_BLUR;
  }
  return inputs.systemMaterialCreated
    ? TopBarMaterialPath.SYSTEM_MATERIAL
    : TopBarMaterialPath.HDS_CANVAS;
}

/** 首屏让位的下限（vp）：状态栏读数尚未就绪时使用的兜底起始位置。 */
export const TOP_BAR_MIN_START_OFFSET_VP: number = 94;

/**
 * 普通页面首屏内容起点（vp）：max(94, 状态栏高度 + 顶栏内容区域 56vp)。
 * 只决定滚动容器的 contentStartOffset，不影响视口本身延伸到顶栏后方。
 */
export function topBarStartOffsetVp(statusBarHeightVp: number): number {
  const safeStatusBar: number = statusBarHeightVp > 0 ? statusBarHeightVp : 0;
  return Math.max(TOP_BAR_MIN_START_OFFSET_VP, safeStatusBar + TOP_BAR_AREA_HEIGHT_VP);
}

/**
 * 信息流首屏内容起点（vp）：在普通起点上上浮 overlapVp，让首条贴住胶囊下沿，
 * 但不得高于一屏顶栏区域本身。
 */
export function topBarFeedStartOffsetVp(statusBarHeightVp: number, overlapVp: number): number {
  const safeOverlap: number = overlapVp > 0 ? overlapVp : 0;
  return Math.max(TOP_BAR_AREA_HEIGHT_VP, topBarStartOffsetVp(statusBarHeightVp) - safeOverlap);
}
