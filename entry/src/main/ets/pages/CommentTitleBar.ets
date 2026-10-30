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
 * 评论页 HDS 标题栏内容：标题栏的滚动态材质由 HdsNavDestination 承载，返回键走共享
 * 悬浮圆按钮，根评论/子评论标题经 AppStorage 跨构建树更新。
 */
@Component
export struct CommentTitleBar {
  stateId: string = '';
  onBack: () => void = (): void => {
  };
  @StorageProp('commentTitleStates') private states: CommentTitleState[] = [];

  private replying(): boolean {
    return this.states.find((item: CommentTitleState): boolean => item.id === this.stateId)?.replying ?? false;
  }

  build() {
    TopBarContent({
      backMode: TopBarBackMode.CUSTOM,
      title: this.replying() ? '回复' : '评论',
      titleId: 'comments_title',
      backId: 'comments_back',
      centerTitle: true,
      onBack: (): void => {
        this.onBack();
      }
    })
  }
}
