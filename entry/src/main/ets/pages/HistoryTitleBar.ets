import { TopBarActionButton } from './components/TopBarActionButton';
import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

/**
 * 历史记录页标题栏内容：左对齐标题 + 右上角溢出菜单（查看本地历史记录/清除历史记录）。
 * 与 ReadHistoryPage 分属 HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 SearchTitleBar 模式）；菜单动作只发 tick，确认弹窗与跳转由内容页承接。
 *
 * 返回键由 HDS 原生 backIcon 承载（栈内入口）；作为一级页签时不出现返回键，标题从 12vp 起排。
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
  /** 栈内入口让出 HDS 返回键区域；一级页签入口不预留。 */
  @Prop backMode: TopBarBackMode = TopBarBackMode.HDS;
  @State private menuVisible: boolean = false;

  build() {
    TopBarContent({
      backMode: this.backMode,
      title: this.title,
      titleId: 'history_title',
      hasTrailingSlot: true,
      trailingSlot: (): void => this.historyAction()
    })
  }

  @Builder
  private historyAction() {
    // 菜单必须绑在内置节点上：绑到自定义组件实例收不到触发。
    Row() {
      TopBarActionButton({
        icon: $r('sys.symbol.ellipsis_circle'),
        elementId: 'history_overflow',
        label: '历史记录选项',
        onAction: (): void => {
          this.menuVisible = true;
        }
      })
    }
      .bindMenu(this.menuVisible, this.historyMenu(), {
        onDisappear: (): void => {
          this.menuVisible = false;
        }
      })
  }

  @Builder
  private historyMenu() {
    Menu() {
      ForEach(this.historyMenuActions(), (item: HistoryMenuAction) => {
        MenuItem({ content: item.value })
          .onClick((): void => {
            this.menuVisible = false;
            item.action();
          })
      }, (item: HistoryMenuAction): string => item.value)
    }
  }

  private historyMenuActions(): Array<HistoryMenuAction> {
    return [
      { value: '查看本地历史记录', action: (): void => publishReadHistoryOpenLocal() },
      { value: '清除历史记录', action: (): void => publishReadHistoryClear() }
    ];
  }
}
