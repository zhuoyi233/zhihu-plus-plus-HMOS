export enum P1DestinationName {
  HOME = 'Home',
  QUESTION = 'Question',
  ANSWER = 'Answer',
  ARTICLE = 'Article',
  PIN = 'Pin',
  PEOPLE = 'People',
  COMMENT = 'Comment',
  SEARCH = 'Search',
  COLLECTION = 'Collection',
  NOTIFICATION = 'Notification',
  SETTINGS = 'Settings',
  TECHNICAL_LAB = 'TechnicalLab'
}

export interface StatelessDestination {
  readonly name: P1DestinationName.HOME | P1DestinationName.NOTIFICATION;
}

export interface ShellDestination {
  readonly name: P1DestinationName.SETTINGS | P1DestinationName.TECHNICAL_LAB;
}

export interface ContentDestination {
  readonly name: P1DestinationName.QUESTION | P1DestinationName.ANSWER |
    P1DestinationName.ARTICLE | P1DestinationName.PIN |
    P1DestinationName.PEOPLE | P1DestinationName.COLLECTION;
  readonly id: string;
}

export interface CommentDestination {
  readonly name: P1DestinationName.COMMENT;
  readonly contentId: string;
  readonly commentId?: string;
}

export interface SearchDestination {
  readonly name: P1DestinationName.SEARCH;
  readonly query: string;
}

export type P1Destination = StatelessDestination | ShellDestination | ContentDestination |
  CommentDestination | SearchDestination;

export function isP1DestinationName(name: string): boolean {
  switch (name) {
    case P1DestinationName.HOME:
    case P1DestinationName.QUESTION:
    case P1DestinationName.ANSWER:
    case P1DestinationName.ARTICLE:
    case P1DestinationName.PIN:
    case P1DestinationName.PEOPLE:
    case P1DestinationName.COMMENT:
    case P1DestinationName.SEARCH:
    case P1DestinationName.COLLECTION:
    case P1DestinationName.NOTIFICATION:
    case P1DestinationName.SETTINGS:
    case P1DestinationName.TECHNICAL_LAB:
      return true;
    default:
      return false;
  }
}
