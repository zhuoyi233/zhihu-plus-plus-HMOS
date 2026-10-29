/** 用稳定来源键隔离离屏信息流，页签显示顺序不参与判断。 */
export function setFeedScrollOwner(key: string): void {
  if (AppStorage.get<string>('bottomBarScrollOwner') === key) { return; }
  AppStorage.setOrCreate('bottomBarScrollOwner', key);
  AppStorage.setOrCreate('bottomBarHiddenByScroll', false);
}

export function publishFeedScroll(key: string, offset: number): void {
  if (offset === 0 || key.length === 0 || AppStorage.get<string>('bottomBarScrollOwner') !== key) { return; }
  AppStorage.setOrCreate('bottomBarHiddenByScroll', offset > 0);
}
