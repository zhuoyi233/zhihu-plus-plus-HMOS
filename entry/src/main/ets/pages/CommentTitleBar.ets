import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

/** 评论页标题栏状态；用内容来源作键，避免返回被覆盖的评论页时串到其他页面。 */
export interface CommentTitleState {
  id: string;
  replying: boolean;
  previewing?: boolean;
}

export function commentTitleStateId(contentType: string, contentId: string): string {
  return `${contentType}:${contentId}`;
}

export function publishCommentTitle(state: CommentTitleState): void {
  const states = AppStorage.get<CommentTitleState[]>('commentTitleStates') ?? [];
  const previous = states.find((item: CommentTitleState): boolean => item.id === state.id);
  if (previous?.replying === state.replying && previous?.previewing === state.previewing) {
    return;
  }
  AppStorage.setOrCreate('commentTitleStates',
    states.filter((item: CommentTitleState): boolean => item.id !== state.id).concat([state]));
}

export function removeCommentTitle(id: string): void {
  const states = AppStorage.get<CommentTitleState[]>('commentTitleStates') ?? [];
  AppStorage.setOrCreate('commentTitleStates',
    states.filter((item: CommentTitleState): boolean => item.id !== id));
}

/**
 * 评论页标题栏内容：main 设置页同款左对齐标题（随根评论/子评论切换文案），
 * 返回键由 HDS 原生 backIcon 承载（含"返回评论/返回详情"的层级回调由宿主绑定）。
 * 标题栏的常驻可读背景仍由 HdsNavDestination 的 getPersistentImmersiveTitleBarStyle 承担。
 */
@Component
export struct CommentTitleBar {
  stateId: string = '';
  @StorageProp('commentTitleStates') private states: CommentTitleState[] = [];

  private replying(): boolean {
    return this.states.find((item: CommentTitleState): boolean => item.id === this.stateId)?.replying ?? false;
  }

  build() {
    TopBarContent({
      backMode: TopBarBackMode.HDS,
      title: this.replying() ? '回复' : '评论',
      titleId: 'comments_title'
    })
  }
}
