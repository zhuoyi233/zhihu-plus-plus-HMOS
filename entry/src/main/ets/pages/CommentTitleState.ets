/** 评论页标题状态由正文广播，HDS 原生标题由 AppShell 绘制。 */
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
