import { UserProfile } from '../domain/DomainModels';

export interface PeopleRepository {
  getUser(idOrToken: string): Promise<UserProfile>;
}
