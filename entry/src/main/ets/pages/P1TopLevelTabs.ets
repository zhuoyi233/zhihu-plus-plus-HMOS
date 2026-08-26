import { P1Destination, P1DestinationName } from 'core';

/** 根导航的稳定顺序，与 Android Lite 的首页、关注、热榜、日报、账号语义保持一致。 */
export enum P1TopLevelTab {
  HOME = 0,
  FOLLOWING = 1,
  HOT = 2,
  DAILY = 3,
  ACCOUNT = 4
}

export function p1TopLevelTabForDestination(destination: P1Destination): P1TopLevelTab | undefined {
  switch (destination.name) {
    case P1DestinationName.HOME:
      return P1TopLevelTab.HOME;
    case P1DestinationName.FOLLOWING:
      return P1TopLevelTab.FOLLOWING;
    case P1DestinationName.HOT:
      return P1TopLevelTab.HOT;
    case P1DestinationName.DAILY:
      return P1TopLevelTab.DAILY;
    case P1DestinationName.SETTINGS:
      return P1TopLevelTab.ACCOUNT;
    default:
      return undefined;
  }
}

export function p1TopLevelTabLabel(tab: P1TopLevelTab): string {
  switch (tab) {
    case P1TopLevelTab.HOME:
      return '首页';
    case P1TopLevelTab.FOLLOWING:
      return '关注';
    case P1TopLevelTab.HOT:
      return '热榜';
    case P1TopLevelTab.DAILY:
      return '日报';
    case P1TopLevelTab.ACCOUNT:
      return '我的';
  }
}

export function isP1TopLevelTabIndex(value: number): boolean {
  return Number.isInteger(value) && value >= P1TopLevelTab.HOME && value <= P1TopLevelTab.ACCOUNT;
}
