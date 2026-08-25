import { isSafeDecimalContentId } from 'core';
import { ExistingAnswerForEditing, MAX_CREATION_HTML_LENGTH } from 'data';

/**
 * 从已打开的详情页进入编辑时使用的一次性内存种子。
 * 它不持久化、不写日志、不进入导航参数；控制器仍以加密本地草稿为优先恢复来源。
 */
interface PendingAnswerEditSeed extends ExistingAnswerForEditing {
}

let pendingSeed: PendingAnswerEditSeed | undefined = undefined;

export function stageAnswerEditSeed(answerId: string, html: string, tocEnabled: boolean = false): boolean {
  if (!isSafeDecimalContentId(answerId) || html.length > MAX_CREATION_HTML_LENGTH) {
    pendingSeed = undefined;
    return false;
  }
  pendingSeed = { answerId: answerId, html: html, tocEnabled: tocEnabled };
  return true;
}

/** 只可被同一回答 ID 消费一次，避免在返回栈或其他页面中遗留正文。 */
export function takeAnswerEditSeed(answerId: string): ExistingAnswerForEditing | undefined {
  const seed = pendingSeed;
  if (seed === undefined || !isSafeDecimalContentId(answerId) || seed.answerId !== answerId) {
    return undefined;
  }
  pendingSeed = undefined;
  return { answerId: seed.answerId, html: seed.html, tocEnabled: seed.tocEnabled };
}

export function clearAnswerEditSeed(): void {
  pendingSeed = undefined;
}
