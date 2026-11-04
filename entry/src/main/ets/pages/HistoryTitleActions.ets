/** HDS 原生历史菜单发出操作信号，内容页负责导航与清除确认。 */
export const READ_HISTORY_OPEN_LOCAL_TICK_KEY = 'readHistoryOpenLocalTick';
export const READ_HISTORY_CLEAR_TICK_KEY = 'readHistoryClearTick';

export function publishReadHistoryOpenLocal(): void {
  AppStorage.setOrCreate(READ_HISTORY_OPEN_LOCAL_TICK_KEY,
    (AppStorage.get<number>(READ_HISTORY_OPEN_LOCAL_TICK_KEY) ?? 0) + 1);
}

export function publishReadHistoryClear(): void {
  AppStorage.setOrCreate(READ_HISTORY_CLEAR_TICK_KEY,
    (AppStorage.get<number>(READ_HISTORY_CLEAR_TICK_KEY) ?? 0) + 1);
}
