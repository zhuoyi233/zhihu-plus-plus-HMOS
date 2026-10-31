/**
 * 顶栏统一几何与材质路径策略（纯映射，可单测）。
 *
 * 本文件不导入 `@kit.ArkUI` / `@kit.UIDesignKit`（本地单测 host 对 kit 无桩，导入会破坏测试装载），
 * 材质对象是否创建成功由调用方提供，见 TopBarGlass.ets 与各顶栏组件。
 * 规则来源：docs/top-bars-immersive-material-plan.md §3.1、§3.7、§4.1。
 *
 * 整条普通顶栏以 main 设置页为唯一样板：HDS 原生返回、左对齐 20fp Medium 标题、
 * 40vp 圆形动作、10vp 间距、右侧 12vp 与无动作时的单个 40vp 空占位。
 * 返回键不由本层绘制，因此这里没有自绘返回的画布／裁剪几何。
 */

/** 顶部圆按钮可见直径（vp）——所有顶栏动作按钮的唯一轮廓值（main 设置页同款）。 */
export const TOP_BAR_BUTTON_DIAMETER_VP: number = 40;

/** 顶部圆按钮图标字号（fp）：随系统字号放大，不改变按钮轮廓。 */
export const TOP_BAR_ICON_FONT_SIZE: number = 20;

/** 顶栏内容行高（vp）。 */
export const TOP_BAR_CONTENT_ROW_HEIGHT_VP: number = 48;

/** 顶栏内容区域高度（vp）：HDS 标题栏自身高度，用于首屏让位计算。 */
export const TOP_BAR_AREA_HEIGHT_VP: number = 56;

/** 顶栏横向基础留白（vp），与 page_padding 同值。 */
export const TOP_BAR_HORIZONTAL_PADDING_VP: number = 12;

/** 标题与动作、动作与动作之间的间距（vp）——main 设置页的 spacing_small。 */
export const TOP_BAR_ACTION_SPACING_VP: number = 10;

/** 首页搜索胶囊高度（vp）。 */
export const TOP_BAR_SEARCH_PILL_HEIGHT_VP: number = 40;

/**
 * HDS 原生返回键在标题栏中占用的横向预留（vp）。
 * 返回由 HDS 承载，stackBuilder 只负责标题与动作，因此普通二级栏统一让出这一段，
 * 与 main 设置页一致（不保留其他页面旧的 64vp 起点）。
 */
export const TOP_BAR_HDS_BACK_RESERVE_VP: number = 80;

/** 顶部圆按钮的渲染路径：系统材质 / 普通模糊兜底，两者互斥。 */
export enum TopBarMaterialPath {
  SYSTEM_MATERIAL = 'systemMaterial',
  FALLBACK_BLUR = 'fallbackBlur'
}

/** 路径判定的输入：API 26 系统材质对象是否创建成功。 */
export interface TopBarMaterialInputs {
  readonly systemMaterialCreated: boolean;
}

/**
 * 两档接入（main 设置页同款）：材质对象存在时用系统材质，否则用普通模糊兜底。
 * 不按 HDS 沉浸能力二次分流，也没有画布分支；同一控件只走一条路径。
 */
export function resolveTopBarMaterialPath(inputs: TopBarMaterialInputs): TopBarMaterialPath {
  return inputs.systemMaterialCreated
    ? TopBarMaterialPath.SYSTEM_MATERIAL
    : TopBarMaterialPath.FALLBACK_BLUR;
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

/**
 * N 个可见动作占用的区域宽度（vp）：40×N＋10×(N−1)，不含标题到动作的 10vp 与右边距。
 * 零动作时返回单个 40vp 空占位宽度（main 设置页只留一个 Blank）。
 */
export function topBarActionsWidthVp(visibleActionCount: number): number {
  const count: number = visibleActionCount > 0 ? Math.floor(visibleActionCount) : 0;
  if (count === 0) {
    return TOP_BAR_BUTTON_DIAMETER_VP;
  }
  return TOP_BAR_BUTTON_DIAMETER_VP * count + TOP_BAR_ACTION_SPACING_VP * (count - 1);
}
