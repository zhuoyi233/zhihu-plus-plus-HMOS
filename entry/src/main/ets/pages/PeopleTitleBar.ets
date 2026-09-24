/** 用户主页顶栏状态：昵称 + 滚动折叠信号。
 * 跨页面经 AppStorage 广播（同 AnswerTitleBar/ArticleTitleBar 模式，HDS 标题栏在
 * NavDestination 的 stackBuilder 树下常规传值不更新，必须走存储通道）。 */
export interface PeopleTitleState {
  id: string;
  name: string;
  scrolled: boolean;
}

const PEOPLE_TITLE_DEFAULT = '用户主页';

export function publishPeopleTitle(state: PeopleTitleState): void {
  const states = AppStorage.get<PeopleTitleState[]>('peopleTitleStates') ?? [];
  const previous = states.find((item: PeopleTitleState): boolean => item.id === state.id);
  if (previous !== undefined && previous.name === state.name && previous.scrolled === state.scrolled) {
    return;
  }
  AppStorage.setOrCreate('peopleTitleStates',
    states.filter((item: PeopleTitleState): boolean => item.id !== state.id).concat([state]));
}

export function removePeopleTitle(id: string): void {
  const states = AppStorage.get<PeopleTitleState[]>('peopleTitleStates') ?? [];
  AppStorage.setOrCreate('peopleTitleStates',
    states.filter((item: PeopleTitleState): boolean => item.id !== id));
}

/** 顶栏文案：默认「用户主页」，昵称滚出顶栏下沿后改显昵称，滚回还原。
 * 按路由 id 取本页状态，栈内多层用户主页互不串台；页面出栈即由 removePeopleTitle 清理。 */
export function peopleTitleText(states: PeopleTitleState[], id: string): string {
  const current = states.find((item: PeopleTitleState): boolean => item.id === id);
  if (current === undefined || !current.scrolled || current.name.trim().length === 0) {
    return PEOPLE_TITLE_DEFAULT;
  }
  return current.name;
}
