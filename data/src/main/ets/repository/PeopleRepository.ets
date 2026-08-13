import { PeopleProfile, UserProfile } from '../domain/DomainModels';

export interface PeopleRepository {
  getUser(idOrToken: string): Promise<UserProfile>;
}

export interface PeopleDetailRepository {
  getUser(idOrToken: string): Promise<PeopleProfile>;
  cancel(): void;
}
