import { PeopleContentPage, PeopleContentSection } from '../domain/DomainModels';

export interface PeopleContentRepository {
  getContentPage(identifier: string, section: PeopleContentSection, cursor?: string): Promise<PeopleContentPage>;
  cancel(): void;
}
