/**
 * 历史记录页 HDS 标题栏注入内容：标题 + 右上角溢出菜单（查看本地历史记录/清除历史记录）。
 * 与 ReadHistoryPage 分属 HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 SearchTitleBar 模式）；菜单动作只发 tick，确认弹窗与跳转由内容页承接。
 */
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

interface HistoryMenuAction {
  readonly value: string;
  readonly action: () => void;
}

@Component
export struct HistoryTitleBar {
  title: string = '历史记录';

  build() {
    Row({ space: 8 }) {
      // 返回键由 HDS 标题栏默认 backIcon 承载（P1Shell 传入 action），这里从其右侧起排。
      Text(this.title)
        .id('p2_history_title')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('p2_history_overflow')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('历史记录选项')
      .bindMenu(this.historyMenu())
    }
    .width('100%')
    .height(48)
    // 左侧 64vp 让出 HDS 默认返回键的区域（实测不 pad 会压到其触摸区，同 SearchTitleBar）。
    .padding({ left: 64, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  private historyMenu(): Array<HistoryMenuAction> {
    return [
      { value: '查看本地历史记录', action: (): void => publishReadHistoryOpenLocal() },
      { value: '清除历史记录', action: (): void => publishReadHistoryClear() }
    ];
  }
}
