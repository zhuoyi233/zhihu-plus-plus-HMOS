import {
  removeTopBarActionStateFrom,
  sameTopBarActionState,
  TopBarActionState,
  TopBarRequestKind,
  upsertTopBarActionState
} from './TopBarActionState';

/**
 * 顶栏注册式标题与动作的 AppStorage 通道。
 *
 * 普通二级页的返回键由 HDS 原生 `backIcon` 承载，标题与动作由宿主 AppShell 的
 * `stackBuilder` 绘制；页面只注册"标题是什么、有没有动作、动作被点时做什么"，
 * 不自己再画一条顶栏（计划 §3.1、§3.7、§6）。
 *
 * 跨 HdsNavDestination 的 stackBuilder 与内容两棵子树，`@Builder` 参数与 Provide/Consume
 * 实测不链接，因此沿用项目既有的 AppStorage 广播模式（同 settingsHomeActionTick）：
 * 页面发布状态，宿主渲染共享顶栏，点击写请求 id 并自增 tick，页面 `@Watch` 消费。
 * 返回同理——编辑器、设置双栏等自有退出顺序的页面不能被简单 pop 替代。
 */
const TOP_BAR_ACTION_STATES_KEY = 'topBarActionStates';
const TOP_BAR_ACTION_TICK_KEY = 'topBarActionTick';
const TOP_BAR_ACTION_REQUEST_ID_KEY = 'topBarActionRequestId';
const TOP_BAR_ACTION_REQUEST_KIND_KEY = 'topBarActionRequestKind';

function readStates(): TopBarActionState[] {
  return AppStorage.get<TopBarActionState[]>(TOP_BAR_ACTION_STATES_KEY) ?? [];
}

/** 发布本页顶栏状态；id 用路由标识（如 'blocking_rules'），同页多实例互不串台。 */
export function publishTopBarActionState(state: TopBarActionState): void {
  const states: TopBarActionState[] = readStates();
  const previous: TopBarActionState | undefined =
    states.find((item: TopBarActionState): boolean => item.id === state.id);
  if (sameTopBarActionState(previous, state)) {
    return;
  }
  AppStorage.setOrCreate(TOP_BAR_ACTION_STATES_KEY, upsertTopBarActionState(states, state));
}

/** 页面销毁时撤销注册，避免宿主沿用上一页的残留标题或动作。 */
export function removeTopBarActionState(id: string): void {
  const states: TopBarActionState[] = readStates();
  if (states.find((item: TopBarActionState): boolean => item.id === id) === undefined) {
    return;
  }
  AppStorage.setOrCreate(TOP_BAR_ACTION_STATES_KEY, removeTopBarActionStateFrom(states, id));
}

function requestTopBar(id: string, kind: TopBarRequestKind): void {
  AppStorage.setOrCreate(TOP_BAR_ACTION_REQUEST_ID_KEY, id);
  AppStorage.setOrCreate(TOP_BAR_ACTION_REQUEST_KIND_KEY, kind);
  AppStorage.setOrCreate(TOP_BAR_ACTION_TICK_KEY,
    (AppStorage.get<number>(TOP_BAR_ACTION_TICK_KEY) ?? 0) + 1);
}

/** 宿主点击共享动作按钮。 */
export function requestTopBarAction(id: string): void {
  requestTopBar(id, TopBarRequestKind.ACTION);
}

/** 宿主点击 HDS 原生返回：把退出交给页面自己的顺序（编辑器、设置双栏等）。 */
export function requestTopBarBack(id: string): void {
  requestTopBar(id, TopBarRequestKind.BACK);
}

function consumeTopBar(id: string, kind: TopBarRequestKind): boolean {
  return AppStorage.get<string>(TOP_BAR_ACTION_REQUEST_ID_KEY) === id &&
    AppStorage.get<string>(TOP_BAR_ACTION_REQUEST_KIND_KEY) === kind;
}

/** 页面消费动作请求：只有本次请求的 id 与种类同时匹配时才执行。 */
export function consumeTopBarAction(id: string): boolean {
  return consumeTopBar(id, TopBarRequestKind.ACTION);
}

/** 页面消费返回请求。 */
export function consumeTopBarBack(id: string): boolean {
  return consumeTopBar(id, TopBarRequestKind.BACK);
}

export {
  TopBarActionState,
  TopBarRequestKind,
  topBarActionAvailable,
  topBarActionEnabled,
  topBarActionText,
  topBarActionTitle
} from './TopBarActionState';
