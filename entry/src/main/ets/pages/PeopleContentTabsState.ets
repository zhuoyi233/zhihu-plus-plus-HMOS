import { PeopleContentSection } from 'data';

export interface PeopleTabsLayout {
  width: number;
  buttonWidth: number;
  buttonHeight: number;
  height: number;
  inTitleBar: boolean;
}

/** 只按实际容器宽度与字号决定布局；大字放不进 48vp 顶栏时回到独立胶囊。 */
export function resolvePeopleTabsLayout(viewportWidthVp: number, fontScale: number): PeopleTabsLayout {
  const scale = Number.isFinite(fontScale) && fontScale > 0 ? Math.max(1, fontScale) : 1;
  const buttonWidth = Math.ceil(32 * scale + 40);
  const buttonHeight = Math.max(36, Math.ceil(24 * scale));
  const height = buttonHeight + 8;
  const idealWidth = buttonWidth * 3 + 8;
  const viewport = Number.isFinite(viewportWidthVp) && viewportWidthVp > 0 ? viewportWidthVp : 0;
  return {
    width: viewport > 0 ? Math.min(idealWidth, Math.max(0, viewport - 24)) : idealWidth,
    buttonWidth: buttonWidth,
    buttonHeight: buttonHeight,
    height: height,
    // 每侧还要容纳原生返回/菜单与用户名，避免长用户名与胶囊相撞。
    inTitleBar: viewport >= 840 && height <= 48 && (viewport - idealWidth) / 2 >= 240
  };
}

export interface PeopleTabsState {
  id: string;
  selected: PeopleContentSection;
  pinned: boolean;
  inTitleBar: boolean;
}

export function peopleTabsInTitleBar(states: PeopleTabsState[], id: string): boolean {
  const state = states.find((item: PeopleTabsState): boolean => item.id === id);
  return state !== undefined && state.pinned && state.inTitleBar;
}

export function publishPeopleTabs(state: PeopleTabsState): void {
  const states = AppStorage.get<PeopleTabsState[]>('peopleContentTabsStates') ?? [];
  const previous = states.find((item: PeopleTabsState): boolean => item.id === state.id);
  if (previous !== undefined && previous.selected === state.selected && previous.pinned === state.pinned &&
    previous.inTitleBar === state.inTitleBar) { return; }
  AppStorage.setOrCreate('peopleContentTabsStates',
    states.filter((item: PeopleTabsState): boolean => item.id !== state.id).concat([state]));
}

export function removePeopleTabs(id: string): void {
  const states = AppStorage.get<PeopleTabsState[]>('peopleContentTabsStates') ?? [];
  AppStorage.setOrCreate('peopleContentTabsStates',
    states.filter((item: PeopleTabsState): boolean => item.id !== id));
}

export interface PeopleSectionRequest {
  id: string;
  section: PeopleContentSection;
}

export function requestedPeopleSection(request: PeopleSectionRequest | undefined,
  id: string): PeopleContentSection | undefined {
  return request?.id === id ? request.section : undefined;
}

/** stackBuilder 与内容区之间使用 AppStorage 广播，按路由隔离点击请求。 */
export function requestPeopleSection(id: string, section: PeopleContentSection): void {
  const request: PeopleSectionRequest = { id: id, section: section };
  AppStorage.setOrCreate('peopleContentSectionRequest', request);
  AppStorage.setOrCreate('peopleContentSectionTick',
    (AppStorage.get<number>('peopleContentSectionTick') ?? 0) + 1);
}
