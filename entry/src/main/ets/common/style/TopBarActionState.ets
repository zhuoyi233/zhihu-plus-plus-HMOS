/**
 * 顶栏注册式标题/动作的纯策略（无 AppStorage、无 ArkUI 依赖，可被本地单测直接装载）。
 *
 * 页面把「标题 + 是否有动作 + 动作文案 + 动作可用性」注册进来，宿主 AppShell 据此绘制
 * main 设置页同款顶栏（计划 §3.1、§3.7）。真正跨构建树传递的存储读写见 TopBarActionBus.ets，
 * 本文件只负责数组层面的增删与查询，方便单测覆盖。
 */
export interface TopBarActionState {
  readonly id: string;
  /** 宿主是否渲染这条顶栏（false 时退回 HDS 静态标题）。 */
  readonly available: boolean;
  /** 宿主标题；空串表示沿用路由里的固定标题。 */
  readonly title: string;
  /** 文字主操作文案（如「发布」）；空串表示渲染为 40vp 圆形图标动作。 */
  readonly text: string;
  /** 动作可用性（如编辑器正文为空时禁用发布）。 */
  readonly enabled: boolean;
}

/** 请求种类：动作点击与返回点击共用一个 tick，页面按 kind 区分。 */
export enum TopBarRequestKind {
  ACTION = 'action',
  BACK = 'back'
}

export function topBarActionStateOf(states: TopBarActionState[], id: string): TopBarActionState | undefined {
  return states.find((item: TopBarActionState): boolean => item.id === id);
}

/** 写入/替换一条注册（同 id 覆盖，不改变其他页面注册）。 */
export function upsertTopBarActionState(states: TopBarActionState[],
  state: TopBarActionState): TopBarActionState[] {
  return states.filter((item: TopBarActionState): boolean => item.id !== state.id).concat([state]);
}

/** 撤销一条注册（页面销毁时调用，避免宿主沿用上一页的残留标题或动作）。 */
export function removeTopBarActionStateFrom(states: TopBarActionState[], id: string): TopBarActionState[] {
  return states.filter((item: TopBarActionState): boolean => item.id !== id);
}

/** 两条注册是否等价：等价时不必重写 AppStorage，避免无意义的重绘。 */
export function sameTopBarActionState(left: TopBarActionState | undefined,
  right: TopBarActionState): boolean {
  if (left === undefined) {
    return false;
  }
  return left.available === right.available && left.title === right.title &&
    left.text === right.text && left.enabled === right.enabled;
}

/** 宿主判断是否渲染注册式顶栏。 */
export function topBarActionAvailable(states: TopBarActionState[], id: string): boolean {
  return topBarActionStateOf(states, id)?.available ?? false;
}

/** 宿主取标题；未注册时返回空串，由调用方用固定标题兜底。 */
export function topBarActionTitle(states: TopBarActionState[], id: string): string {
  return topBarActionStateOf(states, id)?.title ?? '';
}

/** 宿主取文字主操作文案；空串表示圆形图标动作。 */
export function topBarActionText(states: TopBarActionState[], id: string): string {
  return topBarActionStateOf(states, id)?.text ?? '';
}

/** 宿主取动作可用性；未注册时按不可用处理。 */
export function topBarActionEnabled(states: TopBarActionState[], id: string): boolean {
  return topBarActionStateOf(states, id)?.enabled ?? false;
}
