import { TopBarActionButton } from './components/TopBarActionButton';
import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

/**
 * 历史记录页 HDS 标题栏注入内容：标题 + 右上角溢出菜单（查看本地历史记录/清除历史记录）。
 * 与 ReadHistoryPage 分属 HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 SearchTitleBar 模式）；菜单动作只发 tick，确认弹窗与跳转由内容页承接。
 *
 * 返回键归属由宿主决定：栈内入口用共享自绘返回（CUSTOM），一级页签入口用 NONE。
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

@Component
export struct HistoryTitleBar {
  title: string = '历史记录';
  @Prop backMode: TopBarBackMode = TopBarBackMode.CUSTOM;
  @State private menuVisible: boolean = false;
  /** 返回语义由宿主注入：顶栏组件不推断「返回」等于 pathStack.pop()。 */
  onBack: () => void = (): void => {
  };

  build() {
    TopBarContent({
      backMode: this.backMode,
      title: this.title,
      titleId: 'history_title',
      backId: 'history_back',
      onBack: (): void => {
        this.onBack();
      },
      hasTrailingSlot: true,
      trailingSlot: (): void => this.historyAction()
    })
  }

  @Builder
  private historyAction() {
    // 菜单必须绑在内置节点上：绑到自定义组件实例收不到触发，Row 作锚点与按钮同心。
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
      MenuItem({ content: '查看本地历史记录' })
        .onClick((): void => {
          this.menuVisible = false;
          publishReadHistoryOpenLocal();
        })
      MenuItem({ content: '清除历史记录' })
        .onClick((): void => {
          this.menuVisible = false;
          publishReadHistoryClear();
        })
    }
  }
}
