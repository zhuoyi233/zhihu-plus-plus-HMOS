import { AppDestination, AppDestinationName } from 'core';

/** 根导航的稳定顺序，与 Android Lite 的首页、关注、热榜、日报、账号语义保持一致。 */
export enum TopLevelTab {
  HOME = 0,
  FOLLOWING = 1,
  HOT = 2,
  DAILY = 3,
  HISTORY = 4,
  COLLECTIONS = 5,
  ACCOUNT = 6
}

export function topLevelTabForDestination(destination: AppDestination): TopLevelTab | undefined {
  switch (destination.name) {
    case AppDestinationName.HOME:
      return TopLevelTab.HOME;
    case AppDestinationName.FOLLOWING:
      return TopLevelTab.FOLLOWING;
    case AppDestinationName.HOT:
      return TopLevelTab.HOT;
    case AppDestinationName.DAILY:
      return TopLevelTab.DAILY;
    case AppDestinationName.READ_HISTORY:
      return TopLevelTab.HISTORY;
    case AppDestinationName.COLLECTIONS:
      return TopLevelTab.COLLECTIONS;
    case AppDestinationName.SETTINGS:
      return TopLevelTab.ACCOUNT;
    default:
      return undefined;
  }
}

export function topLevelTabLabel(tab: TopLevelTab): string {
  switch (tab) {
    case TopLevelTab.HOME:
      return '首页';
    case TopLevelTab.FOLLOWING:
      return '关注';
    case TopLevelTab.HOT:
      return '热榜';
    case TopLevelTab.DAILY:
      return '日报';
    case TopLevelTab.HISTORY:
      return '历史';
    case TopLevelTab.COLLECTIONS:
      return '收藏夹';
    case TopLevelTab.ACCOUNT:
      return '我的';
  }
}

export function isTopLevelTabIndex(value: number): boolean {
  return Number.isInteger(value) && value >= TopLevelTab.HOME && value <= TopLevelTab.ACCOUNT;
}
