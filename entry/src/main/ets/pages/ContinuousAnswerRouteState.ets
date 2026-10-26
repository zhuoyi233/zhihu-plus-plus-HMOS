import { appDestinationIdentity, AppDestinationName } from 'core';

export interface ContinuousAnswerTitleState {
  readonly routeId: string;
  readonly title: string;
}

export function continuousAnswerRouteId(questionId: string, answerId: string, sort: string): string {
  return appDestinationIdentity({ name: AppDestinationName.CONTINUOUS_ANSWER,
    questionId: questionId, answerId: answerId, sort: sort });
}

export function continuousAnswerTitle(states: Array<ContinuousAnswerTitleState>, routeId: string): string {
  return states.find((state: ContinuousAnswerTitleState): boolean => state.routeId === routeId)?.title ?? '';
}

export function updateContinuousAnswerTitle(states: Array<ContinuousAnswerTitleState>, routeId: string,
  title?: string): Array<ContinuousAnswerTitleState> {
  const remaining = states.filter((state: ContinuousAnswerTitleState): boolean => state.routeId !== routeId);
  return title === undefined ? remaining : remaining.concat([{ routeId: routeId, title: title }]);
}
